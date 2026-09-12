# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Monitoring (on host) → `status`** — reports the host stack's prerequisites,
  where it actually lives, its containers and ports, and its health: Prometheus
  readiness, scrape targets as `N of M up` with each failing exporter named, and
  whether Grafana's database is reachable. Read-only, and needs no credentials.
  Discovery starts from Docker rather than `STACK_DIR`, because a stack
  provisioned by hand or with `STACK_DIR` overridden is invisible to a
  path-based check — reporting "not installed" while it is plainly running would
  be worse than not reporting at all. Exits non-zero only when the report itself
  cannot be made.
- **Multipass → `ssh key`** — adds your SSH public key to a VM's
  `authorized_keys` and saves a host-side copy to `~/.mp_<name>/authorized_keys`
  for recovery. Runs automatically at the end of `new` and `new + prometheus`,
  and can be applied to an existing VM from the menu. Keeps a VM reachable over
  plain `ssh` if Multipass' own key is lost, which otherwise leaves no way in
  short of editing the instance's qcow2 disk offline. Idempotent; a missing host
  key warns instead of failing a launch.

### Fixed
- **Prometheus (on VM) → `install`** and **Multipass → `new + prometheus`** failed
  with `[sftp] cannot open local file .../.config/unix-manager/scripts/
  install_node_exporter.sh: Permission denied` when Multipass is installed as a
  snap. Snaps may only read non-hidden files under `$HOME`, and the scripts live
  under `~/.config`. Both commands now feed the script to `multipass transfer`
  on stdin (`transfer -`), the workaround Multipass' maintainers recommend, so
  the snap never opens the hidden path. Until now `new + prometheus` produced a
  VM without a node exporter: the transfer failed after the launch and mount had
  already succeeded.
- A menu command that exits non-zero no longer quits the TUI. `unix-manager.sh`
  runs under `set -e`, so the `eval` in `run_command` ended the whole program on
  the first failing command, before the "Exit code" line and the "Press Enter"
  prompt could appear. The failure now shows its exit code and returns to the
  menu, as the code always intended. Both bugs fixed today (a missing systemd
  unit, a snap-blocked transfer) were only noticed because the shell prompt
  appeared where the menu should have been.

## [1.2.9] — 2026-09-10

### Changed
- Repository moved from Bitbucket to GitHub
  (`github.com/linasbutenas/unix-manager`). The install one-liner in the README
  and `REPO_URL` in `install.sh` now point at GitHub.
- `install.sh` repoints an existing install's `origin` from Bitbucket to GitHub
  automatically, so machines installed from the old remote keep updating. The
  check runs before the re-exec, so it also applies when `install.sh` is run
  from the canonical directory — which is how **Unix Manager → update** runs it.
- **Unix Manager → update** now continues to `install.sh` even if `git pull`
  fails, so an install still pointing at Bitbucket can reach the repoint above
  instead of stopping at the failed pull.

## [1.2.8] — 2026-08-25

### Added
- **Monitoring (on host)** group with `install stack`, provisioning the host-side
  Prometheus + Grafana stack via `install_monitoring_stack.sh`, and `targets`
  for inspecting scrape health. The script derives every path from a single
  `STACK_DIR`, so the config and the compose file can no longer be written to
  different directories — the mismatch that made the Docker daemon create a
  root-owned directory at the bind-mount source and left Prometheus unable to
  start. It validates the config with `promtool` before starting and verifies
  every scrape target is up afterwards. The Grafana admin password is injected
  at run time rather than written into `docker-compose.yml`.

## [1.2.7] — 2026-08-25

### Added
- New **Prometheus (on VM)** group: `install`, `status`, `upgrade`, `metrics`, and
  `remove` for Prometheus Node Exporter inside an existing Multipass VM (each
  command lists the VMs and prompts for a name).
- `prometheus-node-exporter` added to the **Unix Program Installer** checklist
  for installing the exporter on the local machine.

