variable "os_version" {
  type        = string
  description = "The version of the operating system to download and install"
}

variable "architecture" {
  type = object({
    name  = string
    image = string
    qemu  = string
  })
  description = "The type of CPU to use when building"
}

variable "machine_type" {
  default     = "pc"
  type        = string
  description = "The type of machine to use when building"
}

variable "cpu_type" {
  default     = "qemu64"
  type        = string
  description = "The type of CPU to use when building"
}

variable "memory" {
  default     = 4096
  type        = number
  description = "The amount of memory to use when building the VM in megabytes"
}

variable "cpus" {
  default     = 2
  type        = number
  description = "The number of cpus to use when building the VM"
}

variable "disk_size" {
  default     = "12G"
  type        = string
  description = "The size in bytes of the hard disk of the VM"
}

variable "checksum" {
  type        = string
  description = "The checksum for the virtual hard drive file"
}

variable "root_password" {
  default     = "vagrant"
  type        = string
  description = "The password for the root user"
}

variable "secondary_user_password" {
  default     = "vagrant"
  type        = string
  description = "The password for the `secondary_user_username` user"
}

variable "secondary_user_username" {
  default     = "vagrant"
  type        = string
  description = "The name for the secondary user"
}

variable "headless" {
  default     = false
  description = "When this value is set to `true`, the machine will start without a console"
}

variable "use_default_display" {
  default     = true
  type        = bool
  description = "If true, do not pass a -display option to qemu, allowing it to choose the default"
}

variable "display" {
  default     = "cocoa"
  description = "What QEMU -display option to use"
}

variable "accelerator" {
  default     = "tcg"
  type        = string
  description = "The accelerator type to use when running the VM"
}

variable "firmware" {
  type        = string
  description = "The firmware file to be used by QEMU"
}

variable "root_password_pre_steps" {
  default     = [[""]]
  type        = list(list(string))
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
  default     = "f"
  type        = string
  description = "The key used to select the compiler tools set"
}

variable "key_x11_sets" {
  default     = "n"
  type        = string
  description = "The key used to select the X11 sets"
}

variable "generate_entropy_steps" {
  type        = list(list(string))
  description = "The steps to generate entropy"
}

variable "hostname_step" {
  type        = list(list(string))
  description = "Step to set hostname"
}

variable "keyboard_layout_steps" {
  type        = list(list(string))
  description = "Step to select keyboard layout"
}

variable "correct_geometry_steps" {
  type        = list(list(string))
  description = "Step to say the geometry is correct"
}

variable "bootblock_selection_steps" {
  type        = list(list(string))
  description = "Step to select bootblock"
}

variable "partition_type_steps" {
  default = [
    ["a<enter><wait5>", "Guid Partition Table"]
  ]
  type        = list(list(string))
  description = "Steps to select the partition type (GPT, MBR, disklabel). Empty on architectures that skip this step."
}

variable "pkgin_network_information_step" {
  type        = list(list(string))
  description = "Step to confirm network information during pkgin install"
}

variable "pkgin_install_steps" {
  default = [
    ["x<enter><wait2m>", "Install pkgin and update package summary"],
    ["<enter><wait5>", "Hit enter to continue"]
  ]
  type        = list(list(string))
  description = "Steps to install pkgin from the repository the installer derived from the release version, or to abandon that step on a release pkgsrc publishes no package set for"
}

variable "net_device" {
  default     = "virtio-net"
  type        = string
  description = "The network device to use in the VM"
}

variable "disk_interface" {
  default     = "virtio"
  type        = string
  description = "The disk interface type to use when building"
}

variable "boot_wait" {
  default     = "10s"
  type        = string
  description = "The time to wait after booting the initial virtual machine before typing the boot command"
}

variable "initial_boot_steps" {
  default = [
    ["1<wait20s>", "Boot normally"]
  ]
  type        = list(list(string))
  description = "The initial boot steps before the installer starts"
}

variable "step_wait" {
  default     = "5"
  type        = string
  description = "The number of seconds to wait between each installer step"
}

variable "install_wait" {
  default     = "5m"
  type        = string
  description = "The time to wait for the OS installation to complete"
}

variable "network_wait" {
  default     = "20"
  type        = string
  description = "The number of seconds to wait for network autoconfiguration"
}

variable "qemuargs" {
  default     = []
  type        = list(list(string))
  description = "Additional architecture-specific QEMU arguments"
}

