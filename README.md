# unix-manager

A minimal bash TUI for organizing and running shell commands from a config file.

## Requirements

- `bash` 4+
- `dialog` — install with:
  ```
  sudo apt install dialog      # Debian/Ubuntu
  sudo dnf install dialog      # Fedora
  sudo pacman -S dialog        # Arch
  ```

## Installation

```bash
./install.sh
```

This copies:
- `unix-manager.sh` → `~/.local/bin/unix-manager`
- `unix-manager.conf` → `~/.config/unix-manager/config.conf` (**always overwritten** on reinstall)
- `config_local.conf` → `~/.config/unix-manager/config_local.conf` (created once, never overwritten)
- `scripts/` → `~/.config/unix-manager/scripts/`
- Adds `alias um='unix-manager'` and PATH export to `~/.bashrc`

Re-running `install.sh` is safe — local config and scripts are preserved, global config is always synced from the repo.

## Usage

```bash
um
```

Navigate with arrow keys, confirm with Enter, quit with Escape or the Quit button.

## Config files

The menu is built from two config files, with **local commands shown first**:

| File | Purpose | On reinstall |
|---|---|---|
| `~/.config/unix-manager/config.conf` | Global commands (from repo) | Always overwritten |
| `~/.config/unix-manager/config_local.conf` | Personal commands | Never touched |

Format for both files:

```ini
# Lines starting with # are comments

[Group Name]
short = full command to run
build = docker build -t myapp .
log   = git log --oneline -15
```

- **Groups** are `[Section]` headers — shown as folder-like headers in the menu.
- **Commands** are `name = command` pairs under a group.
- Commands support pipes, redirects, and any valid bash syntax.
- For multi-step prompts use `bash -c '...'` with `read -rp` inside.
- Local groups are marked with `[local]` in the menu.

## Built-in command groups (config.conf)

| Group | Commands |
|---|---|
| Docker | `ps`, `prune` |
| Git | `st`, `log`, `diff`, `push` |
| Multipass | `list`, `info`, `shell`, `new`, `new + prometheus` |
| System | `df`, `mem`, `top`, `ports` |

### Multipass — `new`

Prompts for name, CPUs (default 2), memory (default 4G), disk (default 8G), then:
1. Launches the VM
2. Creates `~/.mp_<name>` on the host
3. Mounts it inside the VM at `/home/ubuntu/host_drive`

### Multipass — `new + prometheus`

Same as `new`, plus transfers and runs `install_node_exporter.sh` inside the VM, which installs and enables Prometheus Node Exporter as a systemd service.

### Multipass — `shell`

Runs `multipass list` first, then prompts for the VM name to connect to.

## Project structure

```
unix-manager.sh           # main script
unix-manager.conf         # global config (always deployed by install.sh)
config_local.conf         # local config template (deployed once, never overwritten)
install.sh                # installer
scripts/
  install_node_exporter.sh    # installs Prometheus Node Exporter inside a Multipass VM
```
