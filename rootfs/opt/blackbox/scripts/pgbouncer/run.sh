#!/bin/bash
# PgBouncer run script
# Copyright Blackbox Tooling
# SPDX-License-Identifier: Apache-2.0

set -o errexit
set -o nounset
set -o pipefail

# shellcheck disable=SC1091
. /opt/blackbox/scripts/pgbouncer-env.sh
# shellcheck disable=SC1091
. /opt/blackbox/scripts/libpgbouncer.sh

log_info "Starting PgBouncer..."

# Run setup first
/opt/blackbox/scripts/pgbouncer/setup.sh

# Build command flags
declare -a flags=("$PGBOUNCER_CONF_FILE")

# Add extra flags if specified
if [[ -n "$PGBOUNCER_EXTRA_FLAGS" ]]; then
    read -r -a extra_flags <<< "$PGBOUNCER_EXTRA_FLAGS"
    flags+=("${extra_flags[@]}")
fi

# Add any command line arguments
flags+=("$@")

log_info "PgBouncer configuration:"
log_info "  - Listen: $PGBOUNCER_LISTEN_ADDRESS:$PGBOUNCER_PORT"
log_info "  - Pool mode: $PGBOUNCER_POOL_MODE"
log_info "  - Auth type: $PGBOUNCER_AUTH_TYPE"
log_info "  - Backend: $POSTGRESQL_HOST:$POSTGRESQL_PORT"

# Run PgBouncer in foreground (no daemon mode for container)
log_info "Launching PgBouncer..."
exec pgbouncer "${flags[@]}"
