#!/usr/bin/env bash
# agent-snapshot.sh — snapshot the root EBS volume.
#
# Prints the snapshot ID on stdout. Safe to run while the instance is running.
#
# Usage:
#   scripts/agent-snapshot.sh                  # auto description
#   scripts/agent-snapshot.sh "pre-upgrade"    # custom suffix

set -euo pipefail
source "$(dirname "$0")/_agent-env.sh"
agent::require aws

suffix="${1:-}"
date_tag=$(date -u '+%Y-%m-%dT%H%M%SZ')
desc="agent root snapshot ${date_tag}"
[[ -n "$suffix" ]] && desc="${desc} — ${suffix}"

agent::log "finding root volume for $AGENT_INSTANCE_ID..."
root_device=$(aws ec2 describe-instances \
  --instance-ids "$AGENT_INSTANCE_ID" \
  --region "$AGENT_REGION" \
  --query 'Reservations[0].Instances[0].RootDeviceName' \
  --output text)

volume_id=$(aws ec2 describe-instances \
  --instance-ids "$AGENT_INSTANCE_ID" \
  --region "$AGENT_REGION" \
  --query "Reservations[0].Instances[0].BlockDeviceMappings[?DeviceName=='${root_device}'].Ebs.VolumeId | [0]" \
  --output text)

[[ -n "$volume_id" && "$volume_id" != "None" ]] || agent::die \
  "could not resolve root volume id (device=$root_device)"

agent::log "root device: $root_device  volume: $volume_id"
agent::log "creating snapshot: $desc"

snapshot_id=$(aws ec2 create-snapshot \
  --volume-id "$volume_id" \
  --region "$AGENT_REGION" \
  --description "$desc" \
  --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=agent-root-${date_tag}},{Key=agent-deploy,Value=true},{Key=instance-id,Value=${AGENT_INSTANCE_ID}}]" \
  --query 'SnapshotId' \
  --output text)

agent::log "snapshot created: $snapshot_id"
echo "$snapshot_id"
