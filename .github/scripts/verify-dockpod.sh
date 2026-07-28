#!/usr/bin/env bash
set -euo pipefail

# Integration test for the dockpod CLI.
# Exercises install, test, status, info, switch, stop, start, restart, uninstall.
# Must run as root on amd64.
# Usage: verify-dockpod.sh <path-to-tarball> <runtime>

TARBALL="${1:?Usage: verify-dockpod.sh <path-to-tarball> <runtime>}"
RUNTIME="${2:?Usage: verify-dockpod.sh <path-to-tarball> <runtime>}"

pass=0
fail=0

ok()   { echo "  ✔  $1"; ((pass++)) || true; }
fail() { echo "  ✘  $1"; ((fail++)) || true; }

run_step() {
    local label="$1"
    shift
    echo "==> ${label}..."
    if "$@"; then
        ok "$label"
    else
        fail "$label"
    fi
}

# ─── Extract tarball and setup dockpod ───

echo "==> Extracting ${TARBALL}..."
EXTRACT_DIR=$(mktemp -d /tmp/dockpod-extract.XXXXXX)
tar -xzf "$TARBALL" --strip-components=1 -C "$EXTRACT_DIR"

DOCKPOD="${EXTRACT_DIR}/dockpod.sh"
chmod +x "$DOCKPOD"

# ─── Install ───

# Buildx is opt-in and Docker-only
INSTALL_FLAGS=(-y)
if [[ "$RUNTIME" != "podman" ]]; then
    INSTALL_FLAGS+=(--with-buildx)
fi

run_step "dockpod install ${RUNTIME}" $DOCKPOD install "$RUNTIME" "${INSTALL_FLAGS[@]}"

if [[ "$RUNTIME" != "podman" ]]; then
    run_step "docker buildx version" docker buildx version
fi

# ─── Test ───

run_step "dockpod test ${RUNTIME}" $DOCKPOD test "$RUNTIME"

# ─── Status ───

run_step "dockpod status" $DOCKPOD status

# ─── Info ───

run_step "dockpod info" $DOCKPOD info

# ─── Stop ───

run_step "dockpod stop ${RUNTIME}" $DOCKPOD stop "$RUNTIME"

# ─── Start ───

run_step "dockpod start ${RUNTIME}" $DOCKPOD start "$RUNTIME"

# ─── Restart ───

run_step "dockpod restart ${RUNTIME}" $DOCKPOD restart "$RUNTIME"

# ─── Switch ───

run_step "dockpod switch ${RUNTIME}" $DOCKPOD switch "$RUNTIME"

# ─── Pre-uninstall cleanup (CI only: release overlay mounts) ───

if [[ "$RUNTIME" == "podman" || "$RUNTIME" == "both" ]]; then
    podman rm -af 2>/dev/null || true
    podman system prune -af 2>/dev/null || true
fi
if [[ "$RUNTIME" == "docker" || "$RUNTIME" == "both" ]]; then
    docker rm -af 2>/dev/null || true
    docker system prune -af 2>/dev/null || true
fi

# ─── Uninstall ───

run_step "dockpod uninstall ${RUNTIME}" $DOCKPOD uninstall "$RUNTIME" -y

if [[ "$RUNTIME" != "podman" ]]; then
    echo "==> buildx removed..."
    if command -v docker-buildx &>/dev/null; then
        fail "buildx removed"
    else
        ok "buildx removed"
    fi
fi

# ─── Cleanup ───

rm -rf "$EXTRACT_DIR"

# ─── Summary ───

echo ""
total=$((pass + fail))
echo "==> Results: ${pass}/${total} passed"
if [[ $fail -gt 0 ]]; then echo "  ${fail} FAILED"; exit 1; fi
echo "==> All passed"
