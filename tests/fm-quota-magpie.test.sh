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

cat > "$TMP_ROOT/split.json" <<'JSON'
[
  {"provider":"codex","user":"hidden-one","windows":[],"error":"Unauthorized"},
  {"provider":"codex","user":"hidden-two","windows":[{"name":"5 hours","used":5,"remaining":95}]},
  {"provider":"grok","user":"hidden-grok","windows":[{"name":"7 days","used":100,"remaining":0}]},
  {"provider":"opencode-go","user":"hidden-go","windows":[
    {"name":"5 hours","used":0,"remaining":100},
    {"name":"7 days","used":40,"remaining":60}
  ]},
  {"provider":"not a key","user":"hidden-bad","windows":[{"used":1,"remaining":99}]}
]
JSON
if ! "$TOOL" "$TMP_ROOT/split.json" > "$TMP_ROOT/out.json" 2>"$TMP_ROOT/err"; then
  fail "a valid magpie document must normalize: $(cat "$TMP_ROOT/err")"
fi
# shellcheck source=bin/fm-quota-axi-lib.sh
. "$ROOT/bin/fm-quota-axi-lib.sh"
fm_quota_json_valid < "$TMP_ROOT/out.json" || fail "normalized magpie snapshot must validate as schema 6"
jq -e '
  .schemaVersion == 6 and
  (.providers | length) == 1 and
  .providers[0].provider == "magpie" and
  .providers[0].accountKey == "unattributed" and
  .providers[0].quotaSemantics.status == "unknown" and
  (.providers[0].quotaSemantics.effectiveAvailability[0].status == "unknown") and
  (.providers[0].quotaSemantics.effectiveAvailability[0] | has("effectivePercentRemaining") | not) and
  (.providers[0].quotaSemantics.effectiveAvailability[0] | has("selection") | not) and
  ([.. | strings] | index("hidden-one")) == null and
  ([.. | strings] | index("hidden-two")) == null and
  ([.. | strings] | index("spendPriority") | not)
' "$TMP_ROOT/out.json" >/dev/null || fail "a full sibling must not become known quota or a login"
first=$(cat "$TMP_ROOT/out.json")
jq 'reverse' "$TMP_ROOT/split.json" > "$TMP_ROOT/reordered.json"
"$TOOL" "$TMP_ROOT/reordered.json" > "$TMP_ROOT/reordered-out.json"
[ "$first" = "$(cat "$TMP_ROOT/reordered-out.json")" ] || fail "list order must not change the snapshot"
pass "missing account attribution stays unknown, and order does not matter"

printf '%s\n' '{"providers":[]}' > "$TMP_ROOT/bad.json"
if "$TOOL" "$TMP_ROOT/bad.json" >/dev/null 2>"$TMP_ROOT/err"; then
  fail "a non-array payload must fail"
fi
pass "a non-array payload is an error"

git -C "$ROOT" diff --exit-code -- bin/fm-quota-axi-lib.sh bin/fm-quota-choose.sh bin/fm-procevent-quota.sh \
  || fail "sourcing the validator must not rewrite a quota-axi script"
pass "quota-axi scripts stay untouched after the adapter runs"

printf '# all fm-quota-magpie tests passed\n'
