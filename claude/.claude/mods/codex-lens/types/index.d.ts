export type LiveRun = {
  /** codex-live file stem: <thread_key>-<UTC start>-<pid> */
  run: string
  /** review, plan or consult, from the thread key */
  kind: string
  round: number | null
  /** the worktree folder it runs in when that is not the session's own folder, else '' */
  where: string
  startedAtMs: number
  /** the newest command codex started, its shell wrapper stripped */
  lastCommand: string
  /** whole seconds since the start, as of the last poll; a change redraws the band */
  elapsed: number
}

export type Step =
  /** say: a message codex wrote (its preambles and its answer); think: a reasoning summary */
  | { kind: 'say' | 'think' | 'error'; text: string }
  | {
      kind: 'run'
      /** the event stream's item id, pairing a command's start with its end */
      id: string
      command: string
      isDone: boolean
      exit: number | null
      /** when this session first saw it start; null for steps read back after a load */
      seenAtMs: number | null
      tookMs: number | null
      /** the last lines of a failed command's output, else empty */
      output: string[]
    }

export type Trail = {
  run: string
  kind: string
  round: number | null
  where: string
  startedAtMs: number
  /** null while it runs */
  endedAtMs: number | null
  /** the verdict, `done` or `exit N` once it ended */
  outcome: string | null
  steps: Step[]
}

export type PaneChoice = {
  /** opened by the person's /codex-lens: it stays open between runs */
  isPinned: boolean
  /** the run whose pane the person closed: it is not reopened for that run */
  dismissed: string | null
}

declare module 'claude-code' {
  interface PluginState {
    'codex-lens': {
      live: LiveRun | null
      /** runs this session saw running, toasted and dropped when they are seen done */
      watching: string[]
      /** the steps of the run the pane follows: the running one, else the last that ran */
      trail: Shaped<Trail | null>
      pane: Shaped<PaneChoice>
    }
  }
}
