#!/usr/bin/env bash
set -euo pipefail

# Update CONTUP_VERSION in contup.sh
# Usage: publish.sh

SCRIPT="contup.sh"

# ─── Validate ───

if [[ ! -f "$SCRIPT" ]]; then
    echo "Error: $SCRIPT not found (run from repo root)"
    exit 1
fi

# ─── Parse current version ───

CURRENT=$(sed -n 's/^CONTUP_VERSION="\(.*\)"/\1/p' "$SCRIPT")
CURRENT_VER="${CURRENT%% *}"
IFS='.' read -r MAJOR MINOR HOTFIX <<< "$CURRENT_VER"

# ─── Prompt ───

echo "Current version: ${CURRENT_VER}"
echo ""
echo "  0) hash    → ${CURRENT_VER} (update hash only)"
echo "  1) hotfix  → ${MAJOR}.${MINOR}.$((HOTFIX + 1))"
echo "  2) minor   → ${MAJOR}.$((MINOR + 1)).0"
echo "  3) major   → $((MAJOR + 1)).0.0"
echo ""
read -rp "Select bump type [0-3]: " choice

# ─── Bump ───

case "${choice:-0}" in
    0) ;;
    1) HOTFIX=$((HOTFIX + 1)) ;;
    2) MINOR=$((MINOR + 1)); HOTFIX=0 ;;
    3) MAJOR=$((MAJOR + 1)); MINOR=0; HOTFIX=0 ;;
    *) echo "Error: invalid choice"; exit 1 ;;
esac

# ─── Apply ───

VERSION="${MAJOR}.${MINOR}.${HOTFIX}"
HASH=$(git rev-parse --short HEAD)
NEW="${VERSION} (${HASH})"

sed -i.bak "s/CONTUP_VERSION=\".*\"/CONTUP_VERSION=\"${NEW}\"/" "$SCRIPT"
rm -f "${SCRIPT}.bak"

echo ""
echo "==> ${CURRENT} → ${NEW}"

# ─── Release ───

TAG="v${VERSION}"

echo ""
echo "  0) skip"
echo "  1) push     → commit and push to origin"
echo "  2) build    → push and trigger build workflow"
echo "  3) release  → push and trigger release workflow"
echo ""
read -rp "Select action [0-3]: " action

action="${action:-0}"

if [[ "$action" =~ ^[1-3]$ ]]; then
    git add -A
    git commit -m "Bump version to ${VERSION} ${HASH}"
    git push origin main
    echo ""
    echo "==> Pushed ${TAG}"
fi

if [[ "$action" == "2" ]]; then
    echo ""
    echo "  0) both"
    echo "  1) amd64"
    echo "  2) arm64"
    echo ""
    read -rp "Select platform [0-2]: " p
    case "${p:-0}" in
        1) PLATFORM="amd64" ;; 2) PLATFORM="arm64" ;; *) PLATFORM="both" ;;
    esac

    echo ""
    echo "  0) both"
    echo "  1) docker"
    echo "  2) podman"
    echo ""
    read -rp "Select runtime [0-2]: " r
    case "${r:-0}" in
        1) RUNTIME="docker" ;; 2) RUNTIME="podman" ;; *) RUNTIME="both" ;;
    esac

    echo ""
    echo "  0) true"
    echo "  1) false"
    echo ""
    read -rp "Include compose [0-1]: " c
    case "${c:-0}" in
        1) COMPOSE="false" ;; *) COMPOSE="true" ;;
    esac

    gh workflow run build.yml \
        -f version="$TAG" \
        -f platform="$PLATFORM" \
        -f runtime="$RUNTIME" \
        -f compose="$COMPOSE"
    echo ""
    echo "==> Triggered build workflow (${PLATFORM}, ${RUNTIME}, compose=${COMPOSE})"
elif [[ "$action" == "3" ]]; then
    gh workflow run release.yml -f version="$TAG"
    echo "==> Triggered release workflow"
fi
