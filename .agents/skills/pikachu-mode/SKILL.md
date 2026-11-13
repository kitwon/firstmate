---
name: pikachu-mode
description: >-
  Route one task through the Pikachu workflow: a worker runs it with go-pikachu, a different worker or agent accepts the evidence with knock-off, and delivery checks the AI Code review pipeline and every AI Bot finding.
  Use when the captain invokes /pikachu-mode or asks for a task to be run in Pikachu mode.
user-invocable: true
metadata:
  internal: true
---

# Pikachu mode

One task, one developer, and one verdict from someone else.
This skill assigns the roles and the acceptance handoff.
`go-pikachu` owns execution, `knock-off` owns the evidence contract, `pr` owns the pull request body, and the Firstmate contract owns everything else.

## Resolve the shared skills

Resolve `go-pikachu` and `knock-off` by name on the skill surface the session and the worker harness expose, which is the advertised catalog for the skills it lists and the explicit skill command for the one it hides.
Report a name that surface does not serve and stop, because the workflow needs both.
The shared skills come from the installed package, so a target project needs no Pikachu package of its own, and a remembered source path never stands in for a resolved name.
Load `knock-off` before writing the acceptance assignment, because it owns the inputs and checks that assignment hands over.

## Split the task

Complex means any of these:
- the change spans several surfaces or workflows whose acceptance evidence is independent,
- backend, data, or deploy work needs write proof and then read proof,
- acceptance crosses several states or roles.

A screenshot, one staging check, or several commands do not make a task complex.

A complex task gets two assigned workstreams, a developer and a verifier, each with its own brief naming the same revision.
Every other task keeps one developer and one acceptance assignment.

## Assign development

File the work item and spawn the developer through the ordinary dispatch path.
The brief names `go-pikachu` as the execution skill and requires the worker to invoke it explicitly through the form `harness-adapters` owns.
The brief also names the evidence directory under `data/<id>/`, where `result.md` and any proof files land.

## Assign acceptance

Every task ends with a verdict from a different worker or agent, assigned through the same dispatch path.
A secondmate whose scope fits may accept, and it opens no pull request of its own.
The assignment names the frozen revision, the task's `result.md`, and the evidence the task produced.
The agent runs `knock-off` at that revision, records its own acceptance rows there, and judges the evidence the developer actually supplied rather than general code quality.
The verdict is `pass`, `fail`, or `blocked`, and a failure returns to the developer as finding id, reproduction, and expectation.
A changed revision voids the verdict, so a fix earns a fresh acceptance on the new head.

## Check delivery

The developer proves these on the published head before declaring ready, and acceptance rechecks them.
- the repository's `AI Code review` pipeline ran on this head, or the repository has none and the task records that from repository evidence,
- every `AI Bot` finding on this head is dispositioned, either fixed on this branch with the fixing commit and a recheck, or answered with the reason it does not apply, and `pr` owns the `### AI review` section that records each one,
- a visual claim carries a rendered snapshot of the running page, not an HTTP status.

`knock-off` owns how those rows are supplied and `pr` owns the body the pull request needs.
A task that publishes no pull request marks the pull request rows not applicable and keeps the evidence rows.

## Land after acceptance

Landing waits for a `pass` verdict on the ready head.
Merge authority, merge tools, and the project's yolo posture are unchanged, so this gate grants and removes nothing.

## Boundaries

Intake, capacity, delivery mode, publication, and merge authority stay with AGENTS.md section 7, and supervision stays with section 8.
This skill adds roles and evidence requirements and changes no authority.
It adds no pipeline, daemon, review pass, second pull request, or automatic merge.
The developer never accepts its own evidence, and it never spawns the acceptance agent itself.
