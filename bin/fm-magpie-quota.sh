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
# Output is one schema-6 snapshot the existing quota join already accepts:
# provider magpie, one row per subscription in list order (codex-1, codex-2).
# The login is not the key and is not copied. Percentages are not summed
# across accounts. A row with an error or no windows is unknown. Remaining
# percent is that account's tightest window. Magpie does not publish
# spendPriority; the scalar is the mean remaining fraction, and only when
# every window is above zero. It is headroom, not pace.
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
  def window_known:
    (.used | type) == "number" and (.remaining | type) == "number" and
    .remaining >= 0 and .remaining <= 100 and .used >= 0;
  def family_id($p):
    ($p | type) == "string" and ($p | test("^[a-z0-9]+(-[a-z0-9]+)*$"));
  def one($entry; $family; $index):
    ([($entry.windows // [])[] | select(window_known)]) as $known |
    (if ($entry.error | type) == "string" and ($entry.error | length) > 0 then true else false end) as $errored |
    {provider: "magpie", accountKey: ($family + "-" + ($index | tostring)),
     quotaSemantics: (
       if ($known | length) == 0 then
         {status: "unknown", effectiveAvailability: [
           {scope: "all_models", status: "unknown", runway: {status: "unknown"}}]}
       else
         ($known | min_by(.remaining)) as $tight |
         {status: "known",
          effectiveAvailability: [{
            scope: "all_models",
            status: "known",
            effectivePercentRemaining: $tight.remaining,
            runway: {status: (if $tight.remaining <= 0 then "exhausted_now" else "through_reset" end)},
            selection: (
              if $errored or any($known[]; .remaining <= 0) then {}
              else {spendPriority: (($known | map(.remaining) | add) / (($known | length) * 100))}
              end)
          }]}
       end)};
  if type != "array" then error("magpie quota is not an array") else . end |
  reduce .[] as $entry ({n: {}, rows: []};
    ($entry.provider // "") as $family |
    if family_id($family) | not then .
    else .n[$family] = ((.n[$family] // 0) + 1) |
         .rows += [one($entry; $family; .n[$family])]
    end) |
  if (.rows | length) == 0 then error("magpie quota has no provider rows") else . end |
  {schemaVersion: 6, providers: .rows}
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
