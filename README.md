# agent-deploy

A beginner-friendly toolkit for running AI coding agents on a dedicated AWS EC2 instance — so your laptop stays free while agents work around the clock.

This repo gives you everything you need to launch a secure cloud box, connect to it over a private mesh VPN, and run any AI coding agent you want: [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex CLI](https://github.com/openai/codex), [Gemini CLI](https://github.com/google-gemini/gemini-cli), [Hermes](https://github.com/NousResearch/hermes-agent), [OpenClaw](https://github.com/openclaw/openclaw), [pi-coding-agent](https://github.com/nichochar/pi-coding-agent), or any other AI CLI tool.

## Why Use This?

| Problem | How agent-deploy solves it |
|---|---|
| Agents hog your laptop's CPU and memory | Run them on a dedicated cloud instance instead |
| Long tasks die when you close your laptop | Agents run in `tmux` — they survive disconnects, reboots, and network blips |
| Exposing your machine to the internet is risky | No public SSH. All access goes through a private mesh VPN |
| Cloud instances are hard to set up securely | Hardened by default: firewall, fail2ban, encrypted disk, daily backups |
| You only want to use one agent | Agent-agnostic — install whichever CLI tools you need, all on one box |
| Cloud costs add up | A `t4g.large` costs ~$0.07/hr. Stop it when you're done. Full teardown commands included |

## Prerequisites

Before you begin, make sure you have:

- **An AWS account** — [Sign up here](https://aws.amazon.com/) if you don't have one. You'll need the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installed and configured (`aws configure`).
- **A mesh VPN** — Either [NordVPN](https://nordvpn.com/) (with Meshnet) or [Tailscale](https://tailscale.com/) (free tier works). This is how you'll connect to your instance privately.
- **An SSH client** — Already built in on macOS and Linux. On Windows, use [Windows Terminal](https://aka.ms/terminal) with OpenSSH or [PuTTY](https://www.putty.org/).
- **API keys** for the AI agents you want to use (e.g., Anthropic, OpenAI, Google).
- **Git** — [Install Git](https://git-scm.com/downloads) if you don't already have it.

## Install Just (Command Runner)

This project uses [`just`](https://github.com/casey/just) as a command runner — it gives you simple shortcuts like `just ssh` and `just start` instead of remembering long script paths. It's optional (you can always run the scripts directly), but it makes everything easier.

Pick the install method for your operating system:

### macOS

```bash
brew install just
```

If you don't have Homebrew, [install it first](https://brew.sh/), then run the command above.

### Windows

Pick whichever package manager you have:

```powershell
# Using winget (built into Windows 10/11):
winget install --id Casey.Just --exact

# Using Scoop:
scoop install just

# Using Chocolatey:
choco install just
```

### Linux

```bash
# Ubuntu 24.04+ / Debian 13+
sudo apt install just

# Fedora
sudo dnf install just

# Arch
sudo pacman -S just
```

### Any OS (universal)

If the above doesn't work for you, this script downloads a pre-built binary:

```bash
# Download just to ~/bin (works on Linux, macOS, and WSL)
mkdir -p ~/bin
curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to ~/bin
export PATH="$PATH:$HOME/bin"
```

Or install via npm (if you already have Node.js):

```bash
npm install -g rust-just
```

**Verify it worked:**

```bash
just --version
```

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/Chameleon-Labs-LLC/agent-deploy.git
cd agent-deploy

# 2. Run the interactive setup wizard
#    It checks your dependencies, detects your mesh VPN, and creates your config file.
just setup

# 3. Follow the setup guide to launch your EC2 instance
#    (see docs/agent-ec2-setup.md for the full walkthrough)

# 4. Once your instance is running, use these shortcuts:
just start          # Start the instance
just ssh            # SSH into it over mesh VPN
just health         # Check that everything is healthy
just status         # See instance state + mesh reachability
```

Don't want to use `just`? You can run the scripts directly:

```bash
scripts/agent-setup.sh          # same as: just setup
scripts/agent-start.sh          # same as: just start
scripts/agent-ssh.sh            # same as: just ssh
scripts/agent-health.sh         # same as: just health
```

For the full step-by-step setup guide (from zero to running agents), see [`docs/agent-ec2-setup.md`](docs/agent-ec2-setup.md).

## Supported Agents

This toolkit is **agent-agnostic** — it works with any AI coding agent that runs as a CLI tool. Here are some popular ones:

| Agent | Provider | Install Command | API Key Env Var |
|---|---|---|---|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Anthropic | `npm install -g @anthropic-ai/claude-code` | `ANTHROPIC_API_KEY` |
| [Codex CLI](https://github.com/openai/codex) | OpenAI | `npm install -g @openai/codex` | `OPENAI_API_KEY` |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | Google | `npm install -g @google/gemini-cli` | `GEMINI_API_KEY` |
| [Hermes](https://github.com/NousResearch/hermes-agent) | Nous Research | `curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \| bash` | `OPENROUTER_API_KEY` or `ANTHROPIC_API_KEY` |
| [OpenClaw](https://github.com/openclaw/openclaw) | OpenClaw Foundation | `npm install -g openclaw@latest` | `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, or `GOOGLE_API_KEY` |
| [OpenCode](https://opencode.ai/) | opencode-ai | `npm install -g opencode-ai@latest` | Varies by model provider |
| [pi-coding-agent](https://github.com/nichochar/pi-coding-agent) | Multi-provider | `npm install -g @mariozechner/pi-coding-agent` | Depends on backend |

> **Using a different agent?** No problem. SSH into your instance (`just ssh`), install whatever CLI tool you need, and add your API keys. The setup guide covers how to securely store keys and configure new agents.

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

Every script lives in the `scripts/` folder and can be run directly or via `just`. All scripts read your settings from `agent-env.sh` (created during setup).

| Just recipe | Script | What it does |
|---|---|---|
| `just setup` | `agent-setup.sh` | Interactive wizard — checks deps, detects mesh VPN, creates your config |
| `just ssh` | `agent-ssh.sh` | SSH into your instance over mesh VPN |
| `just ssm` | `agent-ssm.sh` | Emergency shell via AWS SSM (if mesh is down) |
| `just status` | `agent-status.sh` | Show instance state, public IP, and mesh reachability |
| `just probe` | `agent-status.sh --probe` | Same as status, plus a remote uptime check |
| `just start` | `agent-start.sh` | Start the instance (safe to run if already started) |
| `just stop` | `agent-stop.sh` | Stop the instance (asks for confirmation) |
| `just health` | `agent-health.sh` | Remote check: uptime, memory, disk, agent services |
| `just logs` | `agent-logs.sh` | Tail logs from a service on the instance |
| `just snapshot` | `agent-snapshot.sh` | Take an on-demand EBS snapshot (backup) |
| `just snapshots` | `agent-snapshot-list.sh` | List your recent snapshots |
| `just secrets-sync` | `agent-secrets-sync.sh` | Push API keys to the instance (securely, via stdin) |
| `just cost` | `agent-cost.sh` | Show your month-to-date AWS spend |
| `just ip` | `agent-ip.sh` | Print the instance's current public IP |
| `just verify` | — | Start + probe + health in one shot |
| `just run <cmd>` | — | Run any command on the instance over SSH |

## Cost

| Scenario | Monthly (approx.) |
|---|---|
| Running 24/7 (`t4g.large`) | ~$54 |
| Running 8 hrs/day, stopped the rest | ~$18 |
| Stopped (EBS storage only) | ~$4 |

The setup guide includes an optional auto-stop timer that shuts down your instance at midnight automatically — so you're not paying while you sleep.

## Security Model

This toolkit takes security seriously. Here's what's in place:

- **No public SSH.** Port 22 is closed on the security group. The only way in is through your mesh VPN.
- **SSM break-glass.** If your mesh goes down, AWS Session Manager gets you in as a fallback.
- **Dedicated API keys.** One key per instance per provider. If a key leaks, revoke just that one.
- **Secrets never on the command line.** Keys are piped over stdin or read from files — they never show up in `ps` output or shell history.
- **Private config file.** All instance-specific values (IDs, IPs, keys) live in `agent-env.sh`, which is gitignored. The repo itself is safe to fork and share.

## Project Structure

```
agent-deploy/
  docs/
    agent-ec2-setup.md        # Full setup guide — start here
  scripts/
    _agent-env.sh              # Shared defaults (sourced by all scripts)
    agent-setup.sh             # Interactive setup wizard
    agent-ssh.sh               # SSH over mesh or bootstrap
    agent-start.sh             # Start the instance
    agent-stop.sh              # Stop the instance
    agent-health.sh            # Remote health check
    ...                        # See the Scripts table above for the rest
  agent-env.example.sh         # Template for your private config
  justfile                     # Just recipes (shortcuts for all scripts)
  .gitignore
  LICENSE
  README.md
```

## Troubleshooting

| Problem | Fix |
|---|---|
| `just: command not found` | Install `just` using the instructions above for your OS |
| `aws: command not found` | Install the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) and run `aws configure` |
| SSH connection refused | Make sure your mesh VPN is connected and the instance is running (`just status`) |
| Permission denied (SSH) | Check that your SSH key is correct in `agent-env.sh` and on the instance |
| Instance won't start | Check your AWS region in `agent-env.sh` and verify the instance ID is correct |

## Links

- **Chameleon Labs:** [chameleonlabs.ai](https://chameleonlabs.ai)
- **Discord:** [discord.gg/chameleonlabs](https://discord.gg/chameleonlabs)
- **GitHub:** [github.com/Chameleon-Labs-LLC](https://github.com/Chameleon-Labs-LLC)
- **Setup Guide:** [`docs/agent-ec2-setup.md`](docs/agent-ec2-setup.md)
- **Just (command runner):** [github.com/casey/just](https://github.com/casey/just)

## License

MIT
