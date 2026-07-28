#!/usr/bin/env bash
set -euo pipefail

# Bundle all built binaries into a release tarball
# Usage: bundle-tarball.sh <release-tag> <arch> [runtime]

RELEASE_TAG="${1:?Usage: bundle-tarball.sh <release-tag> <arch> [runtime]}"
ARCH="${2:?Usage: bundle-tarball.sh <release-tag> <arch> [runtime]}"
RUNTIME="${3:-both}"
COMPOSE="${4:-true}"
BUILDX="${5:-true}"

BUNDLE="/tmp/dockpod-bundle"

echo "==> Bundling dockpod-${RELEASE_TAG}-${ARCH} (${RUNTIME})..."

mkdir -p "${BUNDLE}"

# Docker
if [[ "$RUNTIME" != "podman" ]]; then
mkdir -p "${BUNDLE}/docker" "${BUNDLE}/docker-rootless"
cp /tmp/docker-cli/docker                          "${BUNDLE}/docker/"
cp /tmp/moby/dockerd                               "${BUNDLE}/docker/"
cp /tmp/moby/docker-proxy                          "${BUNDLE}/docker/"
cp /tmp/containerd/bin/containerd                  "${BUNDLE}/docker/"
cp /tmp/containerd/bin/containerd-shim-runc-v2     "${BUNDLE}/docker/"
cp /tmp/runc/runc                                  "${BUNDLE}/docker/"
cp /tmp/tini/docker-init                           "${BUNDLE}/docker/"

# Docker rootless
cp /tmp/rootlesskit/rootlesskit                    "${BUNDLE}/docker-rootless/"
cp /tmp/dockerd-rootless.sh                        "${BUNDLE}/docker-rootless/"
cp /tmp/slirp4netns/slirp4netns                    "${BUNDLE}/docker-rootless/"
fi

# Buildx
if [[ "$RUNTIME" != "podman" && "$BUILDX" != "false" ]]; then
mkdir -p "${BUNDLE}/buildx"
cp /tmp/buildx/docker-buildx                       "${BUNDLE}/buildx/"
fi

# Compose
if [[ "$COMPOSE" != "false" ]]; then
mkdir -p "${BUNDLE}/compose"
cp /tmp/compose/docker-compose                     "${BUNDLE}/compose/"
fi

# Podman
if [[ "$RUNTIME" != "docker" ]]; then
mkdir -p "${BUNDLE}/podman"
cp /tmp/podman/bin/podman                          "${BUNDLE}/podman/"
cp /tmp/crun/crun                                  "${BUNDLE}/podman/"
cp /tmp/conmon/bin/conmon                          "${BUNDLE}/podman/"
cp /tmp/netavark/netavark                          "${BUNDLE}/podman/"
cp /tmp/aardvark-dns/aardvark-dns                  "${BUNDLE}/podman/"
cp /tmp/slirp4netns/slirp4netns                    "${BUNDLE}/podman/"
cp /tmp/fuse-overlayfs/fuse-overlayfs               "${BUNDLE}/podman/"
fi

# dockpod.sh
cp dockpod.sh "${BUNDLE}/"

# Strip binaries
echo "  Stripping binaries..."
STRIP_CMD="strip"
if [[ "$ARCH" == "arm64" ]]; then
    STRIP_CMD="aarch64-linux-gnu-strip"
fi
find "${BUNDLE}" -type f -executable ! -name "*.sh" -exec $STRIP_CMD {} \; 2>/dev/null || true

# Create tarball
TARBALL="dockpod-${RELEASE_TAG}-${ARCH}.tar.gz"
TARBALL_DIR="dockpod-${RELEASE_TAG}-${ARCH}"
cd /tmp
mv dockpod-bundle "$TARBALL_DIR"
tar -czf "${TARBALL}" "$TARBALL_DIR"

# Checksum
sha256sum "${TARBALL}" > "${TARBALL}.sha256"

echo "  Tarball:  /tmp/${TARBALL}"
echo "  Checksum: /tmp/${TARBALL}.sha256"

# Export for GitHub Actions
if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "TARBALL=/tmp/${TARBALL}" >> "$GITHUB_ENV"
    echo "CHECKSUM=/tmp/${TARBALL}.sha256" >> "$GITHUB_ENV"
fi

echo "==> Done"
