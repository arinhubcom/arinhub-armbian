#!/usr/bin/env bash
# Tests for config/provisioning.sh.example. Run: bash tests/provisioning.test.sh
# Every system command (apt-get, hostnamectl, ufw, systemctl, sshd, visudo,
# chown, id) is a stub on PATH, and all files go to a sandbox TARGET_ROOT,
# so nothing on this machine changes.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE="$ROOT/config/provisioning.sh.example"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n%s\n' "$1" "${2:-}"; }
check() { if eval "$2"; then ok "$1"; else fail "$1" "${3:-}"; fi; }

command -v ssh-keygen >/dev/null || { echo "ssh-keygen is required"; exit 2; }
ssh-keygen -q -t ed25519 -N '' -C agent@workstation -f "$WORK/agent_key"
ssh-keygen -q -t ed25519 -N '' -C from-preset-user-key -f "$WORK/old_key"
TEST_KEY="$(cat "$WORK/agent_key.pub")"
OLD_KEY="$(cat "$WORK/old_key.pub")"

# --- stubs ----------------------------------------------------------------------
make_stubs() {
  rm -rf "$WORK/bin"; mkdir -p "$WORK/bin"
  local cmd
  for cmd in apt-get hostnamectl ufw systemctl sshd visudo chown fdfind; do
    printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\n' "$cmd" "$WORK" >"$WORK/bin/$cmd"
  done
  printf '#!/bin/sh\necho "sshd $*" >>"%s/calls"\n[ ! -e "%s/sshd_fail" ]\n' "$WORK" "$WORK" >"$WORK/bin/sshd"
  # id succeeds only for the test user.
  printf '#!/bin/sh\necho "id $*" >>"%s/calls"\n[ "$1" = test_user ]\n' "$WORK" >"$WORK/bin/id"
  chmod +x "$WORK/bin/"*
}

# --- sandbox --------------------------------------------------------------------
reset_root() {
  local r="$WORK/root"
  rm -rf "$r" "$WORK/calls" "$WORK/sshd_fail"
  mkdir -p "$r/etc/ssh/sshd_config.d" "$r/etc/sudoers.d" "$r/etc/needrestart/conf.d" \
    "$r/var/log" "$r/usr/local/bin" "$r/home/test_user/.ssh"
  printf '127.0.0.1 localhost\n127.0.1.1 oldname\n' >"$r/etc/hosts"
  printf 'PATH="/usr/bin"\n' >"$r/etc/environment"
  printf '%s\n' "$OLD_KEY" >"$r/home/test_user/.ssh/authorized_keys"
}

# Filled copy; args override answers: hostname user sudo harden key
script_with() {
  local file="$WORK/prov-$RANDOM.sh"
  sed -e "s|__ASK_HOSTNAME__|${1:-armbian-01}|" \
      -e "s|__ASK_USER_NAME__|${2:-test_user}|" \
      -e "s|__ASK_NOPASSWD_SUDO__|${3:-yes}|" \
      -e "s|__ASK_HARDEN_SSH__|${4:-yes}|" \
      -e "s|__ASK_OPTIONAL_SSH_PUBKEY__|${5-$TEST_KEY}|" \
      "$EXAMPLE" >"$file"
  printf '%s' "$file"
}

run() {
  local file="$1"; shift
  PATH="$WORK/bin:$PATH" TARGET_ROOT="$WORK/root" bash "$file" "$@" >"$WORK/out" 2>&1
}

calls() { cat "$WORK/calls" 2>/dev/null; }
R="$WORK/root"
make_stubs

# --- static ---------------------------------------------------------------------
check "example has valid bash syntax" 'bash -n "$EXAMPLE"'
for key in HOSTNAME USER_NAME NOPASSWD_SUDO HARDEN_SSH OPTIONAL_SSH_PUBKEY; do
  check "example asks for $key" "grep -q '\"__ASK_${key}__\"' \"\$EXAMPLE\""
done

# --- validation: nothing may change -----------------------------------------------
reset_root
check "unfilled example refuses to run" '! run "$EXAMPLE"'
check "unfilled example changes nothing" '[ ! -e "$WORK/calls" ]' "$(calls)"

for bad in "Bad_Host" "-dash"; do
  reset_root; f="$(script_with "$bad")"
  check "hostname '$bad' is rejected before any change" '! run "$f" && [ ! -e "$WORK/calls" ]' "$(calls)"
done

reset_root; f="$(script_with armbian-01 test_user maybe)"
check "sudo answer other than yes/no is rejected" '! run "$f"'

reset_root; f="$(script_with armbian-01 test_user yes perhaps)"
check "ssh hardening answer other than yes/no is rejected" '! run "$f"'

reset_root; f="$(script_with armbian-01 test_user yes yes 'not-a-key')"
check "malformed public key is rejected" '! run "$f" && [ ! -e "$WORK/calls" ]'

