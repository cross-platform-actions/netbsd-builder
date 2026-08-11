// The disk image is downloaded and verified by `build.sh`, against the `SHA512`
// file published next to the image, before packer runs.
checksum = "none"

// The riscv port has no directory for the plain release, its packages are
// published under the release and the pkgsrc branch they were built from. This
// is also where the pkgin the image is missing is bootstrapped from.
package_repository = "http://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/riscv64/11.0_2026Q2/All"
