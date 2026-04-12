#!/usr/bin/env bash
# agent-snapshot-list.sh — list EBS snapshots tagged agent-deploy=true.
#
# Usage:
#   scripts/agent-snapshot-list.sh
#   scripts/agent-snapshot-list.sh --ids    # just snapshot IDs

set -euo pipefail
source "$(dirname "$0")/_agent-env.sh"
agent::require aws

ids_only=0
[[ "${1:-}" == "--ids" ]] && ids_only=1

raw=$(aws ec2 describe-snapshots \
  --region "$AGENT_REGION" \
  --owner-ids self \
  --filters "Name=tag:agent-deploy,Values=true" \
  --query 'reverse(sort_by(Snapshots,&StartTime))[].[SnapshotId,State,VolumeSize,StartTime,Description]' \
  --output text)

if [[ -z "$raw" ]]; then
  agent::log "no snapshots tagged agent-deploy=true in $AGENT_REGION"
  exit 0
fi

if [[ "$ids_only" -eq 1 ]]; then
  awk '{print $1}' <<<"$raw"
  exit 0
fi

now_epoch=$(date -u +%s)

printf '%-22s %-10s %6s  %-12s %s\n' "SNAPSHOT" "STATE" "SIZE" "AGE" "DESCRIPTION"
while IFS=$'\t' read -r sid state size start desc; do
  start_clean="${start%.*}Z"
  start_clean="${start_clean%ZZ}Z"
  if start_epoch=$(date -u -d "$start_clean" +%s 2>/dev/null); then
    secs=$(( now_epoch - start_epoch ))
    if   (( secs < 3600 ));    then age="$((secs/60))m"
    elif (( secs < 86400 ));   then age="$((secs/3600))h"
    else                            age="$((secs/86400))d"
    fi
  else
    age="?"
  fi
  printf '%-22s %-10s %5sG  %-12s %s\n' "$sid" "$state" "$size" "$age" "$desc"
done <<<"$raw"
