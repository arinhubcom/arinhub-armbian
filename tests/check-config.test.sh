#!/usr/bin/env bash
# Tests for scripts/check-config.sh. Run: bash tests/check-config.test.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/scripts/check-config.sh"
EXAMPLE="$ROOT/config/not_logged_in_yet.example"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

# Build a fully filled config from the example with test-only values.
filled() {
  sed \
    -e 's/__ASK_WIFI_SSID__/TestNet/' \
    -e 's/__ASK_WIFI_KEY__/test-wifi-key-123/' \
    -e 's/__ASK_ROOT_PASSWORD__/test-root-pass-123/' \
    -e 's/__ASK_USER_PASSWORD__/test-user-pass-123/' \
    -e 's#__ASK_OPTIONAL_USER_KEY_URL__#https://github.com/example.keys#' \
    -e 's/__ASK_WIFI_COUNTRYCODE__/CZ/' \
    -e 's#__ASK_TIMEZONE__#Europe/Prague#' \
    -e 's/__ASK_USER_NAME__/test_user/' \
    -e 's/__ASK_REALNAME__/Test Agent/' \
    "$EXAMPLE"
}

expect() {
  local want="$1" name="$2" file="$3"
  local out rc
  out="$(bash "$CHECK" "$file" 2>&1)"
  rc=$?
  if { [ "$want" = ok ] && [ $rc -eq 0 ]; } || { [ "$want" = fail ] && [ $rc -ne 0 ]; }; then
    PASS=$((PASS + 1))
    printf 'ok   %s\n' "$name"
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL %s (rc=%s)\n%s\n' "$name" "$rc" "$out"
  fi
}

case_file() { printf '%s/%s' "$WORK" "$1"; }

# --- cases ---------------------------------------------------------------------
expect fail "unfilled example is rejected" "$EXAMPLE"

f="$(case_file valid)"; filled >"$f"
expect ok "filled example passes" "$f"

for key in WIFI_COUNTRYCODE TIMEZONE USER_NAME REALNAME; do
  if grep -q "\"__ASK_${key}__\"" "$EXAMPLE"; then
    PASS=$((PASS + 1)); printf 'ok   example asks for %s\n' "$key"
  else
    FAIL=$((FAIL + 1)); printf 'FAIL example does not ask for %s\n' "$key"
  fi
done

f="$(case_file bad-country)"; filled | sed 's/^PRESET_NET_WIFI_COUNTRYCODE=.*/PRESET_NET_WIFI_COUNTRYCODE="cz"/' >"$f"
expect fail "lowercase country code is rejected" "$f"

# Membership is checked against tzdata's ISO 3166 table, as timezones are.
if [ -f /usr/share/zoneinfo/iso3166.tab ]; then
  for code in UK ZZ; do
    f="$(case_file "country-$code")"; filled | sed "s/^PRESET_NET_WIFI_COUNTRYCODE=.*/PRESET_NET_WIFI_COUNTRYCODE=\"$code\"/" >"$f"
    expect fail "unassigned country code $code is rejected" "$f"
  done
else
  printf 'skip country code membership: no /usr/share/zoneinfo/iso3166.tab\n'
fi
f="$(case_file country-GB)"; filled | sed 's/^PRESET_NET_WIFI_COUNTRYCODE=.*/PRESET_NET_WIFI_COUNTRYCODE="GB"/' >"$f"
expect ok "assigned country code GB passes" "$f"

f="$(case_file bad-tz)"; filled | sed 's#^PRESET_TIMEZONE=.*#PRESET_TIMEZONE="Europe/Nowhere"#' >"$f"
expect fail "unknown timezone is rejected" "$f"

f="$(case_file empty-realname)"; filled | sed 's/^PRESET_DEFAULT_REALNAME=.*/PRESET_DEFAULT_REALNAME=""/' >"$f"
expect fail "empty real name is rejected" "$f"

f="$(case_file no-key)"; filled | sed '/^PRESET_USER_KEY=/d' >"$f"
expect ok "optional key line may be deleted" "$f"

f="$(case_file optional-left)"; filled | sed 's#^PRESET_USER_KEY=.*#PRESET_USER_KEY="__ASK_OPTIONAL_USER_KEY_URL__"#' >"$f"
expect fail "unanswered optional placeholder is rejected" "$f"

f="$(case_file dollar)"; filled | sed 's/test-user-pass-123/pa$$word/' >"$f"
expect fail "dollar sign in value is rejected" "$f"

f="$(case_file quote)"; filled | sed 's/test-root-pass-123/pa"ss/' >"$f"
expect fail "double quote in value is rejected" "$f"

f="$(case_file backtick)"; filled | sed 's/test-root-pass-123/pa`id`ss/' >"$f"
expect fail "backtick in value is rejected" "$f"

f="$(case_file short-psk)"; filled | sed 's/test-wifi-key-123/short/' >"$f"
expect fail "Wi-Fi key shorter than 8 chars is rejected" "$f"

f="$(case_file lang-zero)"; filled | sed 's/^SET_LANG_BASED_ON_LOCATION=.*/SET_LANG_BASED_ON_LOCATION="0"/' >"$f"
expect fail "SET_LANG_BASED_ON_LOCATION=0 is rejected" "$f"

f="$(case_file shell-path)"; filled | sed 's#^PRESET_USER_SHELL=.*#PRESET_USER_SHELL="/bin/bash"#' >"$f"
expect fail "shell given as path is rejected" "$f"

f="$(case_file bad-user)"; filled | sed 's/^PRESET_USER_NAME=.*/PRESET_USER_NAME="Root User"/' >"$f"
expect fail "invalid user name is rejected" "$f"

f="$(case_file no-root)"; filled | sed '/^PRESET_ROOT_PASSWORD=/d' >"$f"
expect fail "missing root password is rejected" "$f"

f="$(case_file connect-y)"; filled | sed 's/^PRESET_CONNECT_WIRELESS=.*/PRESET_CONNECT_WIRELESS="Y"/' >"$f"
expect fail "interactive Wi-Fi wizard is rejected" "$f"

f="$(case_file http-key)"; filled | sed 's#https://github.com/example.keys#http://example.com/key#' >"$f"
expect fail "non-HTTPS key URL is rejected" "$f"

f="$(case_file eth-only)"; filled | sed \
  -e 's/^PRESET_NET_WIFI_ENABLED=.*/PRESET_NET_WIFI_ENABLED="0"/' \
  -e '/^PRESET_NET_WIFI_SSID=/d' -e '/^PRESET_NET_WIFI_KEY=/d' >"$f"
expect ok "Ethernet-only config passes without Wi-Fi values" "$f"

f="$(case_file static-partial)"; filled | sed 's/^# PRESET_NET_USE_STATIC=/PRESET_NET_USE_STATIC=/' >"$f"
expect fail "static IP without addresses is rejected" "$f"

f="$(case_file static-full)"; filled | sed 's/^# \(PRESET_NET_\(USE_\)\{0,1\}STATIC\)/\1/' >"$f"
expect ok "complete static IP config passes" "$f"

expect fail "missing file is rejected" "$WORK/does-not-exist"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
