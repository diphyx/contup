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

```
Build                          Verify                    Release
 ├─ Load versions              ├─ Download artifact      ├─ Download artifacts
 ├─ Setup Go + Rust            ├─ Find tarball            ├─ Create checksums
 ├─ Build binaries             └─ Verify dockpod           └─ Create GitHub release
 ├─ Test binaries (amd64)          ├─ install
 ├─ Bundle tarball                 ├─ test
 └─ Upload artifact                ├─ status / info
                                   ├─ stop / start / restart
                                   ├─ switch
                                   └─ uninstall
```

### Build Approach

**Built from source:**

- Docker CLI, dockerd, containerd, runc, tini, rootlesskit
- conmon, podman, netavark, aardvark-dns
- Docker Compose, Docker Buildx

**Pre-built static binaries from GitHub Releases:**

- crun, slirp4netns, fuse-overlayfs
