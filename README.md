# agent-deploy

A battle-tested runbook and ops toolkit for standing up a secure, dedicated AWS EC2 instance that runs AI coding agents 24/7.

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex CLI](https://github.com/openai/codex), [Gemini CLI](https://github.com/google-gemini/gemini-cli), [pi-coding-agent](https://github.com/nichochar/pi-coding-agent), or any other AI CLI tool on a persistent cloud box — reachable only over mesh VPN, hardened by default, with ops scripts for everything.

## Why

- **Free up your laptop.** Let agents run long tasks on a dedicated box while you keep working.
- **Persistent sessions.** Agents survive SSH disconnects, reboots, and network hiccups (use `tmux`).
- **Hardened by default.** No public SSH, UFW firewall, fail2ban, IMDSv2, SSM break-glass, daily snapshots.
- **Any agent, any provider.** The setup is agent-agnostic. Install whichever CLI tools you need.
- **Cheap to try.** ~$0.07/hr for a `t4g.large`. Spin up, test, tear down. Full rollback commands included.

## Quick Start

1. **Read the guide:** [`docs/agent-ec2-setup.md`](docs/agent-ec2-setup.md) — step-by-step, from zero to running agents.
2. **Create your private config:** Copy `agent-env.example.sh` to `agent-env.sh`, fill in your instance IDs and mesh IPs.
3. **Run the scripts:** `scripts/` has ops wrappers for start, stop, SSH, health checks, snapshots, cost tracking, and secrets sync.

## What You Get

| Layer | What's configured |
|---|---|
| **Compute** | `t4g.large` (Graviton arm64), Ubuntu 24.04, 50 GB encrypted gp3 EBS |
| **Network** | Mesh VPN only (NordVPN Meshnet or Tailscale). No public SSH. |
| **Access** | Non-root `agent` user, SSH keys only, `sudo` requires password |
| **Security** | fail2ban, unattended-upgrades, UFW (mesh interface only), IMDSv2 required |
| **Break-glass** | AWS SSM Session Manager — works even if mesh is down |
| **Backups** | Daily EBS snapshots via DLM, 7-day retention |
| **Config sync** | Git bare repo syncs your `~/.claude/` (or any dotfiles) across machines |
| **Secrets** | API keys in `~/.config/agent-secrets/`, never on the command line |

## Scripts

Every script sources `_agent-env.sh` for defaults. All values are overridable via environment variables.

| Script | Purpose |
|---|---|
| `agent-ssh.sh` | SSH over mesh. `--bootstrap` for initial setup. |
| `agent-ssm.sh` | Break-glass shell via AWS SSM Session Manager. |
| `agent-status.sh` | EC2 state, public IP, mesh reachability. `--probe` for uptime. |
| `agent-start.sh` | Idempotent start. Waits for `running`. |
| `agent-stop.sh` | Interactive stop. `--yes` to skip prompt. |
| `agent-health.sh` | Remote health: uptime, memory, disk, agent services, journal. |
| `agent-logs.sh` | Tail a journald unit over mesh. |
| `agent-snapshot.sh` | On-demand EBS snapshot with tags. |
| `agent-snapshot-list.sh` | List tagged snapshots with age. |
| `agent-secrets-sync.sh` | Push API keys from your vault to the instance (stdin, never argv). |
| `agent-cost.sh` | Month-to-date AWS spend via Cost Explorer. |
| `agent-ip.sh` | Print the current public IP (if any). |

## Cost

| Scenario | Monthly (approx.) |
|---|---|
| Running 24/7 (`t4g.large`) | ~$54 |
| Running 8h/day, stopped 16h | ~$18 |
| Stopped (EBS only) | ~$4 |

The guide includes an optional auto-stop timer to shut down at midnight automatically.

## Security Model

- **No public SSH.** Port 22 is closed on the security group. All access is over mesh VPN.
- **SSM break-glass.** If your mesh goes down, AWS Session Manager gets you in.
- **Dedicated API keys.** One key per instance per provider. Revoke one without affecting others.
- **Secrets never on the command line.** Keys are piped over stdin or read from files.
- **Private config file.** All instance-specific values live in `agent-env.sh` (gitignored). The repo itself is safe to share publicly.

## Project Structure

```
agent-deploy/
  docs/
    agent-ec2-setup.md      # The full setup guide (start here)
  scripts/
    _agent-env.sh            # Shared defaults + helpers (sourced by all scripts)
    agent-ssh.sh             # SSH over mesh or bootstrap
    agent-start.sh           # Start the instance
    agent-stop.sh            # Stop the instance
    agent-health.sh          # Remote health check
    ...                      # See Scripts table above
  agent-env.example.sh       # Template for your private config
  .gitignore
  LICENSE
  README.md
```

## Links

- **Chameleon Labs:** [chameleonlabs.ai](https://chameleonlabs.ai)
- **Discord:** [discord.gg/chameleonlabs](https://discord.gg/chameleonlabs)
- **GitHub:** [github.com/Chameleon-Labs-LLC](https://github.com/Chameleon-Labs-LLC)

## License

MIT
