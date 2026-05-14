#!/bin/sh
# SPDX-License-Identifier: ISC
# boot.sh - boot the lua initramfs in qemu with a Debian kernel
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
INITRAMFS="$SRC/initramfs.cpio.gz"
CACHE="$SRC/.cache"

MIRROR="https://mirrors.osuosl.org/debian/dists/stable/main/installer-amd64/current/images"
KERNEL_URL="$MIRROR/netboot/debian-installer/amd64/linux"
KERNEL_SHA256="43f50a610966946ca6e3e816b536682619ad1c3cd9076518f97cb5039fabac6c"
KERNEL="$CACHE/linux"

# Build initramfs if missing
if [ ! -f "$INITRAMFS" ]; then
	echo "Building initramfs..."
	"$SRC/mkinitramfs.sh"
fi

# Download kernel if missing or checksum mismatch
download_kernel() {
	mkdir -p "$CACHE"
	echo "Downloading Debian kernel..."
	curl -fSL -o "$KERNEL.tmp" "$KERNEL_URL"
	# Verify checksum
	got=$(sha256sum "$KERNEL.tmp" | cut -d' ' -f1)
	if [ "$got" != "$KERNEL_SHA256" ]; then
		rm -f "$KERNEL.tmp"
		echo "ERROR: kernel checksum mismatch" >&2
		echo "  expected: $KERNEL_SHA256" >&2
		echo "  got:      $got" >&2
		exit 1
	fi
	mv "$KERNEL.tmp" "$KERNEL"
	echo "Kernel verified: $KERNEL"
}

if [ ! -f "$KERNEL" ]; then
	download_kernel
else
	# Verify existing kernel
	got=$(sha256sum "$KERNEL" | cut -d' ' -f1)
	if [ "$got" != "$KERNEL_SHA256" ]; then
		echo "Cached kernel checksum mismatch, re-downloading..."
		download_kernel
	fi
fi

exec qemu-system-x86_64 \
	-enable-kvm \
	-kernel "$KERNEL" \
	-initrd "$INITRAMFS" \
	-append "console=ttyS0 init=/init devtmpfs.mount=1 quiet loglevel=0" \
	-m 256M \
	-no-reboot \
	-nographic
