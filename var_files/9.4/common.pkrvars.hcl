key_x11_sets = "m"

root_password_pre_steps = [
  ["d<enter><wait5>"],
  ["a<enter><wait5>", "Yes"]
]

generate_entropy_steps = []
hostname_step = []
pkgin_network_information_step = []

# pkgsrc no longer publishes a package set for this release on its CDN, so the
# repository sysinst derives from the release version does not exist and
# installing pkgin from it cannot succeed. Abandon the step rather than letting
# it fail: sysinst retries a failed install by redisplaying its menu, with no
# bound and nothing on the console to say so, which swallows every keystroke
# meant for the screens after it. provision.sh installs pkgin from
# `package_repository` instead.
pkgin_install_steps = [
  ["j<enter><wait5>", "Quit installing binary pkgs"]
]
