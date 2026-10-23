generate_entropy_steps = [
  ["a<enter><wait>", "Manually input random characters"],
  ["{{uuid}}{{uuid}}{{uuid}}{{uuid}}<enter><wait10>", "Enter one line of random characters"]
]

hostname_step = [
  ["<enter><wait>", "Your host name"]
]

pkgin_network_information_step = [
  ["a<enter><wait5>", "Is the network information correct, Yes"]
]

# pkgsrc publishes no package set for this release, so the repository sysinst
# derives from the release version does not exist and installing pkgin from it
# cannot succeed. Abandon the step rather than letting it fail: sysinst retries
# a failed install by redisplaying its menu, with no bound and nothing on the
# console to say so, which swallows every keystroke meant for the screens after
# it. provision.sh installs pkgin from `package_repository` instead.
pkgin_install_steps = [
  ["j<enter><wait5>", "Quit installing binary pkgs"]
]
