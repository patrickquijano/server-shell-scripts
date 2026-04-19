# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## lean-ctx — Token Optimization

lean-ctx is configured as an MCP server. Use lean-ctx MCP tools instead of built-in tools:

| Built-in              | Use instead  | Why                                                            |
| --------------------- | ------------ | -------------------------------------------------------------- |
| Read / cat / head     | `ctx_read`   | Session caching, 6 compression modes, re-reads cost ~13 tokens |
| Bash (shell commands) | `ctx_shell`  | Pattern-based compression for git, npm, cargo, docker, tsc     |
| Grep / rg             | `ctx_search` | Compact context, token-efficient results                       |
| ls / find             | `ctx_tree`   | Compact directory maps with file counts                        |

For shell commands that don't have MCP equivalents, prefix with `lean-ctx -c`:

```bash
lean-ctx -c git status    # compressed output
lean-ctx -c cargo test    # compressed output
lean-ctx -c npm install   # compressed output
```

### ctx_read Modes

- `full` — cached read (use for files you will edit)
- `map` — deps + API signatures (use for context-only files)
- `signatures` — API surface only
- `diff` — changed lines only (after edits)
- `aggressive` — syntax stripped
- `entropy` — Shannon + Jaccard filtering

Write, StrReplace, Delete have no lean-ctx equivalent — use them normally.

## Overview

A collection of standalone Bash scripts for provisioning RHEL 8/9-compatible servers (Rocky Linux, AlmaLinux, etc.). Scripts are organized by OS family under `scripts/`.

## Running Scripts

Scripts require `sudo` and a RHEL-based system with `dnf`.

```bash
# Install Docker CE and add a user to the docker group
sudo sh scripts/rhel/setup-docker.sh <username>

# Configure unattended daily updates via dnf-automatic
sudo sh scripts/rhel/setup-dnf-automatic.sh
```

Scripts can also be executed remotely without cloning:

```bash
curl -fsSL https://raw.githubusercontent.com/patrickquijano/server-shell-scripts/main/scripts/rhel/setup-docker.sh | sudo sh -s -- <username>
```

## Script Conventions

- Start with `#!/bin/sh` and `set -e` — all scripts exit immediately on any error.
- Each script begins with a full `dnf update && dnf upgrade` before installing packages.
- All privileged commands use `sudo` explicitly, even when the script is invoked as root.
- Service management uses `systemctl enable --now <service>` followed by an `is-active` check with a clear success/failure message and `exit 1` on failure.
- Before overwriting existing config files (e.g., `/etc/docker/daemon.json`), the script displays the current contents and prompts the user with `[y/N]`.
- Arguments are validated at the top of the script before any system changes.

## Code Style

Follows `.editorconfig`: 2-space indentation, LF line endings, UTF-8. Shell scripts use `[ ]` for conditionals (POSIX sh) and `"$VAR"` quoting throughout.
