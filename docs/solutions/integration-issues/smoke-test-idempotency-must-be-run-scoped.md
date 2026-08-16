---
title: Smoke test idempotency must be run-scoped
date: 2026-08-14
category: integration-issues
module: milestone-notifications
problem_type: integration_issue
component: email_processing
symptoms:
  - A repeated smoke test reports the original accepted result without sending a new email
  - A smoke test after a DNS or API key repair does not exercise the repaired provider path
root_cause: logic_error
resolution_type: workflow_improvement
severity: high
tags: [email, idempotency, resend, smoke-test, github-actions]
---

# Smoke test idempotency must be run-scoped

## Problem

A provider smoke test used one fixed message and one date-only idempotency key. A second test
on the same day could return the first accepted response without sending another email.

This creates a false green result after an operator repairs DNS, sender, or API key settings.
The second request does not prove that the repaired path works.

## Symptoms

- A repeated smoke run reports `accepted=1`, but no new message appears.
- A new key or DNS repair appears valid because the provider returns its cached response.
- Normal retry protection and operator validation need different idempotency scopes.

## What Didn't Work

- A Perth-date key prevented duplicate smoke messages for 24 hours. It also prevented a new
  workflow run from testing changed provider settings.
- Removing idempotency from smoke requests would make ambiguous network retries unsafe.
- Changing the fixed smoke content would weaken the privacy and repeatability contract.

## Solution

Scope the smoke key to one GitHub workflow attempt. Read `GITHUB_RUN_ID` and
`GITHUB_RUN_ATTEMPT`, and validate both as digits before using them
(`scripts/send-milestone-digest.js:311`).

```js
if (runId) return `fctc-milestones-smoke/${runId}/${runAttempt}`
```

The implementation uses a time-based local fallback when GitHub context is absent
(`scripts/send-milestone-digest.js:323`). A new workflow run or rerun gets a new key. The
provider call can now test repaired settings.

Keep the key stable inside one workflow attempt. The Resend client serializes the payload
once before its retry loop (`scripts/lib/resendBatch.js:40`). Each retry reuses the same
`Idempotency-Key` header (`scripts/lib/resendBatch.js:55`).

## Why This Works

There are two different duplicate boundaries:

- A transport retry repeats one logical request. It must reuse the same key.
- A new smoke workflow is a new validation action. It must use a new key.

The workflow run ID and attempt number separate these boundaries without adding a database.
The fixed subject, body, and recipient remain safe and deterministic.

Resend returns the original response when a key and payload are reused during its retention
window. See the [Resend idempotency guide](https://resend.com/docs/dashboard/emails/idempotency-keys).

## Prevention

- Define the logical request boundary before choosing an idempotency key.
- Test that one workflow attempt keeps one key across transport retries.
- Test that a new workflow run or rerun creates a different smoke key.
- Keep smoke content fixed and free of production data.
- Confirm inbox receipt. Provider acceptance alone does not prove delivery.

## Related Issues

- The normal weekly digest uses the Perth Monday as its logical request boundary.
- The notification runbook is in `README.md` under "Weekly milestone emails".
