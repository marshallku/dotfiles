// Codex Lens: the codex run working for this folder, one line above the prompt, a pane that
// follows what it says and runs, and its verdict as a toast when it ends.
//
// Data comes from ~/.claude/state/codex-live/, which ~/.claude/scripts/codex-exec.sh writes for
// every run: <key>-<run>.status.json ({state, thread_key, round, started_at, ended_at, cwd,
// events, exit, verdict}) and the raw `codex exec --json` stream in <key>-<run>.jsonl. Reading is
// a timer over those files; nothing else is started.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { LiveRun, PaneChoice, Trail } from '../types'
import { clip, label, mmss } from './format'
import { drawPane } from './pane'
import { applyLines, lastCommandOf, wholeLines } from './trail'

const live = atom({ plugin: 'codex-lens', key: 'live' } as const, null as LiveRun | null)
const watching = atom({ plugin: 'codex-lens', key: 'watching' } as const, [] as string[])
const trail = atom({ plugin: 'codex-lens', key: 'trail' } as const, null as Trail | null, { shape: 'trail-1' })
const paneChoice = atom({ plugin: 'codex-lens', key: 'pane' } as const,
  { isPinned: false, dismissed: null } as PaneChoice, { shape: 'pane-1' })

const PANE = 'codex-lens'
const PANE_TITLE = 'Codex'
const COMMAND = 'codex-lens'
const POLL_MS = 1000
const DAY_MS = 24 * 60 * 60 * 1000
// A run still "running" whose event stream has not moved for this long died without saying so.
const STALE_MS = 15 * 60 * 1000
// $.fs.read's own cap on one ranged read.
const READ_BYTES = 4 * 1024 * 1024
// A run first seen this soon after it started is followed from its start, so its lines are timed.
const FRESH_MS = 3 * POLL_MS
const COMMAND_CHARS = 80
// Seated above the prompt (a narrow or non-fullscreen terminal), the pane keeps the transcript in view.
const INLINE_ROWS = 8

type Status = {
  state?: string
  thread_key?: string
  round?: number | null
  started_at?: string
  ended_at?: string | null
  cwd?: string
  repo?: string
  events?: string
  exit?: number | null
  verdict?: string | null
}

type Run = { name: string; status: Status }

const STRING_FIELDS = ['state', 'thread_key', 'started_at', 'ended_at', 'cwd', 'repo', 'events', 'verdict'] as const
const NUMBER_FIELDS = ['round', 'exit'] as const

// A status file as JSON gives `unknown`: keep it only when it is an object whose fields have the
// types codex-exec.sh writes (null allowed). One malformed file must not stop the whole poll.
export function asStatus(value: unknown): Status | undefined {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return undefined
  const record = value as Record<string, unknown>
  for (const key of STRING_FIELDS) {
    if (record[key] !== undefined && record[key] !== null && typeof record[key] !== 'string') return undefined
  }
  for (const key of NUMBER_FIELDS) {
    if (record[key] !== undefined && record[key] !== null && typeof record[key] !== 'number') return undefined
  }
  return record as Status
}

export function kindOf(key: string | undefined): string {
  if (key?.startsWith('review-')) return 'review'
  if (key?.startsWith('plan-')) return 'plan'
  return 'consult'
}

// One folder holds the other: a review runs at the repository root while the session may sit
// in a subfolder, or the reverse.
export function sameFolder(runCwd: string | undefined, cwd: string): boolean {
  if (!runCwd) return false
  return runCwd === cwd || cwd.startsWith(`${runCwd}/`) || runCwd.startsWith(`${cwd}/`)
}

export type Place = { cwd: string; repo: string | null }

// The run belongs to this session when it ran in the session's folder or in any worktree of the
// same repository (worktrees share the git common directory codex-exec.sh records as `repo`).
export function sameWork(status: Status, here: Place): boolean {
  return sameFolder(status.cwd, here.cwd) || (here.repo !== null && status.repo === here.repo)
}

// The worktree a run came from, named only when it is not the session's own folder.
export function whereOf(status: Status, here: Place): string {
  if (!status.cwd || sameFolder(status.cwd, here.cwd)) return ''
  return status.cwd.split('/').filter(Boolean).pop() ?? ''
}

