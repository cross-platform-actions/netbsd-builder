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

# Turn the image's zero ranges into holes, which is what makes `tar --sparse`
# worth asking for: tar uses SEEK_HOLE rather than looking for zeroes itself,
# and the image arrives from the builder fully allocated, so it finds none and
# archives all 12 GB. Digging first takes both ends down to the ~700 MB the
# installation uses.
#
# `fallocate` is Linux-only and works in place. Elsewhere a raw-to-raw qemu-img
# conversion skips the zero blocks and so writes a sparse file.
sparsify() {
  image="$1"

  if command -v fallocate > /dev/null 2>&1; then
    fallocate --dig-holes "$image"
  else
    qemu-img convert -f raw -O raw "$image" "$image.sparse"
    mv "$image.sparse" "$image"
  fi

  echo "image: $(du -h "$image" | cut -f1) on disk, \
$(ls -l "$image" | awk '{print $5}') bytes virtual"
}

# One artifact per image, holding a RAW `disk.img` and, where the release has
# one, a `kernel`. The members are named generically so a consumer needs one
# code path per platform. -19 --long=27 is the knee of the size/speed curve, and
# a 128 MiB window is zstd's default decompression limit, so the consumer needs
# no --long to unpack.
bundle_image() {
  raw="output/netbsd-$OS_VERSION-$ARCHITECTURE.img"
  bundle="output/netbsd-$OS_VERSION-$ARCHITECTURE.tar.zst"

  # Staged inside output/ so that renaming a 12 GB file stays a rename rather
  # than becoming a copy onto another file system.
  rm -rf output/bundle
  mkdir -p output/bundle
  mv "$raw" output/bundle/disk.img

  members='disk.img'

  if [ -f output/kernel ]; then
    mv output/kernel output/bundle/kernel
    members="$members kernel"
  fi

  sparsify output/bundle/disk.img

  # shellcheck disable=SC2086
  tar --sparse -C output/bundle -cf - $members \
    | zstd -19 --long=27 -T0 -o "$bundle" -f

  rm -rf output/bundle
  ls -l "$bundle"
}

# The kernel for QEMU's `microvm` machine type. It goes beside the disk rather
# than inside the image, because that machine type cannot boot from a disk: the
# consumer passes it to QEMU with `-kernel`.
#
# Only releases with the MICROVM configuration publish one, so a release without
# it is not an error. The archive mirror is tried second, as older releases move
# there.
download_microvm_kernel() {
  [ "$ARCHITECTURE" = 'x86-64' ] || return 0

  image_architecture=$(awk -F'"' '/^ *image *=/ { print $2 }' \
    "var_files/$ARCHITECTURE.pkrvars.hcl")
  target=output/kernel
  mkdir -p output

  for base in \
    "https://cdn.netbsd.org/pub/NetBSD/NetBSD-$OS_VERSION" \
    "https://archive.netbsd.org/pub/NetBSD-archive/NetBSD-$OS_VERSION"
  do
    url="$base/$image_architecture/binary/kernel/netbsd-MICROVM.gz"
    echo "microvm kernel: trying $url"
    rm -f /tmp/microvm-kernel.gz
    curl -fL --connect-timeout 30 -o /tmp/microvm-kernel.gz "$url" || continue

    gunzip -c /tmp/microvm-kernel.gz > "$target"
    echo "microvm kernel: obtained from $url"
    ls -l "$target"
    return 0
  done

  echo "microvm kernel: NetBSD $OS_VERSION publishes none"
  return 1
}

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

  # Same bundle as the qemu architectures, so the consumer has one code path.
  # SIMH attaches RAW with the least runtime overhead, so the image here is RAW
  # to begin with; there is no microvm kernel for vax.
  bundle_image
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

  # Before bundling: the kernel is a member of the bundle, not its own artifact.
  download_microvm_kernel || true
  bundle_image
fi
