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
| `config/not_logged_in_yet.example` | Config template with placeholders for sensitive values |
| `scripts/check-config.sh` | Validates a filled config without executing it |
| `tests/check-config.test.sh` | Tests for the validator (`bash tests/check-config.test.sh`) |

## Placeholder convention

The agent finds everything it has to ask about with one command:

```bash
grep -n '__ASK_' config/not_logged_in_yet
```

| Value in the template | Meaning | What the agent does |
| --- | --- | --- |
| `"__ASK_<NAME>__"` | Required, sensitive or user-specific | Must ask the user |
| `"__ASK_OPTIONAL_<NAME>__"` | Optional | Must ask; if declined, deletes the whole line |
| any other value | Sensible default | Shows it once in a summary, keeps it unless the user changes it |

Filled configs live in `config/` and are git-ignored; only `*.example` is tracked.

## How it works

1. The agent copies the template, asks the user for the placeholder values and
   validates the result with `scripts/check-config.sh`.
2. The file is copied to `/root/.not_logged_in_yet` on the flashed boot media.
3. At first boot Armbian applies it through the root console autologin; no
   keyboard or monitor is needed.
4. The agent connects over SSH (or is installed on the board) and hardens the
   system.

---

## Prompt for the AI agent

Paste the block below into Claude Code (or any coding agent) opened in this
repository.

````text
You are setting up a headless Armbian board running Ubuntu 26.04 LTS (resolute)
using the unattended first boot config in this repository. Reference:
https://docs.armbian.com/user-guide/autoconfig/

## Ground rules (security)
- Values marked "__ASK_<NAME>__" or "__ASK_OPTIONAL_<NAME>__" are sensitive or
  user-specific. NEVER guess, invent or reuse example values for them. Ask.
- Never echo a secret back, never print it in a summary, log, commit message
  or command line that ends up in shell history. Refer to it as "set" / "not set".
- The filled file goes to config/not_logged_in_yet only. It is git-ignored;
  never commit it, never copy it anywhere else on this machine.
- Values must not contain the characters  "  $  `  \  because Armbian sources
  the file as shell. If the user's value contains one, explain why and ask for
  another (for Wi-Fi this may mean changing the router password).
- Ask before any action that writes to a block device, reboots, or changes
  SSH/sudo settings on the board.

## Step 0 - Ask about the setup (one message)
1. Control mode: (A) I run on this workstation and control the board over
   SSH, or (B) Claude Code will be installed and run on the board itself?
2. Network: Wi-Fi or Ethernet only? DHCP (default) or a static IP?
3. Where is the flashed boot media: device path (e.g. /dev/sdX, /dev/mmcblk0)
   or already mounted path? If the image is not flashed yet, tell the user to
   flash the Armbian Ubuntu 26.04 image for their board first (Armbian Imager
   or balenaEtcher) and come back.

## Step 1 - Fill the config
1. cp config/not_logged_in_yet.example config/not_logged_in_yet
2. List placeholders:  grep -n '__ASK_' config/not_logged_in_yet
3. Ask the user for each placeholder, in ONE grouped message:
   - __ASK_WIFI_SSID__              Wi-Fi network name (only if Wi-Fi)
   - __ASK_WIFI_KEY__               Wi-Fi password, 8-63 chars (only if Wi-Fi)
   - __ASK_WIFI_COUNTRYCODE__       Wi-Fi country, ISO 3166 code in uppercase,
                                    e.g. CZ (only if Wi-Fi)
   - __ASK_TIMEZONE__               timezone, IANA name, e.g. Europe/Prague
                                    (you may suggest the workstation's one from
                                    `timedatectl show -p Timezone --value`)
   - __ASK_USER_NAME__              login name of the agent user: lowercase,
                                    starts with a letter or _, max 32 chars,
                                    not root
   - __ASK_REALNAME__               full name shown for that user,
                                    e.g. Armbian Agent
   - __ASK_ROOT_PASSWORD__          root password for emergency console access
   - __ASK_USER_PASSWORD__          password of the agent user (also used by sudo)
   - __ASK_OPTIONAL_USER_KEY_URL__  HTTPS URL with the user's SSH public key,
                                    e.g. https://github.com/<github-username>.keys
                                    Strongly recommended for mode A.
   For both passwords offer to generate a strong one instead
   (e.g. `openssl rand -base64 24 | tr -d '/+='`); if the user accepts, write it
   into the file directly and tell them where to read it once
   (`grep PASSWORD config/not_logged_in_yet`) so they can store it in their
   password manager. Do not show it in chat.
