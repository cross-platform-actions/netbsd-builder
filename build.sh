#!/usr/bin/env sh

set -eux

OS_VERSION="$1"; shift
ARCHITECTURE="$1"; shift

# rm -rf packer_cache

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
