# AGENTS.md — netbsd-builder

## Project Overview

This is a **Packer-based VM image builder for NetBSD**. It produces qcow2 disk images
used by the [cross-platform-actions/action](https://github.com/cross-platform-actions/action)
GitHub Action. The build automates the full NetBSD installer via QEMU simulated keyboard
input (Packer `boot_steps`), then provisions the VM over SSH.

**Languages:** HCL2 (Packer), Shell (sh/bash), YAML (CI)
**No compiled source code** — this is an infrastructure/DevOps project.

## Build Commands

### Prerequisites

- [HashiCorp Packer](https://www.packer.io/) >= 1.7.2 (CI uses 1.8.4)
- [QEMU](https://www.qemu.org/)

### Build an Image

```sh
./build.sh <version> <architecture> [extra-packer-args...]

# Examples:
./build.sh 10.1 x86-64
./build.sh 10.1 arm64
./build.sh 9.4 x86-64

# Headless (no GUI window, used in CI):
./build.sh 10.1 x86-64 -var 'headless=true'
```

The script runs `packer init .` then `packer build` with layered variable files.
Output goes to `output/netbsd-<version>-<architecture>.qcow2`.

### Run a Built Image Locally

```sh
# Edit run.sh to point at the correct image, then:
./run.sh
```

### Validate Packer Template

```sh
packer init .
packer validate \
  -var os_version="10.1" \
  -var-file var_files/common.pkrvars.hcl \
  -var-file var_files/x86-64.pkrvars.hcl \
  -var-file var_files/10.1/x86-64.pkrvars.hcl \
  -var-file var_files/10.1/common.pkrvars.hcl \
  netbsd.pkr.hcl
```

### Format HCL Files

```sh
packer fmt netbsd.pkr.hcl
packer fmt var_files/
```

## Testing

There is **no unit test framework**. Testing is done entirely via CI:

1. The built qcow2 image is served over HTTP
2. `cross-platform-actions/action@master` boots the VM
3. Shell assertions verify: `uname` output, hostname, working directory, file sync

There is no way to run a single test locally. To verify changes, either build and
manually test the image with `run.sh`, or push to a branch to trigger CI.

## CI/CD (.github/workflows/build.yml)

- **Triggers:** push to any branch, tags `v*`, PRs to `master`
- **Runner:** `ubuntu-latest`
- **Matrix:** versions (9.2, 9.3, 9.4, 10.0, 10.1) x architectures (x86-64, arm64)
  - ARM64 excluded for 9.x versions
- **Release:** on `v*` tags, creates a draft GitHub release with built images

## Project Structure

```
netbsd-builder/
├── netbsd.pkr.hcl              # Main Packer template (variables, source, build)
├── build.sh                    # Build entry point
├── run.sh                      # Manual VM runner (for local testing)
├── resources/
│   ├── provision.sh            # Main provisioner (packages, sudo, boot config)
│   ├── post_install.sh         # SSH configuration (served via HTTP during install)
│   ├── cleanup.sh              # Disk minimization
│   └── custom.sh               # Empty placeholder for custom provisioning
├── var_files/
│   ├── common.pkrvars.hcl      # Global defaults (memory, cpus, disk, users)
│   ├── x86-64.pkrvars.hcl     # x86-64 architecture config
│   ├── arm64.pkrvars.hcl      # ARM64 architecture config
│   └── <version>/
│       ├── common.pkrvars.hcl  # Version-specific installer steps
│       ├── x86-64.pkrvars.hcl # Version+arch ISO checksum
│       └── arm64.pkrvars.hcl  # Version+arch ISO checksum
├── .github/workflows/build.yml # CI/CD
├── changelog.md
└── readme.md
```

### Variable File Layering (applied in order)

1. `var_files/common.pkrvars.hcl` — global defaults
2. `var_files/<arch>.pkrvars.hcl` — architecture-specific (firmware, boot steps)
3. `var_files/<version>/<arch>.pkrvars.hcl` — version+arch specific (ISO checksum)
4. `var_files/<version>/common.pkrvars.hcl` — version-specific (installer variations)

## Code Style Guidelines

### Shell Scripts (resources/*.sh, build.sh)

- Use `#!/bin/sh` (POSIX sh) for provisioning scripts; `#!/usr/bin/env sh` for build.sh
- Always set `set -eux` or `set -exu` at the top of every script
- Functions use `snake_case` naming
- Define all functions before calling them; place all calls at the bottom of the file
- Use double quotes around variable expansions: `"$variable"`
- Use heredocs (`cat <<EOF`) for multi-line file content
- Keep scripts minimal and focused on a single responsibility

### HCL2 (Packer Templates)

- Variables use `snake_case` naming
- Every variable must have `type` and `description` fields
- Use `locals` block for computed/derived values
- Annotate `boot_steps` entries with inline comments describing each installer step:
  ```hcl
  ["a<enter><wait5>", "Install NetBSD to hard disk"]
  ```
- Separate architecture-specific and version-specific config into layered var files
- Use `concat()` to compose boot step sequences from variables

### File Naming

- All filenames are lowercase
- Use underscores for shell scripts: `post_install.sh`, `cleanup.sh`
- Use hyphens for architecture names: `x86-64`, `arm64`
- Documentation files are lowercase: `readme.md`, `changelog.md`

### Changelog

- Follow [Keep a Changelog](https://keepachangelog.com/) format
- Follow [Semantic Versioning](https://semver.org/)
- Group changes under: Added, Changed, Fixed, Removed

## Architecture Notes

### Boot Steps

The NetBSD installer is automated entirely through simulated keyboard input via
Packer's `boot_steps`. This is fragile — installer UI changes between NetBSD
versions require version-specific step overrides in `var_files/<version>/`.

Key version differences captured in variables:
- `generate_entropy_steps` — present in 10.x+, absent in 9.x
- `hostname_step` — varies between versions
- `pkgin_network_information_step` — added in 10.x
- `key_x11_sets` — "m" for 9.x, "n" for 10.x

### Provisioning Pipeline (after SSH is available)

1. `provision.sh` — installs packages (bash, curl, rsync, sudo), configures sudo,
   sets boot timeout to 0, configures boot scripts for authorized_keys, sets hostname
2. `custom.sh` — empty placeholder for downstream customization
3. `cleanup.sh` — fills disks with zeros for better compression

### Adding a New NetBSD Version

1. Create `var_files/<version>/` directory
2. Add `common.pkrvars.hcl` with version-specific installer step variables
3. Add `x86-64.pkrvars.hcl` (and `arm64.pkrvars.hcl` if applicable) with ISO checksum
4. Add the version to the CI matrix in `.github/workflows/build.yml`
5. Test the build: `./build.sh <version> <architecture>`
6. Update `changelog.md`
