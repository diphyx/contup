#!/usr/bin/env bash
set -euo pipefail

# Build container runtime binaries from source, or download pre-built
# static binaries from GitHub releases when available.
# Requires: versions.env loaded into environment, GOARCH and CARGO_TARGET set
# Optional: COMPONENT=<name>|all  build a single component (default: all)
#           RUNTIME=docker|podman|both  (default: both, COMPONENT=all only)
#           COMPOSE / BUILDX=true|false (default: true, COMPONENT=all only)

COMPONENT="${COMPONENT:-all}"
RUNTIME="${RUNTIME:-both}"
COMPOSE="${COMPOSE:-true}"
BUILDX="${BUILDX:-true}"

download_source() {
    local org_repo="$1" tag="$2" dest="$3"
    local url="https://github.com/${org_repo}/archive/refs/tags/${tag}.tar.gz"
    local tarball="/tmp/$(echo "${org_repo}" | tr '/' '-')-${tag}.tar.gz"

    echo "    Downloading ${url}..."
    curl -fSL -o "$tarball" "$url"
    mkdir -p "$dest"
    tar -xzf "$tarball" --strip-components=1 -C "$dest"
    rm -f "$tarball"
}

download_binary() {
    local org_repo="$1" tag="$2" asset="$3" dest="$4"
    local url="https://github.com/${org_repo}/releases/download/${tag}/${asset}"

    echo "    Downloading ${url}..."
    curl -fSL -o "$dest" "$url"
    chmod +x "$dest"
}

init_git_tag() {
    local dest="$1" tag="$2"

    git -C "$dest" init -q
    git -C "$dest" add -A
    git -C "$dest" -c user.name=build -c user.email=build commit -q -m "$tag"
    git -C "$dest" tag "$tag"
}

