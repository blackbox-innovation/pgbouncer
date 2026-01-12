#!/bin/bash
# PgBouncer library functions
# Copyright Blackbox Tooling
# SPDX-License-Identifier: Apache-2.0

# shellcheck disable=SC1091
. /opt/blackbox/scripts/pgbouncer-env.sh

########################
# Logging functions
########################
log_info() {
    echo "[INFO] $*"
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_debug() {
    if [[ "${PGBOUNCER_VERBOSE:-0}" == "1" ]]; then
        echo "[DEBUG] $*"
    fi
}

########################
# Docker Secrets Support
# Read value from file if _FILE variable is set
# Security: Validates file path is within allowed directories
########################
file_env() {
    local var="$1"
    local file_var="${var}_FILE"
    local default="${2:-}"

    # Get the value of the _FILE variable (e.g., POSTGRESQL_PASSWORD_FILE)
    local file_path="${!file_var:-}"

    if [[ -n "$file_path" ]]; then
        # Security: Validate file path is within allowed directories
        local allowed_paths="/run/secrets/ /opt/blackbox/"
        local path_valid=false
        for allowed in $allowed_paths; do
            if [[ "$file_path" == "$allowed"* ]]; then
                path_valid=true
                break
            fi
        done

        if [[ "$path_valid" != "true" ]]; then
            log_error "Secret file path $file_path is not in allowed directories ($allowed_paths)"
            return 1
        fi

        if [[ -f "$file_path" ]]; then
            # Read value from file with size limit (max 4KB)
            local value
            value="$(head -c 4096 "$file_path")" || {
                log_error "Failed to read secret file $file_path"
                return 1
            }
            export "$var"="$value"
            # Don't log file paths for secrets in debug mode
        else
            log_error "Secret file $file_path for $var does not exist"
            return 1
        fi
    elif [[ -z "${!var:-}" ]]; then
        # Variable not set, use default
        export "$var"="$default"
    fi
    # If variable is already set directly, keep it
}

########################
# Load secrets from files
########################
pgbouncer_load_secrets() {
    log_info "Loading secrets from files..."

    # PostgreSQL connection secrets
    file_env POSTGRESQL_PASSWORD ""
    file_env POSTGRESQL_USERNAME "postgres"
    file_env POSTGRESQL_HOST "postgresql"
    file_env POSTGRESQL_PORT "5432"
    file_env POSTGRESQL_DATABASE "postgres"

    # PgBouncer auth secrets
    file_env PGBOUNCER_AUTH_USER ""
    file_env PGBOUNCER_USERLIST ""

    # Clear _FILE variables from environment after reading
    unset POSTGRESQL_PASSWORD_FILE
    unset POSTGRESQL_USERNAME_FILE
    unset POSTGRESQL_HOST_FILE
    unset POSTGRESQL_PORT_FILE
    unset POSTGRESQL_DATABASE_FILE
    unset PGBOUNCER_AUTH_USER_FILE
    unset PGBOUNCER_USERLIST_FILE

    log_info "Secrets loaded successfully"
}

########################
# Escape special characters for auth file
########################
pgbouncer_escape_auth() {
    local value="$1"
    # Escape double quotes
    printf '%s' "${value//\"/\\\"}"
}

########################
# Validate environment variables
########################
pgbouncer_validate() {
    log_info "Validating PgBouncer configuration..."

    local error_count=0

    # Validate port
    if ! [[ "$PGBOUNCER_PORT" =~ ^[0-9]+$ ]] || [[ "$PGBOUNCER_PORT" -lt 1 ]] || [[ "$PGBOUNCER_PORT" -gt 65535 ]]; then
        log_error "Invalid PGBOUNCER_PORT: $PGBOUNCER_PORT"
        ((error_count++))
    fi

    # Validate pool mode
    case "$PGBOUNCER_POOL_MODE" in
        session|transaction|statement) ;;
        *)
            log_error "Invalid PGBOUNCER_POOL_MODE: $PGBOUNCER_POOL_MODE (must be session, transaction, or statement)"
            ((error_count++))
            ;;
    esac

    # Validate auth type
    case "$PGBOUNCER_AUTH_TYPE" in
        any|trust|plain|md5|scram-sha-256|cert|hba|pam) ;;
        *)
            log_error "Invalid PGBOUNCER_AUTH_TYPE: $PGBOUNCER_AUTH_TYPE"
            ((error_count++))
            ;;
    esac

    # Warn if trust auth is used
    if [[ "$PGBOUNCER_AUTH_TYPE" == "trust" ]]; then
        log_warn "Using 'trust' authentication - this is insecure for production!"
    fi

    # Validate TLS settings - check file existence
    if [[ "$PGBOUNCER_CLIENT_TLS_SSLMODE" != "disable" ]]; then
        if [[ -z "$PGBOUNCER_CLIENT_TLS_CERT_FILE" ]] || [[ -z "$PGBOUNCER_CLIENT_TLS_KEY_FILE" ]]; then
            log_error "Client TLS enabled but PGBOUNCER_CLIENT_TLS_CERT_FILE or PGBOUNCER_CLIENT_TLS_KEY_FILE not set"
            ((error_count++))
        else
            # Check files exist and are readable
            if [[ ! -f "$PGBOUNCER_CLIENT_TLS_CERT_FILE" ]]; then
                log_error "Client TLS cert file does not exist: $PGBOUNCER_CLIENT_TLS_CERT_FILE"
                ((error_count++))
            elif [[ ! -r "$PGBOUNCER_CLIENT_TLS_CERT_FILE" ]]; then
                log_error "Client TLS cert file is not readable: $PGBOUNCER_CLIENT_TLS_CERT_FILE"
                ((error_count++))
            fi
            if [[ ! -f "$PGBOUNCER_CLIENT_TLS_KEY_FILE" ]]; then
                log_error "Client TLS key file does not exist: $PGBOUNCER_CLIENT_TLS_KEY_FILE"
                ((error_count++))
            elif [[ ! -r "$PGBOUNCER_CLIENT_TLS_KEY_FILE" ]]; then
                log_error "Client TLS key file is not readable: $PGBOUNCER_CLIENT_TLS_KEY_FILE"
                ((error_count++))
            fi
        fi
    fi

    # Validate server TLS files if enabled
    if [[ "$PGBOUNCER_SERVER_TLS_SSLMODE" != "disable" ]]; then
        if [[ -n "$PGBOUNCER_SERVER_TLS_CA_FILE" ]] && [[ ! -f "$PGBOUNCER_SERVER_TLS_CA_FILE" ]]; then
            log_error "Server TLS CA file does not exist: $PGBOUNCER_SERVER_TLS_CA_FILE"
            ((error_count++))
        fi
    fi

    if [[ "$error_count" -gt 0 ]]; then
        log_error "Validation failed with $error_count error(s)"
        return 1
    fi

    log_info "Configuration validated successfully"
}

