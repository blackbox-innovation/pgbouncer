# Blackbox PgBouncer Base Image
# Connection pooler for PostgreSQL with Docker Secrets support
ARG PGBOUNCER_VERSION=1.23.1

FROM debian:bookworm-slim

ARG PGBOUNCER_VERSION

# Create blackbox user (uid:gid 900:900, consistent with other Blackbox images)
RUN groupadd -g 900 blackbox && \
    useradd -u 900 -g blackbox -s /bin/bash -m blackbox

# Install PgBouncer and dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    pgbouncer \
    postgresql-client \
    ca-certificates \
    libnss-wrapper \
    tzdata \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set timezone to Berlin
ENV TZ=Europe/Berlin
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Copy scripts
COPY rootfs/ /

# Make scripts executable
RUN chmod +x /opt/blackbox/scripts/pgbouncer/*.sh \
    && chmod +x /opt/blackbox/scripts/*.sh

# Setup directories with correct permissions
RUN mkdir -p /opt/blackbox/pgbouncer/conf \
             /opt/blackbox/pgbouncer/logs \
             /opt/blackbox/pgbouncer/tmp \
             /opt/blackbox/pgbouncer/certs \
    && chown -R 900:900 /opt/blackbox \
    && chown -R 900:900 /etc/pgbouncer \
    && chown -R 900:900 /var/log/postgresql \
    && chown -R 900:900 /var/run/postgresql

# Default environment variables
ENV PGBOUNCER_PORT=6432 \
    PGBOUNCER_LISTEN_ADDRESS=0.0.0.0 \
    PGBOUNCER_AUTH_TYPE=scram-sha-256 \
    PGBOUNCER_POOL_MODE=transaction \
    PGBOUNCER_DEFAULT_POOL_SIZE=20 \
    PGBOUNCER_MIN_POOL_SIZE=0 \
    PGBOUNCER_RESERVE_POOL_SIZE=0 \
    PGBOUNCER_MAX_CLIENT_CONN=100 \
    PGBOUNCER_MAX_DB_CONNECTIONS=0 \
    PGBOUNCER_IDLE_TRANSACTION_TIMEOUT=0 \
    PGBOUNCER_SERVER_IDLE_TIMEOUT=600 \
    PGBOUNCER_LOG_CONNECTIONS=1 \
    PGBOUNCER_LOG_DISCONNECTIONS=1 \
    PGBOUNCER_LOG_POOLER_ERRORS=1 \
    PGBOUNCER_STATS_PERIOD=60 \
    PGBOUNCER_CONF_DIR=/opt/blackbox/pgbouncer/conf \
    PGBOUNCER_LOG_DIR=/opt/blackbox/pgbouncer/logs \
    PGBOUNCER_TMP_DIR=/opt/blackbox/pgbouncer/tmp \
    PGBOUNCER_CERTS_DIR=/opt/blackbox/pgbouncer/certs \
    POSTGRESQL_HOST=postgresql \
    POSTGRESQL_PORT=5432 \
    POSTGRESQL_USERNAME=postgres \
    POSTGRESQL_DATABASE=postgres

EXPOSE 6432

USER blackbox
WORKDIR /opt/blackbox/pgbouncer

ENTRYPOINT ["/opt/blackbox/scripts/pgbouncer/entrypoint.sh"]
CMD ["/opt/blackbox/scripts/pgbouncer/run.sh"]

# Add labels for metadata
LABEL maintainer="Blackbox Tooling" \
      description="PgBouncer connection pooler with Docker Secrets support" \
      pgbouncer.version="${PGBOUNCER_VERSION}" \
      timezone="Europe/Berlin"
