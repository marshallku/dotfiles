import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

const HOME = '/h'
const DIR = `${HOME}/.claude/state/codex-live`
const START = Date.parse('2026-11-22T10:00:00Z')

type File = { text: string; mtimeMs: number }

// An in-memory disk answering $.fs beneath the mod; `dirs` are the folders stat finds besides files.
function disk(on: On, files: Map<string, File>, dirs: Set<string> = new Set()) {
  on('fs.list', (_, e) => ({
    value: [...files.entries()]
      .filter(([path]) => path.startsWith(`${e.path}/`))
      .map(([path, file]) => ({
        name: path.slice(e.path.length + 1), kind: 'file' as const,
        size: file.text.length, mtimeMs: file.mtimeMs, isLink: false,
      })),
  }))
  on('fs.stat', (_, e) => {
    if (dirs.has(e.path)) return { value: { kind: 'dir' as const, size: 0, mtimeMs: 0, isLink: false } }
    const file = files.get(e.path)
    if (!file) throw new Error(`ENOENT: ${e.path}`)
    return { value: { kind: 'file' as const, size: file.text.length, mtimeMs: file.mtimeMs, isLink: false } }
  })
  on('fs.read', (_, e) => {
    const file = files.get(e.path)
    if (!file) throw new Error(`ENOENT: ${e.path}`)
    const text = file.text
    const offset = e.offset ?? 0
    return { value: text.slice(offset, e.length === undefined ? undefined : offset + e.length) }
  })
}

function status(name: string, fields: Record<string, unknown>, mtimeMs: number): [string, File] {
  return [`${DIR}/${name}.status.json`, { text: JSON.stringify({ events: `${DIR}/${name}.jsonl`, ...fields }), mtimeMs }]
}

// A run as codex-exec.sh leaves it: running (with a fresh event stream), later done.
function running(files: Map<string, File>, name: string, key: string, round: number, at: number) {
  files.set(...status(name, {
    state: 'running', thread_key: key, round, started_at: new Date(at).toISOString().replace(/\.\d+Z$/, 'Z'),
    cwd: '/w/repo',
  }, at))
  files.set(`${DIR}/${name}.jsonl`, { text: '', mtimeMs: at })
}

function finish(files: Map<string, File>, name: string, key: string, round: number, startedAt: number,
                endedAt: number, verdict: string) {
  const iso = (ms: number) => new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z')
  files.set(...status(name, {
    state: 'done', thread_key: key, round, started_at: iso(startedAt), ended_at: iso(endedAt), cwd: '/w/repo',
    exit: verdict === 'REVISE' ? 1 : 0, verdict,
  }, endedAt))
}

const BAND = (surface: 'terminal' | 'desktop') => ({
  plugin: 'codex-lens', component: 'AbovePrompt', surface,
  props: { hasSurvey: false, isCollapsed: false, isWorking: true, maxRows: 10, bodyColumns: 120,
           scroll: { offset: 0, bodyRows: 10 }, view: {} },
}) as const

async function start($: Engine, on: On, files: Map<string, File>,
                     { cwd = '/w/repo/sub', dirs = new Set<string>() }: { cwd?: string; dirs?: Set<string> } = {}) {
  const clock = mock.clock(on, { now: START + 72_000 })
  mock.env(on, { HOME })
  disk(on, files, dirs)
  const toasts: string[] = []
  on('ui.toast', (_, e) => { toasts.push(e.text); return { value: undefined } })
  on('session.cwd', () => ({ value: cwd }))
  // The engine's own band, beneath the mod: older kits (2.1.311 on the mac-mini) answer nothing.
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  await $.session.start({ cwd, surface: 'terminal', isInteractive: true })
  return { clock, toasts }
}

test('a running review of this repository is shown above the prompt, on every surface', async ($, on) => {
  const now = START + 72_000
  const files = new Map<string, File>([
    status('review-abc-20261122T100000Z-1', {
      state: 'running', thread_key: 'review-abc', round: 2, started_at: '2026-11-22T10:00:00Z', cwd: '/w/repo',
    }, now),
    [`${DIR}/review-abc-20261122T100000Z-1.jsonl`, { text: [
      JSON.stringify({ type: 'item.started', item: { type: 'command_execution', command: "/usr/bin/zsh -lc 'rg -n useLogFlow src'" } }),
      JSON.stringify({ type: 'item.completed', item: { type: 'command_execution', exit_code: 0 } }),
    ].join('\n'), mtimeMs: now }],
    status('review-other-20261122T100000Z-2', {
      state: 'running', thread_key: 'review-other', round: 1, started_at: '2026-11-22T10:00:00Z', cwd: '/elsewhere',
    }, now),
  ])
  await start($, on, files)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount(BAND(surface))
    const line = await ui.find({ type: 'Text', text: /codex review r2/ })
    expect(line?.text).toBe('⟳ codex review r2 · 1:12 · ▶ rg -n useLogFlow src')
    await ui.unmount()
  }
})

