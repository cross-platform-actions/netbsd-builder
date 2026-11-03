checksum = "sha512:0537e517be46055adec7f5c7a34551ab0ca0cee96fac316bf5f451f2e2c62dfeeede5dda5c9393355edf6a5e5f071e6c51e890a974c7577eefa55b8898d7ba89"

# pkgsrc's current 10.0 branch for sparc64, which this release's repository
# redirects to, has neither pkgin nor rsync. This is the newest branch that has
# both. sysinst can't install pkgin from the repository it derives, so
# provision.sh installs it from this one instead.
package_repository = "http://archive.NetBSD.org/pub/pkgsrc-archive/packages/NetBSD/sparc64/10.0_2025Q4/All"

pkgin_install_steps = [
  ["j<enter><wait15s>", "Quit installing binary pkgs"]
]