reset_root; f="$(script_with armbian-01 ghost)"
check "unknown user is rejected before any change" '! run "$f" && ! grep -qv "^id " "$WORK/calls"' "$(calls)"
check "rejection reason is written to the log" 'grep -q "does not exist" "$R/var/log/armbian-provisioning.log"' "$(cat "$R/var/log/armbian-provisioning.log" 2>/dev/null)"

# sed cannot put a newline into a value, so build this case with bash.
reset_root; f="$WORK/prov-multiline.sh"; content="$(cat "$(script_with)")"
printf '%s\n' "${content//"$TEST_KEY"/"$TEST_KEY"$'\n'"command=/bin/sh $TEST_KEY"}" >"$f"
check "multi-line test script really holds two key lines" '[ "$(grep -c "ssh-ed25519" "$f")" -ge 2 ] && bash -n "$f"'
check "multi-line public key is rejected" '! run "$f" && grep -q "not a single-line OpenSSH public key" "$WORK/out"' "$(cat "$WORK/out")"

reset_root; f="$(script_with armbian-01 ghost)"
check "--check does not need the user to exist on the workstation" 'run "$f" --check' "$(cat "$WORK/out")"

reset_root; f="$(script_with)"
check "--check validates without changing anything" 'run "$f" --check && ! grep -qv "^id " "$WORK/calls" 2>/dev/null' "$(cat "$WORK/out"; calls)"

# --- full run -----------------------------------------------------------------------
reset_root; f="$(script_with)"
check "valid script runs" 'run "$f"' "$(cat "$WORK/out")"
check "apt index is updated" 'grep -q "^apt-get .*update" "$WORK/calls"' "$(calls)"
check "apt waits for the dpkg lock" '! grep "^apt-get" "$WORK/calls" | grep -qv "DPkg::Lock::Timeout="' "$(calls)"
check "system is upgraded without config prompts" 'grep -q "^apt-get .*--force-confold.* upgrade" "$WORK/calls"' "$(calls)"
check "agent packages are installed" 'grep -q "^apt-get .*install .*ripgrep" "$WORK/calls"' "$(calls)"
check "nodejs is not installed" '! grep -q "nodejs" "$WORK/calls"'
check "hostname is set" 'grep -qx "hostnamectl set-hostname armbian-01" "$WORK/calls"'
check "hosts file maps the new hostname" 'grep -qx "127.0.1.1 armbian-01" "$R/etc/hosts" && ! grep -q oldname "$R/etc/hosts"' "$(cat "$R/etc/hosts")"
check "new key is added" 'grep -qxF "$TEST_KEY" "$R/home/test_user/.ssh/authorized_keys"'
check "key from PRESET_USER_KEY is kept" 'grep -qxF "$OLD_KEY" "$R/home/test_user/.ssh/authorized_keys"'
check "key ownership is fixed" 'grep -q "^chown -R test_user:test_user .*/home/test_user/.ssh" "$WORK/calls"' "$(calls)"
check "sudoers drop-in grants NOPASSWD" 'grep -qx "test_user ALL=(ALL) NOPASSWD:ALL" "$R/etc/sudoers.d/90-test_user-agent"'
check "sudoers drop-in is checked with visudo" 'grep -q "^visudo -cf" "$WORK/calls"'
check "sudoers drop-in has mode 440" '[ "$(stat -c %a "$R/etc/sudoers.d/90-test_user-agent")" = 440 ]'
check "sshd drop-in disables passwords" 'grep -qx "PasswordAuthentication no" "$R/etc/ssh/sshd_config.d/10-agent-hardening.conf"'
check "sshd drop-in disables root login" 'grep -qx "PermitRootLogin no" "$R/etc/ssh/sshd_config.d/10-agent-hardening.conf"'
check "sshd config is tested before reload" 'grep -q "^sshd -t" "$WORK/calls" && grep -q "^systemctl try-reload-or-restart ssh" "$WORK/calls"' "$(calls)"
check "firewall allows SSH and mDNS, then enables" 'grep -q "^ufw allow 22/tcp" "$WORK/calls" && grep -q "^ufw allow 5353/udp" "$WORK/calls" && grep -q "^ufw --force enable" "$WORK/calls"' "$(calls)"
check "DEBIAN_FRONTEND is set globally" 'grep -qx "DEBIAN_FRONTEND=noninteractive" "$R/etc/environment"'
check "needrestart restarts services without asking" 'grep -q "restart} = .a." "$R/etc/needrestart/conf.d/90-agent-no-prompt.conf"'
check "fd is linked to fdfind" '[ -L "$R/usr/local/bin/fd" ]'
check "run is logged" 'grep -q "Provisioning complete" "$R/var/log/armbian-provisioning.log"'

run "$f"
check "second run keeps a single key line" '[ "$(grep -cxF "$TEST_KEY" "$R/home/test_user/.ssh/authorized_keys")" = 1 ]'
check "second run keeps a single DEBIAN_FRONTEND line" '[ "$(grep -c DEBIAN_FRONTEND "$R/etc/environment")" = 1 ]'

