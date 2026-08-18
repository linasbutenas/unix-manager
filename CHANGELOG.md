# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

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
