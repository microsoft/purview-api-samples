# GitHub Copilot instructions — microsoft/purview-api-samples

This file points coding agents at the repo's canonical guidance. **Start with
[`AGENTS.md`](../AGENTS.md)** for the sample map, entry points, verification, and
guardrails.

## Repo shape

A multi-sample collection of independent Microsoft Purview developer samples
(PowerShell, .NET 8 WPF, Python/AWS Lambda, a browser frontend, and a Postman
collection). There is no single buildable service; each top-level folder is its
own sample with its own README.

## Before you change anything

- Read the affected sample's README and [`docs/conventions.md`](../docs/conventions.md).
- Keep edits scoped to one sample per PR; avoid cross-sample refactors.
- Never hard-code secrets, tenant IDs, or client IDs — use placeholders and the
  patterns already ignored in [`.gitignore`](../.gitignore).

## Verify before you commit

Run [`scripts/verify.ps1`](../scripts/verify.ps1) from the repo root. It must
pass. See [`docs/build-and-test.md`](../docs/build-and-test.md) for per-sample
commands.

## PR-size guardrails

- Prefer small, single-purpose PRs (roughly < 400 changed lines); split larger
  work into reviewable steps.
- One sample per PR where practical; call out cross-cutting changes explicitly.
- Update the touched sample's README in the same PR when behavior changes.

## Telemetry tagging (mandatory)

Apply the labels and the description-footer block defined in
[`.github/instructions/telemetry.instructions.md`](instructions/telemetry.instructions.md)
to every PR and ADO work item, on every turn.
