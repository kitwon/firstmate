---
name: show-me-the-works
description: >-
  Write one fixed-structure work trail for the whole fleet: one row per task naming what it did and the absolute path that proves it.
  Use when the captain invokes /show-me-the-works or asks what the fleet actually did and where the evidence is.
user-invocable: true
metadata:
  internal: true
---

# show-me-the-works

One output: the **trail**, a markdown table in `data/show-me-the-works.md` where every task the bearings snapshot can surface holds exactly one row.
It runs at the root of a firstmate home, where `bin/` and `data/` live, and only works there.
It answers "show me your work" for the whole fleet, so the captain reads one file instead of a dozen transcripts.
The snapshot supplies every fact; your judgment trims each row's prose and orders the buckets.

## What it does

1. **Gather every task with one bounded command.**
   Run `snapshot=$(mktemp)`, then `bin/fm-bearings-snapshot.sh --json --all-in-flight --all-decisions --all-landed --all-queued --all-secondmates --all-recorded-prs --fields bodies > "$snapshot"`.
   The `--all-*` opt-ins lift the projection's display bounds, so live work, captain-held tasks, queued gates, landed work, and each registered secondmate home's work are all in hand.
   `bin/fm-bearings-snapshot.sh`'s header owns the exact fields.
   Done when those surfaces are captured; if the command fails, report that in chat and write no trail.

2. **Compose one row per task.**
   A task seen on two surfaces keeps its one row; the second surface's state belongs in the evidence cell, not in a second row.
   A secondmate-owned task arrives as `<home>/<task-id>`, and its row names that home.
   Synthetic gates such as `(main-inventory)` and `(return-catchup)` are warnings rather than tasks, so they belong under `## Coverage`.
   Done when every task id in the snapshot holds exactly one row.

3. **Write the trail fresh.**
   Compose it at `data/.show-me-the-works.md.tmp`, then `mv` it over `data/show-me-the-works.md`, then delete the gathered snapshot file.
   The atomic replace makes every call a complete snapshot of its own, with no row carried over from the previous call.
   Done when the target path holds this run's trail and the temp files are gone.

4. **Answer in chat with the trail's shape, not its table.**
   Reply with the header's counts, the trail path, and each Coverage and Attention fact in plain words, following `AGENTS.md` section 9.
   Done when the reply carries all three.

## The format

The trail is a framing header, then three sections in this order: `## Work trail`, `## Coverage`, `## Attention`.

The header is `# Show me the works - <YYYY-MM-DD>`, then two or three sentences: the snapshot time and home from `generated` and `home`, the task count split by bucket, and the weakest coverage fact when any home or surface was unreadable.

`## Work trail` is one markdown table with these columns and no others:

- **ts.** The row's own durable date from the snapshot (`filed` for a queued gate), or `-` when the surface records none.
  A decision's date stays the surface's date.
- **phase.** The row's bucket, one of `decision`, `underway`, `queued`, `landed`.
- **decision.** What the task did or what is being decided, one line. Say the outcome, not the plan.
- **evidence.** One absolute path or URL that proves the row: the task's report as a full absolute path such as `/home/<user>/.firstmate/data/<task-id>/report.md` or a landed row's `artifact` resolved the same way, or a full `https://...` PR URL the snapshot records for that task.
  Prefer the report path; use the PR URL when the task has no report. `-` when the snapshot holds no pointer at all.

Cells stay single line, with any `|` inside a cell written as `/`.
Rows go by bucket (`decision`, then `underway`, then `queued`, then `landed`), and inside a bucket by durable date newest first, undated rows after dated ones in snapshot order.

An example row, plain-spoken so the captain reads it at a glance:

```
| - | decision | Audit the new-page-builder security findings for review and approval | /Users/kit./.firstmate/data/npb-security-why-how/report.md |
```

## Coverage

One bullet each for what the snapshot could not see, so an absence never reads as an all-clear:

- one per `omitted[]` surface with its `reveal` flag,
- one per synthetic warning gate,
- one per unreadable, cached, or unhealthy secondmate home,
- one per unhealthy worker endpoint.

A surface the snapshot reports as null or not at all is unavailable, which earns a coverage bullet rather than an empty result.
`Everything the snapshot can measure was readable.` when there is none.

## Attention

List what a reviewer should check before trusting the trail: a finished task whose evidence cell is `-`, a `done` run with no recorded PR, an unreadable worker record for a task that shows as finished, a hold older than the fleet's usual patience, a landed row whose artifact never resolved.
`No flags.` is allowed; an invented flag is not.

## Where it lives

`data/show-me-the-works.md`, one fixed path with no date in the name, replaced on every call.
The trail is a current snapshot rather than a log: a task's durable history stays in its backlog record, its landed rows, and `data/<task-id>/`, so overwriting the file loses nothing.
`data/` is captain-private and gitignored, so the trail is never committed.

## Rules

- Read-only apart from the one trail write.
  Composing leaves tasks, PRs, dispatches, workers, decisions, and every other `data/` and `state/` file as they were.
- Every row comes from the snapshot, and a failed or unverified result stays that way in its row.
- Evidence is an absolute path or a full URL, never a relative one and never a bare task id.
- The trail is private but still carries paths, task ids, and PR URLs, so secrets, tokens, and PHI stay out of it.
- Write in plain words with no AI speak or abstract jargon, so the captain reads a row and knows what happened without decoding it.
