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
## 📦 contup ${TAG}

Prebuilt static container runtime binaries for Linux.

### 🧩 Included Versions

| Component | Version |
|---|---|
| 🐳 Docker | \`${DOCKER_VERSION}\` |
| 🦭 Podman | \`${PODMAN_VERSION}\` |
| 🔌 Compose | \`${COMPOSE_VERSION}\` |

### 📥 Download

| Architecture | Tarball |
|---|---|
| x86_64 (amd64) | \`contup-${TAG}-amd64.tar.gz\` |
| aarch64 (arm64) | \`contup-${TAG}-arm64.tar.gz\` |

### 🚀 Quick Install

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/diphyx/contup/main/contup.sh | bash
\`\`\`

### ✅ Verify Checksums

\`\`\`bash
sha256sum -c checksums.txt
\`\`\`
EOF
)" \
    artifacts/contup-*.tar.gz \
    artifacts/checksums.txt

echo "==> Release ${TAG} created"