########################
# Generate userlist.txt
# Security: Uses umask to prevent race condition
########################
pgbouncer_create_auth_file() {
    log_info "Creating authentication file..."

    local auth_file="$PGBOUNCER_AUTH_FILE"

    # Security: Create file with restrictive permissions from the start
    (
        umask 077
        : > "$auth_file"
    )

    # Add PostgreSQL user
    if [[ -n "$POSTGRESQL_USERNAME" ]] && [[ -n "$POSTGRESQL_PASSWORD" ]]; then
        local escaped_user
        local escaped_pass
        escaped_user=$(pgbouncer_escape_auth "$POSTGRESQL_USERNAME")
        escaped_pass=$(pgbouncer_escape_auth "$POSTGRESQL_PASSWORD")
        # Use printf to avoid password appearing in process list
        printf '"%s" "%s"\n' "$escaped_user" "$escaped_pass" >> "$auth_file"
        log_info "Added user '$POSTGRESQL_USERNAME' to userlist"
    fi

    # Add auth user if different from main user
    if [[ -n "$PGBOUNCER_AUTH_USER" ]] && [[ "$PGBOUNCER_AUTH_USER" != "$POSTGRESQL_USERNAME" ]]; then
        local escaped_auth_user
        escaped_auth_user=$(pgbouncer_escape_auth "$PGBOUNCER_AUTH_USER")
        # Auth user needs access but password comes from auth_query
        printf '"%s" ""\n' "$escaped_auth_user" >> "$auth_file"
        log_info "Added auth user '$PGBOUNCER_AUTH_USER' to userlist"
    fi

    # Add additional users from PGBOUNCER_USERLIST (validate format)
    if [[ -n "$PGBOUNCER_USERLIST" ]]; then
        # Basic validation: each line should match "user" "password" format
        if echo "$PGBOUNCER_USERLIST" | grep -qvE '^"[^"]*" "[^"]*"$'; then
            log_warn "PGBOUNCER_USERLIST may contain invalid entries"
        fi
        printf '%s\n' "$PGBOUNCER_USERLIST" >> "$auth_file"
        log_info "Added additional users from PGBOUNCER_USERLIST"
    fi
}

