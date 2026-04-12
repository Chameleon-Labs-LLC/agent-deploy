# agent-deploy — ops shortcuts
# Usage: just <recipe>       e.g. just ssh, just status, just start

set dotenv-load := false
scripts := "scripts"

# Show available recipes
default:
    @just --list

# Run the interactive setup wizard
setup:
    {{scripts}}/agent-setup.sh

# SSH into the instance over meshnet
ssh *args:
    {{scripts}}/agent-ssh.sh {{args}}

# Show instance state, IP, and mesh reachability
status:
    {{scripts}}/agent-status.sh

# Show status with remote uptime probe
probe:
    {{scripts}}/agent-status.sh --probe

# Start the instance
start:
    {{scripts}}/agent-start.sh

# Stop the instance (interactive confirm)
stop:
    {{scripts}}/agent-stop.sh

# Stop without confirmation prompt
stop-yes:
    {{scripts}}/agent-stop.sh -y

# Run remote health check (uptime, memory, disk, agents)
health:
    {{scripts}}/agent-health.sh

# Tail a journald unit on the instance (default: claude-agent)
logs *args:
    {{scripts}}/agent-logs.sh {{args}}

# SSM break-glass session (if mesh is down)
ssm:
    {{scripts}}/agent-ssm.sh

# Print current public IP (if any)
ip:
    {{scripts}}/agent-ip.sh

# Create an on-demand EBS snapshot
snapshot *args:
    {{scripts}}/agent-snapshot.sh {{args}}

# List recent EBS snapshots
snapshots:
    {{scripts}}/agent-snapshot-list.sh

# Sync API keys to instance over meshnet
secrets-sync *args:
    {{scripts}}/agent-secrets-sync.sh {{args}}

# Show month-to-date AWS spend
cost *args:
    {{scripts}}/agent-cost.sh {{args}}

# Start and verify everything
verify:
    {{scripts}}/agent-start.sh && {{scripts}}/agent-status.sh --probe && {{scripts}}/agent-health.sh

# Run a command on the instance over SSH
run *cmd:
    #!/usr/bin/env bash
    set -euo pipefail
    source {{scripts}}/_agent-env.sh
    ssh "${AGENT_MESH_USER}@${AGENT_MESH_HOST}" {{cmd}}
