#!/usr/bin/env bash
set -euo pipefail

# Copy built binaries into the release bundle layout.
# Usage: stage-binaries.sh <component>|all [bundle-dir]
# Optional (all only): RUNTIME=docker|podman|both, COMPOSE / BUILDX=true|false

COMPONENT="${1:?Usage: stage-binaries.sh <component>|all [bundle-dir]}"
BUNDLE="${2:-/tmp/dockpod-bundle}"
RUNTIME="${RUNTIME:-both}"
COMPOSE="${COMPOSE:-true}"
BUILDX="${BUILDX:-true}"

stage() {
    local subdir="$1"
    shift
    mkdir -p "${BUNDLE}/${subdir}"
    cp "$@" "${BUNDLE}/${subdir}/"
    for f in "$@"; do
        echo "    ${subdir}/$(basename "$f")"
    done
}

stage_component() {
    case "$1" in
        docker-cli)
            stage docker /tmp/docker-cli/docker
            ;;
        moby)
            stage docker /tmp/moby/dockerd /tmp/moby/docker-proxy
            stage docker-rootless /tmp/dockerd-rootless.sh
            ;;
        containerd)
            stage docker /tmp/containerd/bin/containerd /tmp/containerd/bin/containerd-shim-runc-v2
            ;;
        docker-extras)
            stage docker /tmp/runc/runc /tmp/tini/docker-init
            stage docker-rootless /tmp/rootlesskit/rootlesskit /tmp/slirp4netns/slirp4netns
            ;;
        buildx)
            stage buildx /tmp/buildx/docker-buildx
            ;;
        compose)
            stage compose /tmp/compose/docker-compose
            ;;
        podman)
            stage podman /tmp/podman/bin/podman
            ;;
        podman-extras)
            stage podman /tmp/crun/crun /tmp/conmon/bin/conmon \
                /tmp/slirp4netns/slirp4netns /tmp/fuse-overlayfs/fuse-overlayfs
            ;;
        podman-net)
            stage podman /tmp/netavark/netavark /tmp/aardvark-dns/aardvark-dns
            ;;
        *)
            echo "::error::Unknown component: $1"
            exit 1
            ;;
    esac
}

echo "==> Staging ${COMPONENT} into ${BUNDLE}..."

mkdir -p "$BUNDLE"

if [[ "$COMPONENT" != "all" ]]; then
    stage_component "$COMPONENT"
    echo "==> Done"
    exit 0
fi

if [[ "$RUNTIME" != "podman" ]]; then
    stage_component docker-cli
    stage_component moby
    stage_component containerd
    stage_component docker-extras
    if [[ "$BUILDX" != "false" ]]; then
        stage_component buildx
    fi
fi

if [[ "$COMPOSE" != "false" ]]; then
    stage_component compose
fi

if [[ "$RUNTIME" != "docker" ]]; then
    stage_component podman
    stage_component podman-extras
    stage_component podman-net
fi

echo "==> Done"
