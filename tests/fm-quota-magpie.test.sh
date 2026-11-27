#!/usr/bin/env bash
# Behavior of bin/fm-magpie-quota.sh, the Magpie quota reader.
# Fixtures only. No live magpie process and no credential read.
# bin/fm-quota-axi-lib.sh must stay byte-identical to HEAD.
set -u

# The structural fixtures predate a floor-meeting pace calculator. Keep them on
# that contract; the selection cases below opt back in.
export FM_MAGPIE_DISABLE_PACE=1

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
  {"provider":"codex","kind":"subscription","plan":"team","user":"hidden-two","readAt":"2026-10-30T06:00:00Z","last":true,"lastServedAt":"2026-10-30T05:59:00Z","windows":[{"name":"5 hours","used":5,"remaining":95,"resetsAt":"2026-10-30T10:00:00Z","holds":{"user":"hidden-nested"}}],"resetsUsed":[{"user":"hidden-history"}]},
  {"provider":"grok","user":"hidden-grok","windows":[{"name":"7 days","used":100,"remaining":0}]},
  {"provider":"opencode-go","user":"hidden-go","windows":[
    {"name":"5 hours","used":0,"remaining":100},
    {"name":"7 days","used":40,"remaining":60}
  ]},
  {"provider":"deepseek","kind":"balance","user":"hidden-balance","balance":"¥15.86","windows":[]},
  {"provider":"not a key","user":"hidden-bad","windows":[{"used":1,"remaining":99}]}
]
JSON
if ! "$TOOL" "$TMP_ROOT/split.json" > "$TMP_ROOT/out.json" 2>"$TMP_ROOT/err"; then
  fail "a valid magpie document must normalize: $(cat "$TMP_ROOT/err")"
fi
# shellcheck source=bin/fm-quota-axi-lib.sh
. "$ROOT/bin/fm-quota-axi-lib.sh"
fm_quota_json_valid < "$TMP_ROOT/out.json" || fail "normalized magpie snapshot must validate as schema 6"
# A Magpie route names its own subscription provider, so one subscription per
# provider is that route's real window list, and two subscriptions under one
# provider name still identify no single account.
jq -e '
  ([.providers[] | select(.provider == "codex")][0]) as $c
  | ([.providers[] | select(.provider == "deepseek")][0]) as $d
  | .schemaVersion == 6 and
    ([.providers[].provider] == ["codex", "deepseek", "grok", "opencode-go"]) and
    all(.providers[]; .accountKey == "default") and
    $c.quotaSemantics.status == "unknown" and
    ($c.note | test("^2 subscriptions named codex")) and
    ($c.quotaSemantics.effectiveAvailability[0].status == "unknown") and
    ($c.quotaSemantics.effectiveAvailability[0] | has("effectivePercentRemaining") | not) and
    $d.quotaSemantics.status == "unknown" and
    ($d.note | test("no percentage window")) and
    ([.. | objects | keys[]] | index("spendPriority")) == null and
    ([.. | strings] | index("hidden-one")) == null and
    ([.. | strings] | index("hidden-two")) == null
' "$TMP_ROOT/out.json" >/dev/null \
  || fail "one provider with two subscriptions must stay unknown, without a margin derived from one account"
pass "two subscriptions under one provider stay unmeasured when an account could not be read"
jq -e '
  ([.providers[] | select(.provider == "grok")][0].quotaSemantics) as $g
  | ([.providers[] | select(.provider == "opencode-go")][0].quotaSemantics) as $o
  | $g.status == "known" and
    [$g.effectiveAvailability[] | [.scope, .status, .effectivePercentRemaining, .window, .runway.status]] ==
      [["all_models", "known", 0, "7 days", "unknown"]] and
    $o.status == "known" and
    [$o.effectiveAvailability[] | [.scope, .status, .effectivePercentRemaining, .window]] ==
      [["all_models", "known", 100, "5 hours"], ["all_models", "known", 60, "7 days"]] and
    all($o.effectiveAvailability[]; .runway.status == "unknown" and (has("selection") | not))
' "$TMP_ROOT/out.json" >/dev/null \
  || fail "a provider magpie reports once must supply that provider's own windows"