export function normalize(path: string): string {
  const out: string[] = []
  for (const part of path.split('/')) {
    if (part === '' || part === '.') continue
    if (part === '..') out.pop()
    else out.push(part)
  }
  return `/${out.join('/')}`
}

function absolute(path: string, base: string): string {
  return normalize(path.startsWith('/') ? path : `${base}/${path}`)
}

async function realPath($: EngineInterface, path: string): Promise<string> {
  const stat = await $.fs.stat(path, { resolve: true }).catch(() => undefined)
  return stat?.realPath ?? normalize(path)
}

async function readText($: EngineInterface, path: string): Promise<string | undefined> {
  const text = await $.fs.read(path).catch(() => undefined)
  return typeof text === 'string' ? text : undefined
}

// The git common directory for a folder, read from disk as git does: `.git` is the directory
// itself, or in a worktree a file `gitdir: <dir>` whose `commondir` names the shared one.
export async function gitCommonDir($: EngineInterface, cwd: string): Promise<string | null> {
  for (let dir = normalize(cwd); ; dir = normalize(`${dir}/..`)) {
    const dotGit = `${dir}/.git`
    const stat = await $.fs.stat(dotGit).catch(() => undefined)
    if (stat?.kind === 'dir') return realPath($, dotGit)
    if (stat?.kind === 'file') {
      const pointer = (await readText($, dotGit))?.match(/^gitdir:\s*(.+?)\s*$/m)?.[1]
      if (!pointer) return null
      const gitdir = absolute(pointer, dir)
      const common = (await readText($, `${gitdir}/commondir`))?.trim()
      return realPath($, common ? absolute(common, gitdir) : gitdir)
    }
    if (dir === '/') return null
  }
}

/** How far this load has read one run's event stream. */
export type Cursor = { run: string; offset: number }

/**
 * Reads the event stream's new whole lines into the trail. A trail this load has not read yet
 * (a new run, or any run after a reload) is read again from the start; its lines are timed only
 * when the run began moments ago, else their times are unknown.
 * Every read begins at a line start and keeps whole lines only, so each decoded chunk is exact
 * UTF-8 and the offset moves by its own bytes; a line still being written waits for the next poll.
 */
export async function follow($: EngineInterface, path: string, base: Trail, cursor: Cursor | null,
                             now: number): Promise<{ trail: Trail; cursor: Cursor }> {
  const { size } = await $.fs.stat(path)
  const isCatchUp = cursor === null || cursor.run !== base.run || size < cursor.offset
  let offset = isCatchUp ? 0 : cursor.offset
  let steps = isCatchUp ? [] : base.steps
  const isLive = !isCatchUp || (base.steps.length === 0 && now - base.startedAtMs <= FRESH_MS)
  while (offset < size) {
    const length = Math.min(READ_BYTES, size - offset)
    const chunk = await $.fs.read(path, { offset, length })
    if (typeof chunk !== 'string') break
    const { lines, bytes } = wholeLines(chunk)
    if (bytes === 0) {
      // One line longer than a whole read: skip past it rather than stall on it forever.
      if (length === READ_BYTES) offset += READ_BYTES
      else break
      continue
    }
    steps = applyLines(steps, lines, isLive ? now : null)
    offset += bytes
  }
  return { trail: { ...base, steps }, cursor: { run: base.run, offset } }
}

function outcomeOf(status: Status): string {
  return status.verdict ?? (status.exit === 0 ? 'done' : `exit ${status.exit ?? '?'}`)
}

function trailOf(run: Run, here: Place, now: number): Trail {
  return {
    run: run.name,
    kind: kindOf(run.status.thread_key),
    round: run.status.round ?? null,
    where: whereOf(run.status, here),
    startedAtMs: Date.parse(run.status.started_at ?? '') || now,
    endedAtMs: null,
    outcome: null,
    steps: [],
  }
}

type Listing = {
  /** false when the directory could not be listed: nothing is known, nothing is pruned */
  ok: boolean
  /** every status file the directory holds, read or not */
  names: Set<string>
  runs: Run[]
}