########################
# Generate pgbouncer.ini
# Security: Uses umask to prevent race condition
########################
pgbouncer_create_config() {
    log_info "Creating PgBouncer configuration file..."

    local config_file="$PGBOUNCER_CONF_FILE"
    local database_name="${PGBOUNCER_DATABASE:-$POSTGRESQL_DATABASE}"

    # Security: Create file with restrictive permissions from the start
    (
        umask 077
        cat > "$config_file" << EOF
;; PgBouncer configuration file
;; Generated by Blackbox PgBouncer container

[databases]
EOF
    )

    # Add database entries
    # Check for DSN_* variables for multi-backend support
    local has_dsn=false
    local var dsn_name dsn_value
    while IFS= read -r var; do
        [[ -z "$var" ]] && continue
        has_dsn=true
        dsn_name="${var#PGBOUNCER_DSN_}"
        dsn_value="${!var}"
        # Security: Quote DSN value properly
        printf '%s = %s\n' "${dsn_name,,}" "$dsn_value" >> "$config_file"
        log_info "Added database from DSN: ${dsn_name,,}"
    done < <(compgen -e | grep -E '^PGBOUNCER_DSN_' || true)

    # If no DSN variables, use default connection
    if [[ "$has_dsn" == "false" ]]; then
        if [[ -n "$database_name" ]]; then
            printf '%s = host=%s port=%s dbname=%s\n' "$database_name" "$POSTGRESQL_HOST" "$POSTGRESQL_PORT" "$POSTGRESQL_DATABASE" >> "$config_file"
        fi
        printf '* = host=%s port=%s\n' "$POSTGRESQL_HOST" "$POSTGRESQL_PORT" >> "$config_file"
        log_info "Added default database connection to $POSTGRESQL_HOST:$POSTGRESQL_PORT"
    fi

    # PgBouncer settings
    cat >> "$config_file" << EOF

[pgbouncer]
listen_addr = $PGBOUNCER_LISTEN_ADDRESS
listen_port = $PGBOUNCER_PORT
unix_socket_dir = $PGBOUNCER_TMP_DIR
auth_type = $PGBOUNCER_AUTH_TYPE
auth_file = $PGBOUNCER_AUTH_FILE
EOF

    # Auth query (for database-based authentication)
    if [[ -n "$PGBOUNCER_AUTH_QUERY" ]]; then
        printf 'auth_query = %s\n' "$PGBOUNCER_AUTH_QUERY" >> "$config_file"
    fi

    if [[ -n "$PGBOUNCER_AUTH_USER" ]]; then
        printf 'auth_user = %s\n' "$PGBOUNCER_AUTH_USER" >> "$config_file"
    fi

    if [[ -n "$PGBOUNCER_AUTH_HBA_FILE" ]]; then
        printf 'auth_hba_file = %s\n' "$PGBOUNCER_AUTH_HBA_FILE" >> "$config_file"
    fi

    # Pool settings
    cat >> "$config_file" << EOF

; Pool settings
pool_mode = $PGBOUNCER_POOL_MODE
default_pool_size = $PGBOUNCER_DEFAULT_POOL_SIZE
min_pool_size = $PGBOUNCER_MIN_POOL_SIZE
reserve_pool_size = $PGBOUNCER_RESERVE_POOL_SIZE
reserve_pool_timeout = $PGBOUNCER_RESERVE_POOL_TIMEOUT
max_client_conn = $PGBOUNCER_MAX_CLIENT_CONN
max_db_connections = $PGBOUNCER_MAX_DB_CONNECTIONS
max_user_connections = $PGBOUNCER_MAX_USER_CONNECTIONS

; Timeout settings
query_timeout = $PGBOUNCER_QUERY_TIMEOUT
query_wait_timeout = $PGBOUNCER_QUERY_WAIT_TIMEOUT
client_idle_timeout = $PGBOUNCER_CLIENT_IDLE_TIMEOUT
client_login_timeout = $PGBOUNCER_CLIENT_LOGIN_TIMEOUT
server_idle_timeout = $PGBOUNCER_SERVER_IDLE_TIMEOUT
server_lifetime = $PGBOUNCER_SERVER_LIFETIME
server_connect_timeout = $PGBOUNCER_SERVER_CONNECT_TIMEOUT
server_login_retry = $PGBOUNCER_SERVER_LOGIN_RETRY
idle_transaction_timeout = $PGBOUNCER_IDLE_TRANSACTION_TIMEOUT

; Logging
logfile = $PGBOUNCER_LOG_FILE
pidfile = $PGBOUNCER_PID_FILE
log_connections = $PGBOUNCER_LOG_CONNECTIONS
log_disconnections = $PGBOUNCER_LOG_DISCONNECTIONS
log_pooler_errors = $PGBOUNCER_LOG_POOLER_ERRORS
stats_period = $PGBOUNCER_STATS_PERIOD
verbose = $PGBOUNCER_VERBOSE

; Low-level settings
server_reset_query = $PGBOUNCER_SERVER_RESET_QUERY
server_reset_query_always = $PGBOUNCER_SERVER_RESET_QUERY_ALWAYS
server_check_query = $PGBOUNCER_SERVER_CHECK_QUERY
server_check_delay = $PGBOUNCER_SERVER_CHECK_DELAY
server_fast_close = $PGBOUNCER_SERVER_FAST_CLOSE
server_round_robin = $PGBOUNCER_SERVER_ROUND_ROBIN
application_name_add_host = $PGBOUNCER_APPLICATION_NAME_ADD_HOST
ignore_startup_parameters = $PGBOUNCER_IGNORE_STARTUP_PARAMETERS
disable_pqexec = $PGBOUNCER_DISABLE_PQEXEC

; TCP settings
so_reuseport = $PGBOUNCER_SO_REUSEPORT
tcp_keepalive = $PGBOUNCER_TCP_KEEPALIVE
tcp_keepcnt = $PGBOUNCER_TCP_KEEPCNT
tcp_keepidle = $PGBOUNCER_TCP_KEEPIDLE
tcp_keepintvl = $PGBOUNCER_TCP_KEEPINTVL
tcp_user_timeout = $PGBOUNCER_TCP_USER_TIMEOUT

; Admin access
admin_users = $POSTGRESQL_USERNAME
stats_users = ${PGBOUNCER_STATS_USERS:-$POSTGRESQL_USERNAME}
EOF

    # Client TLS
    if [[ "$PGBOUNCER_CLIENT_TLS_SSLMODE" != "disable" ]]; then
        cat >> "$config_file" << EOF

; Client TLS
client_tls_sslmode = $PGBOUNCER_CLIENT_TLS_SSLMODE
client_tls_cert_file = $PGBOUNCER_CLIENT_TLS_CERT_FILE
client_tls_key_file = $PGBOUNCER_CLIENT_TLS_KEY_FILE
EOF
        if [[ -n "$PGBOUNCER_CLIENT_TLS_CA_FILE" ]]; then
            printf 'client_tls_ca_file = %s\n' "$PGBOUNCER_CLIENT_TLS_CA_FILE" >> "$config_file"
        fi
        printf 'client_tls_protocols = %s\n' "$PGBOUNCER_CLIENT_TLS_PROTOCOLS" >> "$config_file"
        printf 'client_tls_ciphers = %s\n' "$PGBOUNCER_CLIENT_TLS_CIPHERS" >> "$config_file"
        printf 'client_tls_dheparams = %s\n' "$PGBOUNCER_CLIENT_TLS_DHEPARAMS" >> "$config_file"
        printf 'client_tls_ecdhcurve = %s\n' "$PGBOUNCER_CLIENT_TLS_ECDHCURVE" >> "$config_file"
    fi

    # Server TLS
    if [[ "$PGBOUNCER_SERVER_TLS_SSLMODE" != "disable" ]]; then
        cat >> "$config_file" << EOF

; Server TLS
server_tls_sslmode = $PGBOUNCER_SERVER_TLS_SSLMODE
EOF
        if [[ -n "$PGBOUNCER_SERVER_TLS_CERT_FILE" ]]; then
            printf 'server_tls_cert_file = %s\n' "$PGBOUNCER_SERVER_TLS_CERT_FILE" >> "$config_file"
        fi
        if [[ -n "$PGBOUNCER_SERVER_TLS_KEY_FILE" ]]; then
            printf 'server_tls_key_file = %s\n' "$PGBOUNCER_SERVER_TLS_KEY_FILE" >> "$config_file"
        fi
        if [[ -n "$PGBOUNCER_SERVER_TLS_CA_FILE" ]]; then
            printf 'server_tls_ca_file = %s\n' "$PGBOUNCER_SERVER_TLS_CA_FILE" >> "$config_file"
        fi
        printf 'server_tls_protocols = %s\n' "$PGBOUNCER_SERVER_TLS_PROTOCOLS" >> "$config_file"
        printf 'server_tls_ciphers = %s\n' "$PGBOUNCER_SERVER_TLS_CIPHERS" >> "$config_file"
    fi

    log_info "Configuration file created at $config_file"
}