get_commit_sha() {
    local org_repo="$1" tag="$2"
    local ref_json sha type
    local -a auth=()

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi

    ref_json=$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/${org_repo}/git/ref/tags/${tag}")
    sha=$(echo "$ref_json" | grep -o '"sha":"[^"]*"' | head -1 | cut -d'"' -f4)
    type=$(echo "$ref_json" | grep -o '"type":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [[ "$type" == "tag" ]]; then
        sha=$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/${org_repo}/git/tags/${sha}" \
            | grep -o '"sha":"[^"]*"' | tail -1 | cut -d'"' -f4)
    fi

    echo "${sha:0:7}"
}

# Set pkg-config search path for arm64 cross-compilation
if [[ "${CC:-}" == *aarch64* ]]; then
    export PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig
fi

# Map GOARCH to arch names used by release binaries
if [[ "${GOARCH:-amd64}" == "arm64" ]]; then
    CRUN_ARCH="linux-arm64"
    UNAME_ARCH="aarch64"
else
    CRUN_ARCH="linux-amd64"
    UNAME_ARCH="x86_64"
fi

# ─── Docker stack ───

build_docker_cli() {
    echo "  Building docker CLI..."
    download_source docker/cli "$DOCKER_VERSION" /tmp/docker-cli
    cd /tmp/docker-cli
    ln -s vendor.mod go.mod
    ln -s vendor.sum go.sum
    DOCKER_GITCOMMIT=$(get_commit_sha docker/cli "$DOCKER_VERSION")
    CGO_ENABLED=0 GOOS=linux go build -mod=vendor \
        -ldflags "-X github.com/docker/cli/cli/version.Version=${DOCKER_VERSION#v} -X github.com/docker/cli/cli/version.GitCommit=${DOCKER_GITCOMMIT}" \
        -o docker ./cmd/docker
}

build_moby() {
    echo "  Building dockerd + docker-proxy..."
    download_source moby/moby "docker-${DOCKER_VERSION}" /tmp/moby
    cd /tmp/moby
    MOBY_GITCOMMIT=$(get_commit_sha moby/moby "docker-${DOCKER_VERSION}")
    GOOS=linux go build -mod=vendor \
        -ldflags "-X github.com/docker/docker/dockerversion.Version=${DOCKER_VERSION#v} -X github.com/docker/docker/dockerversion.GitCommit=${MOBY_GITCOMMIT}" \
        -o dockerd ./cmd/dockerd
    CGO_ENABLED=0 GOOS=linux go build -mod=vendor -o docker-proxy ./cmd/docker-proxy

    echo "  Copying dockerd-rootless.sh..."
    cp /tmp/moby/contrib/dockerd-rootless.sh /tmp/dockerd-rootless.sh
    chmod +x /tmp/dockerd-rootless.sh
}

build_containerd() {
    echo "  Building containerd..."
    download_source containerd/containerd "$CONTAINERD_VERSION" /tmp/containerd
    cd /tmp/containerd
    CGO_ENABLED=0 GOOS=linux go build -mod=vendor -o bin/containerd ./cmd/containerd
    CGO_ENABLED=0 GOOS=linux go build -mod=vendor -o bin/containerd-shim-runc-v2 ./cmd/containerd-shim-runc-v2
}

build_runc() {
    echo "  Building runc..."
    download_source opencontainers/runc "$RUNC_VERSION" /tmp/runc
    init_git_tag /tmp/runc "$RUNC_VERSION"
    cd /tmp/runc
    make static
}

build_tini() {
    echo "  Building docker-init (tini)..."
    download_source krallin/tini "$TINI_VERSION" /tmp/tini
    cd /tmp/tini
    local cmake_args="-DCMAKE_BUILD_TYPE=Release"
    if [[ "${CC:-}" == *aarch64* ]]; then
        cmake_args+=" -DCMAKE_C_COMPILER=${CC} -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64"
    fi
    cmake $cmake_args .
    make tini-static
    cp tini-static docker-init
}

build_rootlesskit() {
    echo "  Building rootlesskit..."
    download_source rootless-containers/rootlesskit "$ROOTLESSKIT_VERSION" /tmp/rootlesskit
    cd /tmp/rootlesskit
    CGO_ENABLED=0 GOOS=linux go build -o rootlesskit ./cmd/rootlesskit
}

build_buildx() {
    echo "  Building buildx..."
    download_source docker/buildx "$BUILDX_VERSION" /tmp/buildx
    cd /tmp/buildx
    BUILDX_GITCOMMIT=$(get_commit_sha docker/buildx "$BUILDX_VERSION")
    CGO_ENABLED=0 GOOS=linux go build -mod=vendor -trimpath \
        -ldflags "-X github.com/docker/buildx/version.Version=${BUILDX_VERSION} -X github.com/docker/buildx/version.Revision=${BUILDX_GITCOMMIT}" \
        -o docker-buildx ./cmd/buildx
}

# ─── Compose ───

build_compose() {
    echo "  Building docker-compose..."
    download_source docker/compose "$COMPOSE_VERSION" /tmp/compose
    cd /tmp/compose
    local module
    module=$(head -1 go.mod | awk '{print $2}')
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags "-X ${module}/internal.Version=${COMPOSE_VERSION}" -o docker-compose ./cmd
}

# ─── Podman stack ───

build_podman() {
    echo "  Building podman..."
    download_source containers/podman "$PODMAN_VERSION" /tmp/podman
    cd /tmp/podman
    CGO_ENABLED=1 GOOS=linux go build -mod=vendor \
        -tags "osusergo netgo seccomp systemd libsqlite3 exclude_graphdriver_btrfs exclude_graphdriver_devicemapper containers_image_openpgp" \
        -ldflags '-s -w -extldflags "-static -lm"' \
        -o bin/podman ./cmd/podman
}

build_conmon() {
    echo "  Building conmon..."
    download_source containers/conmon "$CONMON_VERSION" /tmp/conmon
    init_git_tag /tmp/conmon "$CONMON_VERSION"
    cd /tmp/conmon
    sed -i 's/$(LIBS)$/-Wl,--start-group $(LIBS) -lcap -Wl,--end-group/' Makefile
    make CC="${CC:-gcc}" PKG_CONFIG='pkg-config --static' CFLAGS='-static' LDFLAGS='-static'
}

build_netavark() {
    echo "  Building netavark..."
    download_source containers/netavark "$NETAVARK_VERSION" /tmp/netavark
    cd /tmp/netavark
    cargo build --release --target "$CARGO_TARGET"
    cp "target/${CARGO_TARGET}/release/netavark" netavark
}

build_aardvark_dns() {
    echo "  Building aardvark-dns..."
    download_source containers/aardvark-dns "$AARDVARK_DNS_VERSION" /tmp/aardvark-dns
    cd /tmp/aardvark-dns
    cargo build --release --target "$CARGO_TARGET"
    cp "target/${CARGO_TARGET}/release/aardvark-dns" aardvark-dns
}

# ─── Pre-built static binaries ───

download_crun() {
    echo "  Downloading crun..."
    mkdir -p /tmp/crun
    download_binary containers/crun "$CRUN_VERSION" "crun-${CRUN_VERSION}-${CRUN_ARCH}" /tmp/crun/crun
}

download_slirp4netns() {
    echo "  Downloading slirp4netns..."
    mkdir -p /tmp/slirp4netns
    download_binary rootless-containers/slirp4netns "$SLIRP4NETNS_VERSION" "slirp4netns-${UNAME_ARCH}" /tmp/slirp4netns/slirp4netns
}

download_fuse_overlayfs() {
    echo "  Downloading fuse-overlayfs..."
    mkdir -p /tmp/fuse-overlayfs
    download_binary containers/fuse-overlayfs "${FUSE_OVERLAYFS_VERSION}" "fuse-overlayfs-${UNAME_ARCH}" /tmp/fuse-overlayfs/fuse-overlayfs
}

# ─── Dispatch ───

build_component() {
    case "$1" in
        docker-cli)     build_docker_cli ;;
        moby)           build_moby ;;
        containerd)     build_containerd ;;
        docker-extras)  build_runc; build_tini; build_rootlesskit; download_slirp4netns ;;
        buildx)         build_buildx ;;
        compose)        build_compose ;;
        podman)         build_podman ;;
        podman-extras)  download_crun; build_conmon; download_slirp4netns; download_fuse_overlayfs ;;
        podman-net)     build_netavark; build_aardvark_dns ;;
        *)              echo "::error::Unknown component: $1"; exit 1 ;;
    esac
}

if [[ "$COMPONENT" != "all" ]]; then
    echo "==> Building ${COMPONENT}..."
    build_component "$COMPONENT"
    echo "==> Done"
    exit 0
fi

if [[ "$RUNTIME" != "podman" ]]; then
    echo "==> Building Docker stack..."
    build_component docker-cli
    build_component moby
    build_component containerd
    build_component docker-extras
    if [[ "$BUILDX" != "false" ]]; then
        build_component buildx
    fi
fi

if [[ "$COMPOSE" != "false" ]]; then
    echo "==> Building Docker Compose..."
    build_component compose
fi

if [[ "$RUNTIME" != "docker" ]]; then
    echo "==> Building Podman stack..."
    build_component podman
    build_component podman-extras
    build_component podman-net
fi

echo "==> All binaries built"
