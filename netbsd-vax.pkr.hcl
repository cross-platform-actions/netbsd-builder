variable "os_version" {
  type        = string
  description = "The version of the operating system to download and install"
}

variable "disk_type" {
  default     = "RA92"
  type        = string
  description = "The SIMH disk type for RQ0 (e.g. RA92, RD54)"
}

variable "checksum" {
  type        = string
  description = "The checksum for the ISO image"
}

variable "root_password" {
  default     = "vagrant"
  type        = string
  description = "The password for the root user"
}

variable "secondary_user_password" {
  default     = "vagrant"
  type        = string
  description = "The password for the secondary user"
}

variable "secondary_user_username" {
  default     = "vagrant"
  type        = string
  description = "The name for the secondary user"
}

locals {
  iso_target_extension = "iso"
  iso_target_path      = "packer_cache"
  image                = "NetBSD-${var.os_version}-vax.${local.iso_target_extension}"
  vm_name              = "netbsd-${var.os_version}-vax"
  full_remote_path     = "images/${var.os_version}/${local.image}"
}

source "simh" "vax" {
  simh_binary = "vax"

  # Old releases move to archive.netbsd.org (see netbsd.pkr.hcl); the
  # archive URL 404s for current releases and packer falls through.
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
  iso_checksum         = var.checksum
  iso_target_extension = local.iso_target_extension
  iso_target_path      = local.iso_target_path

  output_directory = "output"
  vm_name          = local.vm_name

  # Hardcoded: the KA655 VAX tops out at 64 MB, and loading the shared
  # var_files/common.pkrvars.hcl would otherwise set this to the qemu
  # value (4096). With no `memory` variable declared, common's value is
  # just an ignored undeclared-variable warning.
  memory = "64M"

  # CPU options. SIMHALT traps to SCP on the guest's HALT instruction so
  # that NetBSD's `halt -p` at the end of post_install_vax.sh returns
  # control to SCP, which then runs the auto-QUIT and exits cleanly with
  # the disk image preserved.
  #
  # IDLE=NETBSD parks the simulator thread when the guest is idle
  # instead of burning 100% of a host core.
  #
  # We do NOT boot the installed system from disk inside this same SIMH
  # process: the KA655 SSC self-test is unreliable on in-process
  # re-entry. All provisioning is done from the installer
  # (post_install_vax.sh, with the target mounted at /mnt) and then the
  # build halts. The disk image is the artifact; a fresh SIMH process
  # boots it correctly.
  cpu_options = ["SIMHALT", "IDLE=NETBSD"]

  # No NVR (non-volatile RAM) attachment: it would only persist the
  # firmware's default boot device, but the build boots the CD
  # explicitly (BOOT DUA1) and ships only the RAW disk. The consumer
  # autoboots the disk from its own SIMH command file via EXPECT/SEND
  # (`expect ">>>" send "boot dua0\r"; go`).

  # System disk — RA92 (1.5 GB), RAW format (SIMH's default; no FORMAT
  # command needed) for the least runtime overhead on the consumer. The
  # on-disk image is a full 1.5 GB, but build.sh compresses it with zstd
  # to ~90 MB for distribution; minimize_disk in post_install_vax.sh
  # zeroes the free space so it compresses well.
  disk_attachments {
    device       = "RQ0"
    path         = "{{ .OutputDir }}/${local.vm_name}.img"
    set_commands = [var.disk_type]
  }

  # Install CD — attached read-only on RQ1
  disk_attachments {
    device       = "RQ1"
    path         = "{{ .ISOPath }}"
    set_commands = ["CDROM"]
  }

  # Network — XQ0 with plain slirp NAT, no port redirect. The build
  # never connects into the guest (communicator = "none"; provisioning
  # happens via the installer console), and the "nat:" prefix is what
  # triggers the plugin's HTTPIP detection (10.0.2.2 instead of
  # 127.0.0.1) so post_install_vax.sh can fetch over HTTP.
  #
  # Do NOT use "nat:tcp={{ .HostPort }}:10.0.2.15:{{ .GuestPort }}":
  # with communicator = "none" both template variables interpolate to
  # 0 and feeding "nat:tcp=0:10.0.2.15:0" to libslirp wedges
  # sim_slirp_open in a getaddrinfo() call (mDNS lookup on the service
  # name "0").
  network_device {
    device      = "XQ"
    attach_type = "nat:"
  }

  boot_wait         = "15s"
  boot_key_interval = "50ms"
  boot_step_timeout = "30m"

  # Boot steps: drive the VAX console and NetBSD installer via expect/send.
  #
  # The SIMH plugin's expect matching is windowed: each step's expect is
  # matched only against console output that arrived after the previous
  # step's send began (the plugin records a buffer offset just before each
  # send). Text painted on earlier screens — repeated password prompts,
  # menu items rendered before a detour — can never satisfy a later
  # expect; only fresh bytes can. An anchor therefore only needs to be
  # unique within the output the guest paints between the previous send
  # and the screen we're waiting for, and must not appear in the echo of
  # the immediately preceding send (the echo is inside the window).
  #
  # Timed sends (empty expect plus <waitNs>) remain only where no
  # reliable fresh anchor exists: toggling a row on an already-painted
  # curses menu may repaint only the changed row, and advancing between
  # fields of an already-painted form may emit only cursor movement.
  #
  # The VAX VMB firmware presents a ">>>" prompt. We boot the CD-ROM
  # (BOOT DUA1) to run the installer. After installation
  # post_install_vax.sh runs `halt -p`; SIMHALT traps it to SCP, which
  # runs the command file's trailing QUIT and exits.
  #
  # Each step is [expect, send, description]:
  #   - expect: substring to match in console output (empty = send immediately)
  #   - send:   text to send (supports <enter>, <wait5s>, etc.)
  #   - description: human-readable label for Packer output

  boot_steps = [
    # --- VMB firmware ---
    [">>>", "BOOT DUA1<enter>", "Boot from CD-ROM to start installer"],

    # --- NetBSD installer (sysinst) ---
    # The serial console boot prompts for terminal emulation before sysinst
    # launches. Accept the default (vt220) by sending just <enter>.
    ["Terminal type",
     "<enter>",
     "Accept default terminal type (vt220)"],

    # Wait for installer to load — VAX is slow under emulation
    ["a: Installation messages in English",
     "a<enter>",
     "Installation messages in English"],

    ["a: Install NetBSD to hard disk",
     "a<enter>",
     "Install NetBSD to hard disk"],

    ["Shall we continue?",
     "b<enter>",
     "Yes, continue"],

    # "Available disks" menu — use descriptive text unique to this screen
    ["Available disks",
     "a<enter>",
     "Select available disk (ra0)"],

    # VAX uses disklabel, not GPT — no partition type selection step

    ["b: Use default partition sizes",
     "b<enter>",
     "Use default partition sizes"],

    ["x: Partition sizes ok",
     "x<enter>",
     "Partition sizes ok"],

    # Second "Shall we continue?" — the "last chance to quit" confirmation
    ["last chance to quit",
     "b<enter>",
     "Yes, proceed with installation"],

    # VAX has no bootblock selection step

    ["d: Custom installation",
     "d<enter>",
     "Custom installation"],

    # Distribution set: on VAX 10.1 "Compiler tools" is at letter 'e'
    # (Kernel modules appears between Kernel and Base, shifting items).
    ["e: Compiler tools",
     "e<enter>",
     "Toggle compiler tools to Yes"],

    # VAX has no framebuffer, so skip X11 — go straight to install
    ["x: Install selected sets",
     "x<enter>",
     "Install selected sets"],

    # "Install from" menu — match the HTTP option as a stable anchor
    # ('a' is always CD-ROM when booted from CD).
    ["b: HTTP",
     "a<enter>",
     "Install from CD-ROM"],

    # Wait for installation to complete
    ["Hit enter to continue",
     "<enter>",
     "Installation complete, continue"],

    # Set root password.
    #
    # NetBSD's passwd(1) warns about weak passwords and re-prompts. The
    # root_password (resolved to "runner" via common.pkrvars.hcl) is
    # all-lowercase and trips the warning, so the system asks for "New
    # password:" twice before "Retype new password:". Match the warning
    # text to handle the re-prompt.
    ["New password:",
     "${var.root_password}<enter>",
     "Enter root password"],

    ["lower case password",
     "${var.root_password}<enter>",
     "Re-enter root password after weak-password warning"],

    ["Retype new password:",
     "${var.root_password}<enter>",
     "Retype root password"],

    # Entropy seeding.
    #
    # sysinst's entropy menu option `x: Not now, continue!` looks like
    # it skips entropy collection, but it triggers a kernel entropy
    # re-check and cycles back to the menu unless entropy is sufficient.
    # Providing a manual entropy line instead is unconditionally safe:
    # sysinst SHA256-hashes whatever we type and writes the digest to
    # /dev/random.
    #
    # Anchor on `x: Not now, continue!` (the last menu option) so its
    # appearance guarantees the menu has finished painting and sysinst
    # is at getch(), then select `a:` to enter the manual-input screen.
    ["x: Not now, continue!",
     "<wait5s>a<wait1s><enter>",
     "Select manual entropy input"],

    # sysinst SHA256-hashes the typed line and writes the digest to
    # /dev/random, so the entropy credit comes from the *content* of
    # the line, not from keystroke timing. Four UUIDs give ~480 bits
    # of randomness against the 256-bit requirement.
    ["Enter one line of random characters",
     "<wait5s>{{uuid}}{{uuid}}{{uuid}}{{uuid}}<enter>",
     "Provide entropy line"],

    # Add secondary user. The configmenu is painted for the first time
    # only after the entropy flow ends, so the "o: Add a user" row is
    # fresh bytes in the window. The small leading wait is settle margin
    # in case the menu paints in stages.
    ["o: Add a user",
     "<wait2s>o<enter>",
     "Add a user"],

    # The user-add form opens with sysinst's MSG_addusername prompt
    # ("8 character username to add"), painted fresh on activation.
    ["8 character username to add",
     "${var.secondary_user_username}<enter>",
     "Enter username"],

    # After the username field, sysinst opens a "Do you wish to add
    # this user to group wheel?" popup (MSG_addusertowheel). 'a'
    # selects Yes.
    ["group wheel",
     "a<enter>",
     "Add user to group wheel"],

    # Then the "User shell" popup opens with a: /bin/sh, b: /bin/ksh,
    # c: /bin/csh. Anchor on "/bin/ksh" — unique to this popup and
    # impossible to confuse with the echo of our own 'a'. 'a' selects
    # /bin/sh.
    ["/bin/ksh",
     "a<enter>",
     "User shell: sh"],

    # User password. These prompts repeat the exact text of the root
    # password prompts from earlier, but windowed matching only sees
    # output that arrived after the shell selection above, so each
    # occurrence here is fresh bytes. The secondary_user_password is
    # also all-lowercase, so passwd(1) re-prompts for "New password:"
    # before "Retype new password:" — three prompts total. This is the
    # password the CI harness logs in with over ssh.
    ["New password:",
     "${var.secondary_user_password}<enter>",
     "Enter user password"],

    ["lower case password",
     "${var.secondary_user_password}<enter>",
     "Re-enter user password after weak-password warning"],

    ["Retype new password:",
     "${var.secondary_user_password}<enter>",
     "Retype user password"],

    # Enable services and configure network.
    #
    # When the user-add flow returns, process_menu clears and fully
    # repaints the configmenu, so "g: Enable sshd" arrives as fresh
    # bytes and can be anchored. The consecutive h/i toggles stay
    # timed: after a same-menu row toggle, curses may emit bytes only
    # for the changed row, so there is no reliable fresh anchor between
    # toggles. Each toggle also runs chroot shell commands to inspect
    # and patch rc.conf, which takes a few seconds on an emulated VAX —
    # the queued keystrokes are processed once the menu loop reads
    # input again.
    ["g: Enable sshd",
     "<wait2s>g<enter>",
     "Toggle Enable sshd"],

    ["",
     "<wait5s>h<enter>",
     "Toggle Enable ntpd"],

    ["",
     "<wait5s>i<enter>",
     "Toggle Run ntpdate at boot"],

    # Configure network — enter the sub-flow. Same-menu row activation,
    # so timed like the toggles above.
    ["",
     "<wait5s>a<enter>",
     "Enter Configure network"],

    # Network interface menu — sysinst shows "Which network device would
    # you like to use?" then "Available interfaces". NetBSD/VAX detects
    # the SIMH DELQA as qt0 (not xq0), but match the prompt text to be
    # agnostic.
    ["Which network device",
     "a<enter>",
     "Select first network interface"],

    # The network form (media type, hostname, DNS domain, IPv4
    # address, netmask, gateway) paints all of its labels when it
    # first appears; advancing between fields may emit only cursor
    # movement, so there is no reliable fresh anchor per field. Keep
    # short timed sends for the form fields — early keystrokes queue
    # in the tty and are consumed when the prompt reads. The popups
    # that interrupt the form (autoconfiguration, DNS-server
    # selection, confirmation) are fresh full paints and are
    # expect-anchored instead.
    #
    # Accept default media type (empty = autoconfigure). The first
    # field needs extra margin: sysinst runs ifconfig subprocesses to
    # preload defaults before the prompt appears, slow on an emulated
    # VAX.
    ["",
     "<wait10s><enter>",
     "Accept default media type"],

    # After media type, sysinst pops up "Perform autoconfiguration?" —
    # a fresh popup paint, safe to anchor. Static IP by choice: it
    # matches slirp's fixed NAT layout (gateway 10.0.2.2, DNS 10.0.2.3,
    # first lease 10.0.2.15), is deterministic, and avoids waiting on a
    # DHCP exchange.
    ["Perform autoconfiguration?",
     "b<enter>",
     "No, configure network statically"],

    # Back in the form (timed, see above): hostname / DNS domain accept
    # defaults; static IPv4 settings match SIMH's slirp NAT layout.
    ["",
     "<wait5s><enter>",
     "Accept default hostname"],

    ["",
     "<wait5s><enter>",
     "Accept default DNS domain"],

    ["",
     "<wait5s>10.0.2.15<enter>",
     "IPv4 address"],

    ["",
     "<wait5s>255.255.255.0<enter>",
     "IPv4 netmask"],

    ["",
     "<wait5s>10.0.2.2<enter>",
     "IPv4 gateway"],

    # After gateway, sysinst pops up the "Select DNS server" menu —
    # a fresh popup paint (a-d: Google DNS presets, "e: other" opens
    # a free-text field for a custom address).
    ["Select DNS server",
     "e<enter>",
     "Select 'other' DNS server"],

    # The custom-address field ("Your name server") is a form-style
    # prompt again — keep a short timed send.
    ["",
     "<wait5s>10.0.2.3<enter>",
     "Enter custom DNS server"],

    # Network summary confirmation: sysinst displays the values just
    # entered and asks "Are they OK?" (MSG_netok_ok) in a fresh popup.
    # 'a' selects Yes.
    ["Are they OK",
     "a<enter>",
     "Network settings OK (a: Yes)"],

    # After bringing the interface up (ifconfig/route — the expect
    # absorbs however long that takes), sysinst asks "Is the network
    # information you entered accurate for this machine in regular
    # operation and do you want it installed in /etc?"
    # (MSG_mntnetconfig) — another fresh popup. 'a' selects Yes.
    ["installed in /etc",
     "a<enter>",
     "Install network config in /etc (a: Yes)"],

    # Back in the configmenu, cleared and fully repainted after the
    # network flow returns — the exit row "x: Finished configuring" is
    # fresh bytes. Skip pkgin entirely on VAX: NetBSD doesn't publish
    # prebuilt pkgsrc binaries under the URL sysinst constructs
    # (vax/10.1/All/), so the built-in pkgin installer always fails.
    # Press 'x: Finished configuring' directly instead of 'e' for
    # binary packages.
    ["x: Finished configuring",
     "<wait2s>x<enter>",
     "Finished configuring (skip pkgin on VAX)"],

    # After 'x: Finished configuring', sysinst runs its sanity checks
    # and VAX cleanup silently, then shows a single "Hit enter to
    # continue" prompt and returns to the main NetBSD menu. Expecting
    # the prompt self-paces and avoids stray <enter>s activating
    # main-menu entries.
    ["Hit enter to continue",
     "<enter>",
     "Dismiss install-complete screen"],

    # Post-install: enter utility menu shell and configure SSH. The
    # main menu repaints fresh after the install flow returns, the
    # utility menu is a fresh paint, and /bin/sh prints a fresh "# "
    # prompt once it starts — all anchorable under windowed matching.
    ["e: Utility menu",
     "e<enter>",
     "Enter Utility menu (main menu 'e')"],

    ["a: Run /bin/sh",
     "a<enter>",
     "Run /bin/sh (utility menu 'a')"],

    ["# ",
     "ftp -o /tmp/post_install_vax.sh http://{{ .HTTPIP }}:{{ .HTTPPort }}/resources/post_install_vax.sh<enter>",
     "Download post_install_vax.sh"],

    # ftp download completion: anchor on the shell prompt returning.
    # The window since the ftp send contains the command echo and the
    # progress bar (rendered with '*', not '#'), so the first "# " to
    # arrive is the fresh root prompt after ftp exits.
    #
    # Run the VAX-only post-install script, then `halt -p`. SIMHALT
    # traps the halt to SCP, the trailing QUIT ends the simulator
    # cleanly, and the disk image is the build artifact.
    ["# ",
     "DISK_DEVICE='/dev/ra0a' DISK_NAME='ra0' sh /tmp/post_install_vax.sh && halt -p<enter>",
     "Run post_install_vax.sh, then halt"],
  ]

  # No communicator: we don't try to SSH into the installed system from
  # this build (see cpu_options comment for why). The build's artifact is
  # the disk image; provisioning is done by post_install_vax.sh against
  # the target system at /mnt before the installer halts.
  communicator = "none"

  http_directory   = "."
  shutdown_timeout = "15m"
}

packer {
  required_plugins {
    simh = {
      version = ">= 0.0.1"
      source  = "github.com/cross-platform-actions/simh"
    }
  }
}

build {
  sources = ["simh.vax"]

  # No SSH provisioners on VAX: with communicator = "none" packer never
  # boots the installed system from disk, so the SSH-based provisioners
  # never get a target. Equivalent work is done by post_install_vax.sh
  # against the target system at /mnt during the install.
}
