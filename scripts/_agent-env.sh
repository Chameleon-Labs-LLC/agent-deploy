#!/usr/bin/env bash
# _agent-env.sh — shared defaults for agent ops scripts.
#
# Source this from other scripts:
#   source "$(dirname "$0")/_agent-env.sh"
#
# All values come from environment variables. Set them in your private
# agent-env.sh (copy from agent-env.example.sh at the repo root) or
# export them in your shell before running scripts.
#
# If agent-env.sh exists at the repo root, it is sourced automatically.

_repo_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$_repo_root/agent-env.sh" ]]; then
  source "$_repo_root/agent-env.sh"
fi

# Defaults — override via environment or agent-env.sh
AGENT_INSTANCE_ID="${AGENT_INSTANCE_ID:?Set AGENT_INSTANCE_ID in agent-env.sh}"
AGENT_REGION="${AGENT_REGION:-us-east-1}"
AGENT_MESH_HOST="${AGENT_MESH_HOST:?Set AGENT_MESH_HOST in agent-env.sh}"
AGENT_MESH_USER="${AGENT_MESH_USER:-agent}"
AGENT_BOOTSTRAP_KEY="${AGENT_BOOTSTRAP_KEY:-$HOME/.ssh/agent-bootstrap.pem}"

export AGENT_INSTANCE_ID AGENT_REGION AGENT_MESH_HOST AGENT_MESH_USER AGENT_BOOTSTRAP_KEY

# Logging helpers — all messages go to stderr so scripts that print a value
# on stdout (e.g. agent-ip.sh) stay pipe-friendly.
agent::log()  { echo "[agent] $*" >&2; }
agent::warn() { echo "[agent] WARN: $*" >&2; }
agent::die()  { echo "[agent] ERROR: $*" >&2; exit 1; }

# Require a command to exist, or die with a helpful message.
agent::require() {
  command -v "$1" >/dev/null 2>&1 || agent::die "missing required command: $1"
}

# Describe the instance. Prints: "<state>\t<public_ip>"
# public_ip will be the literal string "None" when absent.
agent::describe() {
  agent::require aws
  aws ec2 describe-instances \
    --instance-ids "$AGENT_INSTANCE_ID" \
    --region "$AGENT_REGION" \
    --query 'Reservations[0].Instances[0].[State.Name,PublicIpAddress]' \
    --output text
}

# Wait until the instance reaches a target state (running|stopped).
# Usage: agent::wait_for running
agent::wait_for() {
  local target="$1"
  agent::require aws
  agent::log "waiting for instance to reach state '$target'..."
  aws ec2 "wait" "instance-${target}" \
    --instance-ids "$AGENT_INSTANCE_ID" \
    --region "$AGENT_REGION"
}
