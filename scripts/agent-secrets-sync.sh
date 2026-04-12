#!/usr/bin/env bash
# agent-secrets-sync.sh — push API keys from your local vault to the instance.
#
# Reads key files from $AGENT_SECRETS_VAULT and writes them to
# ~/.config/agent-secrets/ on the instance over mesh SSH.
#
# Security: keys are piped over stdin, never on the command line.
#
# Usage:
#   scripts/agent-secrets-sync.sh                # all configured keys
#   scripts/agent-secrets-sync.sh anthropic      # just one

set -euo pipefail
source "$(dirname "$0")/_agent-env.sh"

VAULT="${AGENT_SECRETS_VAULT:?Set AGENT_SECRETS_VAULT in agent-env.sh}"
REMOTE_DIR="${AGENT_SECRETS_REMOTE_DIR:-.config/agent-secrets}"

# Build the provider -> filename map from AGENT_SECRET_FILES
declare -A SOURCES
if [[ -n "${AGENT_SECRET_FILES+x}" ]]; then
  for entry in "${AGENT_SECRET_FILES[@]}"; do
    name="${entry%%:*}"
    file="${entry#*:}"
    SOURCES[$name]="$file"
  done
else
  # Fallback defaults
  SOURCES=(
    [anthropic]="anthropic-key.txt"
    [openai]="openai-key.txt"
    [gemini]="gemini-key.txt"
  )
fi

targets=("$@")
if [[ ${#targets[@]} -eq 0 ]]; then
  targets=("${!SOURCES[@]}")
fi

# Validate sources exist BEFORE touching the remote.
for name in "${targets[@]}"; do
  src="${SOURCES[$name]:-}"
  [[ -n "$src" ]] || agent::die "unknown secret: $name (expected one of: ${!SOURCES[*]})"
  [[ -f "$VAULT/$src" ]] || agent::die "vault file missing: $VAULT/$src"
done

# Ensure the remote directory exists with tight perms.
agent::log "preparing $REMOTE_DIR on ${AGENT_MESH_USER}@${AGENT_MESH_HOST}"
ssh "${AGENT_MESH_USER}@${AGENT_MESH_HOST}" \
    "install -d -m 700 \"\$HOME/$REMOTE_DIR\""

for name in "${targets[@]}"; do
  src="$VAULT/${SOURCES[$name]}"
  dst_file="${name}.key"
  agent::log "syncing $name -> ~/$REMOTE_DIR/$dst_file"
  ssh "${AGENT_MESH_USER}@${AGENT_MESH_HOST}" \
      "tee \"\$HOME/$REMOTE_DIR/$dst_file\" >/dev/null && chmod 600 \"\$HOME/$REMOTE_DIR/$dst_file\"" \
      < "$src"
done

agent::log "done. Verify on instance with:  ls -l ~/$REMOTE_DIR"
