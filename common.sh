#!/bin/bash

# ensure that a command (or group of) is present
requires() {
	for command in "$@"; do
		if ! which ${command} &> /dev/null; then
			echo "Need command ${command}"
			exit 1
		fi
	done
}

