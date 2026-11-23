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

declare module 'claude-code' {
  interface PluginState {
    'codex-lens': {
      live: LiveRun | null
      /** runs this session saw running, toasted and dropped when they are seen done */
      watching: string[]
    }
  }
}
