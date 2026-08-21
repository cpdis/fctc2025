// @vitest-environment node

import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'

const workflow = readFileSync(
  join(import.meta.dirname, '..', '.github', 'workflows', 'weekly-data-sync.yml'),
  'utf8'
)

function between(start, end) {
  const startIndex = workflow.indexOf(start)
  const endIndex = workflow.indexOf(end, startIndex + start.length)

  expect(startIndex, `Missing workflow marker: ${start}`).toBeGreaterThanOrEqual(0)
  expect(endIndex, `Missing workflow marker: ${end}`).toBeGreaterThan(startIndex)
  return workflow.slice(startIndex, endIndex)
}

describe('weekly notification workflow contract', () => {
  it('uses one Perth Sunday schedule and queues overlapping runs', () => {
    expect(workflow.match(/^\s+- cron:/gm)).toHaveLength(1)
    expect(workflow).toContain("cron: '17 17 * * 0'")
    expect(workflow).toContain('timezone: Australia/Perth')
    expect(workflow).toMatch(/notification_mode:\n\s+description:.*\n\s+required: true\n\s+default: preview\n\s+type: choice/)
    expect(workflow).toMatch(/options:\n\s+- preview\n\s+- send\n\s+- smoke/)
    expect(workflow).toMatch(/concurrency:\n\s+group: weekly-data-sync\n\s+queue: max\n\s+cancel-in-progress: false/)
  })

  it('limits write access to sync and runs notify only after successful main sync', () => {
    const topLevel = between('permissions:', 'jobs:')
    const sync = between('  sync:', '  notify:')
    const notify = workflow.slice(workflow.indexOf('  notify:'))

    expect(topLevel).toContain('contents: read')
    expect(topLevel).not.toContain('contents: write')
    expect(sync).toMatch(/permissions:\n\s+contents: write/)
    expect(sync).toContain('actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd')
    expect(notify).toContain('needs: sync')
    expect(notify).toContain('success()')
    expect(notify).toContain("github.ref == 'refs/heads/main'")
    expect(notify).toMatch(/environment:\n\s+name: milestone-production/)
    expect(notify).toMatch(/permissions:\n\s+contents: read/)
    expect(notify).toContain('timeout-minutes: 10')
  })

  it('checks out latest main without credentials and previews without secrets', () => {
    const preview = between('      - name: Preview milestone notifications', '      - name: Send milestone notifications')
    const actionRefs = [...workflow.matchAll(/uses: ([^\s]+)/g)].map((match) => match[1])

    expect(actionRefs).toEqual([
      'actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd',
      'actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd',
      'actions/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e',
    ])
    expect(workflow).toMatch(/ref: main\n\s+persist-credentials: false/)
    expect(workflow).toContain("node-version: '24'")
    expect(workflow).toContain('package-manager-cache: false')
    expect(workflow).toContain('npm ci --omit=dev --ignore-scripts')
    expect(preview).toContain('id: milestones')
    expect(preview).toContain('node scripts/send-milestone-digest.js --preview')
    expect(preview).not.toMatch(/RESEND_|MILESTONE_RECIPIENTS|MILESTONE_SMOKE_RECIPIENT|MILESTONE_FROM/)
  })

  it('requires the gate, candidates, main, and both actors for manual sends', () => {
    const send = between('      - name: Send milestone notifications', '      - name: Send milestone smoke test')

    expect(send).toContain("vars.MILESTONE_EMAIL_ENABLED == 'true'")
    expect(send).toContain("steps.milestones.outputs.has_candidates == 'true'")
    expect(send).toContain("github.event_name == 'schedule'")
    expect(send).toContain("github.run_attempt == 1")
    expect(send).toContain("github.event_name == 'workflow_dispatch'")
    expect(send).toContain("inputs.notification_mode == 'send'")
    expect(send).toContain("github.ref == 'refs/heads/main'")
    expect(send).toContain("github.actor == 'cpdis'")
    expect(send).toContain("github.triggering_actor == 'cpdis'")
    expect(send).toContain('node scripts/send-milestone-digest.js --send')
    expect(send).toMatch(/env:\n\s+RESEND_API_KEY:.*\n\s+MILESTONE_RECIPIENTS:.*\n\s+MILESTONE_FROM:/)
    expect(send).not.toContain('MILESTONE_SMOKE_RECIPIENT')
    expect(send).not.toContain('continue-on-error')
  })

  it('uses the exact schedule and manual authorization expression', () => {
    const send = between('      - name: Send milestone notifications', '      - name: Send milestone smoke test')
    const expected = [
      "vars.MILESTONE_EMAIL_ENABLED == 'true' &&",
      "steps.milestones.outputs.has_candidates == 'true' &&",
      '(',
      "(github.event_name == 'schedule' && github.run_attempt == 1) ||",
      '(',
      "github.event_name == 'workflow_dispatch' &&",
      "inputs.notification_mode == 'send' &&",
      "github.ref == 'refs/heads/main' &&",
      "github.actor == 'cpdis' &&",
      "github.triggering_actor == 'cpdis'",
      ')',
      ')',
    ].join(' ')
    const actual = send.match(/if: >-\n([\s\S]*?)\n\s+run:/)?.[1]
      ?.trim()
      .replace(/\s+/g, ' ')

    expect(actual).toBe(expected)
  })

  it('reports refused manual sends and skipped scheduled reruns', () => {
    expect(workflow).toContain('milestone_notification delivery=refused reason=unauthorized')
    expect(workflow).toContain('milestone_notification delivery=skipped reason=scheduled-rerun')
  })

  it('uses the FCTC Delivery Service sender for live and smoke emails', () => {
    expect(workflow.match(
      /MILESTONE_FROM: FCTC Delivery Service <runs@notifications\.fctc\.cpd\.dev>/g
    )).toHaveLength(2)
  })

  it('allows smoke only on main for both actors, without the normal gate', () => {
    const smoke = workflow.slice(workflow.indexOf('      - name: Send milestone smoke test'))

    expect(smoke).toContain("github.event_name == 'workflow_dispatch'")
    expect(smoke).toContain("inputs.notification_mode == 'smoke'")
    expect(smoke).toContain("github.ref == 'refs/heads/main'")
    expect(smoke).toContain("github.actor == 'cpdis'")
    expect(smoke).toContain("github.triggering_actor == 'cpdis'")
    expect(smoke).not.toContain('MILESTONE_EMAIL_ENABLED')
    expect(smoke).not.toContain('has_candidates')
    expect(smoke).toContain('node scripts/send-milestone-digest.js --smoke')
    expect(smoke).toMatch(/env:\n\s+RESEND_API_KEY:.*\n\s+MILESTONE_SMOKE_RECIPIENT:.*\n\s+MILESTONE_FROM:/)
    expect(smoke).not.toContain('MILESTONE_RECIPIENTS:')
    expect(smoke).not.toContain('continue-on-error')
  })
})
