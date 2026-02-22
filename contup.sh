#!/usr/bin/env bash
set -euo pipefail

# contup — container up
# Prebuilt container runtime binaries + CLI management tool for Linux
# https://github.com/diphyx/contup

CONTUP_VERSION="1.0.4 (016636a)"
GITHUB_REPO="diphyx/contup"
GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}"

# Binaries
DOCKER_BINARIES="docker dockerd containerd containerd-shim-runc-v2 runc docker-proxy docker-init"
DOCKER_ROOTLESS_BINARIES="dockerd-rootless.sh rootlesskit"
COMPOSE_BINARY="docker-compose"
PODMAN_BINARIES="podman crun conmon netavark aardvark-dns slirp4netns fuse-overlayfs"

# Colors
if [[ -t 1 ]]; then
    C_RESET="\033[0m"
    C_BOLD="\033[1m"
    C_DIM="\033[2m"
    C_RED="\033[31m"
    C_GREEN="\033[32m"
    C_YELLOW="\033[33m"
    C_CYAN="\033[36m"
else
    C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_CYAN=""
fi

# Symbols
S_OK="✔"
S_FAIL="✘"
S_WARN="⚠"
S_DOT="●"
S_ARROW="▸"

# System info
ARCH=""
OS_NAME=""
OS_VERSION=""
KERNEL_VERSION=""
IS_ROOT=false
INSTALL_MODE=""

# Paths
BIN_DIR=""
CONFIG_DIR_DOCKER=""
CONFIG_DIR_PODMAN=""
SYSTEMD_DIR=""
CLI_PLUGINS_DIR=""
TMPDIR_CONTUP=""

# Sockets
DOCKER_HOST_SOCKET=""
PODMAN_HOST_SOCKET=""

# Flags
FLAG_YES=false
FLAG_OFFLINE=false
FLAG_NO_START=false
FLAG_NO_VERIFY=false

## UI

print_banner() {
    echo -e "${C_BOLD}"
    echo "  contup — container up"
    echo -e "${C_DIM}  v${CONTUP_VERSION}${C_RESET}"
    echo ""
}

print_step() {
    local step="$1" title="$2"
    echo -e "\n${C_BOLD}Step ${step} — ${title}${C_RESET}"
}

print_ok() {
    echo -e "  ${C_GREEN}${S_OK}${C_RESET}  $1"
}

print_fail() {
    echo -e "  ${C_RED}${S_FAIL}${C_RESET}  $1"
}

print_warn() {
    echo -e "  ${C_YELLOW}${S_WARN}${C_RESET}  $1"
}

print_info() {
    echo -e "  ${C_CYAN}${S_DOT}${C_RESET}  $1"
}

print_dim() {
    echo -e "  ${C_DIM}$1${C_RESET}"
}

die() {
    echo -e "\n${C_RED}Error:${C_RESET} $1" >&2
    exit 1
}

confirm() {
    local prompt="$1"
    if [[ "$FLAG_YES" == true ]]; then
        return 0
    fi
    echo -en "  ${C_YELLOW}?${C_RESET}  ${prompt} [y/N] "
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

# Arrow-key interactive menu
# Usage: select_menu "Title" result_var "Option1" "Desc1" "Option2" "Desc2" ...
select_menu() {
    local title="$1"
    local -n _result="$2"
    shift 2

    local options=() descriptions=()
    while [[ $# -gt 0 ]]; do
        options+=("$1")
        descriptions+=("$2")
        shift 2
    done

    local count=${#options[@]}
    local selected=0

    # Hide cursor
    tput civis 2>/dev/null || true

    # Restore cursor on exit
    trap 'tput cnorm 2>/dev/null || true' RETURN

    echo -e "\n  ${C_BOLD}${title}${C_RESET}"

    while true; do
        # Draw menu
        for i in $(seq 0 $((count - 1))); do
            if [[ $i -eq $selected ]]; then
                echo -e "    ${C_GREEN}${S_ARROW} ${options[$i]}${C_RESET}  ${C_DIM}${descriptions[$i]}${C_RESET}"
            else
                echo -e "    ${C_DIM}  ${options[$i]}  ${descriptions[$i]}${C_RESET}"
            fi
        done
        echo -e "  ${C_DIM}↑↓ navigate  Enter select${C_RESET}"

        # Read keypress
        IFS= read -rsn1 key
        case "$key" in
            $'\x1b')
                read -rsn2 key
                case "$key" in
                    '[A') ((selected > 0)) && ((selected--)) || true ;;
                    '[B') ((selected < count - 1)) && ((selected++)) || true ;;
                esac
                ;;
            '') break ;;
        esac

        # Move cursor up to redraw
        tput cuu $((count + 1)) 2>/dev/null || echo -en "\033[$((count + 1))A"
        for i in $(seq 0 $((count))); do
            tput el 2>/dev/null || echo -en "\033[2K"
            tput cud1 2>/dev/null || echo -en "\033[1B"
        done
        tput cuu $((count + 1)) 2>/dev/null || echo -en "\033[$((count + 1))A"
    done

    _result="${options[$selected]}"
    tput cnorm 2>/dev/null || true
}

progress_bar() {
    local current="$1" total="$2" label="${3:-}"
    local width=30
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    local bar=""
    for ((i = 0; i < filled; i++)); do bar+="█"; done
    for ((i = 0; i < empty; i++)); do bar+="░"; done
    printf "\r  [%s] %3d%%  %s" "$bar" "$percent" "$label"
    if [[ $current -eq $total ]]; then echo ""; fi
}

spinner() {
    local pid="$1" msg="$2"
    local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  %s  %s" "${chars:i%${#chars}:1}" "$msg" >&2
        ((i++)) || true
        sleep 0.1
    done
    printf "\r\033[2K" >&2
}

print_box() {
    local title="$1"
    shift
    local lines=("$@")

    echo -e "  ${C_BOLD}${title}${C_RESET}"
    echo ""
    for line in "${lines[@]}"; do
        echo -e "  ${line}"
    done
    echo ""
}

## System detection

detect_arch() {
    local machine
    machine=$(uname -m)
    case "$machine" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) die "Unsupported architecture: ${machine}" ;;
    esac
}

detect_os() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        die "contup only supports Linux (detected: $(uname -s))"
    fi

    KERNEL_VERSION=$(uname -r)

    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS_NAME="${NAME:-Linux}"
        OS_VERSION="${VERSION_ID:-}"
    else
        OS_NAME="Linux"
        OS_VERSION=""
    fi
}

detect_install_mode() {
    if [[ $(id -u) -eq 0 ]]; then
        IS_ROOT=true
        INSTALL_MODE="root"
        BIN_DIR="/usr/local/bin"
        CONFIG_DIR_DOCKER="/etc/docker"
        CONFIG_DIR_PODMAN="/etc/containers"
        SYSTEMD_DIR="/etc/systemd/system"
        CLI_PLUGINS_DIR="/usr/local/lib/docker/cli-plugins"
        DOCKER_HOST_SOCKET="unix:///var/run/docker.sock"
        PODMAN_HOST_SOCKET="unix:///run/podman/podman.sock"
    else
        IS_ROOT=false
        INSTALL_MODE="rootless"
        BIN_DIR="${HOME}/.local/bin"
        CONFIG_DIR_DOCKER="${HOME}/.config/docker"
        CONFIG_DIR_PODMAN="${HOME}/.config/containers"
        SYSTEMD_DIR="${HOME}/.config/systemd/user"
        CLI_PLUGINS_DIR="${HOME}/.docker/cli-plugins"
        DOCKER_HOST_SOCKET="unix://${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/docker.sock"
        PODMAN_HOST_SOCKET="unix://${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock"
    fi
}