### Changed
- `install_node_exporter.sh` now installs the `prometheus-node-exporter` apt
  package instead of a pinned 1.7.0 tarball and hand-written systemd unit, so
  the exporter is upgraded by the regular `apt update && apt upgrade` cycle
  (also used by Multipass → `new + prometheus`).

## [1.2.6] — 2026-08-18

### Changed
- Moved the Docker install from the **Docker** group into the **Unix Program
  Installer** checklist (as `docker`), so its installed state is detected
  alongside the other tools.

## [1.2.5] — 2026-08-18

### Changed
- The menu now shows only command names for **all** groups; the full command is
  no longer displayed after the arrow. (Supersedes the earlier per-group
  changes.)

## [1.2.4] — 2026-08-18

### Changed
- The **System** group now shows only the command name for `ufw`, `adduser`,
  and `listusers` (matching the Unix Manager group); other System commands still
  show their command after the arrow.
- The **Multipass** group now shows only command names in the menu, without the
  full command after the arrow.

## [1.2.3] — 2026-08-18

### Changed
- The **Unix Manager** group now shows only the command name in the menu
  (e.g. `update`), without the full command after the arrow.

## [1.2.2] — 2026-08-18

### Changed
- Moved the Claude Code CLI install from the **Claude** group into the **Unix
  Program Installer** checklist (as `claude`), so its installed state is
  detected alongside the other tools.
- The Unix Program Installer now shows a short description beside each program
  (e.g. `glow` — Markdown reader) instead of a redundant "not installed" label.

## [1.2.1] — 2026-08-18

### Added
- **Claude → install**: install the Claude Code CLI via
  `curl -fsSL https://claude.ai/install.sh | bash`.

## [1.2.0] — 2026-08-18

### Added
- **System → listusers**: list human/login users (UID ≥ 1000) with their UID
  and home directory.
- **System → ufw**: checklist window to manage a fixed set of firewall rules
  (SSH rate-limit, HTTP, HTTPS, default deny incoming, firewall enable). Current
  state is detected read-only; changes are confirmed, applied rules-first, and
  guarded by a lock-out warning when enabling without an SSH rule.

## [1.1.1] — 2026-08-17

### Added
- **System → adduser**: optional step to copy your `~/.ssh/authorized_keys` to
  the new user. When enabled, the file is copied into the new user's `~/.ssh/`,
  ownership is set to the new user, and `700`/`600` permissions are applied so
  SSH accepts the keys.

## [1.1.0] — 2026-07-28

### Added
- **System → adduser**: create a local Unix user, with username validation,
  optional supplementary groups, optional sudo, and an interactive password.
- **Unix Program Installer** group: an **open** launcher opens a checklist
  window that detects installed programs (shown as a locked `*` list) and
  installs the ones you tick. Bundled programs: `mc`, `htop`, `zip`, `unzip`,
  and `glow` (via the Charm apt repository).
- **System → upgrade**: `apt update && apt upgrade -y`.
- **Unix Manager → readme**: view the README from the menu.
- **Claude** group: `sessions` and `resume` commands.

### Changed
- The menu window now sizes dynamically to the item count and the terminal,
  instead of a fixed height.
- Moved the **Unix Manager** group to the end of the menu.
- Raised the `ship` commit-message limit to 13 words.
- Widened the dialog to fit longer session names.

### Fixed
- Installer crash caused by `((count++))` aborting under `set -e` when the
  counter started at zero.
- Installer unbound-variable crash under `set -u`; arrays are now initialised
  with `=()`.

## [1.0.0] — 2026-05-07

### Added
- Initial release: a `dialog`-based TUI that builds its menu from
  `config.conf` and `config_local.conf`.
- Built-in groups: Docker, Git, Multipass, and System.
- `install.sh` / `uninstall.sh`, the in-menu **update** command, and the
  Prometheus Node Exporter provisioning script for Multipass VMs.
