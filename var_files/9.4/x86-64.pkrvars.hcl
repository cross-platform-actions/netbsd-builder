checksum = "sha512:93f0005c4dc46718475729ed76064aecc436491507b75cf29fb686f393e6a79be044e429b4a633ac2b4e26e1be32050667a71b356b7b2b11390524c63aed1a16"

# The 9.0 branch that the release's own repository points at has an unfinished
# bulk build, whose index is missing rsync and sudo. This is the last finished
# quarterly branch for the same ABI.
package_repository = "http://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/x86_64/9.0_2026Q1/All"
