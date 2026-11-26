import { expect, test } from 'claude-code/testing'

import { applyLines, lastCommandOf, utf8Length, wholeLines } from '../hooks/trail'

const line = (event: unknown) => `${JSON.stringify(event)}\n`
const started = (id: string, command: string) =>
  line({ type: 'item.started', item: { id, type: 'command_execution', command, aggregated_output: '', exit_code: null } })
const completed = (id: string, command: string, exit: number, output = '') =>
  line({ type: 'item.completed', item: { id, type: 'command_execution', command, aggregated_output: output, exit_code: exit } })

test('a command start and end pair by item id, timed when seen live', () => {
  let steps = applyLines([], started('item_1', "/usr/bin/zsh -lc 'rg -n foo src'"), 1000)
  expect(lastCommandOf(steps)).toBe('rg -n foo src')
  steps = applyLines(steps, completed('item_1', "/usr/bin/zsh -lc 'rg -n foo src'", 0, 'src/a.ts:1:foo\n'), 1400)
  expect(steps).toEqual([{
    kind: 'run', id: 'item_1', command: 'rg -n foo src', isDone: true, exit: 0, seenAtMs: 1000, tookMs: 400, output: [],
  }])
})

test('a failed command keeps its last two output lines; read back after a load it has no times', () => {
  const text = started('item_2', 'bash t.sh') + completed('item_2', 'bash t.sh', 1, 'one\ntwo\n\nthree\n')
  const [step] = applyLines([], text, null)
  expect(step).toEqual({
    kind: 'run', id: 'item_2', command: 'bash t.sh', isDone: true, exit: 1, seenAtMs: null, tookMs: null,
    output: ['two', 'three'],
  })
})

test('messages, reasoning summaries and failures become steps; unknown events and bad lines are skipped', () => {
  const text = [
    line({ type: 'thread.started', thread_id: 't' }),
    line({ type: 'item.completed', item: { id: 'item_0', type: 'agent_message', text: 'I’ll trace the retry path.' } }),
    line({ type: 'item.completed', item: { id: 'item_1', type: 'reasoning', text: 'Checking the backoff.' } }),
    line({ type: 'item.completed', item: { id: 'item_2', type: 'some_future_item', text: 'x' } }),
    '{ not json\n',
    line({ type: 'turn.failed', error: { message: 'stream disconnected' } }),
  ].join('')
  expect(applyLines([], text, 5)).toEqual([
    { kind: 'say', text: 'I’ll trace the retry path.' },
    { kind: 'think', text: 'Checking the backoff.' },
    { kind: 'error', text: 'stream disconnected' },
  ])
})

test('only the newest 40 steps are kept', () => {
  let text = ''
  for (let i = 0; i < 45; i += 1) text += line({ type: 'item.completed', item: { type: 'agent_message', text: `m${i}` } })
  const steps = applyLines([], text, 0)
  expect(steps.length).toBe(40)
  expect(steps[0]).toEqual({ kind: 'say', text: 'm5' })
})

test('whole lines are counted in UTF-8 bytes and the unfinished line is left for later', () => {
  expect(utf8Length('a한’😀')).toBe(1 + 3 + 3 + 4)
  const chunk = `{"t":"한글"}\n{"t":"cut`
  expect(wholeLines(chunk)).toEqual({ lines: '{"t":"한글"}\n', bytes: 15 })
  expect(wholeLines('no newline yet')).toEqual({ lines: '', bytes: 0 })
})
