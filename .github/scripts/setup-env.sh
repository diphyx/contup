#!/usr/bin/env bash
set -euo pipefail

# Install build dependencies and set cross-compile environment
# Usage: setup-env.sh <arch>

ARCH="${1:?Usage: setup-env.sh <amd64|arm64>}"

echo "==> Installing build dependencies..."

sudo apt-get update
sudo apt-get install -y \
    build-essential cmake meson ninja-build pkg-config \
    libseccomp-dev libseccomp2 musl-tools \
    autoconf automake libtool \
    libcap-dev libsystemd-dev libyajl-dev go-md2man \
    libglib2.0-dev libslirp-dev libfuse3-dev protobuf-compiler

if [[ "$ARCH" == "arm64" ]]; then
    echo "  Installing arm64 cross-compile toolchain..."
    sudo dpkg --add-architecture arm64
    sudo apt-get update
    sudo apt-get install -y \
        gcc-aarch64-linux-gnu g++-aarch64-linux-gnu libc6-dev-arm64-cross \
        libseccomp-dev:arm64 libyajl-dev:arm64 libglib2.0-dev:arm64 \
        libslirp-dev:arm64 libfuse3-dev:arm64
fi

echo "==> Setting build environment for ${ARCH}..."

if [[ "$ARCH" == "arm64" ]]; then
    echo "CC=aarch64-linux-gnu-gcc" >> "$GITHUB_ENV"
    echo "CXX=aarch64-linux-gnu-g++" >> "$GITHUB_ENV"
    echo "GOARCH=arm64" >> "$GITHUB_ENV"
    echo "CARGO_TARGET=aarch64-unknown-linux-musl" >> "$GITHUB_ENV"
    echo "CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=aarch64-linux-gnu-gcc" >> "$GITHUB_ENV"
else
    echo "GOARCH=amd64" >> "$GITHUB_ENV"
    echo "CARGO_TARGET=x86_64-unknown-linux-musl" >> "$GITHUB_ENV"
fi

echo "==> Done"