// sparc64 quits QEMU by talking to this from inside the guest. Bound to
// loopback, not 0.0.0.0: anything that can reach the build host could otherwise
// drive this monitor. The guest still reaches it, because slirp proxies the
// gateway address it connects to, 10.0.2.2, to the host's loopback.
variable "monitor" {
  default     = "tcp:127.0.0.1:4444,server,nowait"
  type        = string
  description = "The QEMU monitor to expose"
}

variable "qmp_socket" {
  default     = ""
  type        = string
  description = "Path to a Unix socket where QEMU should expose a QMP monitor, for tools that drive the build interactively. Empty means none."
}

variable "post_install_disk_device" {
  type        = string
  description = "The disk device to mount during post install"
}

variable "boot_console" {
  default     = ""
  type        = string
  description = "The console device the boot loader and the kernel should use. An empty value leaves the platform default in place"
}

variable "package_repository" {
  default     = ""
  type        = string
  description = "The binary package repository to install the packages from. An empty value keeps the one the installer configured"
}

variable "boot_timestamps" {
  default     = false
  type        = bool
  description = "Print a timestamped line to the console as every rc.d script starts, to attribute the boot time to individual scripts"
}

variable "disk_name" {
  default     = "sd0"
  type        = string
  description = "The raw disk device name (e.g. sd0 for SCSI/virtio, wd0 for IDE)"
}

variable "reboot_steps" {
  default = [
    ["x<enter><wait5s>", "Exit Utility menu"],
    ["d<enter>", "Reboot the computer"],
  ]
  type        = list(list(string))
  description = "Steps to reboot the system after installation. Overridden on architectures where the standard reboot path does not work."
}

variable "provision_wait" {
  default     = "30m"
  type        = string
  description = "The time to wait for provision.sh to finish when it runs from the installer, on architectures without a communicator"
}

variable "communicator_type" {
  default     = "ssh"
  type        = string
  description = "The communicator type: ssh (default) or none. Use none when SSH is too slow (e.g. sparc64 under TCG) and provisioning is done inline via boot_steps."
}

variable "qemu_binary" {
  default     = ""
  type        = string
  description = "Path to the QEMU binary (or wrapper) to invoke. Empty means use qemu-system-<architecture.qemu>. Set per architecture for cases like sparc64 that need a wrapper to rewrite Packer's network flags."
}

variable "shutdown_timeout" {
  default     = ""
  type        = string
  description = "How long Packer waits for the VM to exit after shutdown. Empty selects a sensible default per communicator: 5m for ssh, 30m for none (slow halt under TCG)."
}

locals {
  iso_target_extension = "iso"
  iso_target_path      = "packer_cache"
  iso_full_target_path = "${local.iso_target_path}/${sha1(var.checksum)}.${local.iso_target_extension}"

  image            = "NetBSD-${var.os_version}-${var.architecture.image}.${local.iso_target_extension}"
  vm_name          = "netbsd-${var.os_version}-${var.architecture.name}.img"
  full_remote_path = "images/${var.os_version}/${local.image}?key=NetBSD"

  default_qemuargs = [
    ["-boot", "strict=off"],
    ["-device", "virtio-scsi-pci"],
    ["-device", "scsi-hd,drive=drive0,bootindex=0"],
    ["-device", "scsi-cd,drive=drive1,bootindex=1"],
    ["-drive", "if=none,file={{ .OutputDir }}/{{ .Name }},id=drive0,cache=writeback,discard=ignore,format=raw"],
    ["-drive", "if=none,file=${local.iso_full_target_path},id=drive1,media=disk,format=raw,readonly=on"],
    ["-netdev", "user,id=user.0,hostfwd=tcp::{{ .SSHHostPort }}-:22,ipv6=off"],
  ]

  effective_qemuargs = length(var.qemuargs) > 0 ? var.qemuargs : local.default_qemuargs

  // Packer holds the monitor it opens itself, so a debugger needs its own.
  qmp_qemuargs = var.qmp_socket != "" ? [["-qmp", "unix:${var.qmp_socket},server=on,wait=off"]] : []

  // provision.sh runs under `set -u`, so it needs all of these wherever it runs.
  provision_environment = [
    "SECONDARY_USER=${var.secondary_user_username}",
    "BOOT_CONSOLE=${var.boot_console}",
    "PACKAGE_REPOSITORY=${var.package_repository}",
    "BOOT_TIMESTAMPS=${var.boot_timestamps}"
  ]

  // Without a communicator there is no booted system to provision over SSH, so
  // provision the installed one from the installer's shell instead. These steps
  // start from the Utility menu.
  installer_provision_steps = var.communicator_type == "none" ? [
    ["a<enter><wait${var.step_wait}s>", "Run /bin/sh"],
    ["ftp -o /mnt/tmp/provision.sh http://{{ .HTTPIP }}:{{ .HTTPPort }}/resources/provision.sh<enter><wait${var.step_wait}s>", "Download provision.sh"],
    // sysinst configured DNS for the installer, which the installed system may
    // not have yet, and provision.sh downloads packages.
    ["cp /etc/resolv.conf /mnt/etc/resolv.conf<enter><wait${var.step_wait}s>", "Copy the DNS configuration"],
    ["chroot /mnt env ${join(" ", formatlist("'%s'", local.provision_environment))} sh /tmp/provision.sh<enter><wait${var.provision_wait}>", "Run provision.sh"],
  ] : []

  qemu_binary      = var.qemu_binary != "" ? var.qemu_binary : "qemu-system-${var.architecture.qemu}"
  shutdown_timeout = var.shutdown_timeout != "" ? var.shutdown_timeout : (var.communicator_type == "ssh" ? "5m" : "30m")
}