pass "a provider magpie reports once supplies its own windows, exhausted or not"
first=$(cat "$TMP_ROOT/out.json")
jq 'reverse' "$TMP_ROOT/split.json" > "$TMP_ROOT/reordered.json"
"$TOOL" "$TMP_ROOT/reordered.json" > "$TMP_ROOT/reordered-out.json"
[ "$first" = "$(cat "$TMP_ROOT/reordered-out.json")" ] || fail "list order must not change the snapshot"
pass "list order does not change the snapshot"
jq -e '
  ([.providers[].subscriptions[]]) as $s |
  ($s | length) == 5 and
  ([$s[] | select(.provider == "codex")] | length) == 2 and
  any($s[]; .error == "Unauthorized" and .windows == []) and
  any($s[]; .plan == "team" and .readAt == "2026-10-30T06:00:00Z" and
    .last == true and .lastServedAt == "2026-10-30T05:59:00Z" and
    .windows == [{name:"5 hours",used:5,remaining:95,resetsAt:"2026-10-30T10:00:00Z"}]) and
  any($s[]; .provider == "deepseek" and .balance == "¥15.86") and
  ([.. | strings | select(startswith("hidden-"))] | length) == 0
' "$TMP_ROOT/out.json" >/dev/null || fail "separate quota evidence must survive without account identity/history"
pass "windows, resets, balances, read errors and freshness survive separately"

cat > "$TMP_ROOT/partial.json" <<'JSON'
[
  {"provider":"kimi","error":"Unauthorized","windows":[{"name":"7 days","used":0,"remaining":100}]},
  {"provider":"cursor","windows":[{"name":"Month","used":10},{"name":"7 days","used":2,"remaining":98}]},
  {"provider":"claude","windows":[{"name":"5 hours","used":0,"remaining":100},{"name":"7 days","used":50,"remaining":50}]}
]
JSON
"$TOOL" "$TMP_ROOT/partial.json" > "$TMP_ROOT/partial-out.json" \
  || fail "a provider whose window or read failed must still normalize"
jq -e '
  ([.providers[] | select(.provider == "kimi")][0]) as $k
  | ([.providers[] | select(.provider == "cursor")][0]) as $u
  | ([.providers[] | select(.provider == "claude")][0].quotaSemantics) as $h
  | $k.quotaSemantics.status == "unknown" and ($k.note | test("read failed: Unauthorized")) and
    $u.quotaSemantics.status == "unknown" and ($u.note | test("window publishes no remaining percentage")) and
    $h.status == "known" and [$h.effectiveAvailability[] | .effectivePercentRemaining] == [100, 50]
' "$TMP_ROOT/partial-out.json" >/dev/null \
  || fail "an unreadable window or failed read must stay visible uncertainty"
pass "a read error or an unreadable window stays visible uncertainty, not healthy allowance"

# A provider Magpie reports more than once is several accounts of one
# subscription, so the row publishes their mean per window: sum divided by
# count. Each account stays in `subscriptions`, the row says it averaged, and
# the earliest reset keeps the figure conservative.
cat > "$TMP_ROOT/average.json" <<'JSON'
[
  {"provider":"codex","kind":"subscription","plan":"team","readAt":"2026-10-30T06:00:00Z","windows":[
    {"name":"5 hours","used":40,"remaining":60,"resetsAt":"2026-10-30T10:00:00Z"},
    {"name":"7 days","used":10,"remaining":90,"resetsAt":"2026-11-04T00:00:00Z"}
  ]},
  {"provider":"codex","kind":"subscription","plan":"team","readAt":"2026-10-30T06:05:00Z","windows":[
    {"name":"5 hours","used":80,"remaining":20,"resetsAt":"2026-10-30T09:00:00Z"},
    {"name":"7 days","used":30,"remaining":70,"resetsAt":"2026-11-06T00:00:00Z"}
  ]}
]
JSON
"$TOOL" "$TMP_ROOT/average.json" > "$TMP_ROOT/average-out.json" \
  || fail "a provider with two readable subscriptions must normalize: $(cat "$TMP_ROOT/err" 2>/dev/null)"