test('a run that finishes is toasted once with its verdict; runs that ended earlier are not', async ($, on) => {
  const now = START + 72_000
  const files = new Map<string, File>([
    status('review-old-20261122T090000Z-3', {
      state: 'done', thread_key: 'review-old', round: 1, started_at: '2026-11-22T09:00:00Z',
      ended_at: '2026-11-22T09:05:00Z', cwd: '/w/repo', exit: 0, verdict: 'APPROVED',
    }, Date.parse('2026-11-22T09:05:00Z')),
    status('plan-p-20261122T100000Z-4', {
      state: 'running', thread_key: 'plan-p', round: null, started_at: '2026-11-22T10:00:00Z', cwd: '/w/repo',
    }, now),
    [`${DIR}/plan-p-20261122T100000Z-4.jsonl`, { text: '', mtimeMs: now }],
  ])
  const { clock, toasts } = await start($, on, files)
  expect(toasts).toEqual([])

  files.set(...status('plan-p-20261122T100000Z-4', {
    state: 'done', thread_key: 'plan-p', round: null, started_at: '2026-11-22T10:00:00Z',
    ended_at: '2026-11-22T10:03:41Z', cwd: '/w/repo', exit: 1, verdict: 'REVISE',
  }, now + 1000))
  await clock.advance(1000)
  await clock.advance(1000)
  expect(toasts).toEqual(['codex plan: REVISE (3:41)'])

  const ui = await $.ui.mount(BAND('terminal'))
  expect(await ui.find({ type: 'Text', text: /codex/ })).toBeUndefined()
  await ui.unmount()
})

test('many runs that ended before the load are never toasted, however long it polls', async ($, on) => {
  const now = START + 72_000
  const files = new Map<string, File>()
  for (let i = 0; i < 60; i += 1) {
    files.set(...status(`review-r${i}-20261122T090000Z-${i}`, {
      state: 'done', thread_key: `review-r${i}`, round: 1, started_at: '2026-11-22T09:00:00Z',
      ended_at: '2026-11-22T09:30:00Z', cwd: '/w/repo', exit: 0, verdict: 'APPROVED',
    }, Date.parse('2026-11-22T09:30:00Z')))
  }
  const { clock, toasts } = await start($, on, files)
  running(files, 'review-new-1', 'review-new', 3, now + 500)
  await clock.advance(1000)
  finish(files, 'review-new-1', 'review-new', 3, now + 500, now + 60_500, 'REVISE')
  for (let i = 0; i < 5; i += 1) await clock.advance(1000)
  expect(toasts).toEqual(['codex review r3: REVISE (1:00)'])
})

test('a run already done at the load is not toasted, even one that ended a moment before', async ($, on) => {
  const files = new Map<string, File>()
  finish(files, 'review-e-1', 'review-e', 1, START + 60_000, START + 71_900, 'APPROVED')
  const { clock, toasts } = await start($, on, files)   // loaded at 10:01:12.000
  await clock.advance(1000)
  await clock.advance(1000)
  expect(toasts).toEqual([])
})

test('a run seen running at the load is toasted when it ends, however soon', async ($, on) => {
  const files = new Map<string, File>()
  running(files, 'review-s-1', 'review-s', 1, START + 60_000)
  const { clock, toasts } = await start($, on, files)
  finish(files, 'review-s-1', 'review-s', 1, START + 60_000, START + 72_001, 'APPROVED')
  await clock.advance(1000)
  expect(toasts).toEqual(['codex review r1: APPROVED (0:12)'])
})

test('an unreadable status, before or after the toast, never toasts twice or loses the run', async ($, on) => {
  const files = new Map<string, File>()
  running(files, 'review-f-1', 'review-f', 1, START + 60_000)
  const { clock, toasts } = await start($, on, files)
  const path = `${DIR}/review-f-1.status.json`
  files.set(path, { text: '{ half-written', mtimeMs: START + 73_000 })   // unreadable while running
  await clock.advance(1000)
  finish(files, 'review-f-1', 'review-f', 1, START + 60_000, START + 90_000, 'APPROVED')
  await clock.advance(1000)
  files.set(path, { text: '{ half-written', mtimeMs: START + 91_000 })   // unreadable after the toast
  await clock.advance(1000)
  finish(files, 'review-f-1', 'review-f', 1, START + 60_000, START + 90_000, 'APPROVED')
  await clock.advance(1000)
  expect(toasts).toEqual(['codex review r1: APPROVED (0:30)'])
})

