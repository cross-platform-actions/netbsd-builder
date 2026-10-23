checksum = "sha512:852a43c498e539fa825775bb32d819cc61d5efa1e644f574147b5804d587ca1376512b74446fd4a9f47b304987211b3b0794d184e048c19b347e69b2676abfb7"

# pkgsrc publishes no `10.2` directory, so the repository the installer derives
# from the release version is a 404. Point at the one for the 10.0 ABI instead,
# which is what `10.1` redirects to as well. It redirects to the newest
# quarterly branch whose build has finished, so unlike a pinned branch it does
# not disappear once that branch is retired.
package_repository = "http://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/x86_64/10.0/All"
