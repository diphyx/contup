#!/usr/bin/env bash
set -euo pipefail

# Find the contup tarball in the artifacts directory
# Exports TARBALL to GITHUB_ENV

TARBALL=$(ls artifacts/contup-*.tar.gz 2>/dev/null | head -1)

if [[ -z "$TARBALL" ]]; then
    echo "Error: No tarball found in artifacts/"
    exit 1
fi

echo "TARBALL=${TARBALL}" >> "$GITHUB_ENV"
echo "==> Found tarball: ${TARBALL}"