check_kernel() {
    local major minor
    major=$(echo "$KERNEL_VERSION" | cut -d. -f1)
    minor=$(echo "$KERNEL_VERSION" | cut -d. -f2)
    if [[ $major -lt 4 ]] || { [[ $major -eq 4 ]] && [[ $minor -lt 18 ]]; }; then
        print_fail "Kernel ${KERNEL_VERSION} — requires ≥ 4.18"
        return 1
    fi
    print_ok "Kernel ${KERNEL_VERSION}"
}

check_cgroups() {
    if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
        print_ok "cgroups v2"
        return 0
    elif [[ -d /sys/fs/cgroup/cpu ]]; then
        print_warn "cgroups v1 (v2 recommended)"
        return 0
    fi
    print_fail "cgroups not found"
    return 1
}

check_iptables() {
    if command -v iptables &>/dev/null; then
        print_ok "iptables available"
    elif command -v nft &>/dev/null; then
        print_ok "nftables available"
    else
        print_warn "iptables/nftables not found — networking may be limited"
    fi
}

check_systemd() {
    if ! command -v systemctl &>/dev/null; then
        print_fail "systemd not found — required for service management"
        return 1
    fi
    print_ok "systemd $(systemctl --version 2>/dev/null | head -1 | awk '{print $2}')"
}

check_newuidmap() {
    if [[ "$IS_ROOT" == true ]]; then
        return 0
    fi
    if command -v newuidmap &>/dev/null && command -v newgidmap &>/dev/null; then
        print_ok "newuidmap/newgidmap available"
    else
        print_warn "newuidmap/newgidmap not found — rootless may not work"
    fi
}

check_existing_install() {
    local runtime="$1"
    case "$runtime" in
        docker)
            if command -v docker &>/dev/null; then
                local ver
                ver=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
                local path
                path=$(command -v docker)
                echo "docker:installed:${ver}:${path}"
                return 0
            fi
            ;;
        podman)
            if command -v podman &>/dev/null; then
                local ver
                ver=$(podman --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
                local path
                path=$(command -v podman)
                echo "podman:installed:${ver}:${path}"
                return 0
            fi
            ;;
        compose)
            if command -v docker-compose &>/dev/null; then
                local ver
                ver=$(docker-compose version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
                echo "compose:installed:${ver}"
                return 0
            fi
            ;;
    esac
    echo "${runtime}:not_installed"
    return 1
}

get_installed_version() {
    local runtime="$1"
    case "$runtime" in
        docker)  docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "" ;;
        podman)  podman --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "" ;;
        compose) docker-compose version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "" ;;
    esac
}

is_runtime_installed() {
    local runtime="$1"
    case "$runtime" in
        docker) command -v docker &>/dev/null && command -v dockerd &>/dev/null ;;
        podman) command -v podman &>/dev/null ;;
        compose) command -v docker-compose &>/dev/null ;;
    esac
}

is_runtime_running() {
    local runtime="$1"
    case "$runtime" in
        docker)
            if [[ "$IS_ROOT" == true ]]; then
                systemctl is-active docker.service &>/dev/null
            else
                systemctl --user is-active docker.service &>/dev/null
            fi
            ;;
        podman)
            if [[ "$IS_ROOT" == true ]]; then
                systemctl is-active podman.socket &>/dev/null
            else
                systemctl --user is-active podman.socket &>/dev/null
            fi
            ;;
    esac
}

get_active_runtime() {
    local host="${DOCKER_HOST:-}"
    if [[ "$host" == *"podman"* ]]; then
        echo "podman"
    elif [[ -n "$host" ]]; then
        echo "docker"
    elif is_runtime_running docker; then
        echo "docker"
    elif is_runtime_running podman; then
        echo "podman"
    else
        echo ""
    fi
}

## Download

detect_mode() {
    local script_dir
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

    if [[ "$FLAG_OFFLINE" == true ]]; then
        if [[ -d "${script_dir}/docker" ]] || [[ -d "${script_dir}/podman" ]]; then
            echo "bundled"
        else
            die "Offline mode requested but no bundled binaries found next to contup.sh"
        fi
    elif [[ -d "${script_dir}/docker" ]] || [[ -d "${script_dir}/podman" ]]; then
        echo "bundled"
    else
        echo "online"
    fi
}

fetch_latest_release() {
    local api_url="${GITHUB_API}/releases/latest"
    local tmp_file="/tmp/contup-release-$$.json"

    print_info "Fetching latest release..." >&2
    if ! curl -fsSL "$api_url" -o "$tmp_file"; then
        die "Failed to fetch latest release from GitHub"
    fi
    cat "$tmp_file"
    rm -f "$tmp_file"
}

download_tarball() {
    local url="$1" dest="$2"
    local tmp_file="${dest}.tmp"
    local name
    name=$(basename "$dest")

    print_info "Downloading ${name}..." >&2
    if ! curl -fsSL -o "$tmp_file" "$url"; then
        die "Download failed: ${url}"
    fi

    mv "$tmp_file" "$dest"
    print_ok "Downloaded ${name}"
}

verify_checksum() {
    local file="$1" expected="$2"
    local actual
    actual=$(sha256sum "$file" | awk '{print $1}')
    if [[ "$actual" != "$expected" ]]; then
        print_fail "Checksum mismatch"
        print_dim "  Expected: ${expected}"
        print_dim "  Actual:   ${actual}"
        return 1
    fi
    print_ok "Checksum verified"
}

extract_binaries() {
    local tarball="$1" dest="$2"
    mkdir -p "$dest"
    tar -xzf "$tarball" -C "$dest" --strip-components=1 || die "Failed to extract tarball"
    print_ok "Extracted binaries"
}

## Install

install_binaries() {
    local src_dir="$1" runtime="$2"
    local binaries=""
    local src_subdir=""

    case "$runtime" in
        docker)
            binaries="$DOCKER_BINARIES"
            src_subdir="docker"
            ;;
        docker-rootless)
            binaries="$DOCKER_ROOTLESS_BINARIES"
            src_subdir="docker-rootless"
            ;;
        compose)
            binaries="$COMPOSE_BINARY"
            src_subdir="compose"
            ;;
        podman)
            binaries="$PODMAN_BINARIES"
            src_subdir="podman"
            ;;
    esac

    mkdir -p "$BIN_DIR"

    local count=0 total
    total=$(echo "$binaries" | wc -w)

    for bin in $binaries; do
        local src="${src_dir}/${src_subdir}/${bin}"
        if [[ ! -f "$src" ]]; then
            print_warn "Binary not found: ${bin} — skipping"
            continue
        fi
        cp "$src" "${BIN_DIR}/${bin}"
        chmod +x "${BIN_DIR}/${bin}"
        ((count++)) || true
        progress_bar "$count" "$total" "$bin"
    done
}

install_self() {
    local src_dir="$1"
    mkdir -p "$BIN_DIR"

    if [[ -f "${src_dir}/contup.sh" ]]; then
        cp "${src_dir}/contup.sh" "${BIN_DIR}/contup.sh"
    else
        # curl | bash mode — download contup.sh from GitHub
        local url="https://raw.githubusercontent.com/${GITHUB_REPO}/main/contup.sh"
        curl -fsSL -o "${BIN_DIR}/contup.sh" "$url" || {
            print_warn "Failed to download contup.sh"
            return 1
        }
    fi

    chmod +x "${BIN_DIR}/contup.sh"
    ln -sf "${BIN_DIR}/contup.sh" "${BIN_DIR}/contup"
    print_ok "Installed contup to ${BIN_DIR}"
}

install_cli_plugins() {
    mkdir -p "$CLI_PLUGINS_DIR"

    # Docker Compose as CLI plugin
    if [[ -f "${BIN_DIR}/docker-compose" ]]; then
        ln -sf "${BIN_DIR}/docker-compose" "${CLI_PLUGINS_DIR}/docker-compose"
        print_ok "Compose CLI plugin → docker compose"
    fi
}

