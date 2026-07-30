checksum = "sha512:2bfce544f762a579f61478e7106c436fc48731ff25cf6f79b392ba5752e6f5ec130364286f7471716290a5f033637cf56aacee7fedb91095face59adf36300c3"

# The 9.0 branch that the release's own repository points at has an unfinished
# bulk build, whose index is missing rsync and sudo. This is the last finished
# quarterly branch for the same ABI.
package_repository = "http://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/x86_64/9.0_2026Q1/All"
