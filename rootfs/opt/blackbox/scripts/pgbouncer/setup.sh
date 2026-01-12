#!/bin/bash
# PgBouncer setup script
# Copyright Blackbox Tooling
# SPDX-License-Identifier: Apache-2.0

set -o errexit
set -o nounset
set -o pipefail

# shellcheck disable=SC1091
. /opt/blackbox/scripts/pgbouncer-env.sh
# shellcheck disable=SC1091
. /opt/blackbox/scripts/libpgbouncer.sh

log_info "Running PgBouncer setup..."

# Initialize PgBouncer (load secrets, validate, create config)
pgbouncer_initialize

log_info "PgBouncer setup completed"
