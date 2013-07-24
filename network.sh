#!/bin/bash

tuntap_exists() {
	local tapif="$1"
	while read line; do
		local tuntapif=$(cut -s -d ':' -f 1 <<< "${line}")
		if [[ "${tuntapif}" == "${tapif}" ]]; then
			return 0
			break
		fi
	done <<< "$(ip tuntap ls)"
	return 1
}


tuntap_get_free() {
	local prefix="$1"

	for (( i=0; i<=10; i+=1 )); do
		tapif="${prefix}${i}"
		if ! tuntap_exists "${tapif}"; then
			echo "${tapif}"
			return 0
		fi
	done
	return 1
}


tuntap_add() {
	local tapif="$1"
	sudo ip tuntap add "${tapif}" mode tap
}


tuntap_del() {
	local tapif="$1"
	sudo ip tuntap del "${tapif}" mode tap
}


bridge_exists_old() {
	local bridgeif="$1"
	requires bridge-utils

	local first_line_discarded=0
	while read line; do
		# discard first line
		if [[ "${first_line_discarded}" == 0 ]]; then
			first_line_discarded=1
			continue
		fi
		local brif=$(cut -f 1 <<< "${line}")
		if [[ "${brif}" == "${bridgeif}" ]]; then
			return 0
			break
		fi
	done <<< "$(brctl show)"
	return 1
}


# check a nic exists and is a bridge
bridge_exists() {
	local nic="$1"

	[[ -d "/sys/class/net/${nic}/bridge" ]]
}


bridge_get_free() {
	local prefix="$1"

	for (( i=0; i<=10; i+=1 )); do
		local brif="${prefix}${i}"
		if ! bridge_exists "${brif}"; then
			echo "${brif}"
			return 0
		fi
	done
	return 1
}


bridge_get_slaves() {
	local brif="$1"

	\ls "/sys/class/net/${brif}/brif/" 2> /dev/null
}


bridge_add() {
	local bridgeif="$1"
	#sudo brctl addbr "${bridgeif}"
	sudo ip link add dev "${bridgeif}" type bridge
}


bridge_del() {
	local bridgeif="$1"
	#sudo brctl delbr "${bridgeif}"
	sudo ip link del dev "${bridgeif}" type bridge
}


bridge_set() {
	local tapif="$1"
	local bridgeif="$2"
	local bridgeaddr="$3"

	# check ip_forward is on
	ip_forward=$(cat /proc/sys/net/ipv4/ip_forward)
	if [[ "${ip_forward}" != "1" ]]; then
		echo "Error: must enable /proc/sys/net/ipv4/ip_forward"
		return 1
	fi

	# ensure the tap interface exists
	if ! tuntap_exists "${tapif}"; then
		tuntap_add "${tapif}"
	fi
	# ensure the bridge interface exists
	if ! bridge_exists "${bridgeif}"; then
		bridge_add "${bridgeif}"
	fi
	# enslave the tap if to the bridge if
	sudo ip link set dev "${tapif}" master "${bridgeif}"
	#sudo brctl addif "${bridgeif}" "${tapif}"
	# init both nics
	sudo ip addr add 0.0.0.0 dev "${tapif}"
	sudo ip addr add "${bridgeaddr}"/24 dev "${bridgeif}"
	sudo ip link set "${tapif}" up
	sudo ip link set "${bridgeif}" up

	# ZZZ
	# set iptables
	# traffic from subnetwork to outside world (!subnetwork) is NATted
	echo sudo iptables -t nat -I POSTROUTING 1 -s "${bridgeaddr}/24" ! -d "${bridgeaddr}/24" -j MASQUERADE

	# traffic from/to subnetwork must be accepted by filter::FORWARD chain
	echo sudo iptables -t filter -I FORWARD 1 -s "${bridgeaddr}/24" -i "${bridgeif}" -j ACCEPT
	echo sudo iptables -t filter -I FORWARD 1 -d "${bridgeaddr}/24" -o "${bridgeif}" -m state --state RELATED,ESTABLISHED -j ACCEPT

}


bridge_cleanup() {
	local tapif="$1"
	local bridgeif="$2"

	# clean up the tap device
	tuntap_del "${tapif}"
	# clean up the bridge
	bridge_del "${bridgeif}"
}
