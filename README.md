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

```bash
git clone https://github.com/Chameleon-Labs-LLC/agent-deploy.git
cd agent-deploy

# Interactive setup — checks deps, detects your mesh VPN, creates agent-env.sh
just setup          # or: scripts/agent-setup.sh

# Follow the guide to launch your EC2 instance
# Then use the ops shortcuts:
just start          # start the instance
just ssh            # SSH over mesh
just health         # remote health check
just status         # instance state + mesh reachability
```

Or do it manually:

1. **Read the guide:** [`docs/agent-ec2-setup.md`](docs/agent-ec2-setup.md) — step-by-step, from zero to running agents.
2. **Create your private config:** Copy `agent-env.example.sh` to `agent-env.sh`, fill in your instance IDs and mesh IPs.
3. **Run the scripts:** `scripts/` has ops wrappers for start, stop, SSH, health checks, snapshots, cost tracking, and secrets sync.

> **Requires:** [just](https://github.com/casey/just#installation) (optional — you can run the scripts directly)

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

## Scripts & Just Recipes

Every script sources `_agent-env.sh` for defaults. All values are overridable via environment variables. A [`justfile`](justfile) provides shortcuts for common operations.

| Just recipe | Script | Purpose |
|---|---|---|
| `just setup` | `agent-setup.sh` | Interactive wizard — checks deps, detects mesh VPN, creates `agent-env.sh` |
| `just ssh` | `agent-ssh.sh` | SSH over mesh. `--bootstrap` for initial setup. |
| `just ssm` | `agent-ssm.sh` | Break-glass shell via AWS SSM Session Manager. |
| `just status` | `agent-status.sh` | EC2 state, public IP, mesh reachability. |
| `just probe` | `agent-status.sh --probe` | Status + remote uptime check. |
| `just start` | `agent-start.sh` | Idempotent start. Waits for `running`. |
| `just stop` | `agent-stop.sh` | Interactive stop. `--yes` to skip prompt. |
| `just health` | `agent-health.sh` | Remote health: uptime, memory, disk, agent services, journal. |
| `just logs` | `agent-logs.sh` | Tail a journald unit over mesh. |
| `just snapshot` | `agent-snapshot.sh` | On-demand EBS snapshot with tags. |
| `just snapshots` | `agent-snapshot-list.sh` | List tagged snapshots with age. |
| `just secrets-sync` | `agent-secrets-sync.sh` | Push API keys from vault to instance (stdin, never argv). |
| `just cost` | `agent-cost.sh` | Month-to-date AWS spend via Cost Explorer. |
| `just ip` | `agent-ip.sh` | Print the current public IP (if any). |
| `just verify` | — | Start + probe + health in one shot. |
| `just run <cmd>` | — | Run any command on the instance over SSH. |

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
    agent-ec2-setup.md        # The full setup guide (start here)
  scripts/
    _agent-env.sh              # Shared defaults + helpers (sourced by all scripts)
    agent-setup.sh             # Interactive setup wizard
    agent-ssh.sh               # SSH over mesh or bootstrap
    agent-start.sh             # Start the instance
    agent-stop.sh              # Stop the instance
    agent-health.sh            # Remote health check
    ...                        # See Scripts table above
  agent-env.example.sh         # Template for your private config
  justfile                     # Just recipes for all ops commands
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