test('a malformed status file is skipped without stopping the others', async ($, on) => {
  const now = START + 72_000
  const files = new Map<string, File>([
    [`${DIR}/bad-null.status.json`, { text: 'null', mtimeMs: now }],
    [`${DIR}/bad-cwd.status.json`, { text: JSON.stringify({ state: 'running', cwd: 42 }), mtimeMs: now }],
    [`${DIR}/bad-array.status.json`, { text: '[1, 2]', mtimeMs: now }],
  ])
  running(files, 'review-ok-1', 'review-ok', 1, START)
  const { clock, toasts } = await start($, on, files)
  const ui = await $.ui.mount(BAND('terminal'))
  expect((await ui.find({ type: 'Text', text: /codex review r1/ }))?.text).toContain('codex review r1')
  await ui.unmount()
  finish(files, 'review-ok-1', 'review-ok', 1, START, START + 80_000, 'APPROVED')
  await clock.advance(1000)
  expect(toasts).toEqual(['codex review r1: APPROVED (1:20)'])
})

test('a run whose event stream went quiet is not shown', async ($, on) => {
  const now = START + 72_000
  const files = new Map<string, File>([
    status('review-dead-20261122T100000Z-5', {
      state: 'running', thread_key: 'review-dead', round: 1, started_at: '2026-11-22T10:00:00Z', cwd: '/w/repo',
    }, now),
    [`${DIR}/review-dead-20261122T100000Z-5.jsonl`, { text: '', mtimeMs: now - 16 * 60 * 1000 }],
  ])
  await start($, on, files)
  const ui = await $.ui.mount(BAND('terminal'))
  expect(await ui.find({ type: 'Text', text: /codex/ })).toBeUndefined()
  await ui.unmount()
})

test('a session in a worktree sees runs from every worktree of its repository, named by folder', async ($, on) => {
  const now = START + 72_000
  const run = (name: string, cwd: string, repo: string, startedAt: string) => [
    status(name, { state: 'running', thread_key: name.split('-2026')[0], round: 1, started_at: startedAt, cwd, repo }, now),
    [`${DIR}/${name}.jsonl`, { text: '', mtimeMs: now }] as [string, File],
  ]
  const files = new Map<string, File>([
    ['/w/wt/feat/.git', { text: 'gitdir: /w/repo/.git/worktrees/feat\n', mtimeMs: 0 }],
    ['/w/repo/.git/worktrees/feat/commondir', { text: '../..\n', mtimeMs: 0 }],
    ...run('review-main-20261122T100000Z-1', '/w/repo', '/w/repo/.git', '2026-11-22T10:00:00Z'),
    ...run('review-x-20261122T100100Z-2', '/x', '/x/.git', '2026-11-22T10:01:00Z'),
  ])
  const { clock, toasts } = await start($, on, files, { cwd: '/w/wt/feat/src', dirs: new Set(['/w/repo/.git']) })
  const ui = await $.ui.mount(BAND('terminal'))
  expect((await ui.find({ type: 'Text', text: /codex review/ }))?.text).toBe('⟳ codex review r1 · repo · 1:12')
  await ui.unmount()

  files.set(...status('review-main-20261122T100000Z-1', {
    state: 'done', thread_key: 'review-main', round: 1, started_at: '2026-11-22T10:00:00Z',
    ended_at: '2026-11-22T10:02:00Z', cwd: '/w/repo', repo: '/w/repo/.git', exit: 0, verdict: 'APPROVED',
  }, now + 1000))
  files.set(...status('review-x-20261122T100100Z-2', {
    state: 'done', thread_key: 'review-x', round: 1, started_at: '2026-11-22T10:01:00Z',
    ended_at: '2026-11-22T10:02:00Z', cwd: '/x', repo: '/x/.git', exit: 0, verdict: 'APPROVED',
  }, now + 1000))
  await clock.advance(1000)
  expect(toasts).toEqual(['codex review r1 (repo): APPROVED (2:00)'])
})

test('a run in the session\'s own worktree carries no folder name', async ($, on) => {
  const now = START + 72_000
  const files = new Map<string, File>([
    ['/w/wt/feat/.git', { text: 'gitdir: /w/repo/.git/worktrees/feat\n', mtimeMs: 0 }],
    ['/w/repo/.git/worktrees/feat/commondir', { text: '../..\n', mtimeMs: 0 }],
    status('review-feat-20261122T100000Z-1', {
      state: 'running', thread_key: 'review-feat', round: 3, started_at: '2026-11-22T10:00:00Z',
      cwd: '/w/wt/feat', repo: '/w/repo/.git',
    }, now),
    [`${DIR}/review-feat-20261122T100000Z-1.jsonl`, { text: '', mtimeMs: now }],
  ])
  await start($, on, files, { cwd: '/w/wt/feat', dirs: new Set(['/w/repo/.git']) })
  const ui = await $.ui.mount(BAND('terminal'))
  expect((await ui.find({ type: 'Text', text: /codex review/ }))?.text).toBe('⟳ codex review r3 · 1:12')
  await ui.unmount()
})
