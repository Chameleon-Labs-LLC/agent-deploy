#!/usr/bin/env bash
# agent-status.sh — one-shot snapshot of the agent instance.
#
# Prints EC2 state, public IP, and mesh reachability.
# --probe also SSHs in and runs `uptime`.
#
# Usage:
#   scripts/agent-status.sh
#   scripts/agent-status.sh --probe

set -euo pipefail
source "$(dirname "$0")/_agent-env.sh"

probe=0
[[ "${1:-}" == "--probe" ]] && probe=1

echo "instance: $AGENT_INSTANCE_ID  region: $AGENT_REGION"

read -r state public_ip < <(agent::describe)
echo "ec2 state: $state"
echo "public ip: ${public_ip}"

if command -v ping >/dev/null 2>&1; then
  if ping -c1 -W2 "$AGENT_MESH_HOST" >/dev/null 2>&1; then
    echo "mesh $AGENT_MESH_HOST: reachable"
  else
    echo "mesh $AGENT_MESH_HOST: unreachable"
  fi
else
  echo "mesh $AGENT_MESH_HOST: (ping not installed, skipped)"
fi

if [[ "$probe" -eq 1 ]]; then
  if [[ "$state" != "running" ]]; then
    agent::warn "--probe skipped: instance is not running"
    exit 0
  fi
  echo "--- remote uptime ---"
  ssh -o ConnectTimeout=5 -o BatchMode=yes \
      "${AGENT_MESH_USER}@${AGENT_MESH_HOST}" uptime \
      || agent::warn "remote probe failed (mesh down? agent user not set up yet?)"
fi
