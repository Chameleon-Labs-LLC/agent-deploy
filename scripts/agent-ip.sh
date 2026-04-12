#!/usr/bin/env bash
# agent-ip.sh — print the current public IP on stdout.
#
# Exits non-zero if the instance has no public IP.

set -euo pipefail
source "$(dirname "$0")/_agent-env.sh"

read -r state public_ip < <(agent::describe)

if [[ -z "$public_ip" || "$public_ip" == "None" ]]; then
  agent::die "no public IP (state=$state). Use mesh or SSM break-glass."
fi

echo "$public_ip"
