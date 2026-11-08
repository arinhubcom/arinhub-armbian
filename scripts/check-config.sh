#!/usr/bin/env bash
# Validate a filled-in Armbian first boot config before it is copied to
# /root/.not_logged_in_yet. The file is parsed as text and NEVER sourced,
# so a malicious or broken value cannot execute here.
#
# Usage: scripts/check-config.sh <path-to-filled-config>
# Exit:  0 = valid, 1 = problems found (listed on stderr), 2 = usage error.
# Secret values are never printed, only key names.
set -u

FILE="${1:-}"
if [ -z "$FILE" ]; then
  echo "usage: $0 <path-to-filled-config>" >&2
  exit 2
fi
if [ ! -f "$FILE" ]; then
  echo "error: file not found: $FILE" >&2
  exit 2
fi

declare -A CFG=()
ERRORS=()

err() { ERRORS+=("$1"); }

# --- parse ---------------------------------------------------------------------
LINE_RE='^([A-Z_][A-Z0-9_]*)="([^"]*)"[[:space:]]*(#.*)?$'
lineno=0
while IFS= read -r line || [ -n "$line" ]; do
  lineno=$((lineno + 1))
  trimmed="${line#"${line%%[![:space:]]*}"}"
  [ -z "$trimmed" ] && continue
  [ "${trimmed:0:1}" = "#" ] && continue
  if [[ "$trimmed" =~ $LINE_RE ]]; then
    CFG["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
  else
    err "line $lineno: not in KEY=\"value\" form (or value contains a double quote)"
  fi
done <"$FILE"

has() { [ -n "${CFG[$1]+x}" ]; }
val() { printf '%s' "${CFG[$1]-}"; }

require() {
  local key
  for key in "$@"; do
    if ! has "$key" || [ -z "$(val "$key")" ]; then
      err "$key: required but missing or empty"
    fi
  done
}

# --- generic value checks --------------------------------------------------------
for key in "${!CFG[@]}"; do
  v="${CFG[$key]}"
  if [[ "$v" == *__ASK_* ]]; then
    err "$key: placeholder not answered yet"
  fi
  if [[ "$v" == *'$'* || "$v" == *'`'* || "$v" == *'\'* ]]; then
    err "$key: contains \$, backtick or backslash (Armbian sources this file as shell)"
  fi
done

# --- accounts ---------------------------------------------------------------------
require PRESET_ROOT_PASSWORD PRESET_USER_NAME PRESET_USER_PASSWORD PRESET_DEFAULT_REALNAME

if has PRESET_USER_NAME && ! [[ "$(val PRESET_USER_NAME)" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  err "PRESET_USER_NAME: must match ^[a-z_][a-z0-9_-]{0,31}\$"
fi
if has PRESET_USER_NAME && [ "$(val PRESET_USER_NAME)" = root ]; then
  err "PRESET_USER_NAME: must not be root"
fi
if has PRESET_USER_SHELL && ! [[ "$(val PRESET_USER_SHELL)" =~ ^(bash|zsh)$ ]]; then
  err "PRESET_USER_SHELL: must be bash or zsh (not a path)"
fi

for key in PRESET_USER_KEY PRESET_ROOT_KEY; do
  if has "$key" && ! [[ "$(val "$key")" =~ ^https://[^[:space:]]+$ ]]; then
    err "$key: must be an https:// URL (or delete the line)"
  fi
done

# --- locale -----------------------------------------------------------------------
if has SET_LANG_BASED_ON_LOCATION && ! [[ "$(val SET_LANG_BASED_ON_LOCATION)" =~ ^[YyNn]$ ]]; then
  err "SET_LANG_BASED_ON_LOCATION: must be Y or n (other values loop forever)"
fi
if has PRESET_TIMEZONE && [ -d /usr/share/zoneinfo ] \
  && [ ! -f "/usr/share/zoneinfo/$(val PRESET_TIMEZONE)" ]; then
  err "PRESET_TIMEZONE: unknown timezone"
fi

# --- network ----------------------------------------------------------------------
if [ "$(val PRESET_NET_WIFI_ENABLED)" = 1 ]; then
  require PRESET_NET_WIFI_SSID PRESET_NET_WIFI_KEY PRESET_NET_WIFI_COUNTRYCODE
  psk="$(val PRESET_NET_WIFI_KEY)"
  if has PRESET_NET_WIFI_KEY && { [ "${#psk}" -lt 8 ] || [ "${#psk}" -gt 63 ]; }; then
    err "PRESET_NET_WIFI_KEY: WPA-PSK must be 8-63 characters"
  fi
  if has PRESET_NET_WIFI_COUNTRYCODE && ! [[ "$(val PRESET_NET_WIFI_COUNTRYCODE)" =~ ^[A-Z]{2}$ ]]; then
    err "PRESET_NET_WIFI_COUNTRYCODE: must be two uppercase letters (ISO 3166)"
  fi
  if [ "$(val PRESET_CONNECT_WIRELESS)" != n ]; then
    err "PRESET_CONNECT_WIRELESS: must be n for an unattended boot"
  fi
fi

IPV4_RE='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
if [ "$(val PRESET_NET_USE_STATIC)" = 1 ]; then
  require PRESET_NET_STATIC_IP PRESET_NET_STATIC_MASK PRESET_NET_STATIC_GATEWAY PRESET_NET_STATIC_DNS
  for key in PRESET_NET_STATIC_IP PRESET_NET_STATIC_MASK PRESET_NET_STATIC_GATEWAY; do
    if has "$key" && ! [[ "$(val "$key")" =~ $IPV4_RE ]]; then
      err "$key: not a valid IPv4 address"
    fi
  done
fi

# --- report -----------------------------------------------------------------------
if [ "${#ERRORS[@]}" -gt 0 ]; then
  printf 'INVALID: %s\n' "$FILE" >&2
  printf '  - %s\n' "${ERRORS[@]}" >&2
  exit 1
fi
printf 'OK: %s\n' "$FILE"
