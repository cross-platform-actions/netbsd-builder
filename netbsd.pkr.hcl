variable "os_version" {
  type = string
  description = "The version of the operating system to download and install"
}

variable "architecture" {
  type = object({
    name = string
    image = string
    qemu = string
  })
  description = "The type of CPU to use when building"
}

variable "machine_type" {
  default = "pc"
  type = string
  description = "The type of machine to use when building"
}

variable "cpu_type" {
  default = "qemu64"
  type = string
  description = "The type of CPU to use when building"
}

variable "memory" {
  default = 4096
  type = number
  description = "The amount of memory to use when building the VM in megabytes"
}

variable "cpus" {
  default = 2
  type = number
  description = "The number of cpus to use when building the VM"
}

variable "disk_size" {
  default = "12G"
  type = string
  description = "The size in bytes of the hard disk of the VM"
}

variable "checksum" {
  type = string
  description = "The checksum for the virtual hard drive file"
}

variable "root_password" {
  default = "vagrant"
  type = string
  description = "The password for the root user"
}

variable "secondary_user_password" {
  default = "vagrant"
  type = string
  description = "The password for the `secondary_user_username` user"
}

variable "secondary_user_username" {
  default = "vagrant"
  type = string
  description = "The name for the secondary user"
}

variable "headless" {
  default = false
  description = "When this value is set to `true`, the machine will start without a console"
}

variable "use_default_display" {
  default = true
  type = bool
  description = "If true, do not pass a -display option to qemu, allowing it to choose the default"
}

variable "display" {
  default = "cocoa"
  description = "What QEMU -display option to use"
}

variable "accelerator" {
  default = "tcg"
  type = string
  description = "The accelerator type to use when running the VM"
}

variable "firmware" {
  type = string
  description = "The firmware file to be used by QEMU"
}

variable "root_password_pre_steps" {
  default = [[""]]
  type = list(list(string))
  description = "A few boot steps needed before entering the root password"
}

# The reference letters in the "Custom installation" distribution set menu are
# positional: every set the port has shifts the ones below it. A release that
# adds a set moves the letters, and it does so per port, since the list depends
# on what that port has. NetBSD 11.0 added "Manual pages (HTML)" everywhere, and
# on amd64 also "Base 32-bit compatibility libraries", so both keys below differ
# per architecture there. Getting one wrong is quiet: the wrong item is toggled
# and the install still succeeds, just not with the sets that were meant.
#
# To re-derive them for a new release, walk an installer to that menu and read
# it, rather than assuming the previous release's letters still hold. On the
# ports whose console is the serial port the menu is in the console log; on
# amd64 it is only on the display, so take a qemu `screendump`.
variable "key_compiler_tools" {
  default = "f"
  type = string
  description = "The key used to select the compiler tools set"
}

variable "key_x11_sets" {
  default = "n"
  type = string
  description = "The key used to select the X11 sets"
}

variable "generate_entropy_steps" {
  type = list(list(string))
  description = "The steps to generate entropy"
}

variable "hostname_step" {
  type = list(list(string))
  description = "Step to set hostname"
}

variable "keyboard_layout_steps" {
  type = list(list(string))
  description = "Step to select keyboard layout"
}

variable "correct_geometry_steps" {
  type = list(list(string))
  description = "Step to say the geometry is correct"
}

variable "bootblock_selection_steps" {
  type = list(list(string))
  description = "Step to select bootblock"
}

variable "pkgin_network_information_step" {
  type = list(list(string))
  description = "Step to confirm network information during pkgin install"
}

variable "post_install_disk_device" {
  type = string
  description = "The disk device to mount during post install"
}

variable "boot_console" {
  default = ""
  type = string
  description = "The console device the boot loader and the kernel should use. An empty value leaves the platform default in place"
}

variable "package_repository" {
  default = ""
  type = string
  description = "The binary package repository to install the packages from. An empty value keeps the one the installer configured"
}

locals {
  iso_target_extension = "iso"
  iso_target_path = "packer_cache"
  iso_full_target_path = "${local.iso_target_path}/${sha1(var.checksum)}.${local.iso_target_extension}"

  image = "NetBSD-${var.os_version}-${var.architecture.image}.${local.iso_target_extension}"
  vm_name = "netbsd-${var.os_version}-${var.architecture.name}.qcow2"
  full_remote_path = "images/${var.os_version}/${local.image}?key=NetBSD"
}

