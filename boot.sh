#!/bin/sh
# SPDX-License-Identifier: ISC
# boot.sh - boot the lua initramfs in qemu with the host kernel
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
INITRAMFS="$SRC/initramfs.cpio.gz"
KERNEL="/boot/8e9dce24dde354032c8d155363fd7c13/6.18.18-gentoo/linux"

# Build initramfs if missing
if [ ! -f "$INITRAMFS" ]; then
	echo "Building initramfs..."
	"$SRC/mkinitramfs.sh"
fi

exec qemu-system-x86_64 \
	-enable-kvm \
	-kernel "$KERNEL" \
	-initrd "$INITRAMFS" \
	-append "console=ttyS0 init=/init devtmpfs.mount=1 quiet loglevel=0" \
	-m 256M \
	-no-reboot \
	-nographic


