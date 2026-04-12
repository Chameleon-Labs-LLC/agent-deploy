#!/usr/bin/env bash
# agent-env.example.sh — template for your private config.
#
# Copy this to agent-env.sh and fill in your values.
# agent-env.sh is .gitignored and never committed.
#
# Share agent-env.sh securely with teammates who need ops access.

# === AWS Instance ===
AGENT_INSTANCE_ID="i-0XXXXXXXXXXXXXXXXX"   # from the setup guide, Task 2
AGENT_REGION="us-east-1"                    # your preferred region

# === Mesh VPN ===
AGENT_MESH_TYPE="nordvpn"                   # "nordvpn" or "tailscale"
AGENT_MESH_HOST="100.x.x.x"               # mesh IP from Task 3
AGENT_MESH_USER="agent"                     # non-root user from Task 4
AGENT_MESH_IFACE="nordlynx"                # "nordlynx" for NordVPN, "tailscale0" for Tailscale

# === SSH ===
AGENT_BOOTSTRAP_KEY="$HOME/.ssh/agent-bootstrap.pem"  # temporary, deleted after Task 8

# === Secrets vault (local path to your API key files) ===
AGENT_SECRETS_VAULT="$HOME/secrets/agent-ec2"
AGENT_SECRETS_REMOTE_DIR=".config/agent-secrets"

# Map of provider name -> local filename in the vault.
# Used by agent-secrets-sync.sh. Add/remove providers as needed.
# Format: "name:filename"
AGENT_SECRET_FILES=(
  "anthropic:anthropic-key.txt"
  "openai:openai-key.txt"
  "gemini:gemini-key.txt"
  # "huggingface:hf-key.txt"
)

# === Config sync (optional) ===
AGENT_DOTFILES_REPO="git@github.com:YOURUSER/agent-dotfiles.git"

# === Cost tracking tag ===
AGENT_COST_TAG="Name,agent-instance"

# === Agent systemd units (for health checks) ===
AGENT_UNITS="claude-agent.service codex-agent.service gemini-agent.service pi-coding-agent.service"

export AGENT_INSTANCE_ID AGENT_REGION AGENT_MESH_HOST AGENT_MESH_USER
export AGENT_BOOTSTRAP_KEY AGENT_SECRETS_VAULT AGENT_DOTFILES_REPO