create_podman_compose_symlink() {
    if [[ -f "${BIN_DIR}/docker-compose" ]] && is_runtime_installed podman; then
        if [[ ! -f "${BIN_DIR}/podman-compose" ]]; then
            ln -sf "${BIN_DIR}/docker-compose" "${BIN_DIR}/podman-compose"
            print_ok "podman-compose → docker-compose symlink"
        fi
    fi
}

## Configuration

write_containers_conf() {
    local dir="$1"
    cat > "${dir}/containers.conf" <<EOF
[containers]

[engine]
helper_binaries_dir = ["${BIN_DIR}"]

[network]
EOF
    print_ok "Configured ${dir}/containers.conf"
}

write_registries_conf() {
    local dir="$1"
    [[ -f "${dir}/registries.conf" ]] && return
    cat > "${dir}/registries.conf" <<'EOF'
unqualified-search-registries = ["docker.io"]
EOF
    print_ok "Created ${dir}/registries.conf"
}

write_storage_conf() {
    local dir="$1"
    [[ -f "${dir}/storage.conf" ]] && return

    local graphroot
    if [[ "$IS_ROOT" == true ]]; then
        graphroot="/var/lib/containers/storage"
    else
        graphroot="${HOME}/.local/share/containers/storage"
    fi

    cat > "${dir}/storage.conf" <<EOF
[storage]
driver = "overlay"
graphroot = "${graphroot}"

[storage.options]

[storage.options.overlay]
EOF
    print_ok "Created ${dir}/storage.conf"
}

write_policy_json() {
    local dir="$1"
    [[ -f "${dir}/policy.json" ]] && return
    cat > "${dir}/policy.json" <<'EOF'
{
    "default": [
        {
            "type": "insecureAcceptAnything"
        }
    ]
}
EOF
    print_ok "Created ${dir}/policy.json"
}

write_docker_systemd_unit() {
    mkdir -p "$SYSTEMD_DIR"

    cat > "${SYSTEMD_DIR}/docker.service" <<EOF
[Unit]
Description=Docker Application Container Engine
After=network-online.target containerd.service
Wants=network-online.target
Requires=containerd.service

[Service]
Type=notify
ExecStart=${BIN_DIR}/dockerd
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
    print_ok "Created docker.service"
}

write_containerd_systemd_unit() {
    mkdir -p "$SYSTEMD_DIR"

    cat > "${SYSTEMD_DIR}/containerd.service" <<EOF
[Unit]
Description=containerd container runtime
After=network.target

[Service]
Type=notify
ExecStart=${BIN_DIR}/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF
    print_ok "Created containerd.service"
}

write_docker_systemd_user_unit() {
    mkdir -p "$SYSTEMD_DIR"

    cat > "${SYSTEMD_DIR}/docker.service" <<EOF
[Unit]
Description=Docker Application Container Engine (Rootless)
After=default.target

[Service]
Type=notify
ExecStart=${BIN_DIR}/dockerd-rootless.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
    print_ok "Created docker.service (user)"
}

write_podman_systemd_unit() {
    mkdir -p "$SYSTEMD_DIR"

    cat > "${SYSTEMD_DIR}/podman.socket" <<'EOF'
[Unit]
Description=Podman API Socket

[Socket]
ListenStream=/run/podman/podman.sock
SocketMode=0660

[Install]
WantedBy=sockets.target
EOF

    cat > "${SYSTEMD_DIR}/podman.service" <<EOF
[Unit]
Description=Podman API Service
Requires=podman.socket
After=podman.socket

[Service]
Type=exec
ExecStart=${BIN_DIR}/podman system service --time=0
KillMode=process
Delegate=yes

[Install]
WantedBy=default.target
EOF
    print_ok "Created podman.socket + podman.service"
}

write_podman_systemd_user_unit() {
    mkdir -p "$SYSTEMD_DIR"

    cat > "${SYSTEMD_DIR}/podman.socket" <<EOF
[Unit]
Description=Podman API Socket

[Socket]
ListenStream=%t/podman/podman.sock
SocketMode=0660

[Install]
WantedBy=sockets.target
EOF

    cat > "${SYSTEMD_DIR}/podman.service" <<EOF
[Unit]
Description=Podman API Service (Rootless)
Requires=podman.socket
After=podman.socket

[Service]
Type=exec
ExecStart=${BIN_DIR}/podman system service --time=0
KillMode=process
Delegate=yes

[Install]
WantedBy=default.target
EOF
    print_ok "Created podman.socket + podman.service (user)"
}

setup_docker_group() {
    if [[ "$IS_ROOT" != true ]]; then return; fi

    if ! getent group docker &>/dev/null; then
        groupadd docker
        print_ok "Created docker group"
    fi

    local real_user="${SUDO_USER:-$USER}"
    if [[ "$real_user" != "root" ]] && ! id -nG "$real_user" | grep -qw docker; then
        usermod -aG docker "$real_user"
        print_ok "Added ${real_user} to docker group"
    fi
}

setup_subuid_subgid() {
    if [[ "$IS_ROOT" == true ]]; then return; fi

    local user
    user=$(whoami)

    for f in /etc/subuid /etc/subgid; do
        if [[ ! -f "$f" ]] || ! grep -q "^${user}:" "$f" 2>/dev/null; then
            print_warn "${f} does not contain entry for ${user}"
            print_dim "You may need to run (as root): usermod --add-subuids 100000-165535 --add-subgids 100000-165535 ${user}"
        fi
    done
}

