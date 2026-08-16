# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Removed
- The `rc.local` hook that mounted the consumer's FAT resources disk and
    installed the SSH key from it. The passwordless login replaces it

### Added
- Publish the kernel for QEMU's `microvm` machine type inside the image bundle,
    where a NetBSD release provides one
- The `runner` user can log in over SSH without a credential on every
    architecture, not just VAX, which lets a consumer stop building the FAT
    resources disk that carries a generated key
- New `boot_timestamps` build variable, which makes `/etc/rc` print a
    timestamped line to the console as each `rc.d` script starts

### Changed
- Distribute every image as a bundle, `netbsd-<version>-<architecture>.tar.zst`,
    holding a RAW `disk.img` and, where the release has one, a `kernel`. qcow2 is
    gone: its own compression has to keep the image writable, so it compresses
    worse than a solid stream, and the consumer pays that on every job. The 11.0
    x86-64 image goes from 497 MiB to 268 MiB
    ([action#151](https://github.com/cross-platform-actions/action/issues/151))
- Turn the image's zero ranges into holes before archiving it. The image comes
    out of the builder fully allocated, and `tar --sparse` asks the file system
    where the holes are rather than looking for zeroes itself, so without this
    the archive carries all 12 GB and the consumer writes all 12 GB back out
    when it unpacks: 47 seconds, against the 4 that converting the qcow2 took
- Freeze the address the hypervisor hands out into the static network
    configuration and disable the DHCP client, taking it off the boot path to
    `sshd`
- Don't run `ntpdate` at boot. It blocks the boot on network round trips to
    correct an offset that is already close to zero, since the emulated RTC is
    seeded from the host clock. `ntpd` stays enabled, now with `-g`
- Don't do duplicate address detection at all, and don't wait for it in
    `/etc/rc.d/network`. An address is unusable while it is probed, so `sshd`
    answered nothing for several seconds after it started listening. There is no
    second host on the hypervisor's user mode network that could hold the
    address

### Fixed
- Stop the boot-time `ntpdate` being able to stall a NetBSD/VAX guest
    indefinitely. It runs inline in the boot sequence, ahead of `sshd`, and the
    DNS lookup for the pool names in the stock `ntp.conf` has no deadline, so a
    lookup that went unanswered left the guest sitting at `Setting date via
    ntp.` It is now given numeric addresses, keeping DNS off the boot path, and
    a per-query timeout
- Bound the VAX image test's wait for `sshd` on the clock. It counted attempts
    instead, and an attempt costs nothing against a closed port but a whole
    `ConnectTimeout` against a guest that stalls after accepting, so the
    intended hour was really anywhere up to four. One stalled guest held a
    runner for over two hours

## [0.7.0] - 2026-08-09
### Added
- Added support for NetBSD 11.0
- Added support for NetBSD VAX via the SIMH simulator using packer-plugin-simh
- Install bash, curl, pkgin, rsync and sudo on NetBSD/VAX from the [netbsd-pkg-repo](https://github.com/cross-platform-actions/netbsd-pkg-repo) release (the official mirrors carry no vax binaries)

### Fixed
- Enable the serial console on the x86-64 image, so the boot log is captured
  when a VM fails to boot ([action#158](https://github.com/cross-platform-actions/action/issues/158))

## [0.6.0] - 2026-04-29
### Changed
- Enable immutable releases ([action#140](https://github.com/cross-platform-actions/action/issues/140))

## [0.5.1] - 2025-12-03
### Fixed
- Fix empty hostname ([action#113](https://github.com/cross-platform-actions/action/issues/113))

## [0.5.0] - 2025-01-21
- Added support for NetBSD 10.1

## [0.4.0] - 2024-05-04
### Added
- Added support for NetBSD 9.4

## [0.3.0] - 2024-04-03
### Added
- Added support for NetBSD 10.0
- Added support for NetBSD ARM64

## [0.2.0] - 2023-05-28
### Added
- Added support for NetBSD 9.3 ([action#53](https://github.com/cross-platform-actions/action/issues/53))

## [0.1.0] - 2023-01-23
### Added
- Bundle all X11 sets ([#3](https://github.com/cross-platform-actions/netbsd-builder/issues/3))

## [0.0.1] - 2021-11-12
### Added
- Initial release

[Unreleased]: https://github.com/cross-platform-actions/netbsd-builder/compare/v0.7.0...HEAD

[0.7.0]: https://github.com/cross-platform-actions/netbsd-builder/compare/v0.6.0...v0.7.0

[0.6.0]: https://github.com/cross-platform-actions/netbsd-builder/compare/v0.5.1...v0.6.0

[0.5.1]: https://github.com/cross-platform-actions/netbsd-builder/compare/v0.5.1...v0.5.0
[0.5.0]: https://github.com/cross-platform-actions/netbsd-builder/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/cross-platform-actions/netbsd-builder/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/cross-platform-actions/netbsd-builder/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/cross-platform-actions/netbsd-builder/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/cross-platform-actions/netbsd-builder/compare/v0.0.1...v0.1.0
[0.0.1]: https://github.com/cross-platform-actions/netbsd-builder/releases/tag/v0.0.1
