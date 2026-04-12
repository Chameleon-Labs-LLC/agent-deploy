#!/usr/bin/env bash
# agent-ssh.sh — SSH into the agent EC2 instance.
#
# Default: connect via mesh VPN as the `agent` user.
# Bootstrap (--bootstrap): connect as `ubuntu` with the bootstrap key,
# resolving the current public IP from AWS CLI.
#
# Usage:
#   scripts/agent-ssh.sh                 # mesh: agent@$AGENT_MESH_HOST
#   scripts/agent-ssh.sh --bootstrap     # bootstrap: ubuntu@<public IP>
#   scripts/agent-ssh.sh -- <ssh args>   # extra args forwarded to ssh

set -euo pipefail
source "$(dirname "$0")/_agent-env.sh"

mode="mesh"
extra_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bootstrap|-b) mode="bootstrap"; shift ;;
    --mesh|-m)      mode="mesh"; shift ;;
    --)             shift; extra_args=("$@"); break ;;
    -h|--help)      sed -n '2,12p' "$0"; exit 0 ;;
    *)              extra_args+=("$1"); shift ;;
  esac
done

if [[ "$mode" == "mesh" ]]; then
  agent::log "connecting via mesh: ${AGENT_MESH_USER}@${AGENT_MESH_HOST}"
  exec ssh "${AGENT_MESH_USER}@${AGENT_MESH_HOST}" ${extra_args[@]+"${extra_args[@]}"}
fi

# bootstrap mode
[[ -f "$AGENT_BOOTSTRAP_KEY" ]] || agent::die \
  "bootstrap key not found: $AGENT_BOOTSTRAP_KEY (deleted after lockdown?)"

agent::log "resolving current public IP for $AGENT_INSTANCE_ID..."
read -r state public_ip < <(agent::describe)

[[ "$state" == "running" ]] || agent::die \
  "instance state is '$state' — start it with scripts/agent-start.sh"

if [[ -z "$public_ip" || "$public_ip" == "None" ]]; then
  agent::warn "instance has no public IP — bootstrap SSH is not reachable."
  agent::die "use SSM break-glass: scripts/agent-ssm.sh"
fi

agent::log "connecting via bootstrap: ubuntu@${public_ip}"
exec ssh -i "$AGENT_BOOTSTRAP_KEY" "ubuntu@${public_ip}" ${extra_args[@]+"${extra_args[@]}"}