########################
# Copy mounted config files
########################
pgbouncer_copy_mounted_config() {
    if [[ -d "$PGBOUNCER_MOUNTED_CONF_DIR" ]]; then
        log_info "Copying mounted configuration files..."

        if [[ -f "$PGBOUNCER_MOUNTED_CONF_DIR/pgbouncer.ini" ]]; then
            cp "$PGBOUNCER_MOUNTED_CONF_DIR/pgbouncer.ini" "$PGBOUNCER_CONF_FILE"
            chmod 600 "$PGBOUNCER_CONF_FILE"
            log_info "Copied custom pgbouncer.ini"
        fi

        if [[ -f "$PGBOUNCER_MOUNTED_CONF_DIR/userlist.txt" ]]; then
            cp "$PGBOUNCER_MOUNTED_CONF_DIR/userlist.txt" "$PGBOUNCER_AUTH_FILE"
            chmod 600 "$PGBOUNCER_AUTH_FILE"
            log_info "Copied custom userlist.txt"
        fi

        if [[ -f "$PGBOUNCER_MOUNTED_CONF_DIR/hba.conf" ]]; then
            cp "$PGBOUNCER_MOUNTED_CONF_DIR/hba.conf" "$PGBOUNCER_CONF_DIR/hba.conf"
            chmod 600 "$PGBOUNCER_CONF_DIR/hba.conf"
            export PGBOUNCER_AUTH_HBA_FILE="$PGBOUNCER_CONF_DIR/hba.conf"
            log_info "Copied custom hba.conf"
        fi
    fi
}

