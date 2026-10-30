#!/usr/bin/env bash
# Read Magpie subscription windows for a provider=magpie dispatch profile.
#
# Usage:
#   fm-magpie-quota.sh <raw-json>
#   fm-magpie-quota.sh --read
#
# <raw-json> is one `magpie quota --json` document already captured.
# --read asks Magpie for current vendor quota (subject to its short cache).
# It does not change reset, credits, auto-reset, or account settings.
# Magpie diagnostics remain on stderr, separate from the JSON snapshot.
#
# Output is one schema-6 snapshot the existing quota join already accepts,
# with one row per Magpie subscription provider, keyed `default`. A Magpie
# route names that provider as magpie/<real provider>/<model>, so a row
# supplies exactly that route's windows. A provider Magpie reports once binds
# its real windows; a provider it reports more than once cannot be attributed
# to the subscription that would serve a request, so that provider stays
# unknown and unmeasured. `subscriptions` always preserves every subscription's
# provider, plan, windows, balance, read errors and freshness as observational
# evidence, without logins or nested usage/reset history.
#
# Magpie names each subscription by `provider` and `user` and gives windows, but
# no stable account id and no field saying which subscription served a model.
# List order is not an id. The login is not copied and is not hashed into a key.
# Magpie does not publish spendPriority, so none is invented from remaining
# percent: real windows decide a route's eligibility, never its economics, and
# an exhausted applicable window blocks that route. A native quota-axi row is
# not one of these accounts.
#
# Diagnostics stay on stderr, apart from the snapshot. This script does not
# source or change bin/fm-quota-axi-lib.sh. quota-axi stays the reader for every
# provider that is not magpie.
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
  def fields($names): with_entries(select(.key as $k | $names | index($k)));
  def evidence:
    fields(["provider", "kind", "plan", "balance", "readAt", "error", "lastServedAt", "last", "windows"])
    | if has("windows") then
        .windows |= map(fields(["name", "used", "remaining", "resetsAt"]))
      else . end;
  def measured: (.remaining | type) == "number" and .remaining >= 0 and .remaining <= 100;
  # One unknown all_models bound plus the note that says why. A window Magpie
  # could not read stays uncertainty rather than an implied healthy allowance.
  def unmeasured($provider; $subs; $note):
    {provider: $provider, accountKey: "default", note: $note, subscriptions: $subs,
     quotaSemantics: {status: "unknown", effectiveAvailability: [
       {scope: "all_models", status: "unknown", runway: {status: "unknown"}}]}};
  def measured_row($provider; $subs; $windows):
    {provider: $provider, accountKey: "default", subscriptions: $subs,
     quotaSemantics: {status: "known", effectiveAvailability: ($windows | map(
       {scope: "all_models", status: "known", effectivePercentRemaining: .remaining,
        runway: {status: "unknown"}}
       + (if .name then {window: .name} else {} end)
       + (if .resetsAt then {resetsAt: .resetsAt} else {} end)))}};
  def provider_row:
    (.[0].provider) as $p | (map(evidence) | sort_by(tojson)) as $subs |
    [$subs[] | .windows[]? | select(measured)] as $windows |
    if ($subs | length) != 1 then
      unmeasured($p; $subs; "\($subs | length) subscriptions named \($p); magpie reports no stable account id")
    elif (($subs[0].error // "") | length) > 0 then
      unmeasured($p; $subs; "subscription read failed: \($subs[0].error)")
    elif ($windows | length) == 0 then
      unmeasured($p; $subs; "subscription publishes no percentage window")
    elif ($windows | length) != (($subs[0].windows // []) | length) then
      unmeasured($p; $subs; "a subscription window publishes no remaining percentage")
    else measured_row($p; $subs; $windows) end;
  if type != "array" then error("magpie quota is not an array") else . end |
  [ .[] | select(type == "object") | select(family_id(.provider // "")) ] as $rows |
  if ($rows | length) == 0 then error("magpie quota has no provider rows") else . end |
  {schemaVersion: 6, providers: ([$rows | group_by(.provider)[]] | sort_by(.[0].provider) | map(provider_row))}
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
  magpie quota --json > "$raw" || die "magpie quota --json failed"
  src=$raw
else
  [ -n "$src" ] || die "need a raw json file or --read"
  [ -f "$src" ] || die "not a file: $src"
fi

out=$(jq -ce "$normalize" "$src") || die "magpie quota --json returned an invalid snapshot"
printf '%s\n' "$out"
