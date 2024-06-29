#!/bin/bash
set -eo pipefail

if [[ $# -eq 0 ]]; then
  echo "No command provided... exiting with error."
  exit 1
fi

if [[ -z "${BW_HOST}" || -z "${BW_USER}" || -z "${BW_PASSWORD}" ]]; then
  echo "BW_HOST, BW_USER and BW_PASSWORD environment variables all need to be set. At least one of them is not set."
  exit 1
fi

echo "-----------------------------------------------------------------------------------------------"
echo "Configuring bitwarden cli to use server: ${BW_HOST}..."
/bw config server ${BW_HOST}
echo "-----------------------------------------------------------------------------------------------"
echo "Logging into bitwarden and generating session token..."
export BW_SESSION=$(/bw login ${BW_USER} --passwordenv BW_PASSWORD --raw)
echo "-----------------------------------------------------------------------------------------------"
echo "Unlocking bitwarden..."
/bw unlock --check
echo "-----------------------------------------------------------------------------------------------"
# shellcheck disable=SC2145
echo "Running provided CMD: $@..."
/bw $@