configure_docker_root() {
    mkdir -p "$CONFIG_DIR_DOCKER"

    # daemon.json
    if [[ ! -f "${CONFIG_DIR_DOCKER}/daemon.json" ]]; then
        cat > "${CONFIG_DIR_DOCKER}/daemon.json" <<'DAEMON_JSON'
{
    "storage-driver": "overlay2",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
DAEMON_JSON
        print_ok "Created ${CONFIG_DIR_DOCKER}/daemon.json"
    else
        print_dim "Skipped daemon.json (already exists)"
    fi

    # systemd units
    write_docker_systemd_unit
    write_containerd_systemd_unit

    # docker group
    setup_docker_group
}

configure_docker_rootless() {
    mkdir -p "$CONFIG_DIR_DOCKER"

    # daemon.json
    if [[ ! -f "${CONFIG_DIR_DOCKER}/daemon.json" ]]; then
        cat > "${CONFIG_DIR_DOCKER}/daemon.json" <<'DAEMON_JSON'
{
    "storage-driver": "overlay2",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
DAEMON_JSON
        print_ok "Created ${CONFIG_DIR_DOCKER}/daemon.json"
    else
        print_dim "Skipped daemon.json (already exists)"
    fi

    # systemd user unit
    write_docker_systemd_user_unit

    # DOCKER_HOST
    update_shell_profile "DOCKER_HOST" "$DOCKER_HOST_SOCKET"
}

configure_podman_root() {
    mkdir -p "$CONFIG_DIR_PODMAN"

    write_containers_conf "$CONFIG_DIR_PODMAN"
    write_registries_conf "$CONFIG_DIR_PODMAN"
    write_storage_conf "$CONFIG_DIR_PODMAN"
    write_policy_json "$CONFIG_DIR_PODMAN"

    # systemd unit
    write_podman_systemd_unit

    # DOCKER_HOST (only if docker not installed)
    if ! is_runtime_installed docker; then
        update_shell_profile "DOCKER_HOST" "$PODMAN_HOST_SOCKET"
    fi
}

configure_podman_rootless() {
    mkdir -p "$CONFIG_DIR_PODMAN"

    write_containers_conf "$CONFIG_DIR_PODMAN"
    write_registries_conf "$CONFIG_DIR_PODMAN"
    write_storage_conf "$CONFIG_DIR_PODMAN"
    write_policy_json "$CONFIG_DIR_PODMAN"

    # subuid/subgid
    setup_subuid_subgid

    # systemd user unit
    write_podman_systemd_user_unit

    # DOCKER_HOST (only if docker not installed)
    if ! is_runtime_installed docker; then
        update_shell_profile "DOCKER_HOST" "$PODMAN_HOST_SOCKET"
    fi
}

configure_compose() {
    install_cli_plugins
    if is_runtime_installed podman; then
        create_podman_compose_symlink
    fi
}

## Shell

update_shell_profile() {
    local var_name="$1" var_value="$2"
    local marker="# contup: ${var_name}"
    local line="export ${var_name}=\"${var_value}\" ${marker}"

    if [[ "$IS_ROOT" == true ]]; then
        local profile="/etc/profile.d/contup.sh"
        mkdir -p /etc/profile.d
        # Remove old entry
        if [[ -f "$profile" ]]; then
            sed -i "/${marker}/d" "$profile"
        fi
        echo "$line" >> "$profile"
        print_ok "Set ${var_name} in ${profile}"
    else
        for rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
            if [[ -f "$rc" ]]; then
                sed -i "/${marker}/d" "$rc"
                echo "$line" >> "$rc"
            fi
        done
        print_ok "Set ${var_name} in shell profiles"
    fi

    # Also export in current session
    export "${var_name}=${var_value}"
}

remove_shell_profile_var() {
    local var_name="$1"
    local marker="# contup: ${var_name}"

    if [[ "$IS_ROOT" == true ]]; then
        local profile="/etc/profile.d/contup.sh"
        if [[ -f "$profile" ]]; then
            sed -i "/${marker}/d" "$profile"
            # Remove file if empty
            if [[ ! -s "$profile" ]]; then
                rm -f "$profile"
            fi
        fi
    else
        for rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
            if [[ -f "$rc" ]]; then
                sed -i "/${marker}/d" "$rc"
            fi
        done
    fi
}

ensure_path() {
    if [[ "$IS_ROOT" == true ]]; then return; fi

    if [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
        update_shell_profile "PATH" "${BIN_DIR}:\${PATH}"
        export PATH="${BIN_DIR}:${PATH}"
        print_ok "Added ${BIN_DIR} to PATH"
    fi
}

install_shell_wrapper() {
    local marker="# contup: shell-wrapper"
    local marker_end="# contup: shell-wrapper-end"
    local wrapper
    read -r -d '' wrapper <<'WRAPPER' || true
contup() { # contup: shell-wrapper
    command contup.sh "$@"; local _rc=$?
    if [[ "$1" == "switch" && $_rc -eq 0 ]]; then
        local _l; _l=$(grep '# contup: DOCKER_HOST' /etc/profile.d/contup.sh ~/.bashrc ~/.zshrc ~/.profile 2>/dev/null | head -1)
        [[ -n "$_l" ]] && eval "${_l#*:}"
    fi
    return $_rc
} # contup: shell-wrapper-end
WRAPPER

    if [[ "$IS_ROOT" == true ]]; then
        local profile="/etc/profile.d/contup.sh"
        mkdir -p /etc/profile.d
        if [[ -f "$profile" ]]; then
            sed -i "/${marker}/,/${marker_end}/d" "$profile"
        fi
        echo "$wrapper" >> "$profile"
    else
        for rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
            if [[ -f "$rc" ]]; then
                sed -i "/${marker}/,/${marker_end}/d" "$rc"
                echo "$wrapper" >> "$rc"
            fi
        done
    fi
    print_ok "Installed contup shell wrapper (switch works without restart)"
}

remove_shell_wrapper() {
    local marker="# contup: shell-wrapper"
    local marker_end="# contup: shell-wrapper-end"

    if [[ "$IS_ROOT" == true ]]; then
        local profile="/etc/profile.d/contup.sh"
        if [[ -f "$profile" ]]; then
            sed -i "/${marker}/,/${marker_end}/d" "$profile"
            if [[ ! -s "$profile" ]]; then
                rm -f "$profile"
            fi
        fi
    else
        for rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
            if [[ -f "$rc" ]]; then
                sed -i "/${marker}/,/${marker_end}/d" "$rc"
            fi
        done
    fi
}

## Services

_systemctl() {
    if [[ "$IS_ROOT" == true ]]; then
        systemctl "$@"
    else
        systemctl --user "$@"
    fi
}

start_runtime() {
    local runtime="$1"

    _systemctl daemon-reload

    case "$runtime" in
        docker)
            if [[ "$IS_ROOT" == true ]]; then
                _systemctl enable --now containerd.service 2>/dev/null || true
            fi
            _systemctl enable --now docker.service
            ;;
        podman)
            _systemctl enable --now podman.socket
            ;;
    esac

    if [[ "$IS_ROOT" != true ]]; then
        loginctl enable-linger "$(whoami)" 2>/dev/null || true
    fi

    # Wait for socket
    wait_for_socket "$runtime"
    print_ok "${runtime} started"
}

stop_runtime() {
    local runtime="$1"

    case "$runtime" in
        docker)
            _systemctl stop docker.service 2>/dev/null || true
            if [[ "$IS_ROOT" == true ]]; then
                _systemctl stop containerd.service 2>/dev/null || true
            fi
            ;;
        podman)
            _systemctl stop podman.socket 2>/dev/null || true
            _systemctl stop podman.service 2>/dev/null || true
            ;;
    esac

    print_ok "${runtime} stopped"
}

restart_runtime() {
    local runtime="$1"
    stop_runtime "$runtime"
    start_runtime "$runtime"
}

wait_for_socket() {
    local runtime="$1"
    local socket_path=""
    local timeout=30 elapsed=0

    case "$runtime" in
        docker)
            socket_path="${DOCKER_HOST_SOCKET#unix://}"
            ;;
        podman)
            socket_path="${PODMAN_HOST_SOCKET#unix://}"
            ;;
    esac

    while [[ ! -S "$socket_path" ]] && [[ $elapsed -lt $timeout ]]; do
        sleep 1
        ((elapsed++)) || true
    done

    if [[ ! -S "$socket_path" ]]; then
        print_warn "Socket not ready after ${timeout}s: ${socket_path}"
        return 1
    fi
}

## Verification

verify_binary() {
    local runtime="$1"
    local cmd version
    case "$runtime" in
        docker)  cmd="docker --version" ;;
        podman)  cmd="podman --version" ;;
        compose) cmd="docker-compose version" ;;
    esac

    if version=$(eval "$cmd" 2>/dev/null); then
        print_ok "${runtime} binary: ${version}"
        return 0
    fi
    print_fail "${runtime} binary not working"
    return 1
}

verify_daemon() {
    local runtime="$1"
    case "$runtime" in
        docker)
            if docker info &>/dev/null; then
                print_ok "Docker daemon responding"
                return 0
            fi
            ;;
        podman)
            if podman info &>/dev/null; then
                print_ok "Podman responding"
                return 0
            fi
            ;;
    esac
    print_fail "${runtime} daemon not responding"
    return 1
}

verify_runtime() {
    local runtime="$1"
    local cmd
    case "$runtime" in
        docker) cmd="docker" ;;
        podman) cmd="podman" ;;
    esac

    if $cmd run --rm hello-world &>/dev/null; then
        print_ok "${runtime} run hello-world"
        return 0
    fi
    print_fail "${runtime} run hello-world failed"
    return 1
}

verify_compose() {
    if command -v docker-compose &>/dev/null && docker-compose version &>/dev/null 2>&1; then
        print_ok "docker-compose"
        return 0
    fi
    if command -v podman-compose &>/dev/null && podman-compose version &>/dev/null 2>&1; then
        print_ok "podman-compose"
        return 0
    fi
    print_fail "compose not working"
    return 1
}

## Cleanup

setup_tmpdir() {
    TMPDIR_CONTUP=$(mktemp -d /tmp/contup.XXXXXX)
    trap cleanup_tmpdir EXIT
}

cleanup_tmpdir() {
    if [[ -n "$TMPDIR_CONTUP" ]] && [[ -d "$TMPDIR_CONTUP" ]]; then
        rm -rf "$TMPDIR_CONTUP"
    fi
}

## Commands

