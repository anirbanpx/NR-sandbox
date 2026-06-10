# Spec-Driven Development (SDD) Workflow

You are working in spec-driven development mode for the NR-sandbox project.
Follow this workflow strictly every session.

## Step 1 — Orient (do this first, every session)

Read these three files in order before writing any code:
1. `spec/requirements.md` — what we are building and why
2. `spec/design.md` — architecture, instrumentation paths, design decisions
3. `spec/implementation.md` — phases, tasks, and current status (checkboxes)

Identify the **first unchecked phase** in `spec/implementation.md`. That is the only
phase to work on this session. Do not skip ahead.

## Step 2 — Confirm scope with the user

State clearly:
- Which phase you are starting (e.g. "Phase 1 — Application & Instrumentation")
- What files will be created or modified
- Any blockers or prerequisites (e.g. credentials needed, AWS setup required)

Get confirmation before writing any code.

## Step 3 — Build against the spec

Work through the tasks in the current phase exactly as described in `spec/implementation.md`.
If something in the spec is ambiguous or needs a decision, surface it before building — do not
make silent assumptions.

Commit locally after each meaningful unit of work (a working file, a passing config, etc.).
Do not accumulate large uncommitted diffs.

## Step 4 — End of session checklist

Before closing the session, run through this checklist:

- [ ] All work for the current phase is committed locally (`git status` is clean)
- [ ] Phase checkbox updated in `spec/implementation.md` if the phase is complete
  - Change `## [ ] Phase N` → `## [x] Phase N`
- [ ] All local commits pushed to GitHub (`git push origin main`)
- [ ] Note anything unfinished or blocked as a comment at the bottom of `spec/implementation.md`

## Spec change rule

If the work this session reveals that the spec needs updating (a design decision changed,
a new constraint discovered), update the relevant spec file (`requirements.md`, `design.md`,
or `implementation.md`) **before** writing the code that reflects the change.
Spec changes are committed separately from code changes.
