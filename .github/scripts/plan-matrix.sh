#!/usr/bin/env bash
set -euo pipefail

# Emit the build matrix (arch × component) consumed by build.yml.
# Each entry carries the toolchain the component needs, so every job
# installs only what it uses.
# Env: PLATFORM=both|amd64|arm64, RUNTIME=both|docker|podman, COMPOSE, BUILDX

PLATFORM="${PLATFORM:-both}"
RUNTIME="${RUNTIME:-both}"
COMPOSE="${COMPOSE:-true}"
BUILDX="${BUILDX:-true}"

# component → "<needs go> <needs rust> <apt profile>"
component_spec() {
    case "$1" in
        docker-cli|containerd|buildx|compose) echo "true false none" ;;
        moby|docker-extras|podman)            echo "true false full" ;;
        podman-extras)                        echo "false false full" ;;
        podman-net)                           echo "false true full" ;;
        *) echo "::error::Unknown component: $1" >&2; exit 1 ;;
    esac
}

case "$PLATFORM" in
    amd64) arches=(amd64) ;;
    arm64) arches=(arm64) ;;
    *)     arches=(amd64 arm64) ;;
esac

components=()

if [[ "$RUNTIME" != "podman" ]]; then
    components+=(docker-cli moby containerd docker-extras)
    if [[ "$BUILDX" != "false" ]]; then
        components+=(buildx)
    fi
fi

if [[ "$COMPOSE" != "false" ]]; then
    components+=(compose)
fi

if [[ "$RUNTIME" != "docker" ]]; then
    components+=(podman podman-extras podman-net)
fi

entries=""
for arch in "${arches[@]}"; do
    for component in "${components[@]}"; do
        read -r go rust apt <<< "$(component_spec "$component")"
        entries+="{\"arch\":\"${arch}\",\"component\":\"${component}\",\"go\":${go},\"rust\":${rust},\"apt\":\"${apt}\"},"
    done
done

printf -v arch_json '"%s",' "${arches[@]}"

matrix="{\"include\":[${entries%,}]}"
arch_list="[${arch_json%,}]"

echo "==> ${#arches[@]} arch × ${#components[@]} components = $((${#arches[@]} * ${#components[@]})) jobs"
echo "  arches:     ${arches[*]}"
echo "  components: ${components[*]}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "matrix=${matrix}" >> "$GITHUB_OUTPUT"
    echo "arches=${arch_list}" >> "$GITHUB_OUTPUT"
else
    echo "matrix=${matrix}"
    echo "arches=${arch_list}"
fi
