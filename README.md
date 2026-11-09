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
| `"__ASK_<NAME>__"` | Required, sensitive or user-specific | Must ask the user |
| `"__ASK_OPTIONAL_<NAME>__"` | Optional | Must ask; if declined, deletes the whole line (`not_logged_in_yet`) or sets it to `""` (`provisioning.sh`) |
| any other value | Sensible default | Shows it once in a summary, keeps it unless the user changes it |

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
You are setting up a headless Armbian board running Ubuntu 26.04 LTS (resolute)
using the unattended first boot config in this repository. Reference:
https://docs.armbian.com/user-guide/autoconfig/

## Ground rules (security)
- Values marked "__ASK_<NAME>__" or "__ASK_OPTIONAL_<NAME>__" are sensitive or
  user-specific. NEVER guess, invent or reuse example values for them. Ask.
- Never echo a secret back, never print it in a summary, log, commit message
  or command line that ends up in shell history. Refer to it as "set" / "not set".
- The filled files go to config/not_logged_in_yet and config/provisioning.sh
  only. They are git-ignored; never commit them, never copy them anywhere else
  on this machine.
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
   or balenaEtcher) and come back. Recommend a minimal (server) image: on
   desktop images armbian-firstlogin may log the console out before it
   reaches the provisioning script.

## Step 1 - Fill the config
1. cp config/not_logged_in_yet.example config/not_logged_in_yet
   cp config/provisioning.sh.example config/provisioning.sh
2. List placeholders:
     grep -n '__ASK_' config/not_logged_in_yet config/provisioning.sh
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
   - __ASK_HOSTNAME__               hostname of the board (provisioning.sh):
                                    lowercase letters, digits, dashes, 1-63
                                    chars, no leading or trailing dash
   - __ASK_NOPASSWD_SUDO__          yes/no: may the agent user run sudo
                                    without a password? Explain: convenient
                                    for an autonomous agent (no hanging on a
                                    password prompt), but anyone with that
                                    user's SSH key becomes root
   - __ASK_HARDEN_SSH__             yes/no: disable SSH password login and
                                    root login? Applied only if the user has
                                    a valid SSH key. In mode A it needs a key
                                    THIS workstation holds (answer
                                    __ASK_OPTIONAL_SSH_PUBKEY__ with it), or
                                    you cannot connect after first boot
   - __ASK_OPTIONAL_SSH_PUBKEY__    one-line OpenSSH public key added for the
                                    agent user (provisioning.sh). In mode A
                                    offer this workstation's key, e.g.
                                    `cat ~/.ssh/id_ed25519.pub` (a public key
                                    is not a secret; never read a private key)
   - __ASK_ROOT_PASSWORD__          root password for emergency console access
   - __ASK_USER_PASSWORD__          password of the agent user (also used by sudo)
   - __ASK_OPTIONAL_USER_KEY_URL__  HTTPS URL with the user's SSH public key,
                                    e.g. https://github.com/<github-username>.keys
                                    Strongly recommended for mode A (or use
                                    __ASK_OPTIONAL_SSH_PUBKEY__ above).
   For both passwords offer to generate a strong one instead
   (e.g. `openssl rand -base64 24 | tr -d '/+='`); if the user accepts, write it
   into the file directly and tell them where to read it once
   (`grep PASSWORD config/not_logged_in_yet`) so they can store it in their
   password manager. Do not show it in chat.
4. Replace each placeholder with the answer. If the user declines an OPTIONAL
   one, delete that whole line in not_logged_in_yet, or set it to "" in
   provisioning.sh. Use the same user name in both files
   (__ASK_USER_NAME__ appears in both). For Ethernet only: set
   PRESET_NET_WIFI_ENABLED="0" and delete the SSID, KEY and COUNTRYCODE
   lines. For a static IP: uncomment the whole static block and ask for
   IP, mask, gateway and DNS.
5. Show ONE summary of the non-secret defaults and ask if any should change:
   locale (en_US.UTF-8), shell (bash), Ethernet fallback (on),
   IP mode (DHCP), and from provisioning.sh: UPGRADE_SYSTEM (yes),
   ENABLE_FIREWALL (yes: ufw denies incoming except SSH 22/tcp and mDNS
   5353/udp), PACKAGES (list them).
6. Validate both until each prints OK:
     scripts/check-config.sh config/not_logged_in_yet
     bash config/provisioning.sh --check
   Both print names only, never secret values. Fix each reported problem by
   asking the user again. `--check` validates only; it changes nothing. That
   the user exists is checked later on the board, before any change.

## Step 2 - Write it to the boot media
1. Run `lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS` and show the user which
   device you believe is the boot media. Get an explicit "yes" before mounting.
