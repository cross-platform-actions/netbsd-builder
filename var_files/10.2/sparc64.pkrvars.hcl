checksum = "sha512:e0b09f0654310059712ac5d3a4e299d2af30491c0b06c26702b03347f04ca414b5b48c2fa411f5215565e114cbc1eedc42f65643792f24d0ba91a16d26fd89d8"

# pkgsrc's current 10.0 branch for sparc64, which this release's repository
# redirects to, has neither pkgin nor rsync. This is the newest branch that has
# both. sysinst can't install pkgin from the repository it derives, so
# provision.sh installs it from this one instead.
package_repository = "http://archive.NetBSD.org/pub/pkgsrc-archive/packages/NetBSD/sparc64/10.0_2025Q4/All"
