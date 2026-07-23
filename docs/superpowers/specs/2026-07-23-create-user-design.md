# Create-user command — design

**Date:** 2026-07-23
**Status:** Approved

## Goal

Add a menu command to unix-manager that creates a local Unix user on the host,
sets a password, adds the user to supplementary groups, and optionally grants
sudo. The command lives under the existing `[System]` menu group.

## Approach

Follow the established pattern for non-trivial operations (as with
`install_docker.sh`): keep the logic in a standalone script under `scripts/`
and add a one-line dispatcher entry in `config.conf`. This keeps the flow
readable, with proper validation and error handling, rather than cramming
multiple prompts onto a single `bash -c` line.

## Components

### `scripts/create_user.sh`

Runs with `set -euo pipefail`. Flow:

1. **Prompt for username.** Validate:
   - non-empty
   - matches a legal Unix login name: `^[a-z_][a-z0-9_-]*$`
   - does not already exist (`id "$user"` check) — abort with a clear message
     if it does.
2. **Create the user:** `sudo useradd -m -s /bin/bash "$user"` (creates the
   home directory and sets the login shell to bash).
3. **Supplementary groups:** prompt for a comma-separated list (optional). For
   each non-empty group, add via `sudo usermod -aG "$group" "$user"`.
4. **Grant sudo (separate prompt):** `Grant sudo? [y/N]` — if yes,
   `sudo usermod -aG sudo "$user"`.
5. **Set password:** `sudo passwd "$user"` (interactive).
6. **Summary:** print `id "$user"` so the resulting groups are visible.

### `config.conf`

Under the existing `[System]` group, add:

```ini
adduser = bash -c 'SCRIPTS="${XDG_CONFIG_HOME:-$HOME/.config}/unix-manager/scripts"; bash "$SCRIPTS/create_user.sh"'
```

### `README.md`

Document the new `adduser` command in the System group section.

## Error handling

- Empty or invalid username: print an error and exit non-zero before any
  `useradd` call.
- Existing user: detected up front, abort without modification.
- `useradd` / `usermod` / `passwd` failures: surface naturally via
  `set -euo pipefail`; the TUI's run wrapper already reports the exit code.

## Out of scope (YAGNI)

- SSH key provisioning.
- Creating users inside Multipass VMs (covered by the separate Multipass group).
- Non-interactive / batch user creation.
