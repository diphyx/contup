# 🛠️ Development Guide

## 🚢 Publishing

Use `publish.sh` to bump the version and optionally trigger a CI workflow:

```bash
./publish.sh
```

**Step 1 — Version bump:**

| Option | Action                  |
| ------ | ----------------------- |
| 0      | Update commit hash only |
| 1      | Bump hotfix (x.y.Z)     |
| 2      | Bump minor (x.Y.0)      |
| 3      | Bump major (X.0.0)      |

**Step 2 — Release action:**

| Option | Action                            |
| ------ | --------------------------------- |
| 0      | Skip (keep changes local)         |
| 1      | Commit and push to origin         |
| 2      | Push and trigger build workflow   |
| 3      | Push and trigger release workflow |

**Step 3 — Build inputs (only when build is selected):**

| Input    | Option | Value  |
| -------- | ------ | ------ |
| Platform | 0      | both   |
|          | 1      | amd64  |
|          | 2      | arm64  |
| Runtime  | 0      | both   |
|          | 1      | docker |
|          | 2      | podman |
| Compose  | 0      | true   |
|          | 1      | false  |
| Buildx   | 0      | true   |
|          | 1      | false  |

---

## 🔧 CI/CD Pipeline

The build pipeline is fully automated via GitHub Actions with three workflows:

### Workflows

| Workflow    | Trigger           | Purpose                                                            |
| ----------- | ----------------- | ------------------------------------------------------------------ |
| **Build**   | Manual / Reusable | Build binaries, run smoke tests, bundle tarballs                   |
| **Verify**  | Called by Release | Full CLI lifecycle test (install, test, status, switch, uninstall) |
| **Release** | Manual            | Build → Verify → Publish GitHub Release                            |

### Build Inputs

| Input      | Options                    | Default | Description                  |
| ---------- | -------------------------- | ------- | ---------------------------- |
| `version`  | any string                 | `dev`   | Release version tag          |
| `platform` | `both`, `amd64`, `arm64`   | `both`  | Target architecture platform |
| `runtime`  | `both`, `docker`, `podman` | `both`  | Container runtime target     |
| `compose`  | `true`, `false`            | `true`  | Include Docker Compose       |
| `buildx`   | `true`, `false`            | `true`  | Include Docker Buildx        |

### Pipeline Stages

Each component builds in its own job, so wall-clock time is the slowest single
component rather than the sum of all of them. amd64 runs on `ubuntu-latest`,
arm64 natively on `ubuntu-24.04-arm` — no cross-compilation.

```
Plan            Build (arch × component, parallel)   Bundle (per arch)
 └─ plan-matrix  ├─ docker-cli                        ├─ Download parts
                 ├─ moby                              ├─ Unpack parts
                 ├─ containerd                        ├─ Test binaries (amd64)
                 ├─ docker-extras                     ├─ Bundle tarball
                 ├─ buildx                            └─ Upload artifact
                 ├─ compose
                 ├─ podman            each job:
                 ├─ podman-extras      load versions → toolchain → cache
                 └─ podman-net         → build → stage → upload part
```

```
Verify                    Release
 ├─ Download artifact      ├─ Download artifacts
 ├─ Find tarball           ├─ Create checksums
 └─ Verify dockpod         └─ Create GitHub release
     ├─ install (--with-buildx on docker)
     ├─ test
     ├─ status / info
     ├─ stop / start / restart
     ├─ switch
     └─ uninstall
```

### Components

| Component       | Produces                                              | Toolchain  |
| --------------- | ----------------------------------------------------- | ---------- |
| `docker-cli`    | `docker`                                              | Go         |
| `moby`          | `dockerd`, `docker-proxy`, `dockerd-rootless.sh`      | Go + CGO   |
| `containerd`    | `containerd`, `containerd-shim-runc-v2`               | Go         |
| `docker-extras` | `runc`, `docker-init`, `rootlesskit`, `slirp4netns`   | Go + C     |
| `buildx`        | `docker-buildx`                                       | Go         |
| `compose`       | `docker-compose`                                      | Go         |
| `podman`        | `podman`                                              | Go + CGO   |
| `podman-extras` | `crun`, `conmon`, `slirp4netns`, `fuse-overlayfs`     | C          |
| `podman-net`    | `netavark`, `aardvark-dns`                            | Rust       |

Run a single component locally with `COMPONENT=<name> .github/scripts/build-binaries.sh`,
or the whole set with `COMPONENT=all` (honors `RUNTIME` / `COMPOSE` / `BUILDX`).
`stage-binaries.sh` then copies the results into the release layout, and
`bundle-tarball.sh` strips and packs whatever is staged.

### Caching

`GOCACHE` is cached per arch and component, the Cargo registry and Rust target
dirs per arch — both keyed on a hash of `versions.env`, so a rebuild at
unchanged versions reuses compiled packages.

### Build Approach

**Built from source:**

- Docker CLI, dockerd, containerd, runc, tini, rootlesskit
- conmon, podman, netavark, aardvark-dns
- Docker Compose, Docker Buildx

**Pre-built static binaries from GitHub Releases:**

- crun, slirp4netns, fuse-overlayfs
