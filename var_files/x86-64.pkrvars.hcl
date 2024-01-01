firmware = "bios-256k.bin"
post_install_disk_device = "/dev/dk0"

architecture = {
  name = "x86-64"
  image = "amd64"
  qemu = "x86_64"
}

keyboard_layout_steps = [
  ["a<enter><wait5>", "Keyboard type: unchanged"]
]

correct_geometry_steps = [
  ["a<enter><wait5>", "This is the correct geometry"]
]

bootblock_selection_steps = [
 ["a<enter><wait>", "Bootblocks selection: Use BIOS console"]
]
