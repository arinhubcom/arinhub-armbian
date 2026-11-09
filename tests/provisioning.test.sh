#!/usr/bin/env bash
# Tests for config/provisioning.sh.example. Run: bash tests/provisioning.test.sh
# apt-get and hostnamectl are replaced by stubs on PATH, so nothing on this
# machine is installed or renamed.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE="$ROOT/config/provisioning.sh.example"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n%s\n' "$1" "${2:-}"; }

# Stubs record every call to $WORK/calls.
mkdir -p "$WORK/bin"
for cmd in apt-get hostnamectl; do
  printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\n' "$cmd" "$WORK" >"$WORK/bin/$cmd"
  chmod +x "$WORK/bin/$cmd"
done

# Write a script copy with the given hostname placeholder answer.
script_with() {
  local file="$WORK/provisioning-$1.sh"
  sed "s/__ASK_HOSTNAME__/$1/" "$EXAMPLE" >"$file"
  printf '%s' "$file"
}

# Run a script in a sandbox; extra args are passed to the script.
run() {
  local file="$1"; shift
  rm -f "$WORK/calls"
  printf '127.0.0.1 localhost\n127.0.1.1 oldname\n' >"$WORK/hosts"
  PATH="$WORK/bin:$PATH" HOSTS_FILE="$WORK/hosts" LOG_FILE="$WORK/log" \
    bash "$file" "$@" >"$WORK/out" 2>&1
}

# --- cases ---------------------------------------------------------------------
if bash -n "$EXAMPLE"; then ok "example has valid bash syntax"; else fail "example has valid bash syntax"; fi

if grep -q '"__ASK_HOSTNAME__"' "$EXAMPLE"; then ok "example asks for the hostname"
else fail "example asks for the hostname"; fi

if run "$EXAMPLE"; then fail "unfilled example refuses to run" "$(cat "$WORK/out")"
elif [ -e "$WORK/calls" ]; then fail "unfilled example changes nothing" "$(cat "$WORK/calls")"
else ok "unfilled example refuses to run and changes nothing"; fi

f="$(script_with Bad_Host)"
if run "$f" || [ -e "$WORK/calls" ]; then fail "invalid hostname is rejected before any change"
else ok "invalid hostname is rejected before any change"; fi

f="$(script_with -leading-dash)"
if run "$f"; then fail "hostname starting with a dash is rejected"
else ok "hostname starting with a dash is rejected"; fi

f="$(script_with armbian-01)"
if run "$f" --check && [ ! -e "$WORK/calls" ]; then ok "--check validates without changing anything"
else fail "--check validates without changing anything" "$(cat "$WORK/out" "$WORK/calls" 2>/dev/null)"; fi

if run "$f"; then ok "valid script runs"; else fail "valid script runs" "$(cat "$WORK/out")"; fi
if grep -q '^apt-get update' "$WORK/calls" && grep -q '^apt-get install -y .*htop' "$WORK/calls"; then
  ok "packages are installed"
else fail "packages are installed" "$(cat "$WORK/calls")"; fi
if grep -qx 'hostnamectl set-hostname armbian-01' "$WORK/calls"; then ok "hostname is set"
else fail "hostname is set" "$(cat "$WORK/calls")"; fi
if grep -qx '127.0.1.1 armbian-01' "$WORK/hosts" && ! grep -q oldname "$WORK/hosts"; then
  ok "hosts file maps the new hostname"
else fail "hosts file maps the new hostname" "$(cat "$WORK/hosts")"; fi
if grep -q 'Provisioning complete' "$WORK/log"; then ok "run is logged"
else fail "run is logged" "$(cat "$WORK/log" 2>/dev/null)"; fi

printf '127.0.0.1 localhost\n' >"$WORK/hosts"
PATH="$WORK/bin:$PATH" HOSTS_FILE="$WORK/hosts" LOG_FILE="$WORK/log" bash "$f" >/dev/null 2>&1
if grep -qx '127.0.1.1 armbian-01' "$WORK/hosts"; then ok "hosts entry is added when missing"
else fail "hosts entry is added when missing" "$(cat "$WORK/hosts")"; fi

printf '#!/bin/sh\nexit 1\n' >"$WORK/bin/apt-get"
if run "$f"; then fail "failing apt-get stops the script"
elif [ -e "$WORK/calls" ] && grep -q hostnamectl "$WORK/calls"; then fail "failing apt-get stops before hostname change"
else ok "failing apt-get stops the script"; fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
