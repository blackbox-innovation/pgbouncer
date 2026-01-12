#!/bin/bash
# PgBouncer container entrypoint
# Copyright Blackbox Tooling
# SPDX-License-Identifier: Apache-2.0

set -o errexit
set -o nounset
set -o pipefail

# shellcheck disable=SC1091
. /opt/blackbox/scripts/pgbouncer-env.sh
# shellcheck disable=SC1091
. /opt/blackbox/scripts/libpgbouncer.sh

echo ""
echo "=========================================="
echo "  Blackbox PgBouncer Container"
echo "=========================================="
echo ""

# Enable NSS wrapper for proper user resolution
pgbouncer_enable_nss_wrapper

# Run setup if this is the setup script
if [[ "$1" == "/opt/blackbox/scripts/pgbouncer/setup.sh" ]]; then
    log_info "** Starting PgBouncer setup **"
    /opt/blackbox/scripts/pgbouncer/setup.sh
    log_info "** PgBouncer setup finished! **"
fi

# Execute the command
exec "$@"
