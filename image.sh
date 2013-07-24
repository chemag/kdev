#!/bin/bash

SECTOR_SIZE=512

# TODO(chema) we should be able to do this without sudo. I tried libguestfs,
# but the ubuntu precise stock version (1.14.8) is utterly broken (1.23.6
# seems more reliable)
image_use() {
	local imagedir="$1"
	local mountdir="$2"

	if [[ -d "${imagedir}" ]]; then
		# if imagedir is a dir, use it
		usedir="${imagedir}"
	elif [[ -f "${imagedir}" ]]; then
		# if imagedir is a file, mount it
		image_mount "${imagedir}" "${mountdir}"
		usedir="${mountdir}"
	else
		echo "Error: ${imagedir} does not exist"
		exit 1
	fi
	echo "${usedir}"
}


image_mount() {
	local imagedir="$1"
	local mountdir="$2"
	local offset="${3:-0}"

	local loop_device=$(sudo losetup -f --show "${imagedir}" \
			--offset $((${SECTOR_SIZE} * ${offset})))
	# ensure the mountdir exists
	if [[ ! -d "${mountdir}" ]]; then
		mkdir "${mountdir}"
	fi
	sudo mount "${loop_device}" "${mountdir}"
}


image_get_loopdevice() {
	local imagedir="$1"

	sudo losetup -a | grep "${imagedir}" | cut -d ':' -f 1
}


image_cleanup() {
	local usedir="$1"

	# if dir is a mounted dir, unmount and delete corresponding loop device
	while read line; do
		local mountdir=$(cut -s -d ' ' -f 3 <<< "${line}")
		if [[ "${mountdir}" == "${usedir}" ]]; then
			local loop_device=$(cut -d ' ' -f 1 <<< "${line}")
			sudo umount "${mountdir}"
			sudo losetup -d "${loop_device}"
			rmdir "${mountdir}"
			break
		fi
	done <<< "$(mount)"
}