########################
# Wait for PostgreSQL to be available
########################
pgbouncer_wait_for_postgresql() {
    local retries="${PGBOUNCER_INIT_MAX_RETRIES}"
    local sleep_time="${PGBOUNCER_INIT_SLEEP_TIME}"

    log_info "Waiting for PostgreSQL at $POSTGRESQL_HOST:$POSTGRESQL_PORT..."

    for ((i=1; i<=retries; i++)); do
        if pg_isready -h "$POSTGRESQL_HOST" -p "$POSTGRESQL_PORT" -U "$POSTGRESQL_USERNAME" -d "$POSTGRESQL_DATABASE" -q 2>/dev/null; then
            log_info "PostgreSQL is ready"
            return 0
        fi
        log_info "PostgreSQL not ready yet (attempt $i/$retries), waiting ${sleep_time}s..."
        sleep "$sleep_time"
    done

    log_warn "PostgreSQL may not be available, but continuing anyway..."
    return 0
}

########################
# Initialize PgBouncer
########################
pgbouncer_initialize() {
    log_info "Initializing PgBouncer..."

    # Load secrets from files
    pgbouncer_load_secrets

    # Validate configuration
    pgbouncer_validate || return 1

    # Copy any mounted config files first
    pgbouncer_copy_mounted_config

    # Only generate config if not provided externally
    if [[ ! -f "$PGBOUNCER_CONF_FILE" ]]; then
        pgbouncer_create_auth_file
        pgbouncer_create_config
    else
        log_info "Using externally provided configuration file"
    fi

    # Wait for PostgreSQL (optional, non-blocking)
    pgbouncer_wait_for_postgresql

    # Security: Clear password from environment after config is written
    unset POSTGRESQL_PASSWORD

    log_info "PgBouncer initialized successfully"
}

########################
# Enable NSS wrapper for non-root users
########################
pgbouncer_enable_nss_wrapper() {
    if [[ "$(id -u)" -ne 0 ]]; then
        local nss_wrapper_passwd="$PGBOUNCER_TMP_DIR/passwd"
        local nss_wrapper_group="$PGBOUNCER_TMP_DIR/group"

        if ! getent passwd "$(id -u)" &>/dev/null; then
            printf 'blackbox:x:%s:%s:Blackbox:%s:/bin/bash\n' "$(id -u)" "$(id -g)" "$PGBOUNCER_BASE_DIR" > "$nss_wrapper_passwd"
            printf 'blackbox:x:%s:\n' "$(id -g)" > "$nss_wrapper_group"

            # Find NSS wrapper library (architecture-independent)
            local nss_lib
            nss_lib=$(find /usr/lib* -name "libnss_wrapper.so" 2>/dev/null | head -1)
            if [[ -n "$nss_lib" ]]; then
                export LD_PRELOAD="$nss_lib"
                export NSS_WRAPPER_PASSWD="$nss_wrapper_passwd"
                export NSS_WRAPPER_GROUP="$nss_wrapper_group"
            else
                log_warn "libnss_wrapper.so not found, NSS wrapper disabled"
            fi
        fi
    fi
}
