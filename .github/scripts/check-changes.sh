#!/usr/bin/env bash
set -euo pipefail

# Check if versions.env has changed and set GitHub Actions output

if git diff --quiet versions.env 2>/dev/null; then
    echo "changed=false" >> "$GITHUB_OUTPUT"
    echo "No version changes detected"
else
    echo "changed=true" >> "$GITHUB_OUTPUT"
    echo "Version changes detected:"
    git diff versions.env || true
fi
