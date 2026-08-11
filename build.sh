#!/usr/bin/env sh

set -eux

OS_VERSION="$1"; shift
ARCHITECTURE="$1"; shift

# rm -rf packer_cache

# Seed packer's ISO cache with a resilient download. Old releases are
# moved to archive.netbsd.org, which intermittently closes connections
# mid-transfer, and packer's go-getter neither retries nor resumes a
# download — curl does both. The file is named sha1(checksum string),
# matching go-getter's cache naming, so packer verifies the seeded file
# and skips its own download. On any failure the cache is left unseeded
# and packer downloads via iso_urls as before.
download_install_media() {
  checksum=$(awk -F'"' '/^checksum *=/ { print $2 }' "var_files/$OS_VERSION/$ARCHITECTURE.pkrvars.hcl")

  if [ "$ARCHITECTURE" = "vax" ]; then
    image_architecture="vax"
  else
    image_architecture=$(awk -F'"' '/^ *image *=/ { print $2 }' "var_files/$ARCHITECTURE.pkrvars.hcl")
  fi

  image="NetBSD-$OS_VERSION-$image_architecture.iso"
  cache_key=$(printf '%s' "$checksum" | openssl dgst -sha1 -r | cut -d ' ' -f 1)
  target="packer_cache/$cache_key.iso"

  if [ -f "$target" ]; then
    return 0
  fi

  mkdir -p packer_cache

  for url in \
    "https://archive.netbsd.org/pub/NetBSD-archive/images/$OS_VERSION/$image" \
    "https://cdn.netbsd.org/pub/NetBSD/images/$OS_VERSION/$image"
  do
    # -C - resumes a partial file, so each attempt continues where the
    # previous one was cut off instead of starting over.
    for _ in 1 2 3 4 5; do
      curl -fL --connect-timeout 30 -C - -o "$target" "$url" && break
    done

    digest_type=${checksum%%:*}
    expected=${checksum#*:}
    actual=$(openssl dgst "-$digest_type" -r "$target" 2>/dev/null | cut -d ' ' -f 1) || actual=""

    if [ "$actual" = "$expected" ]; then
      return 0
    fi

    rm -f "$target"
  done

  return 1
}

# Download a URL to a local file. curl is available on every host that builds
# this, wget is the fallback for the ones where it isn't.
download() {
  _dl_url="$1"
  _dl_out="$2"

  curl -fSL --connect-timeout 30 -o "$_dl_out" "$_dl_url" || wget -O "$_dl_out" "$_dl_url"
}

# Download a path, relative to the top of a NetBSD distribution, trying each
# mirror in turn.
download_from_mirror() {
  _mirror_path="$1"
  _mirror_out="$2"

  for _mirror in \
    "https://cdn.netbsd.org/pub/NetBSD" \
    "https://ftp.netbsd.org/pub/NetBSD" \
    "https://archive.netbsd.org/pub/NetBSD-archive" \
    "https://mirror.planetunix.net/pub/NetBSD" \
    "https://www.nic.funet.fi/pub/NetBSD"
  do
    if download "$_mirror/$_mirror_path" "$_mirror_out"; then
      return 0
    fi
  done

  return 1
}

# Verify a file against a NetBSD `SHA512` checksum file, which uses the BSD
# style format: `SHA512 (<file>) = <checksum>`.
verify_checksum() {
  _checksum_file="$1"
  _checksum_name="$2"
  _checksum_dir="$(dirname "$_checksum_file")"

  _expected="$(sed -n "s/^SHA512 ($_checksum_name) = //p" "$_checksum_file")"
  [ -n "$_expected" ]

  _actual="$(openssl dgst -sha512 -r "$_checksum_dir/$_checksum_name" | cut -d ' ' -f 1)"
  [ "$_expected" = "$_actual" ]
}

# Download a file, together with the `SHA512` file of the directory it lives
# in, verify it and gunzip it.
download_and_extract() {
  _extract_remote_dir="$1"
  _extract_name="$2"
  _extract_out="$3"

  if [ -f "$_extract_out" ]; then
    return 0
  fi

  download_from_mirror "$_extract_remote_dir/$_extract_name" "$CACHE_DIR/$_extract_name"
  download_from_mirror "$_extract_remote_dir/SHA512" "$CACHE_DIR/SHA512.$_extract_name"

  verify_checksum "$CACHE_DIR/SHA512.$_extract_name" "$_extract_name"

  gunzip -c "$CACHE_DIR/$_extract_name" > "$_extract_out"
}

# Install the credentials creds_msdos(8) picks up on the first boot in the
# MS-DOS boot partition of the disk image. A pre-built image has no user
# configured, and NetBSD doesn't allow root to log in over SSH, so this is how
# packer gets a user to connect as.
install_credentials() {
  _creds_image="$1"
  _creds_offset="$(msdos_partition_offset "$_creds_image")"

  cat <<EOF > "$CACHE_DIR/creds.txt"
useradd $(variable_value secondary_user_username) $(variable_value secondary_user_password)
useradd root $(variable_value root_password)
EOF

  MTOOLS_SKIP_CHECK=1 mcopy -o -i "$_creds_image@@$_creds_offset" \
    "$CACHE_DIR/creds.txt" ::creds.txt
}

# Print the byte offset of the MS-DOS boot partition of a disk image. mtools
# can locate a partition itself only when the image has an MBR partition table;
# the NetBSD images use GPT.
msdos_partition_offset() {
  python3 - "$1" <<'EOF'
import struct
import sys

SECTOR_SIZE = 512


def partition_offsets(image):
    image.seek(SECTOR_SIZE)
    header = image.read(SECTOR_SIZE)

    if header[:8] != b'EFI PART':
        image.seek(446)
        table = image.read(64)

        for index in range(4):
            first_sector, sectors = struct.unpack_from('<II', table, index * 16 + 8)

            if sectors:
                yield first_sector * SECTOR_SIZE

        return

    entries_sector, count, size = struct.unpack_from('<QII', header, 72)

    for index in range(count):
        image.seek(entries_sector * SECTOR_SIZE + index * size)
        entry = image.read(size)

        if entry[:16] == bytes(16):
            continue

        yield struct.unpack_from('<Q', entry, 32)[0] * SECTOR_SIZE


def is_msdos(image, offset):
    image.seek(offset)
    sector = image.read(SECTOR_SIZE)

    # The file system type is at a different location for FAT12/FAT16 and
    # FAT32.
    return b'FAT' in sector[54:62] or b'FAT' in sector[82:90]


with open(sys.argv[1], 'rb') as image:
    for offset in partition_offsets(image):
        msdos = is_msdos(image, offset)
        print('partition at offset', offset, 'msdos' if msdos else 'other', file=sys.stderr)

        if msdos:
            print(offset)
            break
    else:
        sys.exit('no MS-DOS partition in %s' % sys.argv[1])
EOF
}

# NetBSD publishes no installation media for the riscv port, only a pre-built
# disk image. Download the image, and the kernel, since the image is booted
# through QEMU's direct kernel boot, and install the credentials packer
# connects with.
prepare_riscv64_image() {
  _riscv_dir="NetBSD-$OS_VERSION/riscv-riscv64/binary"
  _riscv_image="$CACHE_DIR/netbsd-$OS_VERSION-riscv64.img"
  _riscv_kernel="$CACHE_DIR/netbsd-$OS_VERSION-riscv64-GENERIC64"

  mkdir -p "$CACHE_DIR"

  download_and_extract "$_riscv_dir/gzimg" riscv64.img.gz "$_riscv_image"
  download_and_extract "$_riscv_dir/kernel" netbsd-GENERIC64.gz "$_riscv_kernel"

  install_credentials "$(absolute_path "$_riscv_image")"

  EXTRA_ARGS="-var image_path=$(absolute_path "$_riscv_image") -var kernel_path=$(absolute_path "$_riscv_kernel")"
}

absolute_path() {
  echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
}

# Read the value of a string variable from `var_files/common.pkrvars.hcl`.
variable_value() {
  awk -F'"' "/^$1 *=/ { print \$2 }" var_files/common.pkrvars.hcl
}

CACHE_DIR='.cache'
EXTRA_ARGS=''

if [ "$ARCHITECTURE" = "riscv64" ]; then
  prepare_riscv64_image
else
  download_install_media || true
fi

# NetBSD/VAX is built by the SIMH plugin from a separate template. It
# shares var_files/common.pkrvars.hcl (the user/password identity) with
# the qemu builds, but not the qemu-specific layers — the VAX template
# doesn't declare cpus/disk_size/etc. (those become harmless
# undeclared-variable warnings) and fixes memory itself.
if [ "$ARCHITECTURE" = "vax" ]; then
  # Generate the image's SSH host keys on the build host. Generating
  # them on the emulated VAX — whether at build time or by rc.d/sshd on
  # the consumer's first boot — costs ~20 minutes at ~1 MIPS (RSA-3072
  # dominates). post_install_vax.sh fetches these over packer's HTTP
  # server into /mnt/etc/ssh, so the consumer's sshd starts
  # immediately.
  rm -rf ssh_host_keys
  mkdir ssh_host_keys
  for key_type in rsa ecdsa ed25519; do
    ssh-keygen -q -N '' -t "$key_type" -f "ssh_host_keys/ssh_host_${key_type}_key"
  done

  # Fetch the prebuilt vax pkgsrc packages from the netbsd-pkg-repo release
  # into a directory packer serves over HTTP (http_directory = "."). The
  # official NetBSD mirrors carry no vax binaries, so the emulated VAX cannot
  # bootstrap pkgin itself; post_install_vax.sh fetches each package from here
  # into the target and installs it from that local copy (no TLS on the ~1 MIPS
  # VAX). Pinned to a release for reproducibility -- bump pkg_repo_version for a
  # newer set. The same version is published per NetBSD release
  # (NetBSD-<version>-vax--<pkg_repo_version>), so it must exist for every
  # version built here -- v0.1.0 is the first one covering both 10.1 and 11.0.
  pkg_repo="cross-platform-actions/netbsd-pkg-repo"
  pkg_repo_version="v0.1.0"
  pkg_repo_tag="NetBSD-${OS_VERSION}-vax--${pkg_repo_version}"
  pkg_release_url="https://github.com/${pkg_repo}/releases/download/${pkg_repo_tag}"
  rm -rf vax_packages
  mkdir -p vax_packages/All
  gh release download "$pkg_repo_tag" --repo "$pkg_repo" --dir vax_packages/All --clobber
  # A MANIFEST of the .tgz names so post_install_vax.sh can fetch each package
  # by name with the installer's ftp (no directory-listing parsing needed) and
  # install from the local copies.
  ( cd vax_packages/All && ls -1 ./*.tgz | sed 's,^\./,,' > MANIFEST )

  packer init netbsd-vax.pkr.hcl

  packer build \
    -var os_version="$OS_VERSION" \
    -var pkg_repo_release_url="$pkg_release_url" \
    -var-file "var_files/common.pkrvars.hcl" \
    -var-file "var_files/$OS_VERSION/vax.pkrvars.hcl" \
    "$@" \
    netbsd-vax.pkr.hcl

  # Compress the RAW disk image for distribution. The qemu architectures
  # get compression for free from qcow2; the SIMH RAW image does not, so
  # we zstd it here. Build time is irrelevant, so compress hard: -19
  # --long=27 is the knee of the size/speed curve (~90 MB from ~1.5 GB)
  # and a 128 MiB window is exactly zstd's default decompression limit,
  # so the consumer needs no --long flag to `zstd -d`. The consumer
  # stream-decompresses back to RAW (least runtime overhead under SIMH):
  #   curl -sL <url>/netbsd-<ver>-vax.img.zst | zstd -dc > disk.raw
  image="output/netbsd-${OS_VERSION}-vax.img"
  zstd -19 --long=27 -f "$image" -o "$image.zst"
else
  packer init netbsd.pkr.hcl

  # shellcheck disable=SC2086
  packer build \
    -var os_version="$OS_VERSION" \
    -var-file "var_files/common.pkrvars.hcl" \
    -var-file "var_files/$ARCHITECTURE.pkrvars.hcl" \
    -var-file "var_files/$OS_VERSION/$ARCHITECTURE.pkrvars.hcl" \
    -var-file "var_files/$OS_VERSION/common.pkrvars.hcl" \
    $EXTRA_ARGS \
    "$@" \
    netbsd.pkr.hcl
fi
