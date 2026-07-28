#!/usr/bin/env bash
set -euo pipefail

# Strip the staged binaries and pack them into a release tarball.
# Binaries are placed in the bundle dir by stage-binaries.sh.
# Usage: bundle-tarball.sh <release-tag> <arch> [bundle-dir]

RELEASE_TAG="${1:?Usage: bundle-tarball.sh <release-tag> <arch> [bundle-dir]}"
ARCH="${2:?Usage: bundle-tarball.sh <release-tag> <arch> [bundle-dir]}"
BUNDLE="${3:-/tmp/dockpod-bundle}"

echo "==> Bundling dockpod-${RELEASE_TAG}-${ARCH}..."

if [[ ! -d "$BUNDLE" ]]; then
    echo "::error::Bundle directory not found: ${BUNDLE}"
    exit 1
fi

# dockpod.sh
cp dockpod.sh "${BUNDLE}/"

# Strip binaries — cross-strip only when the target arch differs from the host
echo "  Stripping binaries..."
STRIP_CMD="strip"
if [[ "$ARCH" == "arm64" && "$(uname -m)" != "aarch64" ]]; then
    STRIP_CMD="aarch64-linux-gnu-strip"
fi
find "${BUNDLE}" -type f -executable ! -name "*.sh" -exec $STRIP_CMD {} \; 2>/dev/null || true

# Create tarball
TARBALL="dockpod-${RELEASE_TAG}-${ARCH}.tar.gz"
TARBALL_DIR="dockpod-${RELEASE_TAG}-${ARCH}"
cd "$(dirname "$BUNDLE")"
mv "$(basename "$BUNDLE")" "$TARBALL_DIR"
tar -czf "${TARBALL}" "$TARBALL_DIR"

# Checksum
sha256sum "${TARBALL}" > "${TARBALL}.sha256"

echo "  Tarball:  $(pwd)/${TARBALL}"
echo "  Checksum: $(pwd)/${TARBALL}.sha256"

# Export for GitHub Actions
if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "TARBALL=$(pwd)/${TARBALL}" >> "$GITHUB_ENV"
    echo "CHECKSUM=$(pwd)/${TARBALL}.sha256" >> "$GITHUB_ENV"
fi

echo "==> Done"