fm_quota_json_valid < "$TMP_ROOT/average-out.json" || fail "an averaged magpie snapshot must validate as schema 6"
jq -e '
  ([.providers[] | select(.provider == "codex")][0]) as $x
  | $x.quotaSemantics.status == "known"
    and ($x.note | test("^2 subscriptions named codex were averaged"))
    and [$x.quotaSemantics.effectiveAvailability[]
         | [.scope, .window, .effectivePercentRemaining, .resetsAt]] ==
        [["all_models", "5 hours", 40, "2026-10-30T09:00:00Z"],
         ["all_models", "7 days", 80, "2026-11-04T00:00:00Z"]]
    and [$x.windows[] | [.name, .remaining]] == [["5 hours", 40], ["7 days", 80]]
    and ($x.subscriptions | length) == 2
    and [$x.subscriptions[].readAt] == ["2026-10-30T06:00:00Z", "2026-10-30T06:05:00Z"]
' "$TMP_ROOT/average-out.json" >/dev/null \
  || fail "two accounts under one provider must publish their per-window mean with each account preserved"
pass "two accounts under one provider publish the per-window mean and keep both accounts"

# Mismatched or incomplete evidence is never averaged into a figure that reads
# like measured quota: the provider stays unmeasured and the note names why.
cat > "$TMP_ROOT/incomplete.json" <<'JSON'
[
  {"provider":"claude","readAt":"2026-10-30T06:00:00Z","windows":[{"name":"5 hours","used":10,"remaining":90}]},
  {"provider":"claude","readAt":"2026-10-30T06:01:00Z","windows":[{"name":"7 days","used":10,"remaining":90}]},
  {"provider":"cursor","readAt":"2026-10-30T06:00:00Z","windows":[{"name":"Month","used":10,"remaining":90}]},
  {"provider":"cursor","readAt":"2026-10-30T06:01:00Z","windows":[{"name":"Month","used":10}]}
]
JSON
"$TOOL" "$TMP_ROOT/incomplete.json" > "$TMP_ROOT/incomplete-out.json" \
  || fail "an incomplete duplicate provider must still normalize"
jq -e '
  ([.providers[] | select(.provider == "claude")][0]) as $c
  | ([.providers[] | select(.provider == "cursor")][0]) as $u
  | $c.quotaSemantics.status == "unknown"
    and ($c.note | test("publish different window sets"))
    and $u.quotaSemantics.status == "unknown"
    and ($u.note | test("window publishes no remaining percentage"))
' "$TMP_ROOT/incomplete-out.json" >/dev/null \
  || fail "a mismatched or incomplete duplicate must stay unmeasured with an explicit note"
pass "mismatched window sets and a missing percentage stay unmeasured, never averaged"

# Magpie's agy-cli is the Antigravity CLI: its Gemini windows are the provider's
# bound, while its Claude & GPT windows are a separate product a route must opt
# into, so an empty Claude & GPT allowance cannot block a Gemini route.
cat > "$TMP_ROOT/agy.json" <<'JSON'
[
  {"provider":"agy-cli","kind":"subscription","plan":"Google AI Pro","readAt":"2026-10-30T06:00:00Z","windows":[
    {"name":"Gemini · 7 days","used":10,"remaining":90},
    {"name":"Gemini · 5 hours","used":40,"remaining":60},
    {"name":"Claude & GPT · 7 days","used":100,"remaining":0},
    {"name":"Claude & GPT · 5 hours","used":100,"remaining":0}
  ]}
]
JSON
"$TOOL" "$TMP_ROOT/agy.json" > "$TMP_ROOT/agy-out.json" \
  || fail "an agy-cli subscription must normalize"
jq -e '
  ([.providers[] | select(.provider == "agy-cli")][0]) as $a
  | $a.quotaSemantics.status == "known"
    and ($a | has("note") | not)
    and [$a.quotaSemantics.effectiveAvailability[] | [.window, .scope]] ==
        [["Gemini · 7 days", "all_models"],
         ["Gemini · 5 hours", "all_models"],
         ["Claude & GPT · 7 days", "claude_gpt"],
         ["Claude & GPT · 5 hours", "claude_gpt"]]