cmd_setup() {
    print_banner
    detect_install_mode

    print_info "Installing contup CLI..."
    install_self ""
    ensure_path
    install_shell_wrapper

    echo ""
    print_box "${S_OK} contup CLI installed" \
        "Run 'contup install docker' or 'contup install podman' to get started"
}

cmd_install() {
    local runtime="${1:-}"

    print_banner

    # Step 1 — System Check
    print_step "1" "System Check"
    detect_install_mode

    local errors=0
    check_kernel || ((errors++))
    check_cgroups || ((errors++))
    check_iptables
    check_systemd || ((errors++))
    check_newuidmap

    echo ""
    print_box "System Summary" \
        "Arch:    ${ARCH}" \
        "OS:      ${OS_NAME} ${OS_VERSION} (kernel ${KERNEL_VERSION})" \
        "Mode:    ${INSTALL_MODE}" \
        ""

    if [[ $errors -gt 0 ]]; then
        die "System check failed — ${errors} critical issue(s) found"
    fi

    # Step 2 — Select Runtime
    if [[ -z "$runtime" ]]; then
        print_step "2" "Select Runtime"
        select_menu "Select runtime:" runtime \
            "docker" "Docker + Compose" \
            "podman" "Podman + Compose" \
            "both"   "Docker (primary) + Podman"
    fi

    # Normalize
    case "$runtime" in
        docker|podman|both) ;;
        *) die "Unknown runtime: ${runtime}. Use: docker, podman, or both" ;;
    esac

    # Step 3 — Conflict Check
    print_step "3" "Conflict Check"

    if [[ "$runtime" == "docker" || "$runtime" == "both" ]]; then
        if check_existing_install docker &>/dev/null; then
            local info
            info=$(check_existing_install docker)
            local ver path
            ver=$(echo "$info" | cut -d: -f3)
            path=$(echo "$info" | cut -d: -f4)
            print_warn "Docker ${ver} already installed at ${path}"
            if ! confirm "Overwrite existing Docker installation?"; then
                die "Aborted by user"
            fi
        else
            print_ok "No existing Docker installation"
        fi
    fi

    if [[ "$runtime" == "podman" || "$runtime" == "both" ]]; then
        if check_existing_install podman &>/dev/null; then
            local info
            info=$(check_existing_install podman)
            local ver path
            ver=$(echo "$info" | cut -d: -f3)
            path=$(echo "$info" | cut -d: -f4)
            print_warn "Podman ${ver} already installed at ${path}"
            if ! confirm "Overwrite existing Podman installation?"; then
                die "Aborted by user"
            fi
        else
            print_ok "No existing Podman installation"
        fi
    fi

    # Step 4 — Download / Extract
    print_step "4" "Download / Extract"
    setup_tmpdir

    local mode src_dir
    mode=$(detect_mode)

    if [[ "$mode" == "bundled" ]]; then
        src_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
        print_ok "Using bundled binaries"
    else
        local release_json
        release_json=$(fetch_latest_release)

        local tarball_url
        tarball_url=$(echo "$release_json" | grep -o "\"browser_download_url\": *\"[^\"]*contup-[^\"]*-${ARCH}.tar.gz\"" | grep -o 'https://[^"]*' || true)

        if [[ -z "$tarball_url" ]]; then
            die "No tarball found for architecture: ${ARCH}"
        fi

        local tarball_name
        tarball_name=$(basename "$tarball_url")

        local checksum_url
        checksum_url=$(echo "$release_json" | grep -o '"browser_download_url": *"[^"]*checksums[^"]*"' | grep -o 'https://[^"]*' || true)

        download_tarball "$tarball_url" "${TMPDIR_CONTUP}/${tarball_name}"

        if [[ -n "$checksum_url" ]]; then
            local checksums
            checksums=$(curl -fsSL "$checksum_url" 2>/dev/null || true)
            if [[ -n "$checksums" ]]; then
                local expected
                expected=$(echo "$checksums" | grep "$tarball_name" | awk '{print $1}')
                if [[ -n "$expected" ]]; then
                    verify_checksum "${TMPDIR_CONTUP}/${tarball_name}" "$expected"
                fi
            fi
        fi

        src_dir="${TMPDIR_CONTUP}/extracted"
        extract_binaries "${TMPDIR_CONTUP}/${tarball_name}" "$src_dir"
    fi

    # Step 5 — Install Binaries
    print_step "5" "Install Binaries"

    if [[ "$runtime" == "docker" || "$runtime" == "both" ]]; then
        print_info "Installing Docker binaries..."
        install_binaries "$src_dir" "docker"
        if [[ "$INSTALL_MODE" == "rootless" ]]; then
            install_binaries "$src_dir" "docker-rootless"
        fi
    fi

    if [[ "$runtime" == "podman" || "$runtime" == "both" ]]; then
        print_info "Installing Podman binaries..."
        install_binaries "$src_dir" "podman"
    fi

    # Always install compose
    print_info "Installing Compose..."
    install_binaries "$src_dir" "compose"

    # Install contup.sh itself
    install_self "$src_dir"

    ensure_path
    install_shell_wrapper

    # Step 6 — Configure
    print_step "6" "Configure"

    if [[ "$runtime" == "docker" || "$runtime" == "both" ]]; then
        if [[ "$IS_ROOT" == true ]]; then
            configure_docker_root
        else
            configure_docker_rootless
        fi
    fi

    if [[ "$runtime" == "podman" || "$runtime" == "both" ]]; then
        if [[ "$IS_ROOT" == true ]]; then
            configure_podman_root
        else
            configure_podman_rootless
        fi
    fi

    configure_compose

    # Step 7 — Start Services
    if [[ "$FLAG_NO_START" != true ]]; then
        print_step "7" "Start Services"

        if [[ "$runtime" == "docker" || "$runtime" == "both" ]]; then
            start_runtime "docker"
        fi

        if [[ "$runtime" == "podman" || "$runtime" == "both" ]]; then
            start_runtime "podman"
        fi
    fi

    # Step 8 — Verify
    if [[ "$FLAG_NO_VERIFY" != true ]]; then
        print_step "8" "Verify"

        if [[ "$runtime" == "docker" || "$runtime" == "both" ]]; then
            verify_binary "docker" || true
            verify_daemon "docker" || true
            verify_runtime "docker" || true
        fi

        if [[ "$runtime" == "podman" || "$runtime" == "both" ]]; then
            verify_binary "podman" || true
            verify_daemon "podman" || true
            verify_runtime "podman" || true
        fi

        verify_compose || true
    fi

    # Step 9 — Summary
    echo ""
    local active
    active=$(get_active_runtime)
    local docker_ver podman_ver compose_ver
    docker_ver=$(get_installed_version docker)
    podman_ver=$(get_installed_version podman)
    compose_ver=$(get_installed_version compose)

    local summary_lines=()
    summary_lines+=("Mode:      ${INSTALL_MODE}")

    if [[ "$runtime" == "docker" || "$runtime" == "both" ]]; then
        summary_lines+=("Docker:    v${docker_ver:-unknown}")
    fi
    if [[ "$runtime" == "podman" || "$runtime" == "both" ]]; then
        summary_lines+=("Podman:    v${podman_ver:-unknown}")
    fi
    if [[ -n "$compose_ver" ]]; then
        summary_lines+=("Compose:   v${compose_ver}")
    fi

    summary_lines+=("Binaries:  ${BIN_DIR}")
    summary_lines+=("Socket:    ${DOCKER_HOST:-${DOCKER_HOST_SOCKET}}")
    summary_lines+=("")
    summary_lines+=("Quick start:")
    if [[ "$runtime" == "docker" || "$runtime" == "both" ]]; then
        summary_lines+=("  docker run -it alpine sh")
        summary_lines+=("  docker compose up -d")
    elif [[ "$runtime" == "podman" ]]; then
        summary_lines+=("  podman run -it alpine sh")
    fi

    print_box "${S_OK} contup — install complete" "${summary_lines[@]}"
}

