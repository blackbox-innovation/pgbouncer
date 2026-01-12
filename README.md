# Blackbox PgBouncer

Connection pooler for PostgreSQL with Docker Secrets support.

## Quick Start

```yaml
services:
  pgbouncer:
    image: git.blackbox.ms:4567/blackbox-tooling/baseimages/pgbouncer:1.23
    environment:
      POSTGRESQL_HOST: postgres
      POSTGRESQL_PASSWORD: secret
    ports:
      - "6432:6432"
```

## Docker Secrets (Recommended for Production)

Use `_FILE` suffix to read values from mounted secrets:

```yaml
services:
  pgbouncer:
    image: git.blackbox.ms:4567/blackbox-tooling/baseimages/pgbouncer:1.23
    environment:
      POSTGRESQL_HOST_FILE: /run/secrets/pg_host
      POSTGRESQL_PORT_FILE: /run/secrets/pg_port
      POSTGRESQL_USERNAME_FILE: /run/secrets/pg_username
      POSTGRESQL_PASSWORD_FILE: /run/secrets/pg_password
      POSTGRESQL_DATABASE_FILE: /run/secrets/pg_database
      PGBOUNCER_POOL_MODE: transaction
    secrets:
      - pg_host
      - pg_port
      - pg_username
      - pg_password
      - pg_database
    ports:
      - "6432:6432"

secrets:
  pg_host:
    external: true
  pg_port:
    external: true
  pg_username:
    external: true
  pg_password:
    external: true
  pg_database:
    external: true
```

## Environment Variables

### PostgreSQL Backend

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRESQL_HOST` | `postgresql` | Backend hostname |
| `POSTGRESQL_PORT` | `5432` | Backend port |
| `POSTGRESQL_USERNAME` | `postgres` | Backend user |
| `POSTGRESQL_PASSWORD` | - | Backend password |
| `POSTGRESQL_DATABASE` | `postgres` | Backend database |

All support `_FILE` suffix for Docker Secrets.

### Connection & Pool

| Variable | Default | Description |
|----------|---------|-------------|
| `PGBOUNCER_PORT` | `6432` | Listen port |
| `PGBOUNCER_LISTEN_ADDRESS` | `0.0.0.0` | Listen address |
| `PGBOUNCER_DATABASE` | - | Exposed database name (defaults to `POSTGRESQL_DATABASE`) |
| `PGBOUNCER_POOL_MODE` | `transaction` | `session`, `transaction`, or `statement` |
| `PGBOUNCER_DEFAULT_POOL_SIZE` | `20` | Server connections per user/database |
| `PGBOUNCER_MIN_POOL_SIZE` | `0` | Minimum pool connections |
| `PGBOUNCER_RESERVE_POOL_SIZE` | `0` | Extra connections for burst |
| `PGBOUNCER_MAX_CLIENT_CONN` | `100` | Max client connections |
| `PGBOUNCER_MAX_DB_CONNECTIONS` | `0` | Max connections per database (0=unlimited) |

### Authentication

| Variable | Default | Description |
|----------|---------|-------------|
| `PGBOUNCER_AUTH_TYPE` | `scram-sha-256` | `trust`, `md5`, `scram-sha-256`, `cert`, `hba` |
| `PGBOUNCER_AUTH_USER` | - | User for auth_query |
| `PGBOUNCER_AUTH_QUERY` | - | SQL to fetch passwords |
| `PGBOUNCER_AUTH_HBA_FILE` | - | Path to pg_hba.conf style file |
| `PGBOUNCER_USERLIST` | - | Extra entries for userlist.txt |

### Timeouts

| Variable | Default | Description |
|----------|---------|-------------|
| `PGBOUNCER_QUERY_TIMEOUT` | `0` | Query execution timeout (0=disabled) |
| `PGBOUNCER_QUERY_WAIT_TIMEOUT` | `120` | Max time query waits for connection |
| `PGBOUNCER_CLIENT_IDLE_TIMEOUT` | `0` | Disconnect idle clients (0=disabled) |
| `PGBOUNCER_SERVER_IDLE_TIMEOUT` | `600` | Close idle server connections |
| `PGBOUNCER_SERVER_LIFETIME` | `3600` | Max server connection age |
| `PGBOUNCER_SERVER_CONNECT_TIMEOUT` | `15` | Backend connection timeout |
| `PGBOUNCER_IDLE_TRANSACTION_TIMEOUT` | `0` | Kill idle transactions (0=disabled) |

### Client TLS

| Variable | Default | Description |
|----------|---------|-------------|
| `PGBOUNCER_CLIENT_TLS_SSLMODE` | `disable` | `disable`, `allow`, `prefer`, `require`, `verify-ca`, `verify-full` |
| `PGBOUNCER_CLIENT_TLS_CERT_FILE` | - | Certificate file path |
| `PGBOUNCER_CLIENT_TLS_KEY_FILE` | - | Key file path |
| `PGBOUNCER_CLIENT_TLS_CA_FILE` | - | CA certificate path |

### Server TLS (to PostgreSQL)

| Variable | Default | Description |
|----------|---------|-------------|
| `PGBOUNCER_SERVER_TLS_SSLMODE` | `disable` | `disable`, `allow`, `prefer`, `require`, `verify-ca`, `verify-full` |
| `PGBOUNCER_SERVER_TLS_CERT_FILE` | - | Certificate file path |
| `PGBOUNCER_SERVER_TLS_KEY_FILE` | - | Key file path |
| `PGBOUNCER_SERVER_TLS_CA_FILE` | - | CA certificate path |

### Logging

| Variable | Default | Description |
|----------|---------|-------------|
| `PGBOUNCER_LOG_CONNECTIONS` | `1` | Log connects |
| `PGBOUNCER_LOG_DISCONNECTIONS` | `1` | Log disconnects |
| `PGBOUNCER_LOG_POOLER_ERRORS` | `1` | Log pooler errors |
| `PGBOUNCER_STATS_PERIOD` | `60` | Stats log interval (seconds) |
| `PGBOUNCER_VERBOSE` | `0` | Debug logging |

### Init

| Variable | Default | Description |
|----------|---------|-------------|
| `PGBOUNCER_INIT_MAX_RETRIES` | `10` | PostgreSQL connection retries |
| `PGBOUNCER_INIT_SLEEP_TIME` | `10` | Seconds between retries |
| `PGBOUNCER_EXTRA_FLAGS` | - | Additional pgbouncer flags |

## Multi-Backend Support

Use `PGBOUNCER_DSN_*` variables for multiple PostgreSQL backends:

```yaml
environment:
  PGBOUNCER_DSN_MAIN: "host=pg1.example.com port=5432 dbname=app"
  PGBOUNCER_DSN_REPLICA: "host=pg2.example.com port=5432 dbname=app"
  PGBOUNCER_DSN_ANALYTICS: "host=pg3.example.com port=5432 dbname=analytics"
