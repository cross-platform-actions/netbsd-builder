# NetBSD Builder

> [!IMPORTANT]
> This readme documents the `master` branch, which may describe features and
> NetBSD versions that have not been released yet. For the documentation
> matching the latest release, see the
> [readme for the latest release](https://github.com/cross-platform-actions/netbsd-builder/blob/v0.7.0/readme.md).

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

`runner` also has an empty password, which `sshd` and the PAM stack are
configured to accept, so the image can be logged into over SSH without a
credential and without a prompt. Only `runner` is passwordless; `root` keeps the
password set during installation.

## Boot Time

The images are configured to reach a reachable `sshd` as quickly as possible,
because a consumer waits for that on every job:

* The address the hypervisor hands out is frozen into the static network
  configuration at build time and the DHCP client is disabled. Under QEMU's user
  mode networking the lease never changes, and `dhcpcd` is ordered before the
  `NETWORKING` milestone, which is on the path to `sshd`.
* `ntpdate` is not run at boot. Its `rc.d` script runs `ntpdate(8)` inline, so
  the whole boot waits for its network round trips, and it corrects an offset
  that is already close to zero: the hypervisor seeds the emulated RTC from the
  host clock, and the kernel reads it as UTC. `ntpd` stays enabled, with `-g` so
  it can step a large initial offset if one ever exists.
* `/etc/rc.d/network` doesn't wait for IPv6 duplicate address detection
  (`ifconfig_wait_dad_flags=""`). Its default `-w 15 -W 5` waits up to 5 seconds
  for the `detached` flag to clear, which never happens when the guest runs
  behind user mode networking with IPv6 switched off, so it spent that time on
  every boot.

Building with `-var boot_timestamps=true` makes `/etc/rc` print a timestamped
line to the console as each `rc.d` script starts, which attributes the boot time
to individual scripts. The same lines are logged to `/var/run/rc.log`.

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

The FAT resources disk that delivers a generated SSH key to the other ports
can't be mounted on NetBSD/VAX (`msdosfs` is unavailable there), which is why the
passwordless login described above exists. Every architecture now accepts it, so
the resources disk is no longer the only way in.

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