2. Mount the ext4 root partition (Armbian usually has one partition, e.g.
   /dev/sdX1) to a temporary directory, then:
     sudo install -m 600 -o root -g root config/not_logged_in_yet <mnt>/root/.not_logged_in_yet
     sudo install -m 700 -o root -g root config/provisioning.sh <mnt>/root/provisioning.sh
     sync && sudo umount <mnt>
3. Ask the user whether to delete the local filled config now (recommended once
   the board is up) or keep it until Step 3 is verified.

## Step 3 - First boot
1. Tell the user to insert the media and power the board on. First boot
   resizes the filesystem and runs the first login setup; allow 3-5 minutes,
   one reboot is normal.
2. Find the board's IP: try `ping <hostname>.local` (provisioning sets the
   hostname and installs avahi-daemon; allow a few more minutes for the
   package upgrade), ask the user to check the router's DHCP leases, or use
   the static IP if one was set.
3. Mode A: connect with `ssh <user>@<ip>` using the key from
   __ASK_OPTIONAL_SSH_PUBKEY__. Without hardening the user's password also
   works - let the user type it, or use ssh-agent.
   Mode B: the user logs in locally or over SSH once and installs Claude Code
   on the board:  curl -fsSL https://claude.ai/install.sh | bash
   then runs `claude` and completes the login themselves.

## Step 4 - Verify (read-only; ask before any change)
1. Verify:  cat /etc/os-release  (expect Ubuntu 26.04, resolute);
   timedatectl; locale; ip -br addr; nmcli -t -f ACTIVE,SSID dev wifi (Wi-Fi);
   sudo test ! -e /root/.not_logged_in_yet  (the presets file must be gone);
   hostnamectl --static  (expect the chosen hostname);
   sudo tail -n 20 /var/log/armbian-provisioning.log  (expect
   "Provisioning complete"). If provisioning failed, show the log, fix the
   cause (usually no network yet) and, after the user agrees, rerun it with
   `sudo bash /root/provisioning.sh` or a copy from this repository.
2. Verify what provisioning configured:
   sudo -n true  (succeeds only with passwordless sudo, if chosen);
   sudo sshd -T | grep -E '^(passwordauthentication|permitrootlogin) '
   (expect "no" for both if hardening was chosen and a key existed; the log
   says "skipping SSH hardening" if no valid key was found);
   sudo ufw status verbose  (if the firewall was enabled);
   command -v rg fd jq tmux.
3. To change the SSH or sudo setup later, edit config/provisioning.sh, copy it
   to the board and rerun it with `sudo bash /root/provisioning.sh` after the
   user agrees. Answering "no" removes the sudo or SSH drop-in again. Set
   UPGRADE_SYSTEM="no" for such a rerun to skip the full package upgrade. Before any SSH change, keep a second SSH session open and
   confirm a fresh key login works before closing it.
4. Report what was done, the board's IP / hostname, and which secrets the user
   still has to store safely. Never include secret values in the report.
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
- `armbian-firstlogin` sources `/root/provisioning.sh` (`. /root/provisioning.sh`)
  once, as root, at the end of the first successful login. The template then
  re-runs itself as a separate `bash` process, so its `set -euo pipefail` and
  `exit` cannot affect `armbian-firstlogin`, and a failure is only reported.
- Provisioning stops on the first error and logs to
  `/var/log/armbian-provisioning.log`; failed steps are not retried
  automatically. All steps are safe to rerun; a rerun with `no` for sudo or
  SSH hardening removes the drop-in it created earlier.
- Errors, including rejected settings, go to that log too. apt waits up to
  10 minutes for the dpkg lock, which `apt-daily` often holds after first boot.
- SSH hardening is applied only if `ssh-keygen -lf` finds a valid key in
  `authorized_keys`: `armbian-firstlogin` downloads `PRESET_USER_KEY` with
  `curl` without `--fail`, so a wrong URL stores an HTML error page there.
  If `sshd -t` fails, the drop-in is removed and password login stays on.
- On desktop images `armbian-firstlogin` may log the console out before it
  reaches the provisioning script; use a minimal (server) image.
- Local steps (hostname, SSH key, sudo, SSH hardening) run before the
  network-dependent ones (apt, firewall), so a missing network leaves the
  board reachable.
- The Ubuntu sources in Armbian images for `resolute` already enable
  `main restricted universe multiverse`, so no `add-apt-repository` is needed.
- Claude Code's native installer ships an arm64 binary and needs no Node.js.
- The whole config can also be served from a URL with
  `PRESET_CONFIGURATION="https://..."`, as the only line in the file.
