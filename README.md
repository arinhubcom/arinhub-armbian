# arinhub-armbian

Example unattended first boot configuration for **Armbian on Ubuntu 26.04 LTS
(resolute)**, built to be filled in and used by an AI agent (Claude Code).
The board is then either controlled **remotely over SSH** or the agent runs
**locally on the board itself**.

Based on the official docs:
[Armbian automatic first boot configuration](https://docs.armbian.com/user-guide/autoconfig/).

## Contents

| Path | Purpose |
| --- | --- |
| `config/not_logged_in_yet.example` | First boot config template with placeholders for sensitive values |
| `config/provisioning.sh.example` | Provisioning script template, run once as root: hostname, SSH key, sudo, SSH hardening, packages, firewall |
| `scripts/check-config.sh` | Validates a filled config without executing it |
| `tests/check-config.test.sh` | Tests for the validator (`bash tests/check-config.test.sh`) |
| `tests/provisioning.test.sh` | Tests for the provisioning script, with stubbed system commands and a sandbox root |

## Placeholder convention

The agent finds everything it has to ask about with one command:

```bash
grep -n '__ASK_' config/not_logged_in_yet config/provisioning.sh
```

| Value in the template | Meaning | What the agent does |
| --- | --- | --- |
| `"__ASK_<NAME>__"` / `'__ASK_<NAME>__'` | Required, sensitive or user-specific | Must ask the user |
| `"__ASK_OPTIONAL_<NAME>__"` / `'__ASK_OPTIONAL_<NAME>__'` | Optional | Must ask; if declined, deletes the whole line (`not_logged_in_yet`) or sets it to `''` (`provisioning.sh`) |
| any other value | Sensible default | Shows it once in a summary, keeps it unless the user changes it |

`not_logged_in_yet` uses double quotes, and `scripts/check-config.sh` rejects
`$`, backticks and backslashes in its values. `provisioning.sh` uses single
quotes, so those characters stay literal there; its values must not contain a
single quote (for an SSH key whose comment has one, leave the comment out).

Filled configs live in `config/` and are git-ignored; only `*.example` is tracked.

## How it works

1. The agent copies both templates, asks the user for the placeholder values
   and validates the results with `scripts/check-config.sh` and
   `bash config/provisioning.sh --check`.
2. The files are copied to `/root/.not_logged_in_yet` and
   `/root/provisioning.sh` on the flashed boot media.
3. At first boot Armbian applies the config through the root console
   autologin; no keyboard or monitor is needed. At the end of that first login
   it runs the provisioning script once as root: hostname, SSH key,
   passwordless sudo and SSH hardening (if chosen), packages, firewall.
4. The agent connects over SSH (or is installed on the board) and verifies
   the result.

---

## Prompt for the AI agent

Paste the block below into Claude Code (or any coding agent) opened in this
repository.

````text
You are setting up a headless Armbian board (Ubuntu 26.04 LTS, resolute) from
the templates in config/. Docs: https://docs.armbian.com/user-guide/autoconfig/

Rules
- Ask the user for every "__ASK_*__" value; never guess or reuse examples. The
  comment above each value says what it means and which format it needs.
- Keep secrets out of chat, logs, commits and shell history; say "set" or
  "not set" instead.
- Keep the filled files only in config/not_logged_in_yet and
  config/provisioning.sh (git-ignored).
- Get an explicit "yes" before writing to a block device, rebooting, or
  changing SSH or sudo on the board.

1. Setup: ask in one message for the control mode (A: you control the board
   over SSH from this workstation; B: Claude Code runs on the board), Wi-Fi or
   Ethernet, DHCP or static IP, and the boot media, flashed with a minimal
   (server) Armbian Ubuntu 26.04 image.
2. Fill: copy both *.example files without the suffix and ask for all
   placeholders in one message
   (`grep -n '__ASK_' config/not_logged_in_yet config/provisioning.sh`).
   Offer generated passwords (`openssl rand -base64 24 | tr -d '/+='`) written
   straight into the file. In mode A offer this workstation's public key for
   __ASK_OPTIONAL_SSH_PUBKEY__ (without its comment if that holds a single
   quote). Then show the remaining defaults once and
   apply any changes.
3. Validate until both print OK: `scripts/check-config.sh
   config/not_logged_in_yet` and `bash config/provisioning.sh --check`.
4. Write: confirm the device with `lsblk`, mount its ext4 root partition, then
     sudo install -m 600 -o root -g root config/not_logged_in_yet <mnt>/root/.not_logged_in_yet
     sudo install -m 700 -o root -g root config/provisioning.sh <mnt>/root/provisioning.sh
   and sync and unmount.
5. Boot: the user powers the board on; allow 5-10 minutes (resize, one reboot,
   package upgrade). Reach it at <hostname>.local, through the router's DHCP
   leases, or at the static IP. Mode B: the user installs Claude Code on the
   board (`curl -fsSL https://claude.ai/install.sh | bash`) and logs in.
6. Verify, read-only: Ubuntu 26.04 in /etc/os-release, hostname, timezone,
   network, /root/.not_logged_in_yet gone, "Provisioning complete" in
   /var/log/armbian-provisioning.log, and the chosen sudo, SSH
   (`sudo sshd -T`) and ufw state. If provisioning failed, fix the cause and
   rerun `sudo bash /root/provisioning.sh` after the user agrees.
7. Report what was done and the board's address, without secret values, and
   offer to delete the filled files.
````

## Validate a config manually

```bash
cp config/not_logged_in_yet.example config/not_logged_in_yet
cp config/provisioning.sh.example config/provisioning.sh
$EDITOR config/not_logged_in_yet config/provisioning.sh
scripts/check-config.sh config/not_logged_in_yet
bash config/provisioning.sh --check
```

Run the tests:

```bash
bash tests/check-config.test.sh
bash tests/provisioning.test.sh
```
