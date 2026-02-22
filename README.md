# 📦 contup

> **cont**ainer **up** — Prebuilt container runtime binaries for Linux with an interactive installer.

Static builds of **Docker**, **Podman**, and **Docker Compose** — compiled from official sources, bundled into architecture-specific tarballs, and published to [GitHub Releases](https://github.com/diphyx/contup/releases).

---

## 🚀 Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/diphyx/contup/main/contup.sh | bash
```

> Installs Docker + Compose with default settings. For more control, download `contup.sh` and run it directly.

---

## 🤔 Why contup?

No repos. No dependencies. No distro-specific packages. Just **static binaries** from official sources.

| Scenario                    | Description                                                               |
| --------------------------- | ------------------------------------------------------------------------- |
| 🔒 **No root access**       | HPC users, shared servers, or locked-down machines where you can't `sudo` |
| 🌐 **Restricted networks**  | Environments behind firewalls that block distro repos but allow GitHub    |
| ✈️ **Offline / air-gapped** | Download one tarball, transfer via USB or scp, install without network    |
| 📭 **No package manager**   | Minimal containers, scratch VMs, or custom distros without apt/yum/dnf    |

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
- 👤 For rootless mode: `newuidmap` / `newgidmap`

---

## 💻 Usage

```
contup <command> [runtime] [flags]
```

### Commands

| Command     | Arguments                | Description                        |
| ----------- | ------------------------ | ---------------------------------- |
| `install`   | `[docker\|podman\|both]` | 📥 Install container runtime       |
| `uninstall` | `[docker\|podman\|both]` | 🗑️ Remove runtime and configs      |
| `update`    | `[docker\|podman\|both]` | 🔄 Update to latest version        |
| `start`     | `[docker\|podman]`       | ▶️ Start runtime services          |
| `stop`      | `[docker\|podman]`       | ⏹️ Stop runtime services           |
| `restart`   | `[docker\|podman]`       | 🔁 Restart runtime services        |
| `switch`    | `<docker\|podman>`       | 🔀 Switch active runtime           |
| `test`      | `[docker\|podman]`       | 🧪 Test runtime with containers    |
| `status`    |                          | 📊 Show runtime status             |
| `info`      |                          | ℹ️ Show system and runtime details |
| `help`      |                          | ❓ Show help                       |

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

### 🔌 Compose

| Binary           | Source                                              |
| ---------------- | --------------------------------------------------- |
| `docker-compose` | [docker/compose](https://github.com/docker/compose) |

> Installed as both a standalone binary and a Docker CLI plugin (`docker compose`).

### 🦭 Podman Stack

> The `podman` binary is built as a remote client (`CGO_ENABLED=0` with `remote` build tag) that connects to the podman socket service managed by systemd.

| Binary           | Source                                                                                |
| ---------------- | ------------------------------------------------------------------------------------- |
| `podman`         | [containers/podman](https://github.com/containers/podman)                             |
| `crun`           | [containers/crun](https://github.com/containers/crun)                                 |
| `conmon`         | [containers/conmon](https://github.com/containers/conmon)                             |
| `netavark`       | [containers/netavark](https://github.com/containers/netavark)                         |
| `aardvark-dns`   | [containers/aardvark-dns](https://github.com/containers/aardvark-dns)                 |
| `slirp4netns`    | [rootless-containers/slirp4netns](https://github.com/rootless-containers/slirp4netns) |
| `fuse-overlayfs` | [containers/fuse-overlayfs](https://github.com/containers/fuse-overlayfs)             |

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
tar -xzf contup-v1.0.0-amd64.tar.gz
cd contup-v1.0.0-amd64
./contup.sh install docker --offline
```

---

## 🔖 Version Management

Component versions are pinned in [`versions.env`](versions.env). Docker dependency versions (containerd, runc, tini, rootlesskit) are derived from the moby/moby Dockerfile to ensure compatibility.

A weekly GitHub Actions workflow ([`versions.yml`](.github/workflows/versions.yml)) automatically resolves and updates these versions.

---

## 📄 License

MIT