async function runs($: EngineInterface, dir: string, now: number): Promise<Listing> {
  const entries = await $.fs.list(dir).catch(() => undefined)
  if (!entries) return { ok: false, names: new Set(), runs: [] }
  const names = new Set(entries.filter(e => e.name.endsWith('.status.json')).map(e => e.name.replace(/\.status\.json$/, '')))
  const found: Run[] = []
  for (const entry of entries) {
    if (!entry.name.endsWith('.status.json') || now - entry.mtimeMs > DAY_MS) continue
    try {
      const text = await $.fs.read(`${dir}/${entry.name}`)
      if (typeof text !== 'string') continue
      const status = asStatus(JSON.parse(text))
      if (status) found.push({ name: entry.name.replace(/\.status\.json$/, ''), status })
    } catch {
      // Being rewritten (codex-exec writes a temp file and renames it): the next poll reads it.
    }
  }
  return { ok: true, names, runs: found }
}

type Memo = { cursor: Cursor | null }

// The newest running run whose event stream still moves.
async function liveRun($: EngineInterface, dir: string, mine: Run[], now: number): Promise<Run | undefined> {
  const running = mine
    .filter(run => run.status.state === 'running')
    .sort((a, b) => String(b.status.started_at).localeCompare(String(a.status.started_at)))
  for (const run of running) {
    const stat = await $.fs.stat(run.status.events ?? `${dir}/${run.name}.jsonl`).catch(() => undefined)
    if (stat && now - stat.mtimeMs <= STALE_MS) return run
  }
  return undefined
}

// The pane follows the newest live run; once that run ends it keeps its steps and outcome
// until another starts, so a pinned pane still shows what the last run did.
async function followTrail($: EngineInterface, dir: string, here: Place, memo: Memo, now: number,
                           running: Run | undefined, byName: Map<string, Run>): Promise<Trail | null> {
  const before = await read($, trail)
  let next = running && before?.run !== running.name ? trailOf(running, here, now) : before
  if (!next || next.endedAtMs !== null) return next
  const run = byName.get(next.run)
  const followed = await follow($, run?.status.events ?? `${dir}/${next.run}.jsonl`, next, memo.cursor, now)
    .catch(() => undefined)
  if (followed) {
    next = followed.trail
    memo.cursor = followed.cursor
  }
  if (run?.status.state === 'done') {
    next = { ...next, endedAtMs: Date.parse(run.status.ended_at ?? '') || now, outcome: outcomeOf(run.status) }
  }
  return next
}

// Opens the pane when a run starts (unless the person closed it for that run) and closes it
// when the run ends, unless the person pinned it open with /codex-lens.
async function steerPane($: EngineInterface, before: Trail | null, after: Trail | null) {
  if (!after) return
  const choice = await read($, paneChoice)
  const isNew = after.endedAtMs === null && after.run !== before?.run
  if (isNew && choice.dismissed !== after.run) {
    await $.ui.open({ id: PANE, title: PANE_TITLE })
    return
  }
  const hasEnded = before?.run === after.run && before.endedAtMs === null && after.endedAtMs !== null
  if (hasEnded && !choice.isPinned) await $.ui.close({ id: PANE })
}

