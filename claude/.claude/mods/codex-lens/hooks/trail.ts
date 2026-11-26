// The steps of one codex run, folded from its `codex exec --json` event stream: what codex said,
// thought and ran, in order. Pure: register.tsx reads the file and hands the lines in.
import type { Step } from '../types'

const MAX_STEPS = 40
const SAY_CHARS = 600
const OUTPUT_LINES = 2
const OUTPUT_LINE_CHARS = 200

export function stripShell(command: string): string {
  return command.replace(/^"?\/\S*\/(ba|z)?sh -l?c /, '').replace(/^['"]|['"]$/g, '')
}

function lastLines(output: string): string[] {
  return output
    .split('\n')
    .map(line => line.trimEnd())
    .filter(line => line.trim() !== '')
    .slice(-OUTPUT_LINES)
    .map(line => (line.length > OUTPUT_LINE_CHARS ? `${line.slice(0, OUTPUT_LINE_CHARS - 1)}…` : line))
}

function textStep(kind: 'say' | 'think' | 'error', text: unknown): Step | undefined {
  if (typeof text !== 'string' || text.trim() === '') return undefined
  const trimmed = text.trim()
  return { kind, text: trimmed.length > SAY_CHARS ? `${trimmed.slice(0, SAY_CHARS - 1)}…` : trimmed }
}

type Item = { id?: unknown; type?: unknown; command?: unknown; exit_code?: unknown; aggregated_output?: unknown
  text?: unknown; summary?: unknown }

function asItem(value: unknown): Item | undefined {
  return typeof value === 'object' && value !== null ? (value as Item) : undefined
}

/**
* Folds one event into the steps. `nowMs` is when the line was seen live, or null while
* catching up on lines written before this load (their times are unknown).
* Unknown event and item types are ignored, so a newer codex adds nothing rather than breaking.
*/
export function applyEvent(steps: readonly Step[], event: unknown, nowMs: number | null): Step[] {
  if (typeof event !== 'object' || event === null) return [...steps]
  const { type, item: rawItem, error, message } = event as { type?: unknown; item?: unknown; error?: unknown
    message?: unknown }
  const item = asItem(rawItem)
  let next: Step[] = [...steps]

  if (type === 'item.started' && item?.type === 'command_execution') {
    next.push({
      kind: 'run', id: String(item.id ?? ''), command: stripShell(String(item.command ?? '')),
      isDone: false, exit: null, seenAtMs: nowMs, tookMs: null, output: [],
    })
  } else if (type === 'item.completed' && item?.type === 'command_execution') {
    const id = String(item.id ?? '')
    const exit = typeof item.exit_code === 'number' ? item.exit_code : null
    const output = exit !== 0 && typeof item.aggregated_output === 'string' ? lastLines(item.aggregated_output) : []
    const at = next.findIndex(step => step.kind === 'run' && step.id === id && !step.isDone)
    const started = at >= 0 ? next[at] : undefined
    if (started?.kind === 'run') {
      const tookMs = started.seenAtMs !== null && nowMs !== null ? nowMs - started.seenAtMs : null
      next[at] = { ...started, isDone: true, exit, tookMs, output }
    } else {
      next.push({
        kind: 'run', id, command: stripShell(String(item.command ?? '')), isDone: true, exit,
        seenAtMs: null, tookMs: null, output,
      })
    }
  } else if (type === 'item.completed' && item?.type === 'agent_message') {
    const step = textStep('say', item.text)
    if (step) next.push(step)
  } else if (type === 'item.completed' && item?.type === 'reasoning') {
    const step = textStep('think', item.text ?? item.summary)
    if (step) next.push(step)
  } else if (type === 'turn.failed') {
    const step = textStep('error', (error as { message?: unknown } | undefined)?.message ?? 'turn failed')
    if (step) next.push(step)
  } else if (type === 'error') {
    const step = textStep('error', message ?? 'error')
    if (step) next.push(step)
  }

  if (next.length > MAX_STEPS) next = next.slice(-MAX_STEPS)
  return next
}

/** Folds every whole JSON line of `text`; a line that does not parse is skipped. */
export function applyLines(steps: readonly Step[], text: string, nowMs: number | null): Step[] {
  let next: Step[] = [...steps]
  for (const line of text.split('\n')) {
    if (line.trim() === '') continue
    let event: unknown
    try {
      event = JSON.parse(line)
    } catch {
      continue
    }
    next = applyEvent(next, event, nowMs)
  }
  return next
}

/** UTF-8 bytes of `text`, so a file offset advances past exactly the characters consumed. */
export function utf8Length(text: string): number {
  let bytes = 0
  for (let i = 0; i < text.length; i += 1) {
    const code = text.charCodeAt(i)
    if (code < 0x80) bytes += 1
    else if (code < 0x800) bytes += 2
    else if (code >= 0xd800 && code <= 0xdbff) {
      bytes += 4
      i += 1
    } else bytes += 3
  }
  return bytes
}

/**
* Splits a chunk read from the file into the whole lines it holds and how many bytes they
* take; the unfinished last line stays in the file to be read again whole.
*/
export function wholeLines(chunk: string): { lines: string; bytes: number } {
  const end = chunk.lastIndexOf('\n')
  if (end < 0) return { lines: '', bytes: 0 }
  const lines = chunk.slice(0, end + 1)
  return { lines, bytes: utf8Length(lines) }
}

/** The newest command codex started, for the one-line band. */
export function lastCommandOf(steps: readonly Step[]): string {
  for (let i = steps.length - 1; i >= 0; i -= 1) {
    const step = steps[i]
    if (step?.kind === 'run') return step.command
  }
  return ''
}
