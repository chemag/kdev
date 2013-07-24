#!/bin/bash

# parse arguments according to a short/long definition
# input: "optiondef1" "optiondef2" ... -- option1 option2 ...
# where
#   optiondefx: "varname,shortopt,longopt,[|:|::],default"
#               e.g. "debversion,d,debian-version,:,wheezy"
#
#    -> _RET["varname"] is a counter
#   : -> set _RET["varname"] to the value
#
# parsed values are returned in _RET
argparse() {
	local caller="$0"
	# init the return value
	unset _RET
	declare -Ag _RET
	# get the raw arguments
	local -a RARGS=($@)
	# get the parsing options
	local short_str=""
	local long_str=""
	local sep_index=0
	local optiondef
	for optiondef in "${RARGS[@]}"; do
		#echo "${optiondef}"
		local OIFS=${IFS}
		IFS=','
		local -a ARRAY=($optiondef)
		IFS=$OIFS
		if [[ "${optiondef}" == "--" ]]; then
			break
		fi
		sep_index=$(($sep_index + 1))
		local varname="${ARRAY[0]}"
		local shortopt="${ARRAY[1]}"
		local longopt="${ARRAY[2]}"
		local opttype="${ARRAY[3]}"
		local default="${ARRAY[4]}"
		short_str="${short_str}${shortopt}${opttype}"
		long_str="${long_str}${longopt}${opttype},"
		_RET["${varname}"]="${default}"
	done
	# do the parsing
	local -a PARGS=($(getopt -u -o "${short_str}" --long "${long_str}" \
			-n "${caller}" -- "${RARGS[@]:$(( ${sep_index} + 1 ))}"))
	local skip=0
	for arg in "${PARGS[@]}"; do
		#echo "${arg}"
		if [[ "${skip}" == 1 ]]; then
			skip=0
			_RET["${varname}"]="${arg}"
			continue
		fi
		if [[ "${arg}" == "--" ]]; then
			continue
		fi
		# look for the variable name
		vartype=$(search_arg_option "${arg}" "${RARGS[@]::${sep_index}}")
		if [[ -z "${vartype}" ]]; then
			# invalid option: return the rest as remaining
			if [[ ${_RET["remaining"]} ]]; then
				_RET["remaining"]="${_RET["remaining"]} ${arg}"
			else
				_RET["remaining"]="${arg}"
			fi
			#echo "invalid option: ${arg}"
			#echo "	${vartype} <- search_arg_option ${arg} ${RARGS[@]::${sep_index}}"
			continue
		fi
		local varname="${vartype%,*}"
		local opttype="${vartype#*,}"
		if [[ "${opttype}" == "" ]]; then
			# counter
			_RET["${varname}"]=$(( ${_RET["${varname}"]} + 1 ))
		else
			# get the next variable
			skip=1
		fi
	done
}


search_arg_option() {
	local arg="$1"
	shift
	# get the raw arguments
	local -a RARGS=($@)
	local optiondef
	for optiondef in "${RARGS[@]}"; do
		#echo "${optiondef}"
		local OIFS=${IFS}
		IFS=','
		local -a ARRAY=($optiondef)
		IFS=$OIFS
		if [[ "${optiondef}" == "--" ]]; then
			break
		fi
		local varname="${ARRAY[0]}"
		local shortopt="${ARRAY[1]}"
		local longopt="${ARRAY[2]}"
		local opttype="${ARRAY[3]}"
		if [[ "${arg}" == "-${shortopt}" || "${arg}" == "--${longopt}" ]]; then
			echo "${varname},${opttype}"
			return
		fi
	done
}

