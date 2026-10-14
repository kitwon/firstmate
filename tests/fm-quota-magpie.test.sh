#!/usr/bin/env bash
# Behavior of bin/fm-magpie-quota.sh, the Magpie quota reader.
# Fixtures only. No live magpie process and no credential read.
# bin/fm-quota-axi-lib.sh must stay byte-identical to HEAD.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TOOL="$ROOT/bin/fm-magpie-quota.sh"
TMP_ROOT=$(fm_test_tmproot fm-quota-magpie)
chmod +x "$TOOL"

git -C "$ROOT" diff --exit-code -- bin/fm-quota-axi-lib.sh \
  || fail "the quota-axi library must stay untouched"
pass "quota-axi library is untouched"

cat > "$TMP_ROOT/ok.json" <<'JSON'
[
  {"provider":"codex","user":"hidden-one","windows":[],"error":"Unauthorized"},
  {"provider":"codex","user":"hidden-two","windows":[{"name":"5 hours","used":5,"remaining":95}]},
  {"provider":"grok","windows":[{"name":"7 days","used":14,"remaining":86}]},
  {"provider":"opencode-go","windows":[
    {"name":"5 hours","used":0,"remaining":100},
    {"name":"7 days","used":40,"remaining":60}
  ]},
  {"provider":"not a key","windows":[{"used":1,"remaining":99}]}
]
JSON
if ! "$TOOL" "$TMP_ROOT/ok.json" > "$TMP_ROOT/out.json" 2>"$TMP_ROOT/err"; then
  fail "a valid magpie document must normalize: $(cat "$TMP_ROOT/err")"
fi
# shellcheck source=bin/fm-quota-axi-lib.sh
. "$ROOT/bin/fm-quota-axi-lib.sh"
fm_quota_json_valid < "$TMP_ROOT/out.json" || fail "normalized magpie snapshot must validate as schema 6"
jq -e '
  .schemaVersion == 6 and
  (.providers | length) == 4 and
  ([.providers[].accountKey] | sort) == ["codex-1", "codex-2", "grok-1", "opencode-go-1"] and
  (.providers[] | select(.accountKey == "codex-1") | .quotaSemantics.status) == "unknown" and
  (.providers[] | select(.accountKey == "codex-2") | .quotaSemantics.effectiveAvailability[0].effectivePercentRemaining) == 95 and
  (.providers[] | select(.accountKey == "grok-1") | .quotaSemantics.effectiveAvailability[0].effectivePercentRemaining) == 86 and
  (.providers[] | select(.accountKey == "opencode-go-1") | .quotaSemantics.effectiveAvailability[0].effectivePercentRemaining) == 60 and
  (.providers[] | select(.accountKey == "opencode-go-1") | .quotaSemantics.effectiveAvailability[0].selection.spendPriority) == 0.8 and
  ([.. | strings] | index("hidden-one")) == null and
  ([.. | strings] | index("hidden-two")) == null
' "$TMP_ROOT/out.json" >/dev/null || fail "separate accounts, tightest window, and redaction diverged"
pass "success, limit-ready, and unknown rows stay separate accounts"

cat > "$TMP_ROOT/zero.json" <<'JSON'
[{"provider":"grok","windows":[{"used":100,"remaining":0}]}]
JSON
"$TOOL" "$TMP_ROOT/zero.json" > "$TMP_ROOT/out.json"
jq -e '.providers[0].accountKey == "grok-1" and
       .providers[0].quotaSemantics.effectiveAvailability[0].runway.status == "exhausted_now" and
       (.providers[0].quotaSemantics.effectiveAvailability[0].selection | has("spendPriority") | not)' \
  "$TMP_ROOT/out.json" >/dev/null || fail "a zero window must be exhausted and unranked"
pass "a zero window is a limit, not a rankable zero"

printf '%s\n' '{"providers":[]}' > "$TMP_ROOT/bad.json"
if "$TOOL" "$TMP_ROOT/bad.json" >/dev/null 2>"$TMP_ROOT/err"; then
  fail "a non-array payload must fail"
fi
pass "a non-array payload is an error"

git -C "$ROOT" diff --exit-code -- bin/fm-quota-axi-lib.sh bin/fm-quota-choose.sh bin/fm-procevent-quota.sh \
  || fail "sourcing the validator must not rewrite a quota-axi script"
pass "quota-axi scripts stay untouched after the adapter runs"

printf '# all fm-quota-magpie tests passed\n'
