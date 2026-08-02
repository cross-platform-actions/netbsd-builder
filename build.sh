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

download_install_media || true

# NetBSD/VAX is built by the SIMH plugin from a separate template. It
# shares var_files/common.pkrvars.hcl (the user/password identity) with
# the qemu builds, but not the qemu-specific layers — the VAX template
# doesn't declare cpus/disk_size/etc. (those become harmless
# undeclared-variable warnings) and fixes memory itself.
if [ "$ARCHITECTURE" = "vax" ]; then
  packer init netbsd-vax.pkr.hcl

  packer build \
    -var os_version="$OS_VERSION" \
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

  packer build \
    -var os_version="$OS_VERSION" \
    -var-file "var_files/common.pkrvars.hcl" \
    -var-file "var_files/$ARCHITECTURE.pkrvars.hcl" \
    -var-file "var_files/$OS_VERSION/$ARCHITECTURE.pkrvars.hcl" \
    -var-file "var_files/$OS_VERSION/common.pkrvars.hcl" \
    "$@" \
    netbsd.pkr.hcl
fi
