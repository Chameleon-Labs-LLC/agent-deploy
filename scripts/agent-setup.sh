#!/usr/bin/env bash
# agent-setup.sh — interactive setup wizard for agent-deploy.
#
# Walks you through creating agent-env.sh with all required config.
# Detects mesh VPN, checks dependencies, and provides links for
# anything that needs manual setup.
#
# Usage:
#   scripts/agent-setup.sh              # interactive wizard
#   scripts/agent-setup.sh --check      # dependency check only

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$REPO_ROOT/agent-env.sh"

# --- Colors and formatting ---------------------------------------------------

bold()  { printf '\033[1m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
yellow(){ printf '\033[33m%s\033[0m' "$*"; }
red()   { printf '\033[31m%s\033[0m' "$*"; }
dim()   { printf '\033[2m%s\033[0m' "$*"; }

info()  { echo "$(green ">>") $*"; }
warn()  { echo "$(yellow "!!") $*"; }
err()   { echo "$(red "**") $*"; }
step()  { echo; echo "$(bold "=== $* ===")" ; }

ask() {
  local prompt="$1" default="${2:-}"
  if [[ -n "$default" ]]; then
    printf '%s [%s]: ' "$prompt" "$default"
  else
    printf '%s: ' "$prompt"
  fi
  read -r reply
  echo "${reply:-$default}"
}

confirm() {
  local prompt="$1"
  printf '%s [y/N]: ' "$prompt"
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# --- Dependency checking -----------------------------------------------------

declare -A DEP_INSTALL_HINTS=(
  [aws]="https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  [ssh]="sudo apt install openssh-client  (or your OS equivalent)"
  [jq]="sudo apt install jq"
  [curl]="sudo apt install curl"
  [rsync]="sudo apt install rsync"
  [git]="sudo apt install git"
  [ping]="sudo apt install iputils-ping"
  [session-manager-plugin]="https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
  [just]="https://github.com/casey/just#installation"
)

REQUIRED_DEPS=(aws ssh jq curl rsync git)
OPTIONAL_DEPS=(ping session-manager-plugin just)

check_deps() {
  local missing_required=()
  local missing_optional=()

  echo
  info "Checking dependencies..."
  echo

  for cmd in "${REQUIRED_DEPS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      printf '  %-30s %s\n' "$cmd" "$(green "found")"
    else
      printf '  %-30s %s\n' "$cmd" "$(red "MISSING (required)")"
      missing_required+=("$cmd")
    fi
  done

  echo

  for cmd in "${OPTIONAL_DEPS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      printf '  %-30s %s\n' "$cmd" "$(green "found")"
    else
      printf '  %-30s %s\n' "$cmd" "$(yellow "missing (optional)")"
      missing_optional+=("$cmd")
    fi
  done

  if [[ ${#missing_required[@]} -gt 0 ]]; then
    echo
    err "Missing required dependencies:"
    for cmd in "${missing_required[@]}"; do
      echo "  $(bold "$cmd"): ${DEP_INSTALL_HINTS[$cmd]}"
    done
  fi

  if [[ ${#missing_optional[@]} -gt 0 ]]; then
    echo
    warn "Missing optional dependencies:"
    for cmd in "${missing_optional[@]}"; do
      echo "  $(bold "$cmd"): ${DEP_INSTALL_HINTS[$cmd]}"
    done
  fi

  if [[ ${#missing_required[@]} -gt 0 ]]; then
    echo
    if confirm "Attempt to install missing required deps with apt?"; then
      local apt_pkgs=()
      for cmd in "${missing_required[@]}"; do
        case "$cmd" in
          aws)   echo "  $(dim "aws-cli must be installed manually:")"; echo "    ${DEP_INSTALL_HINTS[aws]}" ;;
          ssh)   apt_pkgs+=(openssh-client) ;;
          jq)    apt_pkgs+=(jq) ;;
          curl)  apt_pkgs+=(curl) ;;
          rsync) apt_pkgs+=(rsync) ;;
          git)   apt_pkgs+=(git) ;;
        esac
      done
      if [[ ${#apt_pkgs[@]} -gt 0 ]]; then
        info "Running: sudo apt install -y ${apt_pkgs[*]}"
        sudo apt install -y "${apt_pkgs[@]}"
      fi
    else
      err "Cannot continue without required dependencies. Install them and re-run."
      exit 1
    fi

    # Re-check required deps after install attempt
    local still_missing=()
    for cmd in "${missing_required[@]}"; do
      command -v "$cmd" >/dev/null 2>&1 || still_missing+=("$cmd")
    done
    if [[ ${#still_missing[@]} -gt 0 ]]; then
      err "Still missing: ${still_missing[*]}"
      err "Install these manually and re-run the setup."
      exit 1
    fi
    info "All required dependencies installed."
  else
    info "All required dependencies present."
  fi
}

# --- Mesh VPN detection -------------------------------------------------------

detect_mesh_vpn() {
  local mesh_type=""
  local has_nordvpn=0
  local has_tailscale=0

  command -v nordvpn   >/dev/null 2>&1 && has_nordvpn=1
  command -v tailscale >/dev/null 2>&1 && has_tailscale=1

  if [[ $has_nordvpn -eq 1 && $has_tailscale -eq 1 ]]; then
    info "Both NordVPN and Tailscale detected on this machine."
    echo "  1) NordVPN Meshnet"
    echo "  2) Tailscale"
    local choice
    choice=$(ask "Which mesh VPN are you using?" "1")
    case "$choice" in
      1) mesh_type="nordvpn" ;;
      2) mesh_type="tailscale" ;;
      *) mesh_type="nordvpn" ;;
    esac
  elif [[ $has_nordvpn -eq 1 ]]; then
    info "Detected: $(bold "NordVPN") installed"
    # Try to confirm meshnet is enabled
    if nordvpn meshnet peer list >/dev/null 2>&1; then
      info "NordVPN Meshnet is active with peers."
    else
      warn "NordVPN is installed but meshnet may not be enabled."
      echo "  Enable it with: nordvpn set meshnet on"
    fi
    mesh_type="nordvpn"
  elif [[ $has_tailscale -eq 1 ]]; then
    info "Detected: $(bold "Tailscale") installed"
    if tailscale status >/dev/null 2>&1; then
      info "Tailscale is connected."
    else
      warn "Tailscale is installed but may not be connected."
      echo "  Connect with: sudo tailscale up"
    fi
    mesh_type="tailscale"
  else
    warn "No mesh VPN detected on this machine."
    echo
    echo "  You need one of:"
    echo "    NordVPN Meshnet: $(bold "https://nordvpn.com/meshnet/")"
    echo "    Tailscale:       $(bold "https://tailscale.com/download")"
    echo
    echo "  1) NordVPN Meshnet"
    echo "  2) Tailscale"
    local choice
    choice=$(ask "Which will you use?" "1")
    case "$choice" in
      1) mesh_type="nordvpn" ;;
      2) mesh_type="tailscale" ;;
      *) mesh_type="nordvpn" ;;
    esac
  fi

  echo "$mesh_type"
}

list_mesh_peers() {
  local mesh_type="$1"

  if [[ "$mesh_type" == "nordvpn" ]]; then
    if command -v nordvpn >/dev/null 2>&1; then
      info "Current NordVPN Meshnet peers:"
      nordvpn meshnet peer list 2>/dev/null | head -30 || warn "Could not list peers."
    fi
  elif [[ "$mesh_type" == "tailscale" ]]; then
    if command -v tailscale >/dev/null 2>&1; then
      info "Current Tailscale peers:"
      tailscale status 2>/dev/null | head -20 || warn "Could not list peers."
    fi
  fi
}

# --- AWS detection ------------------------------------------------------------

detect_aws_region() {
  # Try to get from current AWS config
  local region=""
  if command -v aws >/dev/null 2>&1; then
    region=$(aws configure get region 2>/dev/null || true)
  fi
  echo "${region:-us-east-1}"
}

# --- Secrets vault ------------------------------------------------------------

setup_secrets_vault() {
  local default_vault="$HOME/secrets/agent-ec2"
  local vault_path

  echo
  info "API key files are stored locally in a 'secrets vault' directory."
  echo "  This directory should $(bold "NOT") be inside a git repo."
  echo "  Good locations: ~/secrets/agent-ec2, a Dropbox/OneDrive folder,"
  echo "  or any path you can share securely with teammates."
  echo

  # Check if key files exist in the current directory (common mistake)
  local found_keys=0
  for f in *.txt *.key; do
    if [[ -f "$f" ]] && grep -qiE '(api|key|token|secret)' "$f" 2>/dev/null; then
      found_keys=1
      break
    fi
  done

  if [[ $found_keys -eq 1 ]]; then
    warn "Found files that may be API keys in the current directory!"
    echo "  The current directory is a git repo — keys should not be here."
    echo "  Move them to a secure location outside any git repo."
    echo
  fi

  vault_path=$(ask "Secrets vault path" "$default_vault")

  if [[ -d "$vault_path" ]]; then
    info "Directory exists: $vault_path"
    local perms
    perms=$(stat -c '%a' "$vault_path" 2>/dev/null || stat -f '%Lp' "$vault_path" 2>/dev/null || echo "unknown")
    if [[ "$perms" != "700" && "$perms" != "unknown" ]]; then
      warn "Permissions are $perms (should be 700)."
      if confirm "  Fix permissions to 700?"; then
        chmod 700 "$vault_path"
        info "Fixed."
      fi
    fi
  else
    if confirm "Create $vault_path with mode 700?"; then
      mkdir -p "$vault_path"
      chmod 700 "$vault_path"
      info "Created: $vault_path"
    fi
  fi

  echo "$vault_path"
}

# --- API key setup ------------------------------------------------------------

setup_api_keys() {
  local vault_path="$1"
  local -n secret_files_ref=$2

  step "API Keys"
  echo
  echo "  Each AI provider needs a dedicated API key for this instance."
  echo "  Save each key as a plain text file (no trailing newline) in:"
  echo "    $(bold "$vault_path")"
  echo
  echo "  Provider consoles:"
  echo "    Anthropic: $(bold "https://console.anthropic.com/settings/keys")"
  echo "    OpenAI:    $(bold "https://platform.openai.com/api-keys")"
  echo "    Google:    $(bold "https://aistudio.google.com/apikey")"
  echo

  local providers=("anthropic" "openai" "gemini")
  local default_files=("anthropic-key.txt" "openai-key.txt" "gemini-key.txt")
  local configured=()

  for i in "${!providers[@]}"; do
    local provider="${providers[$i]}"
    local default_file="${default_files[$i]}"
    local existing=""

    # Try to find an existing key file
    if [[ -f "$vault_path/$default_file" ]]; then
      existing="$default_file"
    else
      # Check for common naming patterns
      for pattern in "${provider}"*.txt "${provider}"*.key "*${provider}*"; do
        for match in "$vault_path"/$pattern; do
          if [[ -f "$match" ]]; then
            existing=$(basename "$match")
            break 2
          fi
        done
      done
    fi

    if [[ -n "$existing" ]]; then
      info "$provider: found $(bold "$existing")"
      local filename
      filename=$(ask "  Key filename" "$existing")
      configured+=("${provider}:${filename}")
    else
      warn "$provider: no key file found in $vault_path"
      if confirm "  Configure $provider now?"; then
        local filename
        filename=$(ask "  Key filename" "$default_file")
        if [[ ! -f "$vault_path/$filename" ]]; then
          echo "  Create this file with your API key:"
          echo "    printf '%s' 'YOUR_KEY_HERE' > $vault_path/$filename"
          echo "    chmod 600 $vault_path/$filename"
        fi
        configured+=("${provider}:${filename}")
      else
        dim "  Skipping $provider. Add it to agent-env.sh later."
        echo
      fi
    fi
  done

  # Ask about additional providers
  while confirm "Add another provider (HuggingFace, ElevenLabs, etc.)?"; do
    local name
    name=$(ask "  Provider name (lowercase)")
    local filename
    filename=$(ask "  Key filename" "${name}-key.txt")
    configured+=("${name}:${filename}")
  done

  # Return via nameref
  secret_files_ref=("${configured[@]}")
}

# --- Main wizard --------------------------------------------------------------

main() {
  # --check mode: just check deps and exit
  if [[ "${1:-}" == "--check" ]]; then
    check_deps
    exit 0
  fi

  echo
  echo "$(bold "agent-deploy setup wizard")"
  echo "$(dim "Creates agent-env.sh with your instance-specific config.")"
  echo

  # Check for existing config
  if [[ -f "$ENV_FILE" ]]; then
    warn "agent-env.sh already exists at: $ENV_FILE"
    if ! confirm "Overwrite it?"; then
      info "Aborting. Edit agent-env.sh manually or delete it and re-run."
      exit 0
    fi
    echo
  fi

  # ---- Dependencies ----------------------------------------------------------
  step "Dependencies"
  check_deps

  # ---- AWS -------------------------------------------------------------------
  step "AWS Configuration"
  echo

  # Check AWS credentials
  if aws sts get-caller-identity >/dev/null 2>&1; then
    local aws_account aws_user
    aws_account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    aws_user=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)
    info "AWS authenticated: $(bold "$aws_user") (account $aws_account)"
  else
    warn "AWS CLI is not configured or credentials are expired."
    echo "  Configure with: aws configure"
    echo "  Docs: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html"
    echo
    warn "Continuing without AWS validation — you'll need valid credentials before running ops scripts."
  fi

  local default_region
  default_region=$(detect_aws_region)
  local region
  region=$(ask "AWS region" "$default_region")

  local instance_id
  instance_id=$(ask "EC2 instance ID (from the setup guide, Task 2)" "")
  if [[ -z "$instance_id" ]]; then
    warn "No instance ID provided. You can fill this in after launching the instance."
    instance_id="i-0XXXXXXXXXXXXXXXXX"
  fi

  # ---- Mesh VPN --------------------------------------------------------------
  step "Mesh VPN"

  local mesh_type
  mesh_type=$(detect_mesh_vpn)
  info "Using: $(bold "$mesh_type")"

  local mesh_iface
  if [[ "$mesh_type" == "nordvpn" ]]; then
    mesh_iface="nordlynx"
  else
    mesh_iface="tailscale0"
  fi

  echo
  list_mesh_peers "$mesh_type"
  echo

  local mesh_host
  mesh_host=$(ask "Mesh IP or hostname of the EC2 instance (from Task 3)" "100.x.x.x")

  local mesh_user
  mesh_user=$(ask "SSH username on the instance" "agent")

  # ---- SSH -------------------------------------------------------------------
  step "SSH"

  local bootstrap_key="$HOME/.ssh/agent-bootstrap.pem"
  bootstrap_key=$(ask "Bootstrap SSH key path" "$bootstrap_key")

  if [[ -f "$bootstrap_key" ]]; then
    info "Key file exists: $bootstrap_key"
    local perms
    perms=$(stat -c '%a' "$bootstrap_key" 2>/dev/null || stat -f '%Lp' "$bootstrap_key" 2>/dev/null || echo "unknown")
    if [[ "$perms" != "600" && "$perms" != "unknown" ]]; then
      warn "Permissions are $perms (should be 600)."
      if confirm "  Fix permissions to 600?"; then
        chmod 600 "$bootstrap_key"
        info "Fixed."
      fi
    fi
  else
    dim "Key file not found — create it in Task 2 of the setup guide."
    echo
  fi

  # ---- Secrets vault ---------------------------------------------------------
  step "Secrets Vault"
  local vault_path
  vault_path=$(setup_secrets_vault)

  # ---- API keys --------------------------------------------------------------
  local secret_files=()
  setup_api_keys "$vault_path" secret_files

  # ---- Config sync -----------------------------------------------------------
  step "Config Sync (optional)"
  echo
  echo "  You can sync your ~/.claude/ config across machines using a"
  echo "  private git bare repo. See Task 7 in the setup guide."
  echo

  local dotfiles_repo=""
  if confirm "Configure a dotfiles repo?"; then
    dotfiles_repo=$(ask "  Git SSH URL" "git@github.com:YOURUSER/agent-dotfiles.git")
  fi

  # ---- Cost tag --------------------------------------------------------------
  step "Cost Tracking"
  local cost_tag
  cost_tag=$(ask "AWS tag for cost filtering (Key,Value)" "Name,agent-instance")

  # ---- Agent units -----------------------------------------------------------
  step "Agent Services"
  echo
  echo "  List the systemd unit names for your agent services."
  echo "  Used by agent-health.sh to check service status."
  echo
  local agent_units
  agent_units=$(ask "Agent units (space-separated)" "claude-agent.service codex-agent.service gemini-agent.service pi-coding-agent.service")

  # ---- Write config ----------------------------------------------------------
  step "Writing agent-env.sh"

  # Build AGENT_SECRET_FILES block
  local secret_block=""
  for entry in "${secret_files[@]}"; do
    secret_block+="  \"${entry}\""$'\n'
  done

  cat > "$ENV_FILE" << ENVFILE
#!/usr/bin/env bash
# agent-env.sh — private config for your agent EC2 instance.
# Generated by agent-setup.sh on $(date '+%Y-%m-%d %H:%M')
#
# This file is .gitignored. Share it securely with teammates.

# === AWS Instance ===
AGENT_INSTANCE_ID="${instance_id}"
AGENT_REGION="${region}"

# === Mesh VPN ===
AGENT_MESH_TYPE="${mesh_type}"
AGENT_MESH_HOST="${mesh_host}"
AGENT_MESH_USER="${mesh_user}"
AGENT_MESH_IFACE="${mesh_iface}"

# === SSH ===
AGENT_BOOTSTRAP_KEY="${bootstrap_key}"

# === Secrets vault ===
AGENT_SECRETS_VAULT="${vault_path}"
AGENT_SECRETS_REMOTE_DIR=".config/agent-secrets"

AGENT_SECRET_FILES=(
${secret_block})

# === Config sync ===
AGENT_DOTFILES_REPO="${dotfiles_repo}"

# === Cost tracking ===
AGENT_COST_TAG="${cost_tag}"

# === Agent systemd units ===
AGENT_UNITS="${agent_units}"

export AGENT_INSTANCE_ID AGENT_REGION AGENT_MESH_HOST AGENT_MESH_USER
export AGENT_BOOTSTRAP_KEY AGENT_SECRETS_VAULT AGENT_DOTFILES_REPO
ENVFILE

  chmod 600 "$ENV_FILE"
  info "Written: $(bold "$ENV_FILE") (mode 600)"

  # ---- Summary ---------------------------------------------------------------
  step "Setup Complete"
  echo
  echo "  Config:  $(bold "$ENV_FILE")"
  echo "  Vault:   $(bold "$vault_path")"
  echo "  Mesh:    $(bold "$mesh_type") -> ${mesh_user}@${mesh_host}"
  echo "  Region:  $(bold "$region")"
  echo
  echo "  $(bold "Next steps:")"
  echo "    1. Follow docs/agent-ec2-setup.md to launch the EC2 instance"
  echo "    2. Update agent-env.sh with the instance ID and mesh IP"
  echo "    3. Add API key files to your secrets vault:"

  for entry in "${secret_files[@]}"; do
    local name="${entry%%:*}"
    local file="${entry#*:}"
    if [[ ! -f "$vault_path/$file" ]]; then
      echo "       - $vault_path/$file  $(dim "(missing)")"
    else
      echo "       - $vault_path/$file  $(green "(exists)")"
    fi
  done

  echo "    4. Run: $(bold "just secrets-sync") to push keys to the instance"
  echo "    5. Run: $(bold "just verify") to check everything works"
  echo
  warn "Remember: never commit agent-env.sh or key files to git."
  echo
}

main "$@"
