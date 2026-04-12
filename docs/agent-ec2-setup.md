# Dedicated AI Agent EC2 Instance — Setup Guide

> **Last updated:** 2026-04-12
>
> A step-by-step runbook for standing up a secure, dedicated AWS EC2 instance
> that runs AI coding agents (Claude Code, Codex CLI, Gemini CLI, pi-coding-agent,
> or any others) 24/7, reachable only over a mesh VPN, with config synced via
> git and secrets managed outside the repo.
>
> This guide is **agent-agnostic** — it works for any combination of AI CLI
> tools. It is also **public-safe** — all instance-specific values (IDs, IPs,
> keys) are read from a single config file that you keep private.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Config File Setup](#task-0-config-file-setup)
3. [Generate API Keys](#task-1-generate-api-keys)
4. [Launch the EC2 Instance](#task-2-launch-the-ec2-instance)
5. [Install Mesh VPN](#task-3-install-mesh-vpn)
6. [Create the Agent User and Harden SSH](#task-4-create-the-agent-user-and-harden-ssh)
7. [Install Toolchains](#task-5-install-toolchains)
8. [Install API Keys and Authenticate](#task-6-install-api-keys-and-authenticate)
9. [Sync Config via Git Bare Repo](#task-7-sync-config-via-git-bare-repo)
10. [Lock Down Public SSH](#task-8-lock-down-public-ssh)
11. [Backups, Auto-Stop, and Observability](#task-9-backups-auto-stop-and-observability)
12. [Smoke Test](#task-10-smoke-test)
13. [Security Checklist](#security-checklist)
14. [Ops Scripts Reference](#ops-scripts-reference)
15. [Cost Estimate](#cost-estimate)
16. [Rollback / Teardown](#rollback--teardown)

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│  Your Workstation (WSL / macOS / Linux)               │
│  ┌────────────────────────────────────────────────┐   │
│  │ Mesh VPN client (NordVPN Meshnet or Tailscale) │   │
│  └──────────┬─────────────────────────────────────┘   │
│             │ SSH over mesh (100.x.x.x)               │
└─────────────┼────────────────────────────────────────┘
              │
              ▼
┌──────────────────────────────────────────────────────┐
│  EC2 Instance (t4g.large, Ubuntu 24.04 arm64)         │
│                                                       │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌───────────┐  │
│  │ Claude   │ │ Codex   │ │ Gemini  │ │ pi-coding │  │
│  │ Code     │ │ CLI     │ │ CLI     │ │ agent     │  │
│  └─────────┘ └─────────┘ └─────────┘ └───────────┘  │
│                                                       │
│  SSH keys only • no public port 22                    │
│  SSM Session Manager (break-glass)                    │
│  UFW: deny all except mesh interface                  │
│  fail2ban + unattended-upgrades                       │
│  Daily EBS snapshots (7-day retention)                │
└──────────────────────────────────────────────────────┘
```

---

## Prerequisites

- **AWS CLI v2** configured with an IAM user that can create EC2 instances, security groups, IAM roles, and DLM policies
- **A mesh VPN**: either [NordVPN Meshnet](https://nordvpn.com/meshnet/) or [Tailscale](https://tailscale.com/) already working on your workstation
- **SSH client** on your workstation
- **API keys** for the AI providers you plan to use (Anthropic, OpenAI, Google, etc.)
- **A GitHub account** (for config sync via bare repo)
- A local directory to store secrets (e.g., `~/secrets/agent-ec2/` or a synced vault like Dropbox) — never committed to git

---

## Task 0: Config File Setup

Create a **private** config file that holds all instance-specific values.
This file is `.gitignore`'d and never committed. Share it securely with
teammates who need access.

Create `agent-env.sh` (or whatever you name it):

```bash
#!/usr/bin/env bash
# agent-env.sh — private config for your agent EC2 instance.
# This file is .gitignored. Share it securely with teammates.
# Every ops script sources this file for instance-specific values.

# === AWS Instance ===
AGENT_INSTANCE_ID="i-0XXXXXXXXXXXXXXXXX"   # from Task 2
AGENT_REGION="us-east-1"                    # your preferred region

# === Mesh VPN ===
AGENT_MESH_HOST="100.x.x.x"               # mesh IP from Task 3
AGENT_MESH_USER="agent"                     # non-root user from Task 4

# === SSH ===
AGENT_BOOTSTRAP_KEY="$HOME/.ssh/agent-bootstrap.pem"  # from Task 2, deleted after Task 8

# === Secrets vault (local path to API key files) ===
AGENT_SECRETS_VAULT="$HOME/secrets/agent-ec2"

# === Secret file mapping (provider -> local filename) ===
# These files contain raw API keys, one per file, no trailing newline.
AGENT_SECRET_FILES=(
  "anthropic:anthropic-key.txt"
  "openai:openai-key.txt"
  "gemini:gemini-key.txt"
  # Add more providers as needed:
  # "huggingface:hf-key.txt"
)

# === Config sync ===
AGENT_DOTFILES_REPO="git@github.com:YOURUSER/agent-dotfiles.git"

# === Optional: Cost tracking tag ===
AGENT_COST_TAG="Name,agent-instance"

export AGENT_INSTANCE_ID AGENT_REGION AGENT_MESH_HOST AGENT_MESH_USER
export AGENT_BOOTSTRAP_KEY AGENT_SECRETS_VAULT AGENT_DOTFILES_REPO
```

Add to `.gitignore`:
```
agent-env.sh
*.pem
```

---

## Task 1: Generate API Keys

Create **dedicated API keys** for this instance — one per provider. Using
dedicated keys means you can revoke a single instance without affecting other
machines.

- [ ] **Step 1.1:** Go to each provider's console and create a new API key:
  | Provider | Console URL | Env var name |
  |---|---|---|
  | Anthropic | https://console.anthropic.com/settings/keys | `ANTHROPIC_API_KEY` |
  | OpenAI | https://platform.openai.com/api-keys | `OPENAI_API_KEY` |
  | Google | https://aistudio.google.com/apikey | `GEMINI_API_KEY` / `GOOGLE_API_KEY` |

- [ ] **Step 1.2:** Save each key to a separate file in your secrets vault:
  ```bash
  mkdir -p ~/secrets/agent-ec2 && chmod 700 ~/secrets/agent-ec2
  # Paste each key into its file (no trailing newline):
  printf '%s' 'sk-ant-XXXX' > ~/secrets/agent-ec2/anthropic-key.txt
  printf '%s' 'sk-XXXX'     > ~/secrets/agent-ec2/openai-key.txt
  printf '%s' 'AIzaXXXX'    > ~/secrets/agent-ec2/gemini-key.txt
  chmod 600 ~/secrets/agent-ec2/*
  ```

> **Security rule:** Never put API keys on a command line. Always use files,
> stdin pipes, or env vars loaded from files. Command lines are logged in
> shell history, process tables, and audit logs.

---

## Task 2: Launch the EC2 Instance

- [ ] **Step 2.1: Find the latest Ubuntu 24.04 arm64 AMI**
  ```bash
  aws ec2 describe-images --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*" \
    --query 'sort_by(Images,&CreationDate)[-1].[ImageId,Name]' \
    --output text --region $AGENT_REGION
  ```
  Record the AMI ID in `agent-env.sh`.

- [ ] **Step 2.2: Create a bootstrap SSH keypair** (temporary — deleted after Task 8)
  ```bash
  aws ec2 create-key-pair --key-name agent-bootstrap \
    --key-type ed25519 --query 'KeyMaterial' --output text \
    --region $AGENT_REGION > ~/.ssh/agent-bootstrap.pem
  chmod 600 ~/.ssh/agent-bootstrap.pem
  ```

- [ ] **Step 2.3: Create a security group**
  ```bash
  MY_IP=$(curl -s https://checkip.amazonaws.com)
  SG_ID=$(aws ec2 create-security-group \
    --group-name agent-sg \
    --description "Agent EC2 — SSH from my IP only, egress all" \
    --region $AGENT_REGION \
    --query 'GroupId' --output text)
  echo "Security group: $SG_ID"

  # Allow SSH from your current IP (temporary — removed in Task 8)
  aws ec2 authorize-security-group-ingress --group-id $SG_ID \
    --protocol tcp --port 22 --cidr ${MY_IP}/32 --region $AGENT_REGION
  ```

  **If using NordVPN Meshnet**, also open UDP 51820 for WireGuard:
  ```bash
  aws ec2 authorize-security-group-ingress --group-id $SG_ID \
    --protocol udp --port 51820 --cidr 0.0.0.0/0 --region $AGENT_REGION
  ```
  (Tailscale needs no inbound rules — it uses DERP relays.)

- [ ] **Step 2.4: Create IAM instance profile with SSM access**
  ```bash
  aws iam create-role --role-name agent-ec2-role \
    --assume-role-policy-document '{
      "Version":"2012-10-17",
      "Statement":[{
        "Effect":"Allow",
        "Principal":{"Service":"ec2.amazonaws.com"},
        "Action":"sts:AssumeRole"
      }]
    }'
  aws iam attach-role-policy --role-name agent-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
  aws iam create-instance-profile --instance-profile-name agent-ec2-profile
  aws iam add-role-to-instance-profile \
    --instance-profile-name agent-ec2-profile --role-name agent-ec2-role
  ```

  > Wait ~10 seconds for IAM propagation before launching the instance.

- [ ] **Step 2.5: Launch the instance**
  ```bash
  aws ec2 run-instances \
    --image-id <AMI_ID_FROM_2.1> \
    --instance-type t4g.large \
    --key-name agent-bootstrap \
    --security-group-ids $SG_ID \
    --iam-instance-profile Name=agent-ec2-profile \
    --metadata-options 'HttpTokens=required,HttpPutResponseHopLimit=1,HttpEndpoint=enabled' \
    --block-device-mappings '[{
      "DeviceName":"/dev/sda1",
      "Ebs":{
        "VolumeSize":50,
        "VolumeType":"gp3",
        "Encrypted":true,
        "DeleteOnTermination":true
      }
    }]' \
    --tag-specifications 'ResourceType=instance,Tags=[
      {Key=Name,Value=agent-instance},
      {Key=Project,Value=ai-agent},
      {Key=AutoSnapshot,Value=daily}
    ]' \
    --region $AGENT_REGION
  ```

  Record the instance ID and public IP in `agent-env.sh`.

  > **Why `t4g.large`?** 2 vCPU, 8 GB RAM, ARM (Graviton) — enough for
  > multiple CLI agents running concurrently. Costs ~$0.07/hr. Use `t4g.medium`
  > (4 GB) for lighter workloads, or `t4g.xlarge` (16 GB) for heavier ones.

- [ ] **Step 2.6: Wait for it and SSH in**
  ```bash
  aws ec2 wait instance-running --instance-ids $AGENT_INSTANCE_ID --region $AGENT_REGION
  ssh -i ~/.ssh/agent-bootstrap.pem ubuntu@<PUBLIC_IP>
  ```

- [ ] **Step 2.7: Verify SSM break-glass before hardening**
  ```bash
  # From your workstation (NOT from inside the instance):
  aws ssm start-session --target $AGENT_INSTANCE_ID --region $AGENT_REGION
  ```
  You should get a shell. Type `exit`. If this fails, fix the IAM role before
  continuing — SSM is your safety net if mesh breaks.

  > If `session-manager-plugin` is not installed, get it from
  > https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html

---

## Task 3: Install Mesh VPN

Choose **one** path: Tailscale (simpler) or NordVPN Meshnet (if you already use NordVPN).

### Option A: Tailscale

- [ ] **Step 3-T.1:** Install on the instance
  ```bash
  curl -fsSL https://tailscale.com/install.sh | sh
  sudo systemctl enable --now tailscaled
  ```
- [ ] **Step 3-T.2:** Generate a Tailscale auth key at https://login.tailscale.com/admin/settings/keys
- [ ] **Step 3-T.3:** Bring it up with SSH enabled
  ```bash
  sudo tailscale up --ssh --hostname=agent-instance --auth-key=tskey-auth-XXXX
  tailscale ip -4   # record this mesh IP
  ```
- [ ] **Step 3-T.4:** From your workstation: `tailscale ping agent-instance`

### Option B: NordVPN Meshnet

- [ ] **Step 3-N.1:** Install NordVPN
  ```bash
  wget -qO - https://repo.nordvpn.com/gpg/nordvpn_public.asc \
    | sudo tee /etc/apt/trusted.gpg.d/nordvpn_public.asc > /dev/null
  echo "deb https://repo.nordvpn.com/deb/nordvpn/debian stable main" \
    | sudo tee /etc/apt/sources.list.d/nordvpn.list
  sudo apt update && sudo apt install -y nordvpn
  sudo systemctl enable --now nordvpnd
  sudo usermod -aG nordvpn ubuntu && newgrp nordvpn
  ```
- [ ] **Step 3-N.2:** Log in with your access token (from your secrets vault, not the command line):
  ```bash
  # Read the token from a file — never paste it on a command line
  nordvpn login --token "$(cat /path/to/nordvpn-token.txt)"
  ```
- [ ] **Step 3-N.3:** Enable meshnet and set a nickname
  ```bash
  nordvpn set meshnet on
  nordvpn set firewall off   # let UFW handle firewalling instead
  nordvpn meshnet peer nickname set agent-instance
  nordvpn meshnet peer list
  ```
  Record the mesh IP (100.x.x.x) in `agent-env.sh`.

- [ ] **Step 3-N.4:** From your workstation, verify connectivity:
  ```bash
  ping -c3 <MESH_IP>
  ```

> **Note on `.nord` hostnames:** NordVPN's `.nord` hostnames only resolve from
> machines running NordVPN. If your workstation doesn't have NordVPN installed
> (e.g., WSL), use the mesh IP directly.

---

## Task 4: Create the Agent User and Harden SSH

- [ ] **Step 4.1: Create the non-root user**
  ```bash
  sudo adduser --gecos "" --disabled-password agent
  sudo usermod -aG sudo agent
  # If using NordVPN:
  sudo usermod -aG nordvpn agent

  sudo mkdir -p /home/agent/.ssh && sudo chmod 700 /home/agent/.ssh
  sudo cp ~/.ssh/authorized_keys /home/agent/.ssh/authorized_keys
  sudo chown -R agent:agent /home/agent/.ssh
  sudo chmod 600 /home/agent/.ssh/authorized_keys
  ```

- [ ] **Step 4.2: Require password for sudo**
  ```bash
  echo "agent ALL=(ALL:ALL) ALL" | sudo tee /etc/sudoers.d/agent
  sudo passwd agent   # set a strong password; store it in your secrets vault
  ```

- [ ] **Step 4.3: Harden sshd**
  ```bash
  sudo tee /etc/ssh/sshd_config.d/hardening.conf > /dev/null << 'EOF'
  PermitRootLogin no
  PasswordAuthentication no
  PubkeyAuthentication yes
  KbdInteractiveAuthentication no
  X11Forwarding no
  AllowUsers agent ubuntu
  EOF
  sudo systemctl restart ssh
  ```
  > Leave `ubuntu` in `AllowUsers` until Task 8 is done. Remove it then.

- [ ] **Step 4.4: Install fail2ban and unattended-upgrades**
  ```bash
  sudo apt install -y fail2ban unattended-upgrades
  sudo systemctl enable --now fail2ban
  sudo dpkg-reconfigure -plow unattended-upgrades
  ```

---

## Task 5: Install Toolchains

All commands below run as the `agent` user (`sudo -iu agent` or SSH in as `agent`).

- [ ] **Step 5.1: Build prerequisites**
  ```bash
  sudo apt install -y build-essential git curl wget jq ripgrep fd-find unzip tmux htop
  ```

- [ ] **Step 5.2: nvm + Node LTS**
  ```bash
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  source ~/.nvm/nvm.sh
  nvm install --lts
  nvm alias default 'lts/*'
  node --version
  ```

- [ ] **Step 5.3: uv (Python tooling)**
  ```bash
  curl -LsSf https://astral.sh/uv/install.sh | sh
  ```

- [ ] **Step 5.4: Install AI CLIs**

  Install whichever agents you plan to use:
  ```bash
  # Claude Code (Anthropic)
  npm install -g @anthropic-ai/claude-code

  # Codex CLI (OpenAI)
  npm install -g @openai/codex

  # Gemini CLI (Google)
  npm install -g @google/gemini-cli

  # pi-coding-agent (multi-provider)
  npm install -g @mariozechner/pi-coding-agent
  ```

  > **Tip:** Verify package names with `npm search <name>` before installing.
  > Package names can change between releases.

- [ ] **Step 5.5: Verify installations**
  ```bash
  claude --version
  codex --version
  gemini --version
  pi --version
  ```

---

## Task 6: Install API Keys and Authenticate

### 6.1: Copy keys from your workstation to the instance

> **Critical:** Transfer keys over the mesh VPN, not the public IP. This
> proves mesh works and avoids keys traversing the public internet.

```bash
# On your workstation — stage keys, strip Windows line endings, then transfer:
mkdir -p /tmp/agent-keys && chmod 700 /tmp/agent-keys

# Copy from your secrets vault (adjust paths as needed):
for keyfile in "$AGENT_SECRETS_VAULT"/*; do
  name=$(basename "$keyfile")
  tr -d '\r\n' < "$keyfile" > "/tmp/agent-keys/$name"
done
chmod 600 /tmp/agent-keys/*

# Transfer over mesh:
rsync -av /tmp/agent-keys/ agent@$AGENT_MESH_HOST:/home/agent/.config/agent-secrets/

# Clean up local temp copies:
shred -u /tmp/agent-keys/* 2>/dev/null; rm -rf /tmp/agent-keys
```

### 6.2: Set permissions and export env vars on the instance

```bash
# On the instance as `agent`:
chmod 700 ~/.config/agent-secrets && chmod 600 ~/.config/agent-secrets/*

cat >> ~/.bashrc << 'EOF'

# --- AI agent API keys ---
export ANTHROPIC_API_KEY="$(cat ~/.config/agent-secrets/anthropic-key.txt)"
export OPENAI_API_KEY="$(cat ~/.config/agent-secrets/openai-key.txt)"
export GEMINI_API_KEY="$(cat ~/.config/agent-secrets/gemini-key.txt)"
export GOOGLE_API_KEY="$GEMINI_API_KEY"   # some tools use this name
EOF
source ~/.bashrc
```

### 6.3: Verify each tool can reach its provider

```bash
echo "hi, reply with the word 'pong'" | claude -p
echo "hi" | codex --print
echo "hi" | gemini --print
echo "hi" | pi --print
```

If a tool only supports interactive mode, launch it and send a one-word query.

### 6.4 (Optional): Claude Code OAuth / Max subscription

If you want Claude Code to use your Max OAuth instead of API-key billing:
```bash
# From your workstation:
rsync -av ~/.claude/.credentials.json agent@$AGENT_MESH_HOST:/home/agent/.claude/.credentials.json
```
This file contains a refresh token — treat it like a password.
Both OAuth and `ANTHROPIC_API_KEY` can coexist; the CLI prefers OAuth if present.

---

## Task 7: Sync Config via Git Bare Repo

This gives you one-way-authoritative config sync from your workstation to the
instance, with a path to pull changes back.

### 7.1: Create a private GitHub repo

Create a **private** repo (e.g., `your-user/agent-dotfiles`) on GitHub.

### 7.2: Initialize bare repo on your workstation

```bash
git init --bare ~/.agent-dotfiles.git
alias adot='git --git-dir=$HOME/.agent-dotfiles.git --work-tree=$HOME/.claude'
echo "alias adot='git --git-dir=\$HOME/.agent-dotfiles.git --work-tree=\$HOME/.claude'" >> ~/.bashrc
adot config status.showUntrackedFiles no
```

### 7.3: Create `.gitignore` for the config directory

```bash
cat > ~/.claude/.gitignore << 'EOF'
# Secrets — never commit
.credentials.json
*.token
credentials/

# Per-machine state — never commit
projects/
todos/
shell-snapshots/
statsig/
ide/
*.log
.DS_Store

# Memory: default is DON'T sync (re-generate per machine).
# Comment the line below to share memory across machines.
memory/
EOF
```

### 7.4: Commit and push

```bash
adot add .gitignore
adot add CLAUDE.md settings.json agents/ plugins/ skills/ instructions/ commands/ 2>/dev/null || true
adot commit -m "init: agent dotfiles"
adot remote add origin $AGENT_DOTFILES_REPO
adot push -u origin main
```

### 7.5: Clone on the instance

```bash
# On the instance as `agent`:
# First, generate an SSH key and add it to GitHub:
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "agent@instance"
# Add the public key to GitHub: gh ssh-key add ~/.ssh/id_ed25519.pub --title "agent-instance"

cd ~ && git clone --bare $AGENT_DOTFILES_REPO ~/.agent-dotfiles.git
alias adot='git --git-dir=$HOME/.agent-dotfiles.git --work-tree=$HOME/.claude'
echo "alias adot='git --git-dir=\$HOME/.agent-dotfiles.git --work-tree=\$HOME/.claude'" >> ~/.bashrc
mkdir -p ~/.claude
adot checkout
adot config status.showUntrackedFiles no
```

### 7.6: Copy `.gitconfig`

```bash
# From your workstation:
rsync -av ~/.gitconfig agent@$AGENT_MESH_HOST:~/
```

### 7.7: Two-way sync workflow

```
Push changes from INSTANCE to workstation:
  # On instance:
  adot add <file>; adot commit -m "..."; adot push
  # On workstation:
  adot pull --rebase

Push changes from WORKSTATION to instance:
  # On workstation:
  adot add <file>; adot commit -m "..."; adot push
  # On instance:
  adot pull --rebase
```

---

## Task 8: Lock Down Public SSH

> **Do not start this task until mesh SSH is verified from all machines
> you need to connect from.**

- [ ] **Step 8.1:** Verify mesh SSH works from every client machine
- [ ] **Step 8.2:** Verify SSM break-glass still works:
  ```bash
  aws ssm describe-instance-information \
    --filters Key=InstanceIds,Values=$AGENT_INSTANCE_ID \
    --query 'InstanceInformationList[0].PingStatus' \
    --output text --region $AGENT_REGION
  # Should print: Online
  ```
- [ ] **Step 8.3:** Revoke the public SSH rule from the security group:
  ```bash
  aws ec2 revoke-security-group-ingress --group-id $SG_ID \
    --protocol tcp --port 22 --cidr <YOUR_IP>/32 --region $AGENT_REGION
  ```
- [ ] **Step 8.4:** Remove `ubuntu` from AllowUsers and delete the bootstrap key:
  ```bash
  # On the instance:
  sudo sed -i 's/AllowUsers agent ubuntu/AllowUsers agent/' /etc/ssh/sshd_config.d/hardening.conf
  sudo systemctl restart ssh

  # From your workstation:
  aws ec2 delete-key-pair --key-name agent-bootstrap --region $AGENT_REGION
  rm ~/.ssh/agent-bootstrap.pem
  ```
- [ ] **Step 8.5:** Enable UFW
  ```bash
  # On the instance. Use the correct interface for your mesh VPN:
  #   Tailscale:       tailscale0
  #   NordVPN Meshnet: nordlynx
  MESH_IFACE="nordlynx"  # or "tailscale0"

  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow in on $MESH_IFACE
  sudo ufw allow in on lo
  sudo ufw enable
  sudo ufw status verbose
  ```
- [ ] **Step 8.6:** Verify mesh SSH still works after UFW is enabled

---

## Task 9: Backups, Auto-Stop, and Observability

### 9.1: Daily EBS snapshots (DLM)

```bash
# Create the service-linked role (idempotent):
aws iam create-service-linked-role --aws-service-name dlm.amazonaws.com 2>/dev/null || true

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws dlm create-lifecycle-policy \
  --description "agent-daily-snapshot" --state ENABLED \
  --execution-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/aws-service-role/dlm.amazonaws.com/AWSServiceRoleForAmazonDataLifecycleManager" \
  --policy-details '{
    "PolicyType":"EBS_SNAPSHOT_MANAGEMENT",
    "ResourceTypes":["INSTANCE"],
    "TargetTags":[{"Key":"AutoSnapshot","Value":"daily"}],
    "Schedules":[{
      "Name":"daily",
      "CreateRule":{"Interval":24,"IntervalUnit":"HOURS","Times":["06:00"]},
      "RetainRule":{"Count":7},
      "CopyTags":true
    }]
  }'
```

### 9.2 (Optional): Auto-stop at midnight

Stops the instance at midnight to save ~65% on compute. Skip if you want 24/7.

```bash
sudo tee /etc/systemd/system/auto-stop.service > /dev/null << 'EOF'
[Unit]
Description=Auto shutdown for cost savings
[Service]
Type=oneshot
ExecStart=/usr/sbin/shutdown -h now
EOF

sudo tee /etc/systemd/system/auto-stop.timer > /dev/null << 'EOF'
[Unit]
Description=Stop instance at midnight
[Timer]
OnCalendar=*-*-* 00:00:00
Persistent=false
[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now auto-stop.timer
```

### 9.3: Health check cron

```bash
mkdir -p ~/bin && cat > ~/bin/agent-health.sh << 'SCRIPT'
#!/bin/bash
set -e
for cmd in claude codex gemini pi; do
  command -v "$cmd" >/dev/null || echo "ALERT: $cmd missing"
done
df -h / | awk 'NR==2 {if ($5+0 > 85) print "ALERT: disk "$5}'
SCRIPT
chmod +x ~/bin/agent-health.sh

(crontab -l 2>/dev/null; echo "0 * * * * ~/bin/agent-health.sh 2>&1 | logger -t agent-health") | crontab -
```

---

## Task 10: Smoke Test

- [ ] **Step 10.1:** From your workstation, SSH over mesh and run a real Claude Code session on a small repo. Verify it can read/write files and call the API.
- [ ] **Step 10.2:** Test each installed agent with a trivial task.
- [ ] **Step 10.3:** Test SSH from every client machine (laptop, desktop, etc.).
- [ ] **Step 10.4:** Test config sync round-trip:
  ```bash
  # On instance:
  echo "# test" >> ~/.claude/CLAUDE.md
  adot commit -am "test: from instance" && adot push
  # On workstation:
  adot pull --rebase
  # Verify the edit appears, then revert if desired
  ```

---

## Security Checklist

Run through this before declaring the setup complete:

- [ ] API keys are in `~/.config/agent-secrets/*` with `chmod 600`
- [ ] API keys are NOT in any git repo (`adot status`, `git log -p`)
- [ ] `~/.claude/.credentials.json` is in `.gitignore`
- [ ] Public port 22 is closed on the security group
- [ ] `PasswordAuthentication no` in sshd config
- [ ] IMDSv2 is required (`HttpTokens=required`)
- [ ] IAM instance role has ONLY `AmazonSSMManagedInstanceCore`
- [ ] fail2ban and unattended-upgrades are active
- [ ] UFW allows inbound only on the mesh interface + loopback
- [ ] SSM Session Manager tested and works as break-glass
- [ ] Daily DLM snapshot policy exists and targets the instance
- [ ] The `ubuntu` user is removed from AllowUsers
- [ ] Bootstrap key is deleted from AWS
- [ ] `sudo` requires a password (no NOPASSWD lines)
- [ ] Agent user's password is in your secrets vault

---

## Ops Scripts Reference

A set of thin bash scripts wraps common operations. Each script sources a
shared `_agent-env.sh` that reads from your private `agent-env.sh` config
file. All defaults are overridable via environment variables, so the same
scripts can target multiple instances.

| Script | Purpose |
|---|---|
| `agent-ssh.sh` | SSH over mesh. `--bootstrap` for initial setup. |
| `agent-ssm.sh` | Break-glass shell via AWS SSM Session Manager. |
| `agent-ip.sh` | Print the current public IP (if any). |
| `agent-status.sh` | EC2 state, public IP, mesh reachability. `--probe` for uptime. |
| `agent-start.sh` | Idempotent start. Waits for `running`. |
| `agent-stop.sh` | Interactive stop. `--yes` to skip prompt. |
| `agent-health.sh` | Remote health: uptime, memory, disk, agent services, journal. |
| `agent-logs.sh` | Tail a journald unit over mesh. |
| `agent-snapshot.sh` | On-demand EBS snapshot with tags. |
| `agent-snapshot-list.sh` | List tagged snapshots with age. |
| `agent-secrets-sync.sh` | Push API keys from vault to instance over stdin (never argv). |
| `agent-cost.sh` | Month-to-date AWS spend via Cost Explorer. |

### Script conventions

- **Stdout vs stderr:** Logs go to stderr, machine-readable output (IPs, snapshot IDs) goes to stdout — safe for piping.
- **No credentials on the command line** — keys are piped over stdin.
- **Read-only by default.** Only start, stop, snapshot, and secrets-sync mutate state.
- **Refuse on unexpected state** — scripts won't blindly retry if the instance is in `shutting-down` or `terminated`.

### Common recipes

```bash
# Start and verify
./agent-start.sh && ./agent-status.sh --probe && ./agent-health.sh

# Snapshot before risky work
snap=$(./agent-snapshot.sh "pre-risky-change")
echo "rollback: $snap"

# Rotate a single API key
./agent-secrets-sync.sh anthropic

# Mesh is down, need a shell NOW
./agent-ssm.sh
```

---

## Cost Estimate

| Scenario | Monthly cost (approx.) |
|---|---|
| Running 24/7 (`t4g.large`) | ~$54 |
| Running 8h/day, stopped 16h | ~$18 |
| Stopped (EBS only) | ~$4 |
| DLM snapshots (7-day, 50 GB) | ~$3-5 |
| Cost Explorer API (occasional) | <$0.10 |

The auto-stop timer (Task 9.2) is the simplest way to cut costs. Start the
instance when you need it with `./agent-start.sh`.

---

## Rollback / Teardown

If you need to tear everything down:

```bash
# Terminate the instance
aws ec2 terminate-instances --instance-ids $AGENT_INSTANCE_ID --region $AGENT_REGION

# Clean up AWS resources
aws ec2 delete-security-group --group-name agent-sg --region $AGENT_REGION
aws iam remove-role-from-instance-profile \
  --instance-profile-name agent-ec2-profile --role-name agent-ec2-role
aws iam delete-instance-profile --instance-profile-name agent-ec2-profile
aws iam detach-role-policy --role-name agent-ec2-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam delete-role --role-name agent-ec2-role

# Delete DLM policy
aws dlm delete-lifecycle-policy --policy-id <from describe-lifecycle-policies>

# Revoke API keys in each provider console
# Remove the instance from Tailscale/NordVPN admin
```

---

## Tips and Lessons Learned

1. **Test SSM before locking down SSH.** If your mesh VPN breaks and you've
   already closed port 22, SSM is your only way in. Verify it works _before_
   Task 8.

2. **Use dedicated API keys per instance.** If a key is compromised or an
   instance is decommissioned, you revoke one key without affecting other
   machines.

3. **Strip Windows line endings from key files.** If your secrets vault is on
   a Windows filesystem (NTFS, Dropbox, OneDrive), key files may have `\r\n`
   endings. The `tr -d '\r\n'` step in Task 6 prevents subtle auth failures.

4. **NordVPN's `.nord` hostnames don't resolve everywhere.** They only work
   from machines running NordVPN. Use the mesh IP directly from machines
   without NordVPN (e.g., WSL).

5. **Turn off NordVPN's firewall, use UFW instead.** NordVPN's built-in
   firewall can conflict with UFW and block SSM. Let UFW be the single
   firewall and keep NordVPN in mesh-only mode.

6. **The `cdot`/`adot` alias pattern works well for dotfile management.**
   A bare repo with `--work-tree` pointed at your config directory avoids
   nesting a `.git` inside `~/.claude/`, which some tools don't expect.

7. **OAuth credentials (`.credentials.json`) are portable but fragile.**
   They work today but could break if a future CLI update pins tokens to
   machine identity. The `ANTHROPIC_API_KEY` env var is the stable fallback.

8. **Keep your config file (`agent-env.sh`) out of git.** Share it with
   teammates via your secrets vault, not via the repo. The repo contains
   the scripts and this plan — both safe to share publicly.