source "qemu" "qemu" {
  machine_type = var.machine_type
  cpus = var.cpus
  memory = var.memory
  net_device = "virtio-net"

  disk_compression = true
  disk_interface = "virtio"
  disk_size = var.disk_size
  format = "qcow2"

  headless = var.headless
  use_default_display = var.use_default_display
  display = var.display
  accelerator = "none"
  qemu_binary = "qemu-system-${var.architecture.qemu}"
  firmware = var.firmware

  boot_wait = "10s"

  boot_steps = concat(
    [
      ["1<wait20s>", "Boot normally"], // for x86-64, the boot delay is already over
      ["a<enter><wait5>", "Installation messages in English"]
    ],

    var.keyboard_layout_steps,

    [
      ["a<enter><wait5>", "Install NetBSD to hard disk"],
      ["b<enter><wait5>", "Yes"],

      ["a<enter><wait5>", "Available disks: sd0"],
      ["a<enter><wait5>", "Guid Partition Table"],
    ],

    var.correct_geometry_steps,

    [
      ["b<enter><wait5>", "Use default partition sizes"],
      ["x<enter><wait5>", "Partition sizes ok"],
      ["b<enter><wait10>", "Yes"],
    ],

    var.bootblock_selection_steps,

    [
      ["d<enter><wait>", "Custom installation"],
      // Distribution set:
      ["${var.key_compiler_tools}<enter><wait5>", "Compiler tools"],
      ["${var.key_x11_sets}<enter><wait5>", "X11 sets"],
      // X11 sets:
      ["f<enter><wait5>", "Select all of the above sets"],
      ["x<enter><wait5>", "Install selected sets"],
      // Distribution set:
      ["x<enter><wait5>", "Install selected sets"],

      ["a<enter><wait5m>", "Install from: install image media"],

      ["<enter><wait5>", "Hit enter to continue"],

      // Configure the additional items as needed
    ],

    var.root_password_pre_steps,

    [
      // Change root password
      ["${var.root_password}<enter><wait5>", "New password"],
      ["${var.root_password}<enter><wait5>", "New password"],
      ["${var.root_password}<enter><wait5>", "Retype new password"],
    ],

    var.generate_entropy_steps,

    [
      // Add a user
      ["o<enter><wait5>"],
      ["${var.secondary_user_username}<enter><wait5>", "username"],
      ["a<enter><wait5>", "Add user to group wheel, Yes"],
      ["a<enter><wait5>", "User shell, sh"],
      ["${var.secondary_user_password}<enter><wait5>", "New password"],
      ["${var.secondary_user_password}<enter><wait5>", "New password"],
      ["${var.secondary_user_password}<enter><wait5>", "New password"],

      ["g<enter><wait5>", "Enable sshd"],
      ["h<enter><wait5>", "Enable ntpd"],
      ["i<enter><wait5>", "Run ntpdate at boot"],

      // Configure network
      ["a<enter><wait5>"],
      ["a<enter><wait5>", "first interface"],
      ["<enter><wait5>", "Network media type"],
      ["a<enter><wait20>", "Perform autoconfiguration, Yes"]
    ],

    var.hostname_step,

    [
      ["<enter><wait5>", "Your DNS domain"],
      ["a<enter><wait5>", "Are they OK, Yes"],
      ["a<enter><wait5>", "Is the network information accurate. Install in /etc? Yes"],

      // Enable installation of binary packages
      ["e<enter><wait5>"]
    ],

    var.pkgin_network_information_step,

    [
      ["i<enter><wait5>", "Download via http -> ftp"],
      ["x<enter><wait2m>", "Install pkgin and update package summary"],
      ["<enter><wait5>", "Hit enter to continue"],

      ["x<enter><wait5>", "Finished configuring"],
      ["<enter><wait5>", "Hit enter to continue"],

      // post install configuration
      ["e<enter><wait5>", "Utility menu"],
      ["a<enter><wait5>", "Run /bin/sh"],

      // shell
      ["ftp -o /tmp/post_install.sh http://{{.HTTPIP}}:{{.HTTPPort}}/resources/post_install.sh<enter><wait10>"],
      ["DISK_DEVICE='${var.post_install_disk_device}' sh /tmp/post_install.sh && exit<enter><wait5>"],

      ["x<enter><wait5>", "Exit Utility menu"],
      ["d<enter>", "Reboot the computer"],
    ]
  )

  ssh_username = "root"
  ssh_password = var.root_password
  ssh_timeout = "10000s"

  qemuargs = [
    ["-cpu", var.cpu_type],
    ["-boot", "strict=off"],
    ["-monitor", "none"],
    # When the installer goes out of step the only symptom is packer waiting
    # for an SSH server that never appears, so log the console to make that
    # diagnosable.
    #
    # This has to stay a virtual console rather than become `file:`. On the
    # platforms without a display device, the ARM64 one here, the installer's
    # console is the serial port, and it reads the keystrokes packer types from
    # it. A `file:` serial port only writes, so redirecting it there leaves the
    # installer with no input at all and it never gets past its first screen.
    # A chardev keeps the virtual console, and with it packer's input, while
    # also writing everything to a file.
    #
    # The log is not in the output directory: packer refuses to start when that
    # directory already exists and isn't empty, so a log left behind by a
    # previous run would break the next one.
    ["-chardev", "vc,id=console0,logfile=console.log"],
    ["-serial", "chardev:console0"],
    ["-accel", "hvf"],
    ["-accel", "kvm"],
    ["-accel", "tcg"],
    ["-device", "virtio-scsi-pci"],
    ["-device", "scsi-hd,drive=drive0,bootindex=0"],
    ["-device", "scsi-cd,drive=drive1,bootindex=1"],
    ["-drive", "if=none,file={{ .OutputDir }}/{{ .Name }},id=drive0,cache=writeback,discard=ignore,format=qcow2"],
    ["-drive", "if=none,file=${local.iso_full_target_path},id=drive1,media=disk,format=raw,readonly=on"],
    ["-netdev", "user,id=user.0,hostfwd=tcp::{{ .SSHHostPort }}-:22,ipv6=off"]
  ]

  iso_checksum = var.checksum
  iso_target_extension = local.iso_target_extension
  iso_target_path = local.iso_target_path
  # Old releases are moved off the main site to archive.netbsd.org,
  # where cdn/ftp then redirect to a directory URL — the download gets
  # an HTML "Document Moved" page and fails the checksum. The archive
  # mirrors the images/<version>/ layout, so one archive URL covers
  # every moved release; for current releases it just 404s and packer
  # falls through to the mirrors below.
  iso_urls = [
    "https://archive.netbsd.org/pub/NetBSD-archive/${local.full_remote_path}",
    "https://cdn.netbsd.org/pub/NetBSD/${local.full_remote_path}",
    "https://ftp.netbsd.org/pub/NetBSD/${local.full_remote_path}",
    "https://mirror.planetunix.net/pub/NetBSD/${local.full_remote_path}",
    "https://www.nic.funet.fi/pub/NetBSD/${local.full_remote_path}",
    "https://ftp.uni-erlangen.de/netbsd/${local.full_remote_path}",
    "https://ftp.allbsd.org/NetBSD/${local.full_remote_path}",
    "https://ftp.kaist.ac.kr/NetBSD/${local.full_remote_path}"
  ]

  http_directory = "."
  output_directory = "output"
  shutdown_command = "/sbin/poweroff"
  vm_name = local.vm_name
}

packer {
  required_plugins {
    qemu = {
      version = "~> 1.0.8"
      source = "github.com/hashicorp/qemu"
    }
  }
}

build {
  sources = ["qemu.qemu"]

  provisioner "shell" {
    script = "resources/provision.sh"
    environment_vars = [
      "SECONDARY_USER=${var.secondary_user_username}",
      "BOOT_CONSOLE=${var.boot_console}",
      "PACKAGE_REPOSITORY=${var.package_repository}"
    ]
  }

  provisioner "shell" {
    script = "resources/custom.sh"
    environment_vars = [
      "SECONDARY_USER=${var.secondary_user_username}"
    ]
  }

  provisioner "shell" {
    script = "resources/cleanup.sh"
  }
}
