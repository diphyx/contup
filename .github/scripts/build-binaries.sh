#!/usr/bin/env bash
set -euo pipefail

# Build all container runtime binaries from source
# Requires: versions.env loaded into environment, GOARCH and CARGO_TARGET set

echo "==> Building Docker stack..."

# docker CLI
echo "  Building docker CLI..."
git clone --depth 1 --branch "$DOCKER_VERSION" https://github.com/docker/cli.git /tmp/docker-cli
cd /tmp/docker-cli
DOCKER_GITCOMMIT=$(git rev-parse --short HEAD)
CGO_ENABLED=0 GOOS=linux go build \
    -ldflags "-X github.com/docker/cli/cli/version.Version=${DOCKER_VERSION#v} -X github.com/docker/cli/cli/version.GitCommit=${DOCKER_GITCOMMIT}" \
    -o docker ./cmd/docker

# dockerd + docker-proxy
echo "  Building dockerd + docker-proxy..."
git clone --depth 1 --branch "$DOCKER_VERSION" https://github.com/moby/moby.git /tmp/moby
cd /tmp/moby
MOBY_GITCOMMIT=$(git rev-parse --short HEAD)
CGO_ENABLED=0 GOOS=linux go build \
    -ldflags "-X github.com/docker/docker/dockerversion.Version=${DOCKER_VERSION#v} -X github.com/docker/docker/dockerversion.GitCommit=${MOBY_GITCOMMIT}" \
    -o dockerd ./cmd/dockerd
CGO_ENABLED=0 GOOS=linux go build -o docker-proxy ./cmd/docker-proxy

# containerd + shim
echo "  Building containerd..."
git clone --depth 1 --branch "$CONTAINERD_VERSION" https://github.com/containerd/containerd.git /tmp/containerd
cd /tmp/containerd
CGO_ENABLED=0 GOOS=linux go build -o bin/containerd ./cmd/containerd
CGO_ENABLED=0 GOOS=linux go build -o bin/containerd-shim-runc-v2 ./cmd/containerd-shim-runc-v2

# runc
echo "  Building runc..."
git clone --depth 1 --branch "$RUNC_VERSION" https://github.com/opencontainers/runc.git /tmp/runc
cd /tmp/runc
make static

# docker-init (tini)
echo "  Building docker-init (tini)..."
git clone --depth 1 --branch "$TINI_VERSION" https://github.com/krallin/tini.git /tmp/tini
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
git clone --depth 1 --branch "$ROOTLESSKIT_VERSION" https://github.com/rootless-containers/rootlesskit.git /tmp/rootlesskit
cd /tmp/rootlesskit
CGO_ENABLED=0 GOOS=linux go build -o rootlesskit ./cmd/rootlesskit

# dockerd-rootless.sh
echo "  Copying dockerd-rootless.sh..."
cp /tmp/moby/contrib/dockerd-rootless.sh /tmp/dockerd-rootless.sh
chmod +x /tmp/dockerd-rootless.sh

echo "==> Building Docker Compose..."

git clone --depth 1 --branch "$COMPOSE_VERSION" https://github.com/docker/compose.git /tmp/compose
cd /tmp/compose
CGO_ENABLED=0 GOOS=linux go build -trimpath -o docker-compose ./cmd

echo "==> Building Podman stack..."

# podman
echo "  Building podman..."
git clone --depth 1 --branch "$PODMAN_VERSION" https://github.com/containers/podman.git /tmp/podman
cd /tmp/podman
CGO_ENABLED=0 GOOS=linux go build \
    -tags "remote exclude_graphdriver_btrfs btrfs_noversion exclude_graphdriver_devicemapper containers_image_openpgp" \
    -o bin/podman ./cmd/podman

# crun
echo "  Building crun..."
git clone --depth 1 --branch "$CRUN_VERSION" https://github.com/containers/crun.git /tmp/crun
cd /tmp/crun
./autogen.sh
configure_args="--enable-static"
if [[ "${CC:-}" == *aarch64* ]]; then
    configure_args+=" --host=aarch64-linux-gnu"
fi
./configure $configure_args
make

# conmon
echo "  Building conmon..."
git clone --depth 1 --branch "$CONMON_VERSION" https://github.com/containers/conmon.git /tmp/conmon
cd /tmp/conmon
make CC="${CC:-gcc}" PKG_CONFIG='pkg-config --static' CFLAGS='-static' LDFLAGS='-static'

# netavark
echo "  Building netavark..."
git clone --depth 1 --branch "$NETAVARK_VERSION" https://github.com/containers/netavark.git /tmp/netavark
cd /tmp/netavark
cargo build --release --target "$CARGO_TARGET"
cp "target/${CARGO_TARGET}/release/netavark" netavark

# aardvark-dns
echo "  Building aardvark-dns..."
git clone --depth 1 --branch "$AARDVARK_DNS_VERSION" https://github.com/containers/aardvark-dns.git /tmp/aardvark-dns
cd /tmp/aardvark-dns
cargo build --release --target "$CARGO_TARGET"
cp "target/${CARGO_TARGET}/release/aardvark-dns" aardvark-dns

# slirp4netns
echo "  Building slirp4netns..."
git clone --depth 1 --branch "$SLIRP4NETNS_VERSION" https://github.com/rootless-containers/slirp4netns.git /tmp/slirp4netns
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
git clone --depth 1 --branch "$FUSE_OVERLAYFS_VERSION" https://github.com/containers/fuse-overlayfs.git /tmp/fuse-overlayfs
cd /tmp/fuse-overlayfs
meson_args="-Ddefault_library=static"
if [[ "${CC:-}" == *aarch64* ]]; then
    cat > /tmp/meson-cross-aarch64.ini <<'MESON_CROSS'
[binaries]
c = 'aarch64-linux-gnu-gcc'
cpp = 'aarch64-linux-gnu-g++'
strip = 'aarch64-linux-gnu-strip'
pkgconfig = 'pkg-config'

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
MESON_CROSS
    meson_args+=" --cross-file /tmp/meson-cross-aarch64.ini"
fi
meson setup builddir $meson_args
ninja -C builddir

echo "==> All binaries built"
