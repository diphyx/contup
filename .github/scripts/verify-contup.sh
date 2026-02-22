#!/usr/bin/env bash
set -euo pipefail

# Integration test for the contup CLI.
# Exercises install, test, status, info, switch, stop, start, restart, uninstall.
# Must run as root on amd64.
# Usage: verify-contup.sh <path-to-tarball> <runtime>

TARBALL="${1:?Usage: verify-contup.sh <path-to-tarball> <runtime>}"
RUNTIME="${2:?Usage: verify-contup.sh <path-to-tarball> <runtime>}"

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

# ─── Extract tarball and setup contup ───

echo "==> Extracting ${TARBALL}..."
EXTRACT_DIR=$(mktemp -d /tmp/contup-extract.XXXXXX)
tar -xzf "$TARBALL" --strip-components=1 -C "$EXTRACT_DIR"

CONTUP="${EXTRACT_DIR}/contup.sh"
chmod +x "$CONTUP"

# ─── Install ───

run_step "contup install ${RUNTIME}" $CONTUP install "$RUNTIME" -y

# ─── Test ───

run_step "contup test ${RUNTIME}" $CONTUP test "$RUNTIME"

# ─── Status ───

run_step "contup status" $CONTUP status

# ─── Info ───

run_step "contup info" $CONTUP info

# ─── Stop ───

run_step "contup stop ${RUNTIME}" $CONTUP stop "$RUNTIME"

# ─── Start ───

run_step "contup start ${RUNTIME}" $CONTUP start "$RUNTIME"

# ─── Restart ───

run_step "contup restart ${RUNTIME}" $CONTUP restart "$RUNTIME"

# ─── Switch ───

run_step "contup switch ${RUNTIME}" $CONTUP switch "$RUNTIME"

# ─── Uninstall ───

run_step "contup uninstall ${RUNTIME}" $CONTUP uninstall "$RUNTIME" -y

# ─── Cleanup ───

rm -rf "$EXTRACT_DIR"

# ─── Summary ───

echo ""
total=$((pass + fail))
echo "==> Results: ${pass}/${total} passed"
if [[ $fail -gt 0 ]]; then echo "  ${fail} FAILED"; exit 1; fi
echo "==> All passed"
