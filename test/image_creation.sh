#!/bin/bash

TMPDIR=${TMPDIR:=/tmp}
DISKIMG=$(mktemp --dry-run "${TMPDIR}/debian.XXXXXXXX.img")
LINUXREPO="git://git.kernel.org/pub/scm/linux/kernel/git/davem/net-next.git"
LINUXREPO="git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"

cwd=$(readlink -f $(dirname "$0"))
base_dir=$(readlink -f "${cwd}/..")

KDEV="${base_dir}/kdev.sh"

# create an image
${KDEV} rootfs --image-size 3G "${DISKIMG}"

if [[ -z "${KERNEL_DIR}" ]]; then
	# create your own kernel
	pushd ${TMPDIR}
	KERNEL_DIR=$(mktemp -d "${TMPDIR}/linux.XXXXXXXX")
	git clone "${LINUXREPO}" "${KERNEL_DIR}"
	popd
fi

BZIMAGE="${KERNEL_DIR}/arch/x86/boot/bzImage"
if [[ ! -f "${BZIMAGE}" ]]; then
	pushd "${KERNEL_DIR}"
	make defconfig
	make -j 48
	popd
fi

# add kernel modules
${KDEV} modules_install --kernel-dir "${KERNEL_DIR}" "${DISKIMG}"

# run the kernel
${KDEV} qemu "${BZIMAGE}" "${DISKIMG}"

