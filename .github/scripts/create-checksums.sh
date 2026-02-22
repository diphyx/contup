#!/usr/bin/env bash
set -euo pipefail

# Merge individual .sha256 files into a single checksums.txt

cd artifacts
cat *.sha256 > checksums.txt

echo "==> Checksums:"
cat checksums.txt