cmd_uninstall() {
    local runtime="${1:-}"

    print_banner

    if [[ -z "$runtime" ]]; then
        die "Usage: contup uninstall <docker|podman|both>"
    fi

    detect_install_mode

    case "$runtime" in
        docker|podman|both) ;;
        *) die "Unknown runtime: ${runtime}" ;;
    esac

    if ! confirm "Uninstall ${runtime}? This will stop services and remove binaries."; then
        die "Aborted by user"
    fi

    # Stop services
    print_info "Stopping services..."
    if [[ "$runtime" == "docker" || "$runtime" == "both" ]]; then
        stop_runtime "docker" 2>/dev/null || true
        _systemctl disable docker.service 2>/dev/null || true
        if [[ "$IS_ROOT" == true ]]; then
            _systemctl disable containerd.service 2>/dev/null || true
        fi
    fi
    if [[ "$runtime" == "podman" || "$runtime" == "both" ]]; then
        stop_runtime "podman" 2>/dev/null || true
        _systemctl disable podman.socket 2>/dev/null || true
        _systemctl disable podman.service 2>/dev/null || true
    fi

    # Remove binaries
    print_info "Removing binaries..."
    if [[ "$runtime" == "docker" || "$runtime" == "both" ]]; then
        for bin in $DOCKER_BINARIES $DOCKER_ROOTLESS_BINARIES; do
            rm -f "${BIN_DIR}/${bin}"
        done
        print_ok "Removed Docker binaries"
    fi
    if [[ "$runtime" == "podman" || "$runtime" == "both" ]]; then
        for bin in $PODMAN_BINARIES; do
            rm -f "${BIN_DIR}/${bin}"
        done
        rm -f "${BIN_DIR}/podman-compose"
        print_ok "Removed Podman binaries"
    fi

    # Remove compose if both runtimes uninstalled
    if [[ "$runtime" == "both" ]] || { [[ "$runtime" == "docker" ]] && ! is_runtime_installed podman; } || { [[ "$runtime" == "podman" ]] && ! is_runtime_installed docker; }; then
        rm -f "${BIN_DIR}/docker-compose"
        rm -f "${CLI_PLUGINS_DIR}/docker-compose"
        print_ok "Removed Compose"
    fi

    # Remove systemd units
    print_info "Removing systemd units..."
    if [[ "$runtime" == "docker" || "$runtime" == "both" ]]; then
        rm -f "${SYSTEMD_DIR}/docker.service"
        rm -f "${SYSTEMD_DIR}/containerd.service"
    fi
    if [[ "$runtime" == "podman" || "$runtime" == "both" ]]; then
        rm -f "${SYSTEMD_DIR}/podman.socket"
        rm -f "${SYSTEMD_DIR}/podman.service"
    fi
    _systemctl daemon-reload 2>/dev/null || true
    print_ok "Removed systemd units"

    # Config files
    if confirm "Remove configuration files?"; then
        if [[ "$runtime" == "docker" || "$runtime" == "both" ]]; then
            rm -rf "$CONFIG_DIR_DOCKER"
            print_ok "Removed ${CONFIG_DIR_DOCKER}"
        fi
        if [[ "$runtime" == "podman" || "$runtime" == "both" ]]; then
            rm -rf "$CONFIG_DIR_PODMAN"
            print_ok "Removed ${CONFIG_DIR_PODMAN}"
        fi
    fi

    # Data
    if confirm "Remove all container data (images, containers, volumes)? THIS CANNOT BE UNDONE"; then
        if [[ "$runtime" == "docker" || "$runtime" == "both" ]]; then
            if [[ "$IS_ROOT" == true ]]; then
                rm -rf /var/lib/docker
                rm -rf /var/lib/containerd
            else
                rm -rf "${HOME}/.local/share/docker"
            fi
            print_ok "Removed Docker data"
        fi
        if [[ "$runtime" == "podman" || "$runtime" == "both" ]]; then
            if [[ "$IS_ROOT" == true ]]; then
                rm -rf /var/lib/containers
            else
                rm -rf "${HOME}/.local/share/containers"
            fi
            print_ok "Removed Podman data"
        fi
    fi

    # Shell profiles
    remove_shell_profile_var "DOCKER_HOST"

    # If other runtime still installed, switch to it
    if [[ "$runtime" == "docker" ]] && is_runtime_installed podman; then
        update_shell_profile "DOCKER_HOST" "$PODMAN_HOST_SOCKET"
        print_ok "Switched DOCKER_HOST to Podman"
    elif [[ "$runtime" == "podman" ]] && is_runtime_installed docker; then
        update_shell_profile "DOCKER_HOST" "$DOCKER_HOST_SOCKET"
        print_ok "Switched DOCKER_HOST to Docker"
    else
        remove_shell_wrapper
    fi

    echo ""
    print_ok "Uninstall complete"
}

cmd_update() {
    local runtime="${1:-}"

    print_banner

    detect_install_mode
    setup_tmpdir

    local runtimes_to_update=()
    if [[ -z "$runtime" || "$runtime" == "both" ]]; then
        is_runtime_installed docker && runtimes_to_update+=("docker")
        is_runtime_installed podman && runtimes_to_update+=("podman")
    else
        runtimes_to_update+=("$runtime")
    fi

    if [[ ${#runtimes_to_update[@]} -eq 0 ]]; then
        die "No runtimes installed to update"
    fi

    # Check current versions
    for rt in "${runtimes_to_update[@]}"; do
        local current
        current=$(get_installed_version "$rt")
        print_info "${rt}: current version ${current:-unknown}"
    done

    # Download latest
    local release_json
    release_json=$(fetch_latest_release)

    local tarball_url
    tarball_url=$(echo "$release_json" | grep -o "\"browser_download_url\": *\"[^\"]*contup-[^\"]*-${ARCH}.tar.gz\"" | grep -o 'https://[^"]*' || true)

    if [[ -z "$tarball_url" ]]; then
        die "No tarball found for architecture: ${ARCH}"
    fi

    local tarball_name
    tarball_name=$(basename "$tarball_url")

    download_tarball "$tarball_url" "${TMPDIR_CONTUP}/${tarball_name}"

    local src_dir="${TMPDIR_CONTUP}/extracted"
    extract_binaries "${TMPDIR_CONTUP}/${tarball_name}" "$src_dir"

    # Stop → replace → start
    for rt in "${runtimes_to_update[@]}"; do
        local old_ver
        old_ver=$(get_installed_version "$rt")

        print_info "Updating ${rt}..."

        if is_runtime_running "$rt"; then
            stop_runtime "$rt"
        fi

        install_binaries "$src_dir" "$rt"

        if [[ "$rt" == "docker" && "$INSTALL_MODE" == "rootless" ]]; then
            install_binaries "$src_dir" "docker-rootless"
        fi

        if [[ "$rt" == "podman" ]]; then
            write_containers_conf "$CONFIG_DIR_PODMAN"
        fi

        if [[ "$FLAG_NO_START" != true ]]; then
            start_runtime "$rt"
        fi

        local new_ver
        new_ver=$(get_installed_version "$rt")
        print_ok "${rt}: ${old_ver:-unknown} → ${new_ver:-unknown}"
    done

    # Update compose
    if [[ -d "${src_dir}/compose" ]]; then
        install_binaries "$src_dir" "compose"
        install_cli_plugins
        print_ok "Compose updated"
    fi

    # Update contup.sh itself
    install_self "$src_dir"

    # Verify
    if [[ "$FLAG_NO_VERIFY" != true ]]; then
        echo ""
        for rt in "${runtimes_to_update[@]}"; do
            verify_binary "$rt" || true
            verify_daemon "$rt" || true
        done
    fi

    echo ""
    print_ok "Update complete"
}

cmd_start() {
    local runtime="${1:-}"
    detect_install_mode

    if [[ -z "$runtime" ]]; then
        is_runtime_installed docker && start_runtime "docker"
        is_runtime_installed podman && start_runtime "podman"
    else
        start_runtime "$runtime"
    fi
}

cmd_stop() {
    local runtime="${1:-}"
    detect_install_mode

    if [[ -z "$runtime" ]]; then
        is_runtime_installed docker && stop_runtime "docker"
        is_runtime_installed podman && stop_runtime "podman"
    else
        stop_runtime "$runtime"
    fi
}

cmd_restart() {
    local runtime="${1:-}"
    detect_install_mode

    if [[ -z "$runtime" ]]; then
        is_runtime_installed docker && restart_runtime "docker"
        is_runtime_installed podman && restart_runtime "podman"
    else
        restart_runtime "$runtime"
    fi
}

cmd_switch() {
    local target="${1:-}"

    if [[ -z "$target" ]]; then
        die "Usage: contup switch <docker|podman>"
    fi

    detect_install_mode

    case "$target" in
        docker)
            if ! is_runtime_installed docker; then
                die "Docker is not installed"
            fi
            if ! is_runtime_running docker; then
                print_warn "Docker is not running — starting..."
                start_runtime "docker"
            fi
            update_shell_profile "DOCKER_HOST" "$DOCKER_HOST_SOCKET"
            ;;
        podman)
            if ! is_runtime_installed podman; then
                die "Podman is not installed"
            fi
            if ! is_runtime_running podman; then
                print_warn "Podman is not running — starting..."
                start_runtime "podman"
            fi
            update_shell_profile "DOCKER_HOST" "$PODMAN_HOST_SOCKET"
            ;;
        *)
            die "Unknown runtime: ${target}. Use: docker or podman"
            ;;
    esac

    # Update compose symlinks
    if [[ "$target" == "podman" ]]; then
        create_podman_compose_symlink
    fi

    local socket
    case "$target" in
        docker) socket="$DOCKER_HOST_SOCKET" ;;
        podman) socket="$PODMAN_HOST_SOCKET" ;;
    esac

    echo ""
    print_box "${S_OK} Switched to ${target^}" \
        "DOCKER_HOST=${socket}"
}

