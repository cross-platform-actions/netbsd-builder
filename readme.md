# NetBSD Builder

> [!IMPORTANT]
> This readme documents the `master` branch, which may describe features and
> NetBSD versions that have not been released yet. For the documentation
> matching the latest release, see the
> [readme for the latest release](https://github.com/cross-platform-actions/netbsd-builder/blob/v1.0.0/readme.md).

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
VAX has no framebuffer. The RISC-V 64 image installs no sets at all: NetBSD
publishes no installation media for the riscv port, so that image is built from
the pre-built disk image the port publishes instead of being installed with
sysinst, and it contains whatever that image contains.

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
* Duplicate address detection is off (`net.inet.ip.dad_count=0`,
  `net.inet6.ip6.dad_count=0`), and `/etc/rc.d/network` doesn't wait for it
  (`ifconfig_wait_dad_flags=""`). An address is unusable while it is being
  probed, so the kernel drops everything addressed to it and `sshd` answers
  nothing even though it is already listening -- which is what gated a job
  starting. NetBSD probes for IPv4 too (RFC 5227) and the schedule takes several
  seconds. There is nothing to find: the address comes from the hypervisor's own
  user mode network, with exactly one guest on it.

Building with `-var boot_timestamps=true` makes `/etc/rc` print a timestamped
line to the console as each `rc.d` script starts, which attributes the boot time
to individual scripts. The same lines are logged to `/var/run/rc.log`.

## Architectures and Versions

The following architectures and versions are supported:

| Version | x86-64 | ARM64 | RISC-V 64 | VAX |
|---------|--------|-------|-----------|-----|
| 11.0    | ✓      | ✓     | ✓         | ✓   |
| 10.1    | ✓      | ✓     | ✗         | ✓   |
| 10.0    | ✓      | ✓     | ✗         | ✗   |
| 9.4     | ✓      | ✗     | ✗         | ✗   |
| 9.3     | ✓      | ✗     | ✗         | ✗   |
| 9.2     | ✓      | ✗     | ✗         | ✗   |

## Building Locally

### Prerequisite

* [Packer](https://www.packer.io) 1.7.2 or later
* [QEMU](https://qemu.org)

For the RISC-V 64 architecture:

* [mtools](https://www.gnu.org/software/mtools/), to install the credentials in
  the MS-DOS boot partition of the pre-built disk image

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
at the path: `output/netbsd-<version>-<architecture>.tar.zst`.

## Additional Information

The boot loader and the kernel of the x86-64 image use the first serial port,
`com0`, as the console. That allows the boot output to be captured when the VM
is running without a display, which is how the GitHub action runs it. The ARM64
and RISC-V 64 images use the serial port by default, since the QEMU `virt`
machine has no display device at all. The VAX has a single console, the one SIMH
itself drives, so its boot output is captured without any extra configuration.

Every image is distributed as a single artifact,
`netbsd-<version>-<architecture>.tar.zst`, holding:

* `disk.img`, the RAW disk. Every builder is asked for RAW directly, so nothing
  has to be converted afterwards. qcow2 is not used: its own compression has to
  keep the image writable, so it compresses worse than a solid stream does, and a
  consumer pays that difference on every job. The measured numbers are in
  [action#151](https://github.com/cross-platform-actions/action/issues/151).
* `kernel`, for the platforms the consumer boots with QEMU's `-kernel` rather
  than from the disk. That is the `microvm` machine type on x86-64, which has no
  way to boot from a disk, and RISC-V 64, whose port has no boot loader QEMU's
  `virt` machine can start. Either way the kernel can't live inside the image.
  Keeping it in the same artifact means the kernel and the userland it has to
  match can never disagree, and lets a consumer decide whether it can boot the
  fast way by looking at what it unpacked.

The members are named generically rather than after NetBSD or the version, so
that a consumer needs one code path for every platform that ships an image this
way.

The image's zero ranges are turned into actual holes before it is archived, and
the tar records those holes rather than the zeroes in them, so neither end has to
read or write the full 12 GB -- only the ~700 MB the installation uses. That
matters most to the consumer, which writes the image out on every job: without
it, unpacking took 47 seconds against the 4 the qcow2 conversion needed. The
compression window is kept at zstd's default decompression limit, so no extra
flags are needed to unpack it:

```
curl -sL <url>/netbsd-<version>-<architecture>.tar.zst | zstd -dc | tar -x
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

The passwordless login described above started with VAX, which can't mount the
FAT disk the consumer used to deliver a generated SSH key on (`msdosfs` is
unavailable there). Every architecture accepts it now, so there is no key and no
disk to carry one.

NetBSD publishes no installation media for the riscv port, only a pre-built disk
image. The RISC-V 64 image is therefore not installed with sysinst like the
other architectures: `build.sh` downloads that image and the matching kernel,
verifies both against the `SHA512` file published next to them, and packer boots
the image directly and only provisions it. The image is booted through QEMU's
direct kernel boot on top of the built-in OpenSBI firmware, since the port has
no firmware file of its own.

A pre-built image has no user to log in as, so the credentials are installed in
the MS-DOS boot partition of the image, with mtools, before it boots.
[`creds_msdos(8)`](https://man.netbsd.org/creds_msdos.8) turns them into the
`runner` and `root` accounts on the first boot. It cannot enable SSH logins for
root, so packer connects as `runner` and the provisioners escalate with `su`.

Two things about the machine differ from every other QEMU architecture here.
The RISC-V kernel attaches virtio devices only through the MMIO transport and
leaves the ones on the PCI bus unconfigured, hence `virtio-blk-device`,
`virtio-net-device` and `virtio-rng-device` rather than their PCI counterparts.
And the machine cannot power itself off — the kernel leaves the `poweroff`
device unconfigured — so `poweroff` only halts it and QEMU keeps running. The
build lets packer stop the VM instead, after the cleanup provisioner has synced
the file systems and remounted the root read-only.

The packages of the riscv port are not published under the plain release, like
the other architectures, but under the release and the pkgsrc branch they were
built from, which the version's variables file points at. That repository is
also where `pkgin`, which a pre-built image doesn't have, is bootstrapped from.

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
