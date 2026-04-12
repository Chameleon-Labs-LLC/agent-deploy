#!/usr/bin/env bash
# agent-health.sh — remote health check over mesh SSH.
#
# Reports uptime, memory, disk, systemd unit status, and recent journal entries.

set -euo pipefail
source "$(dirname "$0")/_agent-env.sh"

AGENT_UNITS="${AGENT_UNITS:-claude-agent.service codex-agent.service gemini-agent.service pi-coding-agent.service}"

remote_script=$(cat <<'REMOTE'
set -u
echo "=== uptime ==="
uptime
echo
echo "=== memory ==="
free -h
echo
echo "=== disk / ==="
df -h /
echo
echo "=== agent units ==="
for unit in AGENT_UNITS_PLACEHOLDER; do
  if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
    state=$(systemctl is-active "$unit" 2>/dev/null || true)
    printf '  %-30s %s\n' "$unit" "$state"
  else
    printf '  %-30s %s\n' "$unit" "(not installed)"
  fi
done
echo
echo "=== recent journal (last 5 lines per unit) ==="
for unit in AGENT_UNITS_PLACEHOLDER; do
  if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
    echo "--- $unit ---"
    journalctl -u "$unit" -n 5 --no-pager 2>/dev/null || echo "  (no logs)"
  fi
done
REMOTE
)

remote_script="${remote_script//AGENT_UNITS_PLACEHOLDER/$AGENT_UNITS}"

agent::log "running health check on ${AGENT_MESH_USER}@${AGENT_MESH_HOST}"
ssh -o ConnectTimeout=5 -o BatchMode=yes \
    "${AGENT_MESH_USER}@${AGENT_MESH_HOST}" \
    "bash -s" <<<"$remote_script"
