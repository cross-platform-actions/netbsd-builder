# NetBSD Builder

> [!IMPORTANT]
> This readme documents the `master` branch, which may describe features and
> NetBSD versions that have not been released yet. For the documentation
> matching the latest release, see the
> [readme for the latest release](https://github.com/cross-platform-actions/netbsd-builder/blob/v0.6.0/readme.md).

This project builds the NetBSD VM image for the
[cross-platform-actions/action](https://github.com/cross-platform-actions/action)
GitHub action. The image contains a standard NetBSD installation without any
X components. It will install the following distribution sets:

* Kernel (GENERIC)
* Kernel modules
* Base
* Configuration files
* Compiler tools
* X11 base and clients
* X11 programming
* X11 configuration
* X11 fonts
* X11 servers

The VAX image installs the same sets except the X11 ones, since the emulated
VAX has no framebuffer.

In addition to the above file sets, the following packages are installed as well:

* bash
* curl
* pkgin
* rsync
* sudo

On VAX these packages come from the
[netbsd-pkg-repo](https://github.com/cross-platform-actions/netbsd-pkg-repo)
release instead of the official mirrors, which carry no vax binaries. The
`pkgin` in the image is pointed at that same release, so more packages can be
installed from it.

Except for the root user, there's one additional user, `runner`, which is the
user that will be running the commands in the GitHub action. This user is
allowed use `sudo` without a password.

## Architectures and Versions

The following architectures and versions are supported:

| Version | x86-64 | ARM64 | VAX |
|---------|--------|-------|-----|
| 11.0    | ✓      | ✓     | ✓   |
| 10.1    | ✓      | ✓     | ✓   |
| 10.0    | ✓      | ✓     | ✗   |
| 9.4     | ✓      | ✗     | ✗   |
| 9.3     | ✓      | ✗     | ✗   |
| 9.2     | ✓      | ✗     | ✗   |

## Building Locally

### Prerequisite

* [Packer](https://www.packer.io) 1.7.2 or later
* [QEMU](https://qemu.org)

For the VAX architecture, which is built by [SIMH] instead of QEMU:

* The SIMH `vax` simulator on `PATH`, from the
  [simh-builder](https://github.com/cross-platform-actions/simh-builder)
  releases or built from [SIMH] itself
* [zstd](https://github.com/facebook/zstd), to compress the resulting image
* The [GitHub CLI](https://cli.github.com), authenticated, to download the
  prebuilt vax packages from the
  [netbsd-pkg-repo](https://github.com/cross-platform-actions/netbsd-pkg-repo)
  release

### Building

1. Clone the repository:
    ```
    git clone https://github.com/cross-platform-actions/netbsd-builder
    cd netbsd-builder
    ```

2. Run `build.sh` to build the image:
    ```
    ./build.sh <version> <architecture>
    ```
    Where `<version>` and `<architecture>` are the any of the versions or
    architectures available in the above table.

The above command will build the VM image and the resulting disk image will be
at the path: `output/netbsd-9.2-x86-64.qcow2`. For VAX the artifact is the
compressed RAW image instead: `output/netbsd-<version>-vax.img.zst`.

## Additional Information

The boot loader and the kernel of the x86-64 image use the first serial port,
`com0`, as the console. That allows the boot output to be captured when the VM
is running without a display, which is how the GitHub action runs it. The ARM64
image uses the serial port by default, since the QEMU `virt` machine has no
display device at all. The VAX has a single console, the one SIMH itself
drives, so its boot output is captured without any extra configuration.

The qcow2 format is chosen because unused space doesn't take up any space on
disk, it's compressible and easily converts the raw format.

The VAX image is a RAW disk, the format SIMH attaches with the least runtime
overhead, so it gets none of qcow2's compression. It's compressed with zstd for
distribution instead, which brings the 1.5 GB RA92 disk down to roughly 90 MB.
The window size is kept at zstd's default decompression limit, so no extra
flags are needed to decompress it:

```
curl -sL <url>/netbsd-<version>-vax.img.zst | zstd -dc > disk.raw
```

The VAX image is also provisioned differently. The KA655 firmware's self-test
is unreliable when the installed system is booted inside the same SIMH process
that ran the installer, so the build never boots from disk: everything the
SSH provisioners do for the QEMU architectures is done by
[`resources/post_install_vax.sh`](resources/post_install_vax.sh) from the
installer, against the target mounted at `/mnt`, after which the build halts.
That includes generating the SSH host keys on the build host and installing
them into the image, which would otherwise cost around 20 minutes of RSA
key generation at the emulated VAX's ~1 MIPS on the first boot.

Since the FAT resources disk that delivers the SSH key to every other port
can't be mounted on NetBSD/VAX (`msdosfs` is unavailable there), the VAX image
is logged into with a password rather than a key, using the `runner` user and
the password set during installation.

## Contributing

### Changelog

The changelog is maintained in the [changelog.md](changelog.md) file, following
the [Keep a Changelog] format. The changelog is updated incrementally. That is,
for every new feature or bugfix, add an entry to the changelog under the
[Unreleased] section using an appropriate sub header (`Added`, `Changed`,
`Deprecated`, `Removed`, `Fixed`, or `Security`).

Entries under these sub headers determine the semantic version bump when the
next release is cut with [relog].

### Creating a Release

Releases are cut with [relog], driven by the [Unreleased] section of
`changelog.md`. relog derives the next version from the sub headers under
[Unreleased]:

* `### Fixed` only → patch bump
* `### Added`, `### Changed`, `### Deprecated` → minor bump
* `### Removed` (or "Breaking" anywhere in the section) → major bump

To cut a release, from a clean `master` working tree, run:

```
relog
```

To preview the changes without modifying anything:

```
relog --dry-run
```

To override the auto-detected version:

```
relog X.Y.Z
```

relog rewrites the changelog, runs the `pre_commit` hooks in
[`release.conf`](release.conf) (which point the "latest release" link at the top
of this readme at the new tag), commits the result, creates an annotated
`vX.Y.Z` tag, and prompts before pushing. Pushing the `vX.Y.Z` tag triggers the
GitHub Actions workflow defined in
[`.github/workflows/build.yml`](.github/workflows/build.yml), which builds the
VM images and, in the "Create Release" step, creates a draft GitHub release
using the newly added changelog section as the release notes. Review the draft
release on GitHub and publish it.

[SIMH]: https://github.com/simh/simh
[Keep a Changelog]: https://keepachangelog.com/en/1.1.0/
[relog]: https://github.com/jacob-carlborg/relog
[Unreleased]: https://github.com/cross-platform-actions/netbsd-builder/blob/master/changelog.md#unreleased