cmd_test() {
    local runtime="${1:-}"

    print_banner
    detect_install_mode

    local runtimes_to_test=()
    if [[ -z "$runtime" ]]; then
        is_runtime_installed docker && runtimes_to_test+=("docker")
        is_runtime_installed podman && runtimes_to_test+=("podman")
    else
        runtimes_to_test+=("$runtime")
    fi

    if [[ ${#runtimes_to_test[@]} -eq 0 ]]; then
        die "No runtimes installed to test"
    fi

    local total_pass=0 total_fail=0

    for rt in "${runtimes_to_test[@]}"; do
        local cmd="$rt"
        local pass=0 fail=0

        echo -e "\n${C_BOLD}Testing ${rt^}${C_RESET}"

        if ! is_runtime_running "$rt"; then
            print_fail "${rt} is not running"
            ((total_fail++)) || true
            continue
        fi

        # Test 1: hello-world
        if $cmd run --rm hello-world &>/dev/null; then
            print_ok "hello-world"
            ((pass++)) || true
        else
            print_fail "hello-world"
            ((fail++)) || true
        fi

        # Test 2: alpine echo
        if $cmd run --rm alpine echo "contup test ok" &>/dev/null; then
            print_ok "alpine echo"
            ((pass++)) || true
        else
            print_fail "alpine echo"
            ((fail++)) || true
        fi

        # Test 3: nginx port mapping
        local container_id
        container_id=$($cmd run -d -p 0:80 nginx 2>/dev/null) || true
        if [[ -n "$container_id" ]]; then
            sleep 2
            local port
            port=$($cmd port "$container_id" 80 2>/dev/null | head -1 | cut -d: -f2)
            if [[ -n "$port" ]] && curl -sf "http://localhost:${port}" &>/dev/null; then
                print_ok "nginx port map"
                ((pass++)) || true
            else
                print_fail "nginx port map"
                ((fail++)) || true
            fi
            $cmd rm -f "$container_id" &>/dev/null || true
        else
            print_fail "nginx port map"
            ((fail++)) || true
        fi

        # Test 4: compose
        local compose_cmd=""
        if command -v docker-compose &>/dev/null; then
            compose_cmd="docker-compose"
        elif command -v podman-compose &>/dev/null; then
            compose_cmd="podman-compose"
        fi

        if [[ -n "$compose_cmd" ]]; then
            local tmpdir
            tmpdir=$(mktemp -d /tmp/contup-test.XXXXXX)
            cat > "${tmpdir}/compose.yml" <<'COMPOSEYML'
services:
  web:
    image: nginx:alpine
    ports:
      - "0:80"
COMPOSEYML
            if (cd "$tmpdir" && $compose_cmd up -d &>/dev/null && sleep 2 && $compose_cmd down &>/dev/null); then
                print_ok "compose up/down"
                ((pass++)) || true
            else
                print_fail "compose up/down"
                ((fail++)) || true
                (cd "$tmpdir" && $compose_cmd down &>/dev/null 2>&1 || true)
            fi
            rm -rf "$tmpdir"
        else
            print_warn "compose — not available, skipped"
        fi

        # Cleanup
        print_dim "Cleaning up test artifacts..."
        $cmd rmi hello-world alpine nginx nginx:alpine &>/dev/null 2>&1 || true
        $cmd system prune -f &>/dev/null 2>&1 || true

        total_pass=$((total_pass + pass))
        total_fail=$((total_fail + fail))

        echo ""
        print_info "${rt^}: ${pass}/$((pass + fail)) passed"
    done

    # Summary
    echo ""
    if [[ $total_fail -eq 0 ]]; then
        print_box "contup — test results" \
            "${total_pass}/$((total_pass + total_fail)) passed ${S_OK}"
    else
        print_box "contup — test results" \
            "${total_pass}/$((total_pass + total_fail)) passed, ${total_fail} failed ${S_FAIL}"
        return 1
    fi
}

cmd_status() {
    detect_install_mode

    local lines=()

    # Docker
    if is_runtime_installed docker; then
        local ver state state_color
        ver=$(get_installed_version docker)
        if is_runtime_running docker; then
            state="${S_OK} running"
            state_color="${C_GREEN}"
        else
            state="${S_FAIL} stopped"
            state_color="${C_RED}"
        fi
        lines+=("$(printf "Docker:    v%-10s %b%-12s%b %s" "${ver:-?}" "$state_color" "$state" "$C_RESET" "$BIN_DIR")")
    else
        lines+=("Docker:    not installed")
    fi

    # Compose
    if is_runtime_installed compose; then
        local ver
        ver=$(get_installed_version compose)
        lines+=("$(printf "Compose:   v%-10s %b${S_OK} installed%b" "${ver:-?}" "$C_GREEN" "$C_RESET")")
    else
        lines+=("Compose:   not installed")
    fi

    # Podman
    if is_runtime_installed podman; then
        local ver state state_color
        ver=$(get_installed_version podman)
        if is_runtime_running podman; then
            state="${S_OK} running"
            state_color="${C_GREEN}"
        else
            state="${S_FAIL} stopped"
            state_color="${C_RED}"
        fi
        lines+=("$(printf "Podman:    v%-10s %b%-12s%b %s" "${ver:-?}" "$state_color" "$state" "$C_RESET" "$BIN_DIR")")
    else
        lines+=("Podman:    not installed")
    fi

    lines+=("")

    # Active runtime
    local active
    active=$(get_active_runtime)
    if [[ -n "$active" ]]; then
        lines+=("Active:    ${active^}  ◀")
    fi
    lines+=("Mode:      ${INSTALL_MODE}")
    lines+=("Socket:    ${DOCKER_HOST:-none}")
    lines+=("contup:    v${CONTUP_VERSION}")

    print_box "contup — status" "${lines[@]}"
}

cmd_info() {
    detect_install_mode

    local lines=()

    # System info
    lines+=("System:")
    lines+=("  OS:           ${OS_NAME} ${OS_VERSION}")
    lines+=("  Kernel:       ${KERNEL_VERSION}")
    lines+=("  Arch:         ${ARCH}")

    # cgroups
    if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
        lines+=("  cgroups:      v2")
    elif [[ -d /sys/fs/cgroup/cpu ]]; then
        lines+=("  cgroups:      v1")
    else
        lines+=("  cgroups:      unknown")
    fi

    # Init system
    local init_ver=""
    if command -v systemctl &>/dev/null; then
        init_ver="systemd $(systemctl --version 2>/dev/null | head -1 | awk '{print $2}')"
    fi
    lines+=("  Init:         ${init_ver:-unknown}")
    lines+=("  Mode:         ${INSTALL_MODE}")
    lines+=("")

    # Docker info
    if is_runtime_installed docker; then
        local ver state
        ver=$(get_installed_version docker)
        if is_runtime_running docker; then
            state="${S_OK} running"

            local storage data_root containers images volumes disk_usage
            storage=$(docker info --format '{{.Driver}}' 2>/dev/null || echo "unknown")
            data_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "unknown")

            local running stopped paused
            running=$(docker info --format '{{.ContainersRunning}}' 2>/dev/null || echo "0")
            stopped=$(docker info --format '{{.ContainersStopped}}' 2>/dev/null || echo "0")
            paused=$(docker info --format '{{.ContainersPaused}}' 2>/dev/null || echo "0")
            containers="$((running + stopped + paused)) (${running} running, ${stopped} stopped, ${paused} paused)"

            images=$(docker info --format '{{.Images}}' 2>/dev/null || echo "?")
            volumes=$(docker volume ls -q 2>/dev/null | wc -l | tr -d ' ')
            disk_usage=$(docker system df --format 'table {{.Type}}: {{.Size}}' 2>/dev/null | tr '\n' ', ' | sed 's/, $//' || echo "?")

            lines+=("Docker:         v${ver}   ${state}")
            lines+=("  Storage:      ${storage}")
            lines+=("  Data Root:    ${data_root}")
            lines+=("  Containers:   ${containers}")
            lines+=("  Images:       ${images}")
            lines+=("  Volumes:      ${volumes}")
            lines+=("  Disk Usage:   ${disk_usage}")
        else
            lines+=("Docker:         v${ver}   ${S_FAIL} stopped")
        fi
    else
        lines+=("Docker:         not installed")
    fi
    lines+=("")

    # Compose info
    if is_runtime_installed compose; then
        local ver
        ver=$(get_installed_version compose)
        lines+=("Compose:        v${ver}")
    else
        lines+=("Compose:        not installed")
    fi
    lines+=("")

    # Podman info
    if is_runtime_installed podman; then
        local ver state
        ver=$(get_installed_version podman)
        if is_runtime_running podman; then
            state="${S_OK} running"

            local storage data_root containers images volumes disk_usage
            storage=$(podman info --format '{{.Store.GraphDriverName}}' 2>/dev/null || echo "unknown")
            data_root=$(podman info --format '{{.Store.GraphRoot}}' 2>/dev/null || echo "unknown")

            local total running
            total=$(podman ps -a --format '{{.ID}}' 2>/dev/null | wc -l | tr -d ' ')
            running=$(podman ps --format '{{.ID}}' 2>/dev/null | wc -l | tr -d ' ')
            containers="${total} (${running} running)"

            images=$(podman images --format '{{.ID}}' 2>/dev/null | wc -l | tr -d ' ')
            volumes=$(podman volume ls -q 2>/dev/null | wc -l | tr -d ' ')
            disk_usage=$(podman system df --format 'table {{.Type}}: {{.Size}}' 2>/dev/null | tr '\n' ', ' | sed 's/, $//' || echo "?")

            lines+=("Podman:         v${ver}   ${state}")
            lines+=("  Storage:      ${storage}")
            lines+=("  Data Root:    ${data_root}")
            lines+=("  Containers:   ${containers}")
            lines+=("  Images:       ${images}")
            lines+=("  Volumes:      ${volumes}")
            lines+=("  Disk Usage:   ${disk_usage}")
        else
            lines+=("Podman:         v${ver}   ${S_FAIL} stopped")
        fi
    else
        lines+=("Podman:         not installed")
    fi
    lines+=("")

    # Footer
    local active
    active=$(get_active_runtime)
    if [[ -n "$active" ]]; then
        lines+=("Active:         ${active^}  ◀")
    fi
    lines+=("DOCKER_HOST:    ${DOCKER_HOST:-not set}")
    lines+=("contup:         v${CONTUP_VERSION}")

    print_box "contup — info" "${lines[@]}"
}

cmd_help() {
    print_banner
    echo "Usage: contup <command> [runtime] [flags]"
    echo ""
    echo "Commands:"
    echo "  install   [docker|podman|both]    Install container runtime"
    echo "  uninstall [docker|podman|both]    Remove runtime and configs"
    echo "  update    [docker|podman|both]    Update to latest version"
    echo "  start     [docker|podman]         Start runtime services"
    echo "  stop      [docker|podman]         Stop runtime services"
    echo "  restart   [docker|podman]         Restart runtime services"
    echo "  switch    <docker|podman>         Switch active runtime"
    echo "  test      [docker|podman]         Test runtime with containers"
    echo "  status                            Show runtime status"
    echo "  info                              Show system and runtime details"
    echo "  help                              Show this help"
    echo ""
    echo "Flags:"
    echo "  -y, --yes       Auto-confirm all prompts"
    echo "  --offline        Use bundled binaries only (no download)"
    echo "  --no-start       Skip starting services after install/update"
    echo "  --no-verify      Skip verification after install/update"
    echo ""
    echo "Examples:"
    echo "  contup install docker         Install Docker with Compose"
    echo "  contup install podman -y      Install Podman non-interactively"
    echo "  contup switch podman          Switch DOCKER_HOST to Podman"
    echo "  contup update                 Update all installed runtimes"
    echo "  contup test                   Test all installed runtimes"
    echo "  contup status                 Show current status"
    echo "  contup info                   Show detailed system info"
}

## Entry point

parse_args() {
    local command="" runtime="" args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)       FLAG_YES=true ;;
            --offline)      FLAG_OFFLINE=true ;;
            --no-start)     FLAG_NO_START=true ;;
            --no-verify)    FLAG_NO_VERIFY=true ;;
            -h|--help)      command="help" ;;
            -v|--version)   echo "contup v${CONTUP_VERSION}"; exit 0 ;;
            -*)             die "Unknown flag: $1" ;;
            *)              args+=("$1") ;;
        esac
        shift
    done

    if [[ ${#args[@]} -gt 0 ]]; then
        command="${args[0]}"
    fi
    if [[ ${#args[@]} -gt 1 ]]; then
        runtime="${args[1]}"
    fi

    # Default: if piped (curl | bash), install contup CLI only
    if [[ -z "$command" ]]; then
        if [[ ! -t 0 ]]; then
            command="setup"
            FLAG_YES=true
        else
            command="help"
        fi
    fi

    # Detect system early for commands that need it
    detect_arch
    detect_os

    case "$command" in
        setup)      cmd_setup ;;
        install)    cmd_install "$runtime" ;;
        uninstall)  cmd_uninstall "$runtime" ;;
        update)     cmd_update "$runtime" ;;
        start)      cmd_start "$runtime" ;;
        stop)       cmd_stop "$runtime" ;;
        restart)    cmd_restart "$runtime" ;;
        switch)     cmd_switch "$runtime" ;;
        test)       cmd_test "$runtime" ;;
        status)     cmd_status ;;
        info)       cmd_info ;;
        help)       cmd_help ;;
        *)          die "Unknown command: ${command}. Run 'contup help' for usage." ;;
    esac
}

parse_args "$@"
