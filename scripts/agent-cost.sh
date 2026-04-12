#!/usr/bin/env bash
# agent-cost.sh — month-to-date AWS spend, broken down by service.
#
# Notes:
#   - Cost Explorer must be enabled in your AWS account (one-time console click).
#   - ~$0.01 per API call — run sparingly.
#   - Data lags ~24h.
#
# Usage:
#   scripts/agent-cost.sh                # all spend in your region, by service
#   scripts/agent-cost.sh --instance     # filter to instance tag
#   scripts/agent-cost.sh --last-month   # previous calendar month

set -euo pipefail
source "$(dirname "$0")/_agent-env.sh"
agent::require aws

mode="mtd"
filter_instance=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --instance)   filter_instance=1; shift ;;
    --last-month) mode="last"; shift ;;
    -h|--help)    sed -n '2,12p' "$0"; exit 0 ;;
    *)            agent::die "unknown arg: $1" ;;
  esac
done

if [[ "$mode" == "mtd" ]]; then
  start=$(date -u '+%Y-%m-01')
  end=$(date -u -d 'tomorrow' '+%Y-%m-%d')
else
  start=$(date -u -d "$(date -u '+%Y-%m-01') -1 month" '+%Y-%m-01')
  end=$(date -u '+%Y-%m-01')
fi

agent::log "querying Cost Explorer: $start -> $end ($mode)"
agent::warn "this API call costs ~\$0.01"

region_filter='{"Dimensions":{"Key":"REGION","Values":["'"$AGENT_REGION"'"]}}'

if [[ "$filter_instance" -eq 1 ]]; then
  tag_spec="${AGENT_COST_TAG:-Name,agent-instance}"
  tag_key="${tag_spec%%,*}"
  tag_val="${tag_spec##*,}"
  agent::log "filtering to tag: $tag_key=$tag_val"
  tag_filter='{"Tags":{"Key":"'"$tag_key"'","Values":["'"$tag_val"'"]}}'
  filter='{"And":['"$region_filter"','"$tag_filter"']}'
else
  filter="$region_filter"
fi

raw=$(aws ce get-cost-and-usage \
  --region us-east-1 \
  --time-period "Start=$start,End=$end" \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --filter "$filter" \
  --query 'ResultsByTime[0].Groups[].[Keys[0],Metrics.UnblendedCost.Amount,Metrics.UnblendedCost.Unit]' \
  --output text)

if [[ -z "$raw" ]]; then
  agent::log "no spend recorded for $start..$end"
  exit 0
fi

printf '%-40s %12s\n' "SERVICE" "COST"
printf '%-40s %12s\n' "----------------------------------------" "------------"
total=0
while IFS=$'\t' read -r svc amt unit; do
  printf '%-40s %9.2f %s\n' "$svc" "$amt" "$unit"
  total=$(awk -v t="$total" -v a="$amt" 'BEGIN{printf "%.4f", t+a}')
done <<<"$raw"
printf '%-40s %12s\n' "----------------------------------------" "------------"
printf '%-40s %9.2f USD\n' "TOTAL" "$total"
