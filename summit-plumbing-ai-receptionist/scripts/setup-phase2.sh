#!/usr/bin/env bash
# Runs all Phase 2 Field Service setup + seed data scripts, in order.
# Safe to rerun any time -- every script checks for existing records before creating.
#
# Usage: ./scripts/setup-phase2.sh [target-org-alias]

set -euo pipefail

ORG_ALIAS="${1:-summit-plumbing}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for f in \
  "01_operating_hours_and_territory.apex" \
  "02_service_resources.apex" \
  "03_work_types.apex" \
  "04_seed_customers.apex" \
  "05_seed_appointments.apex"
do
  echo "=== Running $f against org '$ORG_ALIAS' ==="
  sf apex run --file "$SCRIPT_DIR/apex/setup/$f" --target-org "$ORG_ALIAS"
  echo ""
done

echo "Phase 2 setup complete."
