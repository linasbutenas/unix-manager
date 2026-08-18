# unix-manager v1.2.2

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
curl -fsSL https://bitbucket.org/linasbprojects/unix-manager/raw/master/install.sh | bash
```

`install.sh` will:
1. Clone the repo to `~/.local/share/unix-manager/` (canonical location)
2. Re-exec itself from there
3. Deploy all files:
   - `unix-manager.sh` → `~/.local/bin/unix-manager`
   - `unix-manager.conf` → `~/.config/unix-manager/config.conf` (**always overwritten**)
   - `config_local.conf` → `~/.config/unix-manager/config_local.conf` (created once, never overwritten)
   - `scripts/` → `~/.config/unix-manager/scripts/`
4. Add `alias um='unix-manager'` and PATH export to `~/.bashrc`

Open a new terminal, then launch with `um`.

## Updating

From inside the TUI: **Unix Manager → update**

This runs `git pull` in `~/.local/share/unix-manager/` and re-runs `install.sh` to deploy the latest files.

## Usage

```bash
um
```

Navigate with arrow keys, confirm with Enter, quit with Escape or the Quit button.

## Config files

The menu is built from two config files, with **local commands shown first**:

| File | Purpose | On update |
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
| Git | `st`, `log`, `diff`, `push`, `ship` |
| Multipass | `list`, `info`, `shell`, `stop`, `new`, `new + prometheus`, `stop all` |
| Unix Manager | `update` |
| System | `upgrade`, `adduser`, `listusers`, `ufw`, `df`, `mem`, `top`, `ports` |
| Unix Program Installer | `open` (checklist: `mc`, `htop`, `zip`, `unzip`, `glow`, `claude`) |

### Git — `ship`

Prompts for a commit message (max 7 words), then runs `git add . && git commit && git push` in one go.

### Multipass — `new`

Prompts for name, CPUs (default 2), memory (default 4G), disk (default 8G), then:
1. Launches the VM
2. Creates `~/.mp_<name>` on the host
3. Mounts it inside the VM at `/home/ubuntu/host_drive`

### Multipass — `new + prometheus`

Same as `new`, plus transfers and runs `install_node_exporter.sh` inside the VM, which installs and enables Prometheus Node Exporter as a systemd service.

### Multipass — `shell` / `stop`

Both show `multipass list` first, then prompt for the VM name before connecting or stopping.

### Multipass — `stop all`

Lists all VMs and asks for confirmation before stopping all of them.

### System — `adduser`

Creates a local Unix user on the host. Prompts for:
1. Username (validated as a legal Unix login name; aborts if it already exists)
2. Supplementary groups (comma-separated, optional)
3. Whether to grant sudo
4. Whether to copy your `~/.ssh/authorized_keys` to the new user (if yes, copies
   the file into the new user's `~/.ssh/`, sets ownership to the new user, and
   applies `700`/`600` permissions so SSH accepts it)
5. A password (set interactively)

Requires `sudo`. Runs `scripts/create_user.sh`.

### System — `ufw`

Opens a checklist window (`scripts/ufw_manager.sh`) for managing a fixed set of
firewall rules. Rules currently in effect are pre-ticked; tick to create, untick
to delete. The managed rules are:

- SSH rate-limited (`ufw limit 22/tcp`)
- HTTP (`ufw allow 80/tcp`)
- HTTPS (`ufw allow 443/tcp`)
- Default deny incoming (`ufw default deny incoming`)
- Firewall enabled (`ufw enable`)

Current state is detected read-only (via `ufw show added`, `/etc/default/ufw`,
and `/etc/ufw/ufw.conf`), so it works whether ufw is active or not. After you
confirm, rule changes are applied first and the enable/disable toggle last, so
the firewall is never enabled before its rules exist. Enabling without an SSH
rule triggers a lock-out warning. Requires `sudo` and `ufw`.

### Unix Program Installer

Installs common tools on a fresh VM. Selecting **open** launches a checklist
window (`scripts/program_installer.sh`). Already-installed programs are detected
(via `command -v`) and shown as a locked list marked with `*` at the top of the
window — they cannot be toggled. Only not-installed programs appear as
checkboxes. Tick the ones you want, press Enter, and they are installed in one
go. If every program is already installed, the window just reports that.

Programs are defined as `name = install command` entries under the
`[Unix Program Installer]` group in `config.conf` — add a tool by appending one
line. The detection assumes the program's command name matches its config name.

Bundled programs:

- `mc` — Midnight Commander, from the standard Ubuntu repos.
- `htop` — interactive process viewer, from the standard Ubuntu repos.
- `zip` / `unzip` — archive tools, from the standard Ubuntu repos.
- `glow` — Charm's markdown renderer. Not in the default Ubuntu repos, so
  `scripts/install_glow.sh` adds the Charm apt repository (GPG key + source
  list) before installing.
- `claude` — the Claude Code CLI, installed via
  `curl -fsSL https://claude.ai/install.sh | bash` (no `sudo` required).

The apt-based programs require `sudo`.

## Project structure

```
unix-manager.sh               # main script
unix-manager.conf             # global config (always deployed by install.sh)
config_local.conf             # local config template (deployed once, never overwritten)
install.sh                    # installer / updater
scripts/
  install_node_exporter.sh    # installs Prometheus Node Exporter inside a Multipass VM
  create_user.sh              # creates a local Unix user (System → adduser)
  install_glow.sh             # installs glow via the Charm apt repo
  program_installer.sh        # checklist installer (Unix Program Installer → open)
  ufw_manager.sh              # checklist firewall rule manager (System → ufw)
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the version history.