' "$TMP_ROOT/agy-out.json" >/dev/null \
  || fail "agy-cli must publish Gemini as the provider bound and Claude & GPT as its own scope"
pass "agy-cli publishes Gemini at all_models and Claude & GPT at claude_gpt"

mkdir "$TMP_ROOT/bin"
cat > "$TMP_ROOT/bin/magpie" <<'SH'
#!/usr/bin/env bash
[ "$*" = "quota --json" ] || exit 99
printf '%s\n' 'quota diagnostic' >&2
if [ "${MAGPIE_TEST_FAIL:-0}" = 1 ]; then exit 1; fi
cat "$MAGPIE_TEST_INPUT"
SH
chmod +x "$TMP_ROOT/bin/magpie"
export MAGPIE_TEST_INPUT="$TMP_ROOT/split.json"
PATH="$TMP_ROOT/bin:$PATH" "$TOOL" --read > "$TMP_ROOT/read.json" 2> "$TMP_ROOT/err"
assert_equals "$first" "$(cat "$TMP_ROOT/read.json")" "live read uses the same normalization"
assert_contains "$(cat "$TMP_ROOT/err")" 'quota diagnostic' "successful read preserves diagnostics on stderr"
if PATH="$TMP_ROOT/bin:$PATH" MAGPIE_TEST_FAIL=1 "$TOOL" --read > "$TMP_ROOT/failed.json" 2> "$TMP_ROOT/err"; then
  fail "failed magpie command must fail the reader"
fi
[ ! -s "$TMP_ROOT/failed.json" ] || fail "failed read must not emit a snapshot"
assert_contains "$(cat "$TMP_ROOT/err")" 'quota diagnostic' "failed read preserves original diagnostics"
assert_contains "$(cat "$TMP_ROOT/err")" 'magpie quota --json failed' "failed read explains the command"
pass "read diagnostics remain visible without contaminating JSON"

printf '%s\n' '{"providers":[]}' > "$TMP_ROOT/bad.json"
if "$TOOL" "$TMP_ROOT/bad.json" >/dev/null 2>"$TMP_ROOT/err"; then
  fail "a non-array payload must fail"
fi
pass "a non-array payload is an error"

git -C "$ROOT" diff --exit-code -- bin/fm-quota-axi-lib.sh bin/fm-quota-choose.sh bin/fm-procevent-quota.sh \
  || fail "sourcing the validator must not rewrite a quota-axi script"
pass "quota-axi scripts stay untouched after the adapter runs"

unset FM_MAGPIE_DISABLE_PACE
pace=$("$TOOL" --print-pace-module)
if [ -z "$pace" ]; then
  pass "spendPriority cases blocked: no quota-axi pace module at or above the floor"
else
  cat > "$TMP_ROOT/ranked.json" <<'JSON'
