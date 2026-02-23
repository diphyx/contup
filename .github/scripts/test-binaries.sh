#!/usr/bin/env bash
set -euo pipefail

# Quick smoke test for built binaries (runs in build job, amd64 only).
# Verifies daemons start and can run a container.
# Optional: RUNTIME=docker|podman|both (default: both)

RUNTIME="${RUNTIME:-both}"
COMPOSE="${COMPOSE:-true}"
BIN_DIR="/usr/local/bin"

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

# ─── Install Docker binaries ───

if [[ "$RUNTIME" != "podman" ]]; then
    echo "==> Installing Docker binaries..."
    cp /tmp/docker-cli/docker /tmp/moby/dockerd /tmp/moby/docker-proxy \
       /tmp/containerd/bin/containerd /tmp/containerd/bin/containerd-shim-runc-v2 \
       /tmp/runc/runc /tmp/tini/docker-init \
       /tmp/rootlesskit/rootlesskit /tmp/dockerd-rootless.sh \
       "$BIN_DIR/"
    chmod +x "$BIN_DIR"/{docker,dockerd,docker-proxy,containerd,containerd-shim-runc-v2,runc,docker-init}
    chmod +x "$BIN_DIR"/{rootlesskit,dockerd-rootless.sh}
fi

# ─── Install Compose binary ───

if [[ "$COMPOSE" != "false" ]]; then
    echo "==> Installing Compose binary..."
    cp /tmp/compose/docker-compose "$BIN_DIR/"
    chmod +x "$BIN_DIR"/docker-compose
fi

# ─── Install Podman binaries ───

if [[ "$RUNTIME" != "docker" ]]; then
    echo "==> Installing Podman binaries..."
    cp /tmp/podman/bin/podman /tmp/crun/crun /tmp/conmon/bin/conmon \
       /tmp/netavark/netavark /tmp/aardvark-dns/aardvark-dns \
       /tmp/slirp4netns/slirp4netns /tmp/fuse-overlayfs/fuse-overlayfs \
       "$BIN_DIR/"
    chmod +x "$BIN_DIR"/{podman,crun,conmon,netavark,aardvark-dns,slirp4netns,fuse-overlayfs}
fi

# ─── Configure Docker ───

if [[ "$RUNTIME" != "podman" ]]; then
    if [[ "$COMPOSE" != "false" ]]; then
        mkdir -p /usr/local/lib/docker/cli-plugins
        ln -sf "$BIN_DIR/docker-compose" /usr/local/lib/docker/cli-plugins/docker-compose
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

if [[ "$RUNTIME" != "docker" ]]; then
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

if [[ "$RUNTIME" != "podman" ]]; then
    echo "==> Testing Docker..."
    systemctl daemon-reload
    systemctl start containerd docker

    for i in $(seq 1 30); do docker info &>/dev/null && break; sleep 1; done

    run_test "docker run" docker run --rm hello-world
    if [[ "$COMPOSE" != "false" ]]; then
        run_test "docker compose" docker compose version
    fi

    docker system prune -af &>/dev/null || true
    systemctl stop docker containerd
fi

# ─── Test Podman ───

if [[ "$RUNTIME" != "docker" ]]; then
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