// A run is toasted when this session saw it running and then sees it done: no timestamps, so
// nothing that ended before the load (never seen running) is toasted and no boundary can drop
// one that ends after. `watching` lives in $.state, so a run that ends while the mod reloads is
// still toasted by the next load. Only a run that starts and ends between two polls (one
// second; codex runs take minutes) goes unseen.
async function poll($: EngineInterface, dir: string, here: Place, memo: Memo) {
  const now = await $.clock.now()
  const listing = await runs($, dir, now)
  const mine = listing.runs.filter(run => sameWork(run.status, here))
  const byName = new Map(mine.map(run => [run.name, run]))

  const running = await liveRun($, dir, mine, now)
  const trailBefore = await read($, trail)
  const trailAfter = await followTrail($, dir, here, memo, now, running, byName)
  if (JSON.stringify(trailBefore) !== JSON.stringify(trailAfter)) await update($, trail, () => trailAfter)
  await steerPane($, trailBefore, trailAfter).catch(() => undefined)

  let current: LiveRun | null = null
  if (running) {
    const startedAtMs = Date.parse(running.status.started_at ?? '') || now
    current = {
      run: running.name,
      kind: kindOf(running.status.thread_key),
      round: running.status.round ?? null,
      where: whereOf(running.status, here),
      startedAtMs,
      lastCommand: trailAfter?.run === running.name ? lastCommandOf(trailAfter.steps) : '',
      elapsed: Math.floor((now - startedAtMs) / 1000),
    }
  }
  const before = await read($, live)
  if (JSON.stringify(before) !== JSON.stringify(current)) await update($, live, () => current)

  const watched = await read($, watching)
  const next: string[] = []
  for (const name of watched) {
    const run = byName.get(name)
    if (run?.status.state === 'done') {
      const { status } = run
      const took = (Date.parse(status.ended_at ?? '') - Date.parse(status.started_at ?? '')) / 1000
      const where = whereOf(status, here)
      $.ui.toast(`${label(kindOf(status.thread_key), status.round)}${where ? ` (${where})` : ''}: ${outcomeOf(status)}`
        + `${took > 0 ? ` (${mmss(took)})` : ''}`)
      continue
    }
    // Gone from a listing that worked: forget it. Unreadable this time, or no listing: keep it.
    if (listing.ok && !listing.names.has(name)) continue
    next.push(name)
  }
  for (const run of mine) {
    if (run.status.state === 'running' && !next.includes(run.name)) next.push(run.name)
  }
  if (JSON.stringify(next) !== JSON.stringify(watched)) await update($, watching, () => next)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    // Without the command the pane still follows runs, so a refusal must not stop the polling.
    await $.command.register({
      name: COMMAND,
      description: 'Show or hide the pane following codex runs (shown, it stays open between runs)',
    }).catch(error => $.ui.log(`codex-lens: /${COMMAND} not registered: ${String(error)}`))
    const home = await $.env.get('HOME')
    const cwd = await $.session.cwd()
    if (home) {
      const dir = `${home}/.claude/state/codex-live`
      const here: Place = { cwd, repo: await gitCommonDir($, cwd).catch(() => null) }
      const memo: Memo = { cursor: null }
      await poll($, dir, here, memo).catch(() => undefined)
      $.clock.every(POLL_MS, () => poll($, dir, here, memo).catch(() => undefined))
    }
    return next(e)
  })

  on('command.run', { command: COMMAND }, async $ => {
    const isOpen = (await $.ui.panes()).some(pane => pane.id === PANE)
    if (isOpen) {
      await update($, paneChoice, choice => ({ ...choice, isPinned: false }))
      await $.ui.close({ id: PANE })
      return { text: 'Codex pane closed; it opens again when the next run starts.' }
    }
    await update($, paneChoice, () => ({ isPinned: true, dismissed: null }))
    await $.ui.open({ id: PANE, title: PANE_TITLE })
    return { text: 'Codex pane opened; it stays open between runs until /codex-lens again.' }
  }).catch(() => ({ text: 'Codex pane could not be toggled; see claude --debug.' }))

  on('ui.close', async ($, e, next) => {
    if (e.id === PANE && e.origin.kind === 'person') {
      const followed = await read($, trail)
      const dismissed = followed && followed.endedAtMs === null ? followed.run : null
      await update($, paneChoice, () => ({ isPinned: false, dismissed }))
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const rows = e.props.placement === 'inline' ? Math.min(INLINE_ROWS, e.props.scroll.bodyRows) : e.props.scroll.bodyRows
    return drawPane($.ui.resolve(e), {
      trail: await read($, trail),
      live: await read($, live),
      columns: e.props.bodyColumns,
      rows,
    })
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const run = e.props.hasSurvey ? null : await read($, live)
    if (!run) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const command = run.lastCommand ? ` · ▶ ${clip(run.lastCommand, COMMAND_CHARS)}` : ''
    return (
      <Box>
        <Text dimColor>
          ⟳ {label(run.kind, run.round)}
          {run.where ? ` · ${run.where}` : ''} · {mmss(run.elapsed)}
          {command}
        </Text>
      </Box>
    )
  })
}
