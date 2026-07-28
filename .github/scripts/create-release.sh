#!/usr/bin/env bash
set -euo pipefail

# Create GitHub Release with tarballs and checksums
# Requires: RELEASE_TAG env var, artifacts/ directory, GH_TOKEN

TAG="${RELEASE_TAG:?RELEASE_TAG is required}"

# shellcheck source=../../versions.env
source versions.env

echo "==> Creating release ${TAG}..."

gh release create "$TAG" \
    --title "${TAG}" \
    --notes "$(cat <<EOF
## 📦 dockpod ${TAG}

Prebuilt static container runtime binaries for Linux.

### 🧩 Included Versions

| Component | Version |
|---|---|
| 🐳 Docker | \`${DOCKER_VERSION}\` |
| 🦭 Podman | \`${PODMAN_VERSION}\` |
| 🔌 Compose | \`${COMPOSE_VERSION}\` |
| 🔨 Buildx | \`${BUILDX_VERSION}\` |

### 📥 Download

| Architecture | Tarball |
|---|---|
| x86_64 (amd64) | \`dockpod-${TAG}-amd64.tar.gz\` |
| aarch64 (arm64) | \`dockpod-${TAG}-arm64.tar.gz\` |

### 🚀 Quick Install

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/diphyx/dockpod/main/dockpod.sh | bash
\`\`\`

### ✅ Verify Checksums

\`\`\`bash
sha256sum -c checksums.txt
\`\`\`
EOF
)" \
    artifacts/dockpod-*.tar.gz \
    artifacts/checksums.txt

echo "==> Release ${TAG} created"
