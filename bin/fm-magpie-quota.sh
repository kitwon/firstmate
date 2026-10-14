#!/usr/bin/env bash
# Read Magpie subscription windows for a provider=magpie dispatch profile.
#
# Usage:
#   fm-magpie-quota.sh <raw-json>
#   fm-magpie-quota.sh --read
#
# <raw-json> is one `magpie quota --json` document already captured.
# --read runs `magpie quota --json` itself. That command is the window list
# Magpie already holds (magpie quota --help). It is not quota reset, credits,
# auto-reset, accounts refresh, or accounts add.
#
# Output is one schema-6 snapshot the existing quota join already accepts,
# with a single unknown magpie row keyed `unattributed`. `magpie quota --json`
# on magpie 0.1.1230 names each subscription by `provider` and `user` and
# gives windows, but no stable account id and no field saying which
# subscription served a model. List order is not an id. The login is not
# copied and is not hashed into a key. Magpie does not publish spendPriority,
# so none is invented from remaining percent. Until a route names the
# account, every magpie profile is unknown and unranked. A native quota-axi
# row is not one of these accounts.
#
# This script does not source or change bin/fm-quota-axi-lib.sh. quota-axi
# stays the reader for every provider that is not magpie.
set -u

die() { printf 'error: %s\n' "$1" >&2; exit 2; }

usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "$0"
}

# jq program. Stdin is the raw Magpie array.
# shellcheck disable=SC2016 # jq program text, not shell expansion
normalize='
  def family_id($p):
    ($p | type) == "string" and ($p | test("^[a-z0-9]+(-[a-z0-9]+)*$"));
  if type != "array" then error("magpie quota is not an array") else . end |
  [ .[] | select(family_id(.provider // "")) ] as $rows |
  if ($rows | length) == 0 then error("magpie quota has no provider rows") else . end |
  {schemaVersion: 6, providers: [
    {provider: "magpie", accountKey: "unattributed",
     quotaSemantics: {status: "unknown", effectiveAvailability: [
       {scope: "all_models", status: "unknown", runway: {status: "unknown"}}]}}]}
'

read_raw=0
src=''
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --read) read_raw=1; shift ;;
    -*) die "unknown flag $1" ;;
    *) [ -z "$src" ] || die "one raw json file only"; src=$1; shift ;;
  esac
done

if [ "$read_raw" -eq 1 ]; then
  [ -z "$src" ] || die "--read takes no file"
  command -v magpie >/dev/null 2>&1 || die "magpie not installed"
  raw=$(mktemp) || die "mktemp failed"
  trap 'rm -f "$raw"' EXIT
  magpie quota --json > "$raw" 2>/dev/null || die "magpie quota --json failed"
  src=$raw
else
  [ -n "$src" ] || die "need a raw json file or --read"
  [ -f "$src" ] || die "not a file: $src"
fi

out=$(jq -ce "$normalize" "$src") || die "magpie quota --json returned an invalid snapshot"
printf '%s\n' "$out"
