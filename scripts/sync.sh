#!/usr/bin/env bash
# Sync the lineage-24.0 + WayDroid-ATV tree, retrying until repo sync succeeds.
set -uo pipefail
cd "$(dirname "$0")/../src"
attempt=0
until repo sync -c -j4 --no-tags --no-clone-bundle --retry-fetches=5 --force-sync --optimized-fetch; do
    attempt=$((attempt + 1))
    echo "=== repo sync failed (attempt $attempt), retrying in 30s: $(date -Is)"
    sleep 30
done
echo "=== repo sync finished after $attempt retries: $(date -Is)"