# --- key edge cases --------------------------------------------------------------------
reset_root; printf '%s' "$OLD_KEY" >"$R/home/test_user/.ssh/authorized_keys"; f="$(script_with)"
run "$f"
check "key is added on its own line after a file without final newline" 'grep -qxF "$TEST_KEY" "$R/home/test_user/.ssh/authorized_keys" && grep -qxF "$OLD_KEY" "$R/home/test_user/.ssh/authorized_keys"' "$(cat "$R/home/test_user/.ssh/authorized_keys")"

reset_root; printf '<html>404 Not Found</html>\n' >"$R/home/test_user/.ssh/authorized_keys"
f="$(script_with armbian-01 test_user no yes '')"
check "runs when authorized_keys holds no valid key" 'run "$f"' "$(cat "$WORK/out")"
check "hardening is skipped when no key is valid" '[ ! -e "$R/etc/ssh/sshd_config.d/10-agent-hardening.conf" ]'

reset_root; touch "$WORK/sshd_fail"; f="$(script_with)"
check "failed sshd -t does not stop provisioning" 'run "$f" && grep -q "^ufw --force enable" "$WORK/calls"' "$(cat "$WORK/out"; calls)"
check "failed sshd -t removes the hardening drop-in" '[ ! -e "$R/etc/ssh/sshd_config.d/10-agent-hardening.conf" ]'
check "failed sshd -t is reported" 'grep -qi "sshd config test failed" "$WORK/out"' "$(cat "$WORK/out")"

reset_root; printf 'PATH="/usr/bin"' >"$R/etc/environment"; f="$(script_with)"
run "$f"
check "environment append keeps PATH on its own line" 'grep -qx "PATH=\"/usr/bin\"" "$R/etc/environment"' "$(cat "$R/etc/environment")"

# --- rerun with options switched off --------------------------------------------------
reset_root; run "$(script_with)"
f="$(script_with armbian-01 test_user no no '')"
check "rerun with sudo and hardening declined succeeds" 'run "$f"' "$(cat "$WORK/out")"
check "rerun with sudo declined removes the sudoers drop-in" '[ ! -e "$R/etc/sudoers.d/90-test_user-agent" ]'
check "rerun with hardening declined removes the sshd drop-in" '[ ! -e "$R/etc/ssh/sshd_config.d/10-agent-hardening.conf" ]'
check "removing the sshd drop-in reloads ssh" 'grep -q "^systemctl try-reload-or-restart ssh" "$WORK/calls"' "$(calls)"

# --- options off ----------------------------------------------------------------------
reset_root; f="$(script_with armbian-01 test_user no no '')"
check "runs with sudo, hardening and key declined" 'run "$f"' "$(cat "$WORK/out")"
check "no sudoers drop-in when declined" '[ ! -e "$R/etc/sudoers.d/90-test_user-agent" ]'
check "no sshd drop-in when declined" '[ ! -e "$R/etc/ssh/sshd_config.d/10-agent-hardening.conf" ]'

reset_root; rm -f "$R/home/test_user/.ssh/authorized_keys"; f="$(script_with armbian-01 test_user no yes '')"
check "hardening without any key still succeeds" 'run "$f"' "$(cat "$WORK/out")"
check "hardening is skipped without any key" '[ ! -e "$R/etc/ssh/sshd_config.d/10-agent-hardening.conf" ]'
check "skipped hardening is reported" 'grep -qi "skipping ssh hardening" "$WORK/out"' "$(cat "$WORK/out")"

# --- sourced by armbian-firstlogin ----------------------------------------------------
sourced() {
  PATH="$WORK/bin:$PATH" TARGET_ROOT="$WORK/root" bash -c '
    . "$1"
    echo "after-source"
    case $- in *e*) echo "LEAK errexit" ;; esac
    case $- in *u*) echo "LEAK nounset" ;; esac
    declare -F | grep -q " _armbian_provisioning$" && echo "LEAK function"
    true' _ "$1" >"$WORK/out" 2>&1
}
reset_root; f="$(script_with)"
sourced "$f"
check "sourcing returns to the caller" 'grep -q after-source "$WORK/out"' "$(cat "$WORK/out")"
check "sourcing leaks no shell options or functions" '! grep -q LEAK "$WORK/out"' "$(cat "$WORK/out")"
check "sourcing provisions the board" 'grep -qx "hostnamectl set-hostname armbian-01" "$WORK/calls"'

reset_root; printf '#!/bin/sh\nexit 1\n' >"$WORK/bin/apt-get"; chmod +x "$WORK/bin/apt-get"
sourced "$f"
check "failed provisioning does not abort the caller" 'grep -q after-source "$WORK/out"' "$(cat "$WORK/out")"
check "failed provisioning is reported to the caller" 'grep -q "Provisioning FAILED" "$WORK/out"' "$(cat "$WORK/out")"
check "sourced run stops at the failing step" '! grep -q "^ufw" "$WORK/calls"' "$(calls)"
reset_root
run "$f"; rc=$?
check "failing apt-get makes a direct run fail" '[ $rc -ne 0 ]'
check "failing apt-get stops before the firewall" '! grep -q "^ufw" "$WORK/calls"' "$(calls)"
make_stubs

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
