#!/usr/bin/env bash
# agent-logs.sh — tail a journald unit on the instance over mesh SSH.
#
# Usage:
#   scripts/agent-logs.sh                    # tails claude-agent by default
#   scripts/agent-logs.sh codex-agent        # short name (.service appended)
#   scripts/agent-logs.sh claude-agent -n 200
#   scripts/agent-logs.sh --no-follow claude-agent -n 500

set -euo pipefail
source "$(dirname "$0")/_agent-env.sh"

follow="-f"
if [[ "${1:-}" == "--no-follow" ]]; then
  follow=""
  shift
fi

unit="${1:-claude-agent}"
shift || true
[[ "$unit" == *.* ]] || unit="${unit}.service"

agent::log "tailing $unit on ${AGENT_MESH_USER}@${AGENT_MESH_HOST} (Ctrl-C to stop)"
# shellcheck disable=SC2029
exec ssh -t "${AGENT_MESH_USER}@${AGENT_MESH_HOST}" \
  "journalctl -u '$unit' $follow --no-pager $*"
