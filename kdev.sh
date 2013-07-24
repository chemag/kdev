#!/bin/bash

source "$(dirname $0)/common.sh"
source "$(dirname $0)/image.sh"
source "$(dirname $0)/network.sh"
source "$(dirname $0)/argparse.sh"


DEFAULT_DEBIAN_VERSION="wheezy"
DEFAULT_HOSTNAME="${DEFAULT_DEBIAN_VERSION}"
DEFAULT_KERNEL_DIR="$(pwd)"
DEFAULT_MOUNT_DIR=$(mktemp -d /tmp/mnt.XXXXXXXX)
DEFAULT_IMAGE_SIZE="4G"
DEFAULT_IMAGE_TYPE="ext2"
DEFAULT_TAP_DEVICE=$(tuntap_get_free "tap")
DEFAULT_BRIDGE_DEVICE=$(bridge_get_free "br")
DEFAULT_BRIDGE_ADDR="192.168.100.254"
DEFAULT_GUEST_ADDR="192.168.100.1"
DEFAULT_GUEST_MASK="255.255.255.0"  # TODO(chema) fixme
DEFAULT_MAC_ADDR="52:54:00:12:34"  # TODO(chema) fixme

help() {
	echo ""
	echo "Usage: $0 <command> [options]"
	echo "Automatizes running kernel images"
	echo ""
	echo "Command list:"
	echo "  rootfs <file.img|dir>: create a root fs into an image file "
	echo "                         or dir (uses debootstrap)"
	echo "  modules_install <file.img|dir>: install kernel modules into file/dir"
	echo "  qemu <bzImage> <file.img|dir>: run a kernel bzImage using the"
	echo "                                 file dir as root fs"
 	exit 1
}


rootfs() {
	requires debootstrap
	local command_options=(
			"debug,d,debug,,0"
			"debversion,v,debian-version,:,${DEFAULT_DEBIAN_VERSION}"
			"imagedir,i,image-dir,:,"
			"hostname,,hostname,:,${DEFAULT_HOSTNAME}"
			"imagesize,,image-size,:,${DEFAULT_IMAGE_SIZE}"
			"imagetype,,image-type,:,${DEFAULT_IMAGE_TYPE}"
			"mountdir,m,mount-dir,:,${DEFAULT_MOUNT_DIR}"
			"guestaddr,,guestaddr,:,${DEFAULT_GUEST_ADDR}"
			"guestmask,,guestmask,:,${DEFAULT_GUEST_MASK}"
			"bridgeaddr,,bridgeaddr,:,${DEFAULT_BRIDGE_ADDR}"
			"create_file,,create-file,,1"
			)
	# parse parameters
	argparse "${command_options[@]}" -- "$@"
	if [[ "${_RET["debug"]}" -gt 0 ]]; then
		for k in ${!_RET[@]}; do echo "$k -> ${_RET[$k]} "; done
	fi
	if [[ ! "${_RET["remaining"]}" ]]; then
		echo "Error: need a valid image (file or dir)"
		help
	else
		local imagedir="${_RET["remaining"]}"
	fi
	# if imagedir does not exist, create it
	if [[ ! -e "${imagedir}" ]]; then
		if [[ "${_RET["create_file"]}" -eq 0 ]]; then
			echo "Error: need to create the image file"
			help
		fi
		qemu-img create -f raw "${imagedir}" "${_RET["imagesize"]}"
		if [[ "$?" -ne 0 ]]; then
			echo "Error: cannot create the image file"
			exit 1
		fi
		mkfs -t "${_RET["imagetype"]}" "${imagedir}"
	fi
	# mount the imagedir
	local usedir=$(image_use "${imagedir}" "${_RET["mountdir"]}")
	# create the debian distro
	sudo debootstrap "${_RET["debversion"]}" "${usedir}"
	# init fs and networking
	init_net "${usedir}" "${_RET["hostname"]}" "${_RET["guestaddr"]}" \
			"${_RET["guestmask"]}" "${_RET["bridgeaddr"]}"
	init_fs "${usedir}" "v_home" "/home/${USER}"
	# clean up
	image_cleanup "${usedir}"
}


