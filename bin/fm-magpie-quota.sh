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
# spendPriority is not read off remaining percent.
# When quota-axi meets the floor in bin/fm-quota-axi-lib.sh, a measured
# subscription gets that package's computeWindowPace, computeEffectiveRunway,
# and summarizeEffectiveSelection.
# The labels "5 hours" and "7 days" use that package's 18000s and 604800s
# durations.
# "Month" and "month_total" get a calendar-month start only for opencode-go and
# kimi, the providers whose own adapters already derive one.
# Any other label, a missing readAt, or an unmeasurable bound leaves selection
# unknown.
# An exhausted window still blocks the route.
# A native quota-axi row is not one of these accounts.
# FM_MAGPIE_DISABLE_PACE=1 skips the calculator.
# FM_QUOTA_PACE_MODULE names pace.js when a test must pin it.
# command -v quota-axi is used when it meets the floor; otherwise a Volta image
# package of quota-axi is used when that one meets the floor.
#
# Diagnostics stay on stderr, apart from the snapshot. This script does not
# source or change bin/fm-quota-axi-lib.sh. quota-axi stays the reader for every
# provider that is not magpie.
set -u

SCRIPT_DIR=$(CDPATH='' cd -P "$(dirname "$0")" && pwd -P) || exit 2

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

version_ge() {
  # True when $1 is a version and it is greater than or equal to $2.
  [ -n "$1" ] && [ -n "$2" ] || return 1
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]
}

pace_floor() {
  awk -F= '/^FM_QUOTA_AXI_MIN=/{print $2; exit}' "$SCRIPT_DIR/fm-quota-axi-lib.sh"
}

pace_from_root() {
  local root=$1 floor ver pace
  [ -f "$root/package.json" ] && [ -f "$root/dist/src/pace.js" ] || return 1
  floor=$(pace_floor)
  ver=$(jq -r '.version // empty' "$root/package.json" 2>/dev/null) || return 1
  version_ge "$ver" "$floor" || return 1
  pace=$root/dist/src/pace.js
  [ -f "$root/dist/src/lib/time.js" ] || return 1
  printf '%s\n' "$pace"
}

# Prints the pace.js path, or fails when no floor-meeting calculator is present.
fm_magpie_pace_module() {
  local bin root volta
  [ "${FM_MAGPIE_DISABLE_PACE:-}" = 1 ] && return 1
  if [ -n "${FM_QUOTA_PACE_MODULE:-}" ]; then
    [ -f "$FM_QUOTA_PACE_MODULE" ] || return 1
    printf '%s\n' "$FM_QUOTA_PACE_MODULE"
    return 0
  fi
  bin=$(command -v quota-axi 2>/dev/null || true)
  if [ -n "$bin" ]; then
    bin=$(readlink -f "$bin" 2>/dev/null || true)
    if [ -n "$bin" ] && [ -f "$bin" ]; then
      root=$(CDPATH='' cd -P "$(dirname "$bin")/../.." 2>/dev/null && pwd -P) || root=''
      if [ -n "$root" ] && pace_from_root "$root"; then
        return 0
      fi
    fi
  fi
  volta=${VOLTA_HOME:-$HOME/.volta}
  pace_from_root "$volta/tools/image/packages/quota-axi/lib/node_modules/quota-axi"
}

# Attach quota-axi pace, runway, and selection to measured rows. Stdin snapshot.
attach_selection() {
  local pace snap enriched
  pace=$(fm_magpie_pace_module) || {
    cat
    return 0
  }
  snap=$(mktemp) || die "mktemp failed"
  cat > "$snap"
  enriched=$(node --input-type=module - "$pace" "$snap" <<'JS'
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";

const pacePath = process.argv[2];
const snap = JSON.parse(readFileSync(process.argv[3], "utf8"));
const pace = await import(pathToFileURL(pacePath).href);
const time = await import(pathToFileURL(join(dirname(pacePath), "lib/time.js")).href);
const { computeWindowPace, computeEffectiveRunway, summarizeEffectiveSelection } = pace;
const { calendarMonthsBefore } = time;
const FIVE_HOURS_SECONDS = 18000;
const WEEK_SECONDS = 604800;
const calendarMonthProviders = new Set(["opencode-go", "kimi"]);

function clockOk(value) {
  return typeof value === "string" && Number.isFinite(Date.parse(value));
}

function builtWindow(provider, window, index) {
  const name = typeof window.name === "string" ? window.name : "";
  const built = {
    id: `${name}#${index}`,
    percentRemaining: window.remaining,
    percentUsed: window.used,
  };
  if (typeof window.resetsAt === "string" && window.resetsAt !== "") {
    built.resetsAt = window.resetsAt;
  }
  if (name === "5 hours") built.windowSeconds = FIVE_HOURS_SECONDS;
  else if (name === "7 days") built.windowSeconds = WEEK_SECONDS;
  else if (calendarMonthProviders.has(provider) && (name === "Month" || name === "month_total") && built.resetsAt) {
    const startsAt = calendarMonthsBefore(built.resetsAt, 1);
    if (startsAt) built.startsAt = startsAt;
  }
  return built;
}

function runwayOf(window, generatedAt) {
  const runway = computeEffectiveRunway([window], generatedAt ?? "");
  const out = { status: runway.status };
  if (typeof runway.usableRunwaySeconds === "number") out.usableRunwaySeconds = runway.usableRunwaySeconds;
  if (typeof runway.projectedExhaustedAt === "string") out.projectedExhaustedAt = runway.projectedExhaustedAt;
  if (typeof runway.limitingWindowId === "string") out.limitingWindowId = runway.limitingWindowId;
  return out;
}

function annotate(provider) {
  const semantics = provider.quotaSemantics;
  if (!semantics || semantics.status !== "known" || !Array.isArray(semantics.effectiveAvailability)) {
    return provider;
  }
  const sub = Array.isArray(provider.subscriptions) ? provider.subscriptions[0] : undefined;
  const raw = Array.isArray(sub?.windows) ? sub.windows : [];
  const generatedAt = clockOk(sub?.readAt) ? sub.readAt : undefined;
  const paced = raw.map((window, index) => {
    const built = builtWindow(provider.provider, window, index);
    return {
      ...built,
      pace: generatedAt ? computeWindowPace(built, generatedAt) : { status: "unknown", reason: "invalid_cycle" },
    };
  });
  const selection = generatedAt
    ? summarizeEffectiveSelection(paced)
    : { status: "unknown" };
  const published = selection.status === "known" && typeof selection.spendPriority === "number"
    ? { status: "known", spendPriority: selection.spendPriority }
    : {
        status: "unknown",
        ...(Array.isArray(selection.unmeasurableWindowIds) && selection.unmeasurableWindowIds.length > 0
          ? { unmeasurableWindowIds: selection.unmeasurableWindowIds }
          : {}),
      };
  return {
    ...provider,
    quotaSemantics: {
      ...semantics,
      effectiveAvailability: semantics.effectiveAvailability.map((row, index) => ({
        ...row,
        runway: runwayOf(paced[index] ?? { id: `window#${index}`, percentRemaining: row.effectivePercentRemaining }, generatedAt),
        selection: published,
      })),
    },
  };
}

process.stdout.write(`${JSON.stringify({ ...snap, providers: (snap.providers ?? []).map(annotate) })}\n`);
JS
) || {
    rm -f "$snap"
    die "magpie spendPriority calculator failed"
  }
  rm -f "$snap"
  printf '%s\n' "$enriched"
}

read_raw=0
src=''
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --print-pace-module) fm_magpie_pace_module || true; exit 0 ;;
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
printf '%s\n' "$out" | attach_selection