```

Clients connect using database names `main`, `replica`, `analytics`.

## Custom Configuration

Mount custom config files to `/opt/blackbox/pgbouncer/mounted-conf/`:

```yaml
volumes:
  - ./pgbouncer.ini:/opt/blackbox/pgbouncer/mounted-conf/pgbouncer.ini:ro
  - ./userlist.txt:/opt/blackbox/pgbouncer/mounted-conf/userlist.txt:ro
  - ./hba.conf:/opt/blackbox/pgbouncer/mounted-conf/hba.conf:ro
```

## TLS Example

```yaml
services:
  pgbouncer:
    image: git.blackbox.ms:4567/blackbox-tooling/baseimages/pgbouncer:1.23
    environment:
      POSTGRESQL_HOST: postgres
      POSTGRESQL_PASSWORD: secret
      # Client TLS (incoming connections)
      PGBOUNCER_CLIENT_TLS_SSLMODE: require
      PGBOUNCER_CLIENT_TLS_CERT_FILE: /certs/server.crt
      PGBOUNCER_CLIENT_TLS_KEY_FILE: /certs/server.key
      # Server TLS (to PostgreSQL)
      PGBOUNCER_SERVER_TLS_SSLMODE: verify-full
      PGBOUNCER_SERVER_TLS_CA_FILE: /certs/ca.crt
    volumes:
      - ./certs:/certs:ro
```

## Healthcheck

```yaml
services:
  pgbouncer:
    # ...
    healthcheck:
      test: ["CMD", "pg_isready", "-h", "localhost", "-p", "6432"]
      interval: 10s
      timeout: 5s
      retries: 3
```

## Admin Console

Connect to pgbouncer admin database:

```bash
psql -h localhost -p 6432 -U postgres pgbouncer
```

Commands: `SHOW POOLS;`, `SHOW CLIENTS;`, `SHOW SERVERS;`, `SHOW STATS;`, `RELOAD;`, `PAUSE;`, `RESUME;`

## Security

- **Always use `_FILE` variants** for passwords in production (Docker Secrets)
- Secrets are read only from `/run/secrets/` or `/opt/blackbox/` directories
- Password environment variables are cleared after config generation
- Config files are created with `600` permissions
- Container runs as non-root user (uid 900)

## Container Details

- **Base**: `debian:bookworm-slim`
- **PgBouncer**: 1.18.x (Debian bookworm package)
- **User**: `blackbox` (uid:gid 900:900)
- **Timezone**: Europe/Berlin
- **Config dir**: `/opt/blackbox/pgbouncer/conf/`
- **Logs**: `/opt/blackbox/pgbouncer/logs/`