[
  {"provider":"grok","readAt":"2030-01-08T00:00:00Z","windows":[
    {"name":"5 hours","used":80,"remaining":20,"resetsAt":"2030-01-08T04:00:00Z"},
    {"name":"7 days","used":10,"remaining":90,"resetsAt":"2030-01-14T00:00:00Z"}
  ]},
  {"provider":"opencode-go","readAt":"2030-01-15T00:00:00Z","windows":[
    {"name":"5 hours","used":0,"remaining":100,"resetsAt":"2030-01-15T05:00:00Z"},
    {"name":"7 days","used":0,"remaining":100},
    {"name":"Month","used":98,"remaining":2,"resetsAt":"2030-02-01T00:00:00Z"}
  ]},
  {"provider":"claude","readAt":"2030-01-08T00:00:00Z","windows":[
    {"name":"7 days","used":100,"remaining":0,"resetsAt":"2030-01-14T00:00:00Z"}
  ]},
  {"provider":"kimi","readAt":"2030-01-08T00:00:00Z","windows":[
    {"name":"7 days","used":10,"remaining":90,"resetsAt":"2030-01-01T00:00:00Z"}
  ]},
  {"provider":"cursor","readAt":"2030-01-08T00:00:00Z","windows":[
    {"name":"Month","used":10,"remaining":90,"resetsAt":"2030-02-01T00:00:00Z"}
  ]},
  {"provider":"codex","user":"hidden-a","windows":[{"name":"5 hours","used":60,"remaining":40,"resetsAt":"2030-01-08T02:30:00Z"}],"readAt":"2030-01-08T00:00:00Z"},
  {"provider":"codex","user":"hidden-b","windows":[{"name":"5 hours","used":80,"remaining":20,"resetsAt":"2030-01-08T03:00:00Z"}],"readAt":"2030-01-08T00:00:00Z"},
  {"provider":"deepseek","windows":[
    {"name":"5 hours","used":0,"remaining":100,"resetsAt":"2030-01-08T05:00:00Z"}
  ]}
]
JSON
  "$TOOL" "$TMP_ROOT/ranked.json" > "$TMP_ROOT/ranked-out.json" \
    || fail "a ranked magpie document must normalize: $(cat "$TMP_ROOT/err" 2>/dev/null)"
  fm_quota_json_valid < "$TMP_ROOT/ranked-out.json" || fail "ranked magpie snapshot must validate as schema 6"
  jq -e '
    ([.providers[] | select(.provider == "grok")][0].quotaSemantics) as $g
    | ([.providers[] | select(.provider == "opencode-go")][0].quotaSemantics) as $o
    | ([.providers[] | select(.provider == "claude")][0].quotaSemantics) as $c
    | ([.providers[] | select(.provider == "kimi")][0].quotaSemantics) as $k
    | ([.providers[] | select(.provider == "cursor")][0].quotaSemantics) as $u
    | ([.providers[] | select(.provider == "codex")][0]) as $x
    | ([.providers[] | select(.provider == "deepseek")][0].quotaSemantics) as $d
    | ($g.effectiveAvailability[0].selection.spendPriority) > ($o.effectiveAvailability[0].selection.spendPriority)
    and $g.effectiveAvailability[0].selection.spendPriority == 0.2315
    and $o.effectiveAvailability[0].selection.spendPriority == -2.1126
    and all($g.effectiveAvailability[]; .selection.spendPriority == 0.2315)
    and $g.effectiveAvailability[0].effectivePercentRemaining == 20
    and $o.effectiveAvailability[0].effectivePercentRemaining == 100
    and $o.effectiveAvailability[2].effectivePercentRemaining == 2
    and $o.effectiveAvailability[2].runway.status == "projected_exhaustion"
    and $o.effectiveAvailability[2].runway.usableRunwaySeconds == 24686
    and $o.effectiveAvailability[0].runway.status == "through_reset"
    and $o.effectiveAvailability[1].runway.status == "unknown"
    and $c.effectiveAvailability[0].runway.status == "exhausted_now"
    and $c.effectiveAvailability[0].runway.usableRunwaySeconds == 0
    and $k.effectiveAvailability[0].selection.status == "unknown"
    and ($k.effectiveAvailability[0].selection | has("spendPriority") | not)
    and $u.effectiveAvailability[0].selection.status == "unknown"
    and ($u.effectiveAvailability[0].selection | has("spendPriority") | not)
    and $x.quotaSemantics.status == "known"
    and ($x.note | test("^2 subscriptions named codex were averaged"))
    and $x.quotaSemantics.effectiveAvailability[0].effectivePercentRemaining == 30
    and $x.quotaSemantics.effectiveAvailability[0].resetsAt == "2030-01-08T02:30:00Z"
    and $x.quotaSemantics.effectiveAvailability[0].selection.status == "known"
    and $x.quotaSemantics.effectiveAvailability[0].selection.spendPriority == -0.8
    and ([.. | strings] | index("hidden-a")) == null
    and $d.effectiveAvailability[0].selection.status == "unknown"
    and ($d.effectiveAvailability[0].selection | has("spendPriority") | not)
  ' "$TMP_ROOT/ranked-out.json" >/dev/null \
    || fail "headroom, the long-period bound, exhaustion, expiry, and missing clocks must stay distinct"
  pass "a fuller short window does not outrank the higher spendPriority, and a month bound stays visible"
  pass "expired, unlabeled month, and a missing readAt stay unranked"
  pass "two accounts of one provider average into a measured, rankable row"
fi

printf '# all fm-quota-magpie tests passed\n'