source "qemu" "qemu" {
  machine_type = var.machine_type
  cpus         = var.cpus
  memory       = var.memory
  net_device   = var.net_device

  disk_interface = var.disk_interface
  disk_size      = var.disk_size

  # RAW, because that is what gets distributed (compressed with zstd, see
  # build.sh). Asking the builder for it directly avoids converting the image
  # afterwards. disk_compression is a qcow2-only option, so it's gone with it.
  format = "raw"

  headless            = var.headless
  use_default_display = var.use_default_display
  display             = var.display
  accelerator         = "none"
  qemu_binary         = local.qemu_binary
  firmware            = var.firmware

  boot_wait = var.boot_wait

  boot_steps = concat(
    var.initial_boot_steps,

    [
      ["a<enter><wait${var.step_wait}s>", "Installation messages in English"]
    ],

    var.keyboard_layout_steps,

    [
      ["a<enter><wait${var.step_wait}s>", "Install NetBSD to hard disk"],
      ["b<enter><wait${var.step_wait}s>", "Yes"],

      ["a<enter><wait${var.step_wait}s>", "Available disks"],
    ],

    var.partition_type_steps,
    var.correct_geometry_steps,

    [
      ["b<enter><wait${var.step_wait}s>", "Use default partition sizes"],
      ["x<enter><wait${var.step_wait}s>", "Partition sizes ok"],
      ["b<enter><wait${var.step_wait}s>", "Yes"],
    ],

    var.bootblock_selection_steps,

    [
      ["d<enter><wait${var.step_wait}s>", "Custom installation"],
      // Distribution set:
      ["${var.key_compiler_tools}<enter><wait${var.step_wait}s>", "Compiler tools"],
      ["${var.key_x11_sets}<enter><wait${var.step_wait}s>", "X11 sets"],
      // X11 sets:
      ["f<enter><wait${var.step_wait}s>", "Select all of the above sets"],
      ["x<enter><wait${var.step_wait}s>", "Install selected sets"],
      // Distribution set:
      ["x<enter><wait${var.step_wait}s>", "Install selected sets"],

      ["a<enter><wait${var.install_wait}>", "Install from: install image media"],

      ["<enter><wait${var.step_wait}s>", "Hit enter to continue"],

      // Configure the additional items as needed
    ],

    var.root_password_pre_steps,

    [
      // Change root password
      ["${var.root_password}<enter><wait${var.step_wait}s>", "New password"],
      ["${var.root_password}<enter><wait${var.step_wait}s>", "New password"],
      ["${var.root_password}<enter><wait${var.step_wait}s>", "Retype new password"],
    ],

    var.generate_entropy_steps,

    [
      // Add a user
      ["o<enter><wait${var.step_wait}s>"],
      ["${var.secondary_user_username}<enter><wait${var.step_wait}s>", "username"],
      ["a<enter><wait${var.step_wait}s>", "Add user to group wheel, Yes"],
      ["a<enter><wait${var.step_wait}s>", "User shell, sh"],
      ["${var.secondary_user_password}<enter><wait${var.step_wait}s>", "New password"],
      ["${var.secondary_user_password}<enter><wait${var.step_wait}s>", "New password"],
      ["${var.secondary_user_password}<enter><wait${var.step_wait}s>", "New password"],

      ["g<enter><wait${var.step_wait}s>", "Enable sshd"],
      ["h<enter><wait${var.step_wait}s>", "Enable ntpd"],
      ["i<enter><wait${var.step_wait}s>", "Run ntpdate at boot"],

      // Configure network
      ["a<enter><wait${var.step_wait}s>"],
      ["a<enter><wait${var.step_wait}s>", "first interface"],
      ["<enter><wait${var.step_wait}s>", "Network media type"],
      ["a<enter><wait${var.network_wait}s>", "Perform autoconfiguration, Yes"]
    ],

    var.hostname_step,

    [
      ["<enter><wait${var.step_wait}s>", "Your DNS domain"],
      ["a<enter><wait${var.step_wait}s>", "Are they OK, Yes"],
      ["a<enter><wait${var.step_wait}s>", "Is the network information accurate. Install in /etc? Yes"],

      // Enable installation of binary packages
      ["e<enter><wait${var.step_wait}s>"]
    ],

    var.pkgin_network_information_step,

    [
      ["i<enter><wait${var.step_wait}s>", "Download via http -> ftp"]
    ],

    // Installing pkgin here is what makes the repository usable, and sysinst
    // retries it in an unbounded loop: a failed `pkg_add` redisplays this menu
    // rather than reporting anything, so every keystroke meant for a later
    // screen lands back in it and the install never finishes. A release that
    // pkgsrc publishes no package set for therefore has to abandon the step
    // explicitly instead of letting it fail; provision.sh installs pkgin from
    // `package_repository` in that case.
    var.pkgin_install_steps,

    [
      ["x<enter><wait${var.step_wait}s>", "Finished configuring"],
      ["<enter><wait${var.step_wait}s>", "Hit enter to continue"],

      // post install configuration
      ["e<enter><wait${var.step_wait}s>", "Utility menu"],
      ["a<enter><wait${var.step_wait}s>", "Run /bin/sh"],

      // shell
      ["ftp -o /tmp/post_install.sh http://{{.HTTPIP}}:{{.HTTPPort}}/resources/post_install.sh<enter><wait${var.step_wait}s>"],
      ["DISK_DEVICE='${var.post_install_disk_device}' DISK_NAME='${var.disk_name}' sh /tmp/post_install.sh && exit<enter><wait${var.step_wait}s>"],

    ],

    local.installer_provision_steps,
    var.reboot_steps
  )

  communicator = var.communicator_type
  ssh_username = "root"
  ssh_password = var.root_password
  ssh_timeout  = "10000s"

  qemuargs = concat(
    [
      ["-cpu", var.cpu_type],
      ["-accel", "hvf"],
      ["-accel", "kvm"],
      ["-accel", "tcg"],
      ["-monitor", var.monitor],

      # When the installer goes out of step the only symptom is packer waiting
      # for an SSH server that never appears, so log the console to make that
      # diagnosable. CI prints and uploads this file.
      #
      # This has to stay a virtual console rather than become `file:`. On the
      # platforms without a display device, the ARM64 one here, the installer's
      # console is the serial port, and it reads the keystrokes packer types
      # from it. A `file:` serial port only writes, so redirecting it there
      # leaves the installer with no input at all and it never gets past its
      # first screen. A chardev keeps the virtual console, and with it packer's
      # input, while also writing everything to a file.
      #
      # The log is not in the output directory: packer refuses to start when
      # that directory already exists and isn't empty, so a log left behind by
      # a previous run would break the next one.
      ["-chardev", "vc,id=console0,logfile=console.log"],
      ["-serial", "chardev:console0"],
    ],
    local.effective_qemuargs,
    local.qmp_qemuargs
  )

  iso_checksum         = var.checksum
  iso_target_extension = local.iso_target_extension
  iso_target_path      = local.iso_target_path
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

  http_directory   = "."
  output_directory = "output"
  shutdown_command = var.communicator_type == "ssh" ? "/sbin/poweroff" : ""
  shutdown_timeout = local.shutdown_timeout
  vm_name          = local.vm_name
}

packer {
  required_plugins {
    qemu = {
      version = "~> 1.0.8"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

build {
  sources = ["qemu.qemu"]

  provisioner "shell" {
    except           = var.communicator_type == "none" ? ["qemu.qemu"] : []
    script           = "resources/provision.sh"
    environment_vars = local.provision_environment
  }

  provisioner "shell" {
    except = var.communicator_type == "none" ? ["qemu.qemu"] : []
    script = "resources/custom.sh"
    environment_vars = [
      "SECONDARY_USER=${var.secondary_user_username}"
    ]
  }

  provisioner "shell" {
    except = var.communicator_type == "none" ? ["qemu.qemu"] : []
    script = "resources/cleanup.sh"
  }
}
