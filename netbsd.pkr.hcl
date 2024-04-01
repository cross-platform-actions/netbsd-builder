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

locals {
  iso_target_extension = "iso"
  iso_target_path = "packer_cache"
  iso_full_target_path = "${local.iso_target_path}/${sha1(var.checksum)}.${local.iso_target_extension}"

  image = "NetBSD-${var.os_version}-${var.architecture.image}.${local.iso_target_extension}"
  vm_name = "netbsd-${var.os_version}-${var.architecture.name}.qcow2"
  full_remote_path = "images/${var.os_version}/${local.image}"
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
      ["f<enter><wait5>", "Compiler tools"],
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
      ["a<enter><wait5>", "Is the network information correct, Yes"],

      // Enable installation of binary packages
      ["e<enter><wait5>"]
    ],

    var.pkgin_network_information_step,

    [
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
  iso_urls = [
    "https://cdn.netbsd.org/pub/NetBSD/${local.full_remote_path}",
    "https://ftp.netbsd.org/pub/NetBSD/${local.full_remote_path}",
    "https://mirror.planetunix.net/pub/NetBSD/${local.full_remote_path}",
    "https://www.nic.funet.fi/pub/NetBSD/${local.full_remote_path}",
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
      "SECONDARY_USER=${var.secondary_user_username}"
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
