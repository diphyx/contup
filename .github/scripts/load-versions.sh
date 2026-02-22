#!/usr/bin/env bash
set -euo pipefail

# Load versions.env into GitHub Actions environment

if [[ ! -f versions.env ]]; then
    echo "::error::versions.env not found. Run versions.yml workflow first."
    exit 1
fi

echo "==> Loading versions.env..."

while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
    line="${line%%#*}"
    line="${line%"${line##*[! ]}"}"
    echo "$line" >> "$GITHUB_ENV"
    echo "  ${line}"
done < versions.env

echo "==> Done"