4. Replace each placeholder with the answer. If the user declines an OPTIONAL
   one, delete that whole line. For Ethernet only: set
   PRESET_NET_WIFI_ENABLED="0" and delete the SSID, KEY and COUNTRYCODE
   lines. For a static IP: uncomment the whole static block and ask for
   IP, mask, gateway and DNS.
5. Show ONE summary of the non-secret defaults and ask if any should change:
   locale (en_US.UTF-8), shell (bash), Ethernet fallback (on),
   IP mode (DHCP).
6. Validate until it prints OK:  scripts/check-config.sh config/not_logged_in_yet
   The script prints key names only, never values. Fix each reported problem
   by asking the user again.

## Step 2 - Write it to the boot media
1. Run `lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS` and show the user which
   device you believe is the boot media. Get an explicit "yes" before mounting.
2. Mount the ext4 root partition (Armbian usually has one partition, e.g.
   /dev/sdX1) to a temporary directory, then:
     sudo install -m 600 -o root -g root config/not_logged_in_yet <mnt>/root/.not_logged_in_yet
     sync && sudo umount <mnt>
3. Ask the user whether to delete the local filled copy now (recommended once
   the board is up) or keep it until Step 3 is verified.

## Step 3 - First boot
1. Tell the user to insert the media and power the board on. First boot
   resizes the filesystem and runs the first login setup; allow 3-5 minutes,
   one reboot is normal.
2. Find the board's IP: ask the user to check the router's DHCP leases, or try
   `ping <board-hostname>.local`, or the static IP if one was set.
3. Mode A: connect with `ssh <user>@<ip>` (key if provided, else the
   user's password - let the user type it, or use ssh-agent).
   Mode B: the user logs in locally or over SSH once and installs Claude Code
   on the board:  curl -fsSL https://claude.ai/install.sh | bash
   then runs `claude` and completes the login themselves.

## Step 4 - Verify and harden (ask before each change)
1. Verify:  cat /etc/os-release  (expect Ubuntu 26.04, resolute);
   timedatectl; locale; ip -br addr; nmcli -t -f ACTIVE,SSID dev wifi (Wi-Fi);
   sudo test ! -e /root/.not_logged_in_yet  (the presets file must be gone).
2. Update:  sudo apt update && sudo apt full-upgrade -y   (or armbian-config).
3. If an SSH key works for the user account, propose a drop-in
   /etc/ssh/sshd_config.d/10-hardening.conf with
     PasswordAuthentication no
     PermitRootLogin no
   Before reloading sshd, open a SECOND SSH session and keep it open, then
   `sudo sshd -t && sudo systemctl reload ssh`, and confirm a fresh key login
   works before closing the old session.
4. Ask whether the agent user should get passwordless sudo. Explain the trade
   off (convenient for an autonomous agent, but anyone with that SSH key
   becomes root). Only on an explicit yes, create
   /etc/sudoers.d/90-<user> with `<user> ALL=(ALL) NOPASSWD:ALL`, mode 440,
   checked with `sudo visudo -cf`.
5. Report what was done, the board's IP / hostname, and which secrets the user
   still has to store safely. Never include secret values in the report.
````

## Validate a config manually

```bash
cp config/not_logged_in_yet.example config/not_logged_in_yet
$EDITOR config/not_logged_in_yet
scripts/check-config.sh config/not_logged_in_yet
```

## Notes and gotchas

- `SET_LANG_BASED_ON_LOCATION` must be `Y` or `n`; `0` makes
  `armbian-firstlogin` loop forever.
- `PRESET_USER_SHELL` is `bash` or `zsh`, not `/bin/bash`.
- `PRESET_CONNECT_WIRELESS="n"` keeps the nmtui wizard from blocking the
  unattended run.
- Setting `PRESET_ROOT_PASSWORD` or `PRESET_USER_NAME` makes first login
  unattended; the four account values (root password, user name, user
  password, real name) must all be present or Armbian still prompts for them.
- Wi-Fi takes priority over Ethernet; a static IP applies to only one of them.
- Passwords and the Wi-Fi key are stored in plaintext on the media until first
  boot finishes; prefer an SSH key (`PRESET_USER_KEY`) and do not leave the
  card lying around.
- The whole config can also be served from a URL with
  `PRESET_CONFIGURATION="https://..."`, as the only line in the file.
