# 📦 contup

[![contup](https://img.shields.io/badge/contup-v2.0.1-green)](https://github.com/diphyx/contup/releases)
[![Docker](https://img.shields.io/badge/Docker-v29.2.1-blue)](https://github.com/moby/moby)
[![Podman](https://img.shields.io/badge/Podman-v5.8.0-purple)](https://github.com/containers/podman)
[![Compose](https://img.shields.io/badge/Compose-v5.0.2-blue)](https://github.com/docker/compose)

> **cont**ainer **up** — Prebuilt container runtime binaries for Linux with an interactive installer.

Static builds of **Docker**, **Podman**, and **Docker Compose** — compiled from official sources, bundled into architecture-specific tarballs, and published to [GitHub Releases](https://github.com/diphyx/contup/releases).

---

## 🚀 Quick Start

```bash
curl -fsSL diphyx.github.io/contup/setup.sh | bash
```

### Install a runtime

```bash
# Install Docker + Compose
contup install docker

# Install Podman + Compose
contup install podman

# Install both Docker and Podman + Compose
contup install both
```

---

## 🤔 Why contup?

No repos. No dependencies. No distro-specific packages. Just **static binaries** from official sources.

- 🔒 **No root access** — HPC users, shared servers, or locked-down machines where you can't `sudo`
- 🌐 **Restricted networks** — environments behind firewalls that block distro repos but allow GitHub
- ✈️ **Offline / air-gapped** — download one tarball, transfer via USB or scp, install without network
- 📭 **No package manager** — minimal containers, scratch VMs, or custom distros without apt/yum/dnf

---

## ✨ Features

- 🏗️ Static prebuilt binaries from official upstream sources
- 🐳 Docker and Podman support with seamless switching
- 👤 Root and rootless installation modes
- 🎯 Interactive arrow-key menu for runtime selection
- ⚙️ Automatic systemd service configuration
- 🔌 Docker Compose as both standalone binary and CLI plugin
- ✅ Checksum verification for downloaded tarballs
- 📦 Offline installation from bundled tarballs

---

## 🖥️ Supported Architectures

| Architecture | Target  |
| ------------ | ------- |
| x86_64       | `amd64` |
| aarch64      | `arm64` |

---

## 📋 Requirements

- 🐧 Linux with kernel >= 4.18
- 🔧 systemd
- 📂 cgroups v2 (v1 supported with warnings)
- 🔥 iptables or nftables

### 👤 Rootless Prerequisites

Rootless mode requires `newuidmap`/`newgidmap` and unprivileged user namespaces. An administrator must configure these before installing:

```bash
# Ubuntu / Debian (Ubuntu 23.10+ also needs userns fix)
sudo apt install uidmap
echo "kernel.apparmor_restrict_unprivileged_userns=0" | sudo tee /etc/sysctl.d/99-rootless.conf && sudo sysctl --system

# Fedora
sudo dnf install shadow-utils

# CentOS / RHEL / Rocky / Alma (RHEL 7 also needs userns fix)
sudo yum install shadow-utils
echo "kernel.unprivileged_userns_clone=1" | sudo tee /etc/sysctl.d/99-rootless.conf && sudo sysctl --system

# Arch / Manjaro
sudo pacman -S shadow

# openSUSE / SLES
sudo zypper install shadow

# Alpine
sudo apk add shadow-uidmap
```

> contup automatically detects missing prerequisites during install and shows the exact commands to fix them.

---

## 💻 Usage

```
contup <command> [runtime] [flags]
```

### Commands

| Command     | Arguments                | Description                     |
| ----------- | ------------------------ | ------------------------------- |
| `setup`     |                          | Install contup CLI only         |
| `install`   | `[docker\|podman\|both]` | Install container runtime       |
| `uninstall` | `[docker\|podman\|both]` | Remove runtime and configs      |
| `update`    | `[docker\|podman\|both]` | Update to latest version        |
| `start`     | `[docker\|podman]`       | Start runtime services          |
| `stop`      | `[docker\|podman]`       | Stop runtime services           |
| `restart`   | `[docker\|podman]`       | Restart runtime services        |
| `switch`    | `<docker\|podman>`       | Switch active runtime           |
| `test`      | `[docker\|podman]`       | Test runtime with containers    |
| `status`    |                          | Show runtime status             |
| `info`      |                          | Show system and runtime details |
| `help`      |                          | Show help                       |

### Flags

| Flag              | Description                                 |
| ----------------- | ------------------------------------------- |
| `-y`, `--yes`     | Auto-confirm all prompts                    |
| `--offline`       | Use bundled binaries only (no download)     |
| `--no-start`      | Skip starting services after install/update |
| `--no-verify`     | Skip verification after install/update      |
| `-v`, `--version` | Show version                                |
| `-h`, `--help`    | Show help                                   |

### Examples

```bash
# Install Docker with Compose (interactive)
contup install docker

# Install Podman non-interactively
contup install podman -y

# Install both Docker and Podman
contup install both

# Switch active runtime to Podman
contup switch podman

# Update all installed runtimes
contup update

# Run tests against installed runtimes
contup test

# Show current status
contup status

# Show detailed system and runtime info
contup info

# Offline install from extracted tarball
contup install docker --offline
```

---

## 🔐 Installation Modes

### 🛡️ Root

When run as root (or with `sudo`), contup installs to:

| Path                                 | Purpose              |
| ------------------------------------ | -------------------- |
| `/usr/local/bin/`                    | Binaries             |
| `/etc/docker/`                       | Docker configuration |
| `/etc/containers/`                   | Podman configuration |
| `/etc/systemd/system/`               | Systemd units        |
| `/usr/local/lib/docker/cli-plugins/` | Docker CLI plugins   |

### 👤 Rootless

When run as a regular user, contup installs to:

| Path                      | Purpose              |
| ------------------------- | -------------------- |
| `~/.local/bin/`           | Binaries             |
| `~/.config/docker/`       | Docker configuration |
| `~/.config/containers/`   | Podman configuration |
| `~/.config/systemd/user/` | Systemd user units   |
| `~/.docker/cli-plugins/`  | Docker CLI plugins   |

> Rootless mode uses `dockerd-rootless.sh` for Docker and configures user-scoped systemd services with `loginctl enable-linger`.

---

## 🧩 What Gets Installed

### 🐳 Docker Stack

| Binary                    | Source                                                                                |
| ------------------------- | ------------------------------------------------------------------------------------- |
| `docker`                  | [docker/cli](https://github.com/docker/cli)                                           |
| `dockerd`                 | [moby/moby](https://github.com/moby/moby)                                             |
| `containerd`              | [containerd/containerd](https://github.com/containerd/containerd)                     |
| `containerd-shim-runc-v2` | [containerd/containerd](https://github.com/containerd/containerd)                     |
| `runc`                    | [opencontainers/runc](https://github.com/opencontainers/runc)                         |
| `docker-proxy`            | [moby/moby](https://github.com/moby/moby)                                             |
| `docker-init`             | [krallin/tini](https://github.com/krallin/tini)                                       |
| `rootlesskit`             | [rootless-containers/rootlesskit](https://github.com/rootless-containers/rootlesskit) |
| `dockerd-rootless.sh`     | [moby/moby](https://github.com/moby/moby)                                             |

### 🦭 Podman Stack

> The `podman` binary is built as a statically linked binary with the API service included, managed via systemd socket activation.

| Binary           | Source                                                                                |
| ---------------- | ------------------------------------------------------------------------------------- |
| `podman`         | [containers/podman](https://github.com/containers/podman)                             |
| `crun`           | [containers/crun](https://github.com/containers/crun)                                 |
| `conmon`         | [containers/conmon](https://github.com/containers/conmon)                             |
| `netavark`       | [containers/netavark](https://github.com/containers/netavark)                         |
| `aardvark-dns`   | [containers/aardvark-dns](https://github.com/containers/aardvark-dns)                 |
| `slirp4netns`    | [rootless-containers/slirp4netns](https://github.com/rootless-containers/slirp4netns) |
| `fuse-overlayfs` | [containers/fuse-overlayfs](https://github.com/containers/fuse-overlayfs)             |

### 🔌 Compose

| Binary           | Source                                              |
| ---------------- | --------------------------------------------------- |
| `docker-compose` | [docker/compose](https://github.com/docker/compose) |

> Installed as a standalone binary and as a Docker CLI plugin (`docker compose`). Works with both Docker and Podman — when Podman is installed, contup automatically creates a `podman-compose` symlink to `docker-compose`.

---

## 🔀 Runtime Switching

When both Docker and Podman are installed, `contup switch` changes the `DOCKER_HOST` environment variable to point to the selected runtime's socket:

```bash
# Switch to Podman
contup switch podman

# Switch back to Docker
contup switch docker
```

> During installation, contup adds a shell wrapper function that automatically reloads environment variables after switching — no manual `source ~/.bashrc` needed.

---

## ✈️ Offline Installation

Download a release tarball, extract it, and run contup with `--offline`:

```bash
# Extract the tarball
tar -xzf contup-v1.0.0-amd64.tar.gz
cd contup-v1.0.0-amd64

# Install using bundled binaries
./contup.sh install docker --offline
```

---

## 📄 License

MIT
