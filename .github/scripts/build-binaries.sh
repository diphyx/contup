#!/usr/bin/env bash
set -euo pipefail

# Build all container runtime binaries from source
# Requires: versions.env loaded into environment, GOARCH and CARGO_TARGET set

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

download_release() {
    local org_repo="$1" tag="$2" asset="$3" dest="$4"
    local url="https://github.com/${org_repo}/releases/download/${tag}/${asset}"
    local tarball="/tmp/${asset}"

    echo "    Downloading ${url}..."
    curl -fSL -o "$tarball" "$url"
    mkdir -p "$dest"
    tar -xzf "$tarball" --strip-components=1 -C "$dest"
    rm -f "$tarball"
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

echo "==> Building Docker stack..."

# docker CLI
echo "  Building docker CLI..."
download_source docker/cli "$DOCKER_VERSION" /tmp/docker-cli
cd /tmp/docker-cli
ln -s vendor.mod go.mod
ln -s vendor.sum go.sum
DOCKER_GITCOMMIT=$(get_commit_sha docker/cli "$DOCKER_VERSION")
CGO_ENABLED=0 GOOS=linux go build -mod=vendor \
    -ldflags "-X github.com/docker/cli/cli/version.Version=${DOCKER_VERSION#v} -X github.com/docker/cli/cli/version.GitCommit=${DOCKER_GITCOMMIT}" \
    -o docker ./cmd/docker

# dockerd + docker-proxy
echo "  Building dockerd + docker-proxy..."
download_source moby/moby "docker-${DOCKER_VERSION}" /tmp/moby
cd /tmp/moby
MOBY_GITCOMMIT=$(get_commit_sha moby/moby "docker-${DOCKER_VERSION}")
GOOS=linux go build -mod=vendor \
    -ldflags "-X github.com/docker/docker/dockerversion.Version=${DOCKER_VERSION#v} -X github.com/docker/docker/dockerversion.GitCommit=${MOBY_GITCOMMIT}" \
    -o dockerd ./cmd/dockerd
CGO_ENABLED=0 GOOS=linux go build -mod=vendor -o docker-proxy ./cmd/docker-proxy

# containerd + shim
echo "  Building containerd..."
download_source containerd/containerd "$CONTAINERD_VERSION" /tmp/containerd
cd /tmp/containerd
CGO_ENABLED=0 GOOS=linux go build -mod=vendor -o bin/containerd ./cmd/containerd
CGO_ENABLED=0 GOOS=linux go build -mod=vendor -o bin/containerd-shim-runc-v2 ./cmd/containerd-shim-runc-v2

# runc
echo "  Building runc..."
download_source opencontainers/runc "$RUNC_VERSION" /tmp/runc
init_git_tag /tmp/runc "$RUNC_VERSION"
cd /tmp/runc
make static

# docker-init (tini)
echo "  Building docker-init (tini)..."
download_source krallin/tini "$TINI_VERSION" /tmp/tini
cd /tmp/tini
cmake_args="-DCMAKE_BUILD_TYPE=Release"
if [[ "${CC:-}" == *aarch64* ]]; then
    cmake_args+=" -DCMAKE_C_COMPILER=${CC} -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64"
fi
cmake $cmake_args .
make tini-static
cp tini-static docker-init

# rootlesskit
echo "  Building rootlesskit..."
download_source rootless-containers/rootlesskit "$ROOTLESSKIT_VERSION" /tmp/rootlesskit
cd /tmp/rootlesskit
CGO_ENABLED=0 GOOS=linux go build -o rootlesskit ./cmd/rootlesskit

# dockerd-rootless.sh
echo "  Copying dockerd-rootless.sh..."
cp /tmp/moby/contrib/dockerd-rootless.sh /tmp/dockerd-rootless.sh
chmod +x /tmp/dockerd-rootless.sh

# docker-compose
echo "==> Building Docker Compose..."
download_source docker/compose "$COMPOSE_VERSION" /tmp/compose
cd /tmp/compose
CGO_ENABLED=0 GOOS=linux go build -trimpath -o docker-compose ./cmd

echo "==> Building Podman stack..."

# podman
echo "  Building podman..."
download_source containers/podman "$PODMAN_VERSION" /tmp/podman
cd /tmp/podman
CGO_ENABLED=0 GOOS=linux go build -mod=vendor \
    -tags "remote exclude_graphdriver_btrfs btrfs_noversion exclude_graphdriver_devicemapper containers_image_openpgp" \
    -o bin/podman ./cmd/podman

# crun
echo "  Building crun..."
download_release containers/crun "$CRUN_VERSION" "crun-${CRUN_VERSION}.tar.gz" /tmp/crun
cd /tmp/crun
configure_args="--enable-static"
if [[ "${CC:-}" == *aarch64* ]]; then
    configure_args+=" --host=aarch64-linux-gnu"
fi
./configure $configure_args
make

# conmon
echo "  Building conmon..."
download_source containers/conmon "$CONMON_VERSION" /tmp/conmon
init_git_tag /tmp/conmon "$CONMON_VERSION"
cd /tmp/conmon
make CC="${CC:-gcc}" PKG_CONFIG='pkg-config --static' CFLAGS='-static' LDFLAGS='-static' DISABLE_SYSTEMD=1

# netavark
echo "  Building netavark..."
download_source containers/netavark "$NETAVARK_VERSION" /tmp/netavark
cd /tmp/netavark
cargo build --release --target "$CARGO_TARGET"
cp "target/${CARGO_TARGET}/release/netavark" netavark

# aardvark-dns
echo "  Building aardvark-dns..."
download_source containers/aardvark-dns "$AARDVARK_DNS_VERSION" /tmp/aardvark-dns
cd /tmp/aardvark-dns
cargo build --release --target "$CARGO_TARGET"
cp "target/${CARGO_TARGET}/release/aardvark-dns" aardvark-dns

# slirp4netns
echo "  Building slirp4netns..."
download_source rootless-containers/slirp4netns "$SLIRP4NETNS_VERSION" /tmp/slirp4netns
init_git_tag /tmp/slirp4netns "$SLIRP4NETNS_VERSION"
cd /tmp/slirp4netns
./autogen.sh
configure_args=""
if [[ "${CC:-}" == *aarch64* ]]; then
    configure_args="--host=aarch64-linux-gnu"
fi
LDFLAGS=-static ./configure $configure_args
make

# fuse-overlayfs
echo "  Building fuse-overlayfs..."
download_source containers/fuse-overlayfs "$FUSE_OVERLAYFS_VERSION" /tmp/fuse-overlayfs
init_git_tag /tmp/fuse-overlayfs "$FUSE_OVERLAYFS_VERSION"
cd /tmp/fuse-overlayfs
./autogen.sh
configure_args="CFLAGS=-static LDFLAGS=-static"
if [[ "${CC:-}" == *aarch64* ]]; then
    configure_args+=" --host=aarch64-linux-gnu"
fi
./configure $configure_args
make

echo "==> All binaries built"
