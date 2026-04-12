#!/usr/bin/env bash
# agent-ssm.sh — break-glass shell via AWS SSM Session Manager.
#
# Use when mesh is broken. Requires session-manager-plugin:
#   https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html

set -euo pipefail
source "$(dirname "$0")/_agent-env.sh"
agent::require aws

if ! command -v session-manager-plugin >/dev/null 2>&1; then
  agent::warn "session-manager-plugin not found on PATH."
  agent::warn "install: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
fi

read -r state _ < <(agent::describe)
[[ "$state" == "running" ]] || agent::die \
  "instance state is '$state' — start it with scripts/agent-start.sh"

agent::log "opening SSM session to $AGENT_INSTANCE_ID..."
exec aws ssm start-session \
  --target "$AGENT_INSTANCE_ID" \
  --region "$AGENT_REGION" \
  "$@"
