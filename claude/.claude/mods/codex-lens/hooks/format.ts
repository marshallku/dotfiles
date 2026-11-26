export function clip(text: string, max: number): string {
  const flat = text.replace(/\s+/g, ' ').trim()
  return flat.length <= max ? flat : `${flat.slice(0, max - 1)}…`
}

export function mmss(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds))
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
}

/** A command's run time: `0.4s` under ten seconds, `1:05` from a minute. */
export function took(ms: number): string {
  const TENTHS_UNDER_MS = 10_000
  const MINUTE_MS = 60_000
  if (ms < TENTHS_UNDER_MS) return `${(Math.max(0, ms) / 1000).toFixed(1)}s`
  if (ms < MINUTE_MS) return `${Math.floor(ms / 1000)}s`
  return mmss(ms / 1000)
}

export function label(kind: string, round: number | null | undefined): string {
  return round ? `codex ${kind} r${round}` : `codex ${kind}`
}
