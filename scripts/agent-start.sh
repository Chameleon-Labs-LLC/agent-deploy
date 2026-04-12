#!/usr/bin/env bash
# agent-start.sh — start the agent EC2 instance.
#
# Safe to run when already running. Waits until 'running'.

set -euo pipefail
source "$(dirname "$0")/_agent-env.sh"
agent::require aws

read -r state _ < <(agent::describe)
case "$state" in
  running) agent::log "already running" ;;
  pending) agent::log "already pending — waiting" ;;
  stopped)
    agent::log "starting $AGENT_INSTANCE_ID..."
    aws ec2 start-instances \
      --instance-ids "$AGENT_INSTANCE_ID" \
      --region "$AGENT_REGION" >/dev/null
    ;;
  *)
    agent::die "unexpected state '$state' — investigate with scripts/agent-status.sh"
    ;;
esac

agent::wait_for running
read -r state public_ip < <(agent::describe)
agent::log "state: $state  public ip: $public_ip"
