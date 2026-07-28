#!/usr/bin/env bash
set -euo pipefail

# Quick smoke test for the staged binaries (runs in the bundle job, amd64 only).
# Verifies daemons start and can run a container.
# Usage: test-binaries.sh [bundle-dir]

BUNDLE="${1:-/tmp/dockpod-bundle}"
BIN_DIR="/usr/local/bin"
PLUGIN_DIR="/usr/local/lib/docker/cli-plugins"

pass=0
fail=0

ok()   { echo "  ✔  $1"; ((pass++)) || true; }
fail() { echo "  ✘  $1"; ((fail++)) || true; }

run_test() {
    local name="$1"; shift
    local output
    if output=$("$@" 2>&1); then
        ok "$name"
    else
        fail "$name"
        echo "$output" | sed 's/^/     /'
    fi
}

install_dir() {
    local subdir="$1"
    [[ -d "${BUNDLE}/${subdir}" ]] || return 0
    echo "==> Installing ${subdir} binaries..."
    local f
    for f in "${BUNDLE}/${subdir}"/*; do
        cp "$f" "$BIN_DIR/"
        chmod +x "${BIN_DIR}/$(basename "$f")"
    done
}

# ─── Install staged binaries ───

install_dir docker
install_dir docker-rootless
install_dir compose
install_dir buildx
install_dir podman

# ─── Configure Docker ───

if [[ -d "${BUNDLE}/docker" ]]; then
    mkdir -p "$PLUGIN_DIR"
    if [[ -f "${BIN_DIR}/docker-compose" ]]; then
        ln -sf "${BIN_DIR}/docker-compose" "${PLUGIN_DIR}/docker-compose"
    fi
    if [[ -f "${BIN_DIR}/docker-buildx" ]]; then
        ln -sf "${BIN_DIR}/docker-buildx" "${PLUGIN_DIR}/docker-buildx"
    fi

    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<'EOF'
{ "storage-driver": "overlay2" }
EOF

    cat > /etc/systemd/system/containerd.service <<EOF
[Unit]
Description=containerd
[Service]
ExecStart=${BIN_DIR}/containerd
Delegate=yes
KillMode=process
[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/docker.service <<EOF
[Unit]
Description=Docker
After=containerd.service
Requires=containerd.service
[Service]
ExecStart=${BIN_DIR}/dockerd
Delegate=yes
KillMode=process
[Install]
WantedBy=multi-user.target
EOF
fi

# ─── Configure Podman ───

if [[ -d "${BUNDLE}/podman" ]]; then
    mkdir -p /etc/containers
    cat > /etc/containers/containers.conf <<EOF
[engine]
helper_binaries_dir = ["${BIN_DIR}"]

[engine.runtimes]
crun = ["${BIN_DIR}/crun"]
EOF
    cat > /etc/containers/registries.conf <<'EOF'
unqualified-search-registries = ["docker.io"]
EOF
    cat > /etc/containers/storage.conf <<'EOF'
[storage]
driver = "overlay"
graphroot = "/var/lib/containers/storage"
EOF
    cat > /etc/containers/policy.json <<'EOF'
{ "default": [{ "type": "insecureAcceptAnything" }] }
EOF
fi

# ─── Test Docker ───

if [[ -d "${BUNDLE}/docker" ]]; then
    echo "==> Testing Docker..."
    systemctl daemon-reload
    systemctl start containerd docker

    for i in $(seq 1 30); do docker info &>/dev/null && break; sleep 1; done

    run_test "docker run" docker run --rm hello-world

    if [[ -f "${BIN_DIR}/docker-compose" ]]; then
        run_test "docker compose" docker compose version
    fi

    if [[ -f "${BIN_DIR}/docker-buildx" ]]; then
        mkdir -p /tmp/buildx-test
        cat > /tmp/buildx-test/Dockerfile <<'EOF'
FROM alpine
RUN echo "dockpod buildx ok"
EOF
        run_test "docker buildx build" docker buildx build -t dockpod-buildx-test /tmp/buildx-test
        rm -rf /tmp/buildx-test
    fi

    docker system prune -af &>/dev/null || true
    systemctl stop docker containerd
fi

# ─── Test Podman ───

if [[ -d "${BUNDLE}/podman" ]]; then
    echo "==> Testing Podman..."
    run_test "podman run" podman run --rm hello-world

    podman system prune -af &>/dev/null || true
fi

# ─── Summary ───

echo ""
total=$((pass + fail))
echo "==> Results: ${pass}/${total} passed"
if [[ $fail -gt 0 ]]; then echo "  ${fail} FAILED"; exit 1; fi
echo "==> All passed"
