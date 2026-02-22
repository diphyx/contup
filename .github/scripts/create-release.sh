#!/usr/bin/env bash
set -euo pipefail

# Create GitHub Release with tarballs and checksums
# Requires: RELEASE_TAG env var, artifacts/ directory, GH_TOKEN

TAG="${RELEASE_TAG:?RELEASE_TAG is required}"

echo "==> Creating release ${TAG}..."

gh release create "$TAG" \
    --title "contup ${TAG}" \
    --notes "$(cat <<EOF
## contup ${TAG}

Prebuilt static container runtime binaries for Linux.

### Download

| Architecture | Tarball |
|---|---|
| x86_64 (amd64) | \`contup-${TAG}-amd64.tar.gz\` |
| aarch64 (arm64) | \`contup-${TAG}-arm64.tar.gz\` |

### Quick Install (Docker)

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/diphyx/contup/main/contup.sh | bash
\`\`\`

### Verify

\`\`\`bash
sha256sum -c checksums.txt
\`\`\`
EOF
)" \
    artifacts/contup-*.tar.gz \
    artifacts/checksums.txt

echo "==> Release ${TAG} created"
