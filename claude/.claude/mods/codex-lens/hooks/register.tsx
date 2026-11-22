// Codex Lens: the codex run working for this folder, one line above the prompt, and its verdict
// as a toast when it ends.
//
// Data comes from ~/.claude/state/codex-live/, which ~/.claude/scripts/codex-exec.sh writes for
// every run: <key>-<run>.status.json ({state, thread_key, round, started_at, ended_at, cwd,
// events, exit, verdict}) and the raw `codex exec --json` stream in <key>-<run>.jsonl. Reading is
// a timer over those files; nothing else is started. Before this, 1,054 reviews (29.8 h) on the
// work Mac showed as one "waiting" line each.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { LiveRun } from '../types'

const live = atom({ plugin: 'codex-lens', key: 'live' } as const, null as LiveRun | null)
const watching = atom({ plugin: 'codex-lens', key: 'watching' } as const, [] as string[])

const POLL_MS = 1000
const DAY_MS = 24 * 60 * 60 * 1000
// A run still "running" whose event stream has not moved for this long died without saying so.
const STALE_MS = 15 * 60 * 1000
const TAIL_BYTES = 65536
const COMMAND_CHARS = 80

type Status = {
  state?: string
  thread_key?: string
  round?: number | null
  started_at?: string
  ended_at?: string | null
  cwd?: string
  events?: string
  exit?: number | null
  verdict?: string | null
}

type Run = { name: string; status: Status }

const STRING_FIELDS = ['state', 'thread_key', 'started_at', 'ended_at', 'cwd', 'events', 'verdict'] as const
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

// The run belongs to this session when one folder holds the other (a review runs at the
// repository root while the session may sit in a subfolder, or the reverse).
export function sameWork(runCwd: string | undefined, cwd: string): boolean {
  if (!runCwd) return false
  return runCwd === cwd || cwd.startsWith(`${runCwd}/`) || runCwd.startsWith(`${cwd}/`)
}

export function stripShell(command: string): string {
  return command.replace(/^"?\/\S*\/(ba|z)?sh -l?c /, '').replace(/^['"]|['"]$/g, '')
}

export function clip(text: string, max: number): string {
  const flat = text.replace(/\s+/g, ' ').trim()
  return flat.length <= max ? flat : `${flat.slice(0, max - 1)}…`
}

export function mmss(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds))
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
}

export function label(kind: string, round: number | null | undefined): string {
  return round ? `codex ${kind} r${round}` : `codex ${kind}`
}

// The newest command codex started, from the tail of its event stream.
export function lastCommandIn(tail: string): string {
  const lines = tail.split('\n')
  for (let i = lines.length - 1; i >= 0; i -= 1) {
    const line = lines[i] ?? ''
    if (!line.includes('"item.started"')) continue
    try {
      const event = JSON.parse(line)
      if (event?.type === 'item.started' && event.item?.type === 'command_execution') {
        return stripShell(String(event.item.command ?? ''))
      }
    } catch {
      // The tail's first line may be cut mid-record.
    }
  }
  return ''
}

async function tailOf($: EngineInterface, path: string): Promise<string> {
  const { size } = await $.fs.stat(path)
  const offset = Math.max(0, size - TAIL_BYTES)
  const text = await $.fs.read(path, { offset, length: size - offset })
  return typeof text === 'string' ? text : ''
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

// A run is toasted when this session saw it running and then sees it done: no timestamps, so
// nothing that ended before the load (never seen running) is toasted and no boundary can drop
// one that ends after. `watching` lives in $.state, so a run that ends while the mod reloads is
// still toasted by the next load. Only a run that starts and ends between two polls (one
// second; codex runs take minutes) goes unseen.
async function poll($: EngineInterface, dir: string, cwd: string) {
  const now = await $.clock.now()
  const listing = await runs($, dir, now)
  const mine = listing.runs.filter(run => sameWork(run.status.cwd, cwd))

  let current: LiveRun | null = null
  const running = mine
    .filter(run => run.status.state === 'running')
    .sort((a, b) => String(b.status.started_at).localeCompare(String(a.status.started_at)))
  for (const run of running) {
    const events = run.status.events ?? `${dir}/${run.name}.jsonl`
    const stat = await $.fs.stat(events).catch(() => undefined)
    if (!stat || now - stat.mtimeMs > STALE_MS) continue
    const startedAtMs = Date.parse(run.status.started_at ?? '') || now
    current = {
      run: run.name,
      kind: kindOf(run.status.thread_key),
      round: run.status.round ?? null,
      startedAtMs,
      lastCommand: lastCommandIn(await tailOf($, events).catch(() => '')),
      elapsed: Math.floor((now - startedAtMs) / 1000),
    }
    break
  }
  const before = await read($, live)
  const changed = JSON.stringify(before) !== JSON.stringify(current)
  if (changed) await update($, live, () => current)

  const watched = await read($, watching)
  const byName = new Map(mine.map(run => [run.name, run]))
  const next: string[] = []
  for (const name of watched) {
    const run = byName.get(name)
    if (run?.status.state === 'done') {
      const { status } = run
      const took = (Date.parse(status.ended_at ?? '') - Date.parse(status.started_at ?? '')) / 1000
      const outcome = status.verdict ?? (status.exit === 0 ? 'done' : `exit ${status.exit ?? '?'}`)
      $.ui.toast(`${label(kindOf(status.thread_key), status.round)}: ${outcome}${took > 0 ? ` (${mmss(took)})` : ''}`)
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
    const home = await $.env.get('HOME')
    const cwd = await $.session.cwd()
    if (home) {
      const dir = `${home}/.claude/state/codex-live`
      await poll($, dir, cwd).catch(() => undefined)
      $.clock.every(POLL_MS, () => poll($, dir, cwd).catch(() => undefined))
    }
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const run = e.props.hasSurvey ? null : await read($, live)
    if (!run) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const command = run.lastCommand ? ` · ▶ ${clip(run.lastCommand, COMMAND_CHARS)}` : ''
    return (
      <Box>
        <Text dimColor>
          ⟳ {label(run.kind, run.round)} · {mmss(run.elapsed)}
          {command}
        </Text>
      </Box>
    )
  })
}
