// The pane: what the followed codex run said and ran, newest at the bottom, cut to the rows it
// has. Depth comes from indent, weight and dimming, not background color: terminals with a
// transparent background show no fill.
import type { EngineInterface } from 'claude-code'

import type { LiveRun, Step, Trail } from '../types'
import { label, mmss, took } from './format'

type Ui = ReturnType<EngineInterface['ui']['resolve']>

export type View = {
  trail: Trail | null
  live: LiveRun | null
  columns: number
  rows: number
}

const TEXT_LINES = 2
const HEADER_ROWS = 1
const STEP_INDENT = 2
const GLYPH_COLUMNS = 2

/** Rows one step takes at `columns`: a message wraps to at most two, a command one plus its output. */
export function rowsOf(step: Step, columns: number): number {
  if (step.kind === 'run') return 1 + step.output.length
  const width = Math.max(1, columns - GLYPH_COLUMNS)
  return Math.min(TEXT_LINES, Math.max(1, Math.ceil(step.text.length / width)))
}

/** The newest steps that fit in `rows`, and how many older ones are left out (a row says so). */
export function fit(steps: readonly Step[], columns: number, rows: number): { shown: Step[]; hidden: number } {
  const shown: Step[] = []
  let used = 0
  for (let i = steps.length - 1; i >= 0; i -= 1) {
    const step = steps[i]
    if (!step) continue
    const need = rowsOf(step, columns)
    const reserve = i > 0 ? 1 : 0
    if (used + need + reserve > rows) break
    shown.unshift(step)
    used += need
  }
  return { shown, hidden: steps.length - shown.length }
}

function isRunning(view: View): boolean {
  return view.live !== null && view.trail !== null && view.live.run === view.trail.run
}

function outcomeColor(outcome: string | null): string {
  if (outcome === 'APPROVED' || outcome === 'done') return 'success'
  if (outcome === 'REVISE') return 'warning'
  return 'error'
}

function header({ ui, view, trail }: { ui: Ui; view: View; trail: Trail }) {
  const { Box, Text } = ui
  const where = trail.where ? ` · ${trail.where}` : ''
  if (isRunning(view) && view.live) {
    return (
      <Box>
        <Text bold>{label(trail.kind, trail.round)}</Text>
        <Text dimColor>{where} · </Text>
        <Text color="claude">● {mmss(view.live.elapsed)}</Text>
      </Box>
    )
  }
  if (trail.endedAtMs !== null) {
    return (
      <Box>
        <Text bold>{label(trail.kind, trail.round)}</Text>
        <Text dimColor>{where} · </Text>
        <Text color={outcomeColor(trail.outcome)}>{trail.outcome ?? 'ended'}</Text>
        <Text dimColor> · {mmss((trail.endedAtMs - trail.startedAtMs) / 1000)}</Text>
      </Box>
    )
  }
  return (
    <Box>
      <Text bold>{label(trail.kind, trail.round)}</Text>
      <Text dimColor>{where} · </Text>
      <Text color="warning">no events lately</Text>
    </Box>
  )
}

function runRow({ ui, step, nowMs }: { ui: Ui; step: Extract<Step, { kind: 'run' }>; nowMs: number | null }) {
  const { Box, Text } = ui
  const pad = ' '.repeat(STEP_INDENT)
  if (!step.isDone) {
    const elapsed = step.seenAtMs !== null && nowMs !== null ? ` ${took(nowMs - step.seenAtMs)}` : ''
    return (
      <Box flexDirection="row">
        <Box flexGrow={1} flexShrink={1}>
          <Text bold wrap="truncate-end">{pad}<Text color="claude">▶</Text> {step.command}</Text>
        </Box>
        <Text color="claude">{elapsed}</Text>
      </Box>
    )
  }
  const isOk = step.exit === 0
  const time = step.tookMs !== null ? ` ${took(step.tookMs)}` : ''
  return (
    <Box flexDirection="column">
      <Box flexDirection="row">
        <Box flexGrow={1} flexShrink={1}>
          <Text dimColor={isOk} wrap="truncate-end">
            {pad}<Text color={isOk ? 'success' : 'error'}>{isOk ? '✓' : '✗'}</Text> {step.command}
          </Text>
        </Box>
        <Text dimColor>{isOk ? '' : ` exit ${step.exit ?? '?'}`}{time}</Text>
      </Box>
      {step.output.map(line => (
        <Text dimColor wrap="truncate-end">{pad}  │ {line}</Text>
      ))}
    </Box>
  )
}

// The glyph sits in a column of its own so a wrapped second line hangs under the text.
function textRow(ui: Ui, glyph: string, text: string, style: { color?: string; dimColor?: boolean; italic?: boolean }) {
  const { Box, Text } = ui
  return (
    <Box flexDirection="row">
      <Text {...style}>{glyph} </Text>
      <Box flexShrink={1}>
        <Text {...style} maxLines={TEXT_LINES}>{text}</Text>
      </Box>
    </Box>
  )
}

function stepRow({ ui, step, nowMs }: { ui: Ui; step: Step; nowMs: number | null }) {
  if (step.kind === 'run') return runRow({ ui, step, nowMs })
  if (step.kind === 'think') return textRow(ui, '∴', step.text, { dimColor: true, italic: true })
  if (step.kind === 'error') return textRow(ui, '✗', step.text, { color: 'error' })
  return textRow(ui, '›', step.text, {})
}

export function drawPane(ui: Ui, view: View) {
  const { Box, Text } = ui
  const { trail } = view
  if (!trail) {
    return (
      <Box flexDirection="column">
        <Text dimColor>No codex run in this repository yet.</Text>
        <Text dimColor>/cross-review, /codex-plan and /ask-codex runs show here as they work.</Text>
      </Box>
    )
  }
  const nowMs = isRunning(view) && view.live ? view.live.startedAtMs + view.live.elapsed * 1000 : null
  const { shown, hidden } = fit(trail.steps, view.columns, Math.max(1, view.rows - HEADER_ROWS))
  return (
    <Box flexDirection="column">
      {header({ ui, view, trail })}
      {hidden > 0 && <Text dimColor>  ⋮ {hidden} earlier</Text>}
      {shown.length === 0 && <Text dimColor>  waiting for codex…</Text>}
      {shown.map(step => stepRow({ ui, step, nowMs }))}
    </Box>
  )
}