append_line() {
	local line="${1}"
	local file="${2}"

	grep "${line}" "${file}" > /dev/null
	if [ ! $? -eq 0 ]; then
		# line does not exist: append it
		echo "${line}" | sudo tee -a "${file}" > /dev/null
	fi
}


init_net() {
	local usedir="${1}"
	local hostname="${2}"
	local guestaddr="${3}"
	local guestmask="${4}"
	local bridgeaddr="${5}"

	# set the hostname
	sudo rm -fr "${usedir}/etc/hostname"
	echo "${hostname}" | sudo tee "${usedir}/etc/hostname" > /dev/null
	local line="${guestaddr} ${hostname}"
	append_line "${line}" "${usedir}/etc/hosts"

	# set the ip address
	nic="eth0"
	echo "$(cat <<EOF
auto ${nic}
iface ${nic} inet static
	address ${guestaddr}
	netmask ${guestmask}
	post-up route add default gw ${bridgeaddr}

auto lo
iface lo inet loopback
EOF
)" | sudo tee "${usedir}/etc/network/interfaces" > /dev/null

}


init_fs() {
	local usedir="${1}"

	# @ref https://github.com/cozybit/distro11s/blob/master/scripts/qemu-cleanups.sh
	# @ref http://www.virtuatopia.com/index.php/Building_a_Debian_or_Ubuntu_Xen_Guest_Root_Filesystem_using_debootstrap
	# @ref http://lists.gnu.org/archive/html/qemu-devel/2007-09/msg00445.html

	# set the timezone
	echo "America/Los_Angeles" | sudo tee "${usedir}/etc/timezone" > /dev/null
	sudo cp /usr/share/zoneinfo/America/Los_Angeles "${usedir}/etc/localtime"

	# disable the root passwd
	sudo sed -i 's/^root:\*:\(.*\)$/root::\1/' ${usedir}/etc/shadow
	#sudo chroot "${usedir}" /usr/bin/passwd
	# automatically login as root
	echo "$(cat <<EOF
#!/bin/sh
exec /bin/login -f root
EOF
	)" | sudo tee "${usedir}/bin/autologin.sh" > /dev/null
	sudo chmod +x ${usedir}/bin/autologin.sh

	# launch a serial terminal at boot
	local line="T0:23:respawn:/sbin/getty -n -l /bin/autologin.sh -L ttyS0 38400 linux"
	append_line "${line}" "${usedir}/etc/inittab"

	# enable virtfs mounts
	shift 1
	for (( i=1; i<=$#; i+=2 )); do
		j=$[i+1]
		local line="${!i} ${!j} 9p trans=virtio,version=9p2000.L 0 0"
		append_line "${line}" "${usedir}/etc/fstab"
	done
}


modules_install() {
	local command_options=(
			"debug,d,debug,,0"
			"imagedir,i,image-dir,:,"
			"mountdir,m,mount-dir,:,${DEFAULT_MOUNT_DIR}"
			"kerneldir,k,kernel-dir,:,${DEFAULT_KERNEL_DIR}"
			)
	# parse parameters
	argparse "${command_options[@]}" -- "$@"
	if [[ "${_RET["debug"]}" -gt 0 ]]; then
		for k in ${!_RET[@]}; do echo "$k -> ${_RET[$k]} "; done
	fi
	if [[ ! ${_RET["remaining"]} ]]; then
		echo "Error: need a valid image (file or dir)"
		help
	else
		local imagedir="${_RET["remaining"]}"
	fi
	# make the kernel modules
	local kerneldir="${_RET["kerneldir"]}"
	cd "${kerneldir}"
	make modules -j 24
	if [[ "$?" -ne 0 ]]; then
		echo "Error: cannot make modules"
		# clean up
		image_cleanup "${usedir}"
		exit 1
	fi
	# mount the imagedir
	local usedir=$(image_use "${imagedir}" "${_RET["mountdir"]}")
	# install the kernel modules
	sudo make modules_install INSTALL_MOD_PATH="${usedir}"
	if [[ "$?" -ne 0 ]]; then
		echo "Error: cannot install modules"
		# clean up
		image_cleanup "${usedir}"
		exit 1
	fi
	# clean up
	image_cleanup "${usedir}"
}


DEFAULT_QEMUBIN="qemu-system-$(uname -m)"
DEFAULT_ID=$$

qemu() {
	local command_options=(
			"debug,d,debug,,0"
			"qemubin,,qemu-bin,:,${DEFAULT_QEMUBIN}"
			"tapif,,tapif,:,${DEFAULT_TAP_DEVICE}"
			"bridgeif,,bridgeif,:,${DEFAULT_BRIDGE_DEVICE}"
			"bridgeaddr,,bridgeaddr,:,${DEFAULT_BRIDGE_ADDR}"
			"macaddr,,macaddr,:,${DEFAULT_MAC_ADDR}"
			"id,,id,:,${DEFAULT_ID}"
			)
	# parse parameters
	argparse "${command_options[@]}" -- "$@"
	local bzimage=$(cut -d ' ' -f 1 <<< "${_RET["remaining"]}")
	local imagedir=$(cut -s -d ' ' -f 2 <<< "${_RET["remaining"]}")
	if [[ ! "${bzimage}" ]]; then
		echo "Error: need a valid kernel (bzImage)"
		help
	fi
	if [[ ! "${imagedir}" ]]; then
		echo "Error: need a valid rootfs image (file or dir)"
		help
	fi
	echo '---------'
	echo 'remember to do:'
	echo 'apt-get install locate file screen tmux ethtool strace'
	echo 'apt-get install openssh-client openssh-server'
	echo 'apt-get install git build-essential gcc make binutils autoconf'
	echo '---------'
	id="${_RET["id"]}"
	idx=3  # TODO(chema) fixme
	# start the tap and bridge interfaces
	tapif="${_RET["tapif"]}"
	bridgeif="${_RET["bridgeif"]}"
	bridgeaddr="${_RET["bridgeaddr"]}"
	bridge_set "${tapif}" "${bridgeif}" "${bridgeaddr}"

	idx=0
	#devmodules=/tmp/distro11s/out/qemu/staging/lib/modules
	devhome="/home/${USER}"
	macaddr="${_RET["macaddr"]}"
	${_RET["qemubin"]} \
			-nographic \
			-kernel "${bzimage}" \
			-drive "file=${imagedir},format=raw" \
			-append "root=/dev/sda combined_mode=ide console=ttyS0" \
			-fsdev "local,id=home,path=${devhome},security_model=mapped" \
			-device virtio-9p-pci,fsdev=home,mount_tag=v_home \
			-device "e1000,netdev=lan0,mac=${macaddr}:$((56 + idx))" \
			-netdev "tap,id=lan0,ifname=${tapif},script=no,downscript=no" \
			-enable-kvm -smp 2 \
			-gdb tcp::$((1234 + idx))

			#-fsdev "local,id=moddir,path=${devmodules},security_model=mapped" \
			#-device virtio-9p-pci,fsdev=moddir,mount_tag=moddir \
			#
	# cleanup
	bridge_cleanup "${tapif}" "${bridgeif}"
}


main() {
	if [[ $1 =~ ^(help|rootfs|modules_install|qemu)$ ]]; then
		"$@"
	else
		echo "Invalid subcommand $1" >&2
		help
		exit 1
	fi
}


if [[ "$BASH_SOURCE" == "$0" ]]; then
	main "$@"
fi

