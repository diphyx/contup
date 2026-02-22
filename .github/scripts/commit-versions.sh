#!/usr/bin/env bash
set -euo pipefail

# Commit and push updated versions.env

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add versions.env
git commit -m "chore: update versions.env"
git push

echo "==> Committed and pushed versions.env"
