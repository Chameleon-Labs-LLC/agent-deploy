#!/usr/bin/env bash
# agent-stop.sh — stop the agent EC2 instance (drops billing to EBS-only).
#
# Prompts for confirmation unless --yes is passed.
#
# Usage:
#   scripts/agent-stop.sh          # interactive confirm
#   scripts/agent-stop.sh --yes    # no prompt (for cron / automation)

set -euo pipefail
source "$(dirname "$0")/_agent-env.sh"
agent::require aws

assume_yes=0
[[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]] && assume_yes=1

read -r state _ < <(agent::describe)
case "$state" in
  stopped)  agent::log "already stopped"; exit 0 ;;
  stopping) agent::log "already stopping — waiting" ;;
  running)
    if [[ "$assume_yes" -ne 1 ]]; then
      echo "About to stop $AGENT_INSTANCE_ID in $AGENT_REGION." >&2
      read -r -p "Proceed? [y/N] " reply
      [[ "$reply" =~ ^[Yy]$ ]] || agent::die "aborted"
    fi
    agent::log "stopping $AGENT_INSTANCE_ID..."
    aws ec2 stop-instances \
      --instance-ids "$AGENT_INSTANCE_ID" \
      --region "$AGENT_REGION" >/dev/null
    ;;
  *)
    agent::die "unexpected state '$state' — investigate with scripts/agent-status.sh"
    ;;
esac

agent::wait_for stopped
agent::log "stopped. Billing is now EBS-only (~\$4/mo)."
