#!/usr/bin/env bash
set -euo pipefail

# Install build dependencies and set the build environment
# Usage: setup-env.sh <arch> [profile]
#
# Profiles:
#   full  — everything the C, Rust and CGO components need (default)
#   none  — pure Go (CGO_ENABLED=0) and download-only components

ARCH="${1:?Usage: setup-env.sh <amd64|arm64> [profile]}"
PROFILE="${2:-full}"

# Cross-compile only when the runner arch differs from the target arch.
# On a native arm64 runner everything builds with the stock toolchain.
CROSS=false
if [[ "$ARCH" == "arm64" && "$(uname -m)" != "aarch64" ]]; then
    CROSS=true
fi

if [[ "$PROFILE" == "none" ]]; then
    echo "==> No system dependencies required (profile: none)"
else
    echo "==> Installing build dependencies..."

    sudo apt-get update
    sudo apt-get install -y \
        build-essential cmake meson ninja-build pkg-config \
        libseccomp-dev libseccomp2 musl-tools \
        autoconf automake libtool \
        libcap-dev libsystemd-dev libyajl-dev go-md2man \
        libglib2.0-dev libslirp-dev libfuse3-dev libnftables-dev protobuf-compiler \
        libsqlite3-dev

    if [[ "$CROSS" == true ]]; then
        echo "  Installing arm64 cross-compile toolchain..."
        sudo dpkg --add-architecture arm64

        # Add ports.ubuntu.com for arm64 packages
        CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
        sudo tee /etc/apt/sources.list.d/arm64-ports.list >/dev/null <<PORTS
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports ${CODENAME} main restricted universe multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports ${CODENAME}-updates main restricted universe multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports ${CODENAME}-security main restricted universe multiverse
PORTS

        # Restrict existing sources to amd64 only
        if [[ -f /etc/apt/sources.list.d/ubuntu.sources ]]; then
            sudo sed -i '/^Architectures:/d; /^Types:/a Architectures: amd64' /etc/apt/sources.list.d/ubuntu.sources
        elif [[ -f /etc/apt/sources.list ]]; then
            sudo sed -i '/^deb http/s/^deb /deb [arch=amd64] /' /etc/apt/sources.list
        fi

        sudo apt-get update
        sudo apt-get install -y \
            gcc-aarch64-linux-gnu g++-aarch64-linux-gnu libc6-dev-arm64-cross \
            libseccomp-dev:arm64 libyajl-dev:arm64 libcap-dev:arm64 \
            libglib2.0-dev:arm64 libslirp-dev:arm64 libfuse3-dev:arm64 libnftables-dev:arm64 \
            libsqlite3-dev:arm64 libsystemd-dev:arm64
    fi
fi

echo "==> Setting build environment for ${ARCH}..."

if [[ "$ARCH" == "arm64" ]]; then
    echo "GOARCH=arm64" >> "$GITHUB_ENV"
    echo "CARGO_TARGET=aarch64-unknown-linux-musl" >> "$GITHUB_ENV"
    if [[ "$CROSS" == true ]]; then
        echo "CC=aarch64-linux-gnu-gcc" >> "$GITHUB_ENV"
        echo "CXX=aarch64-linux-gnu-g++" >> "$GITHUB_ENV"
        echo "CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=aarch64-linux-gnu-gcc" >> "$GITHUB_ENV"
    fi
else
    echo "GOARCH=amd64" >> "$GITHUB_ENV"
    echo "CARGO_TARGET=x86_64-unknown-linux-musl" >> "$GITHUB_ENV"
fi

echo "==> Done"
