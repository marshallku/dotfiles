Comment rubric. Ideal code needs no comments. A comment is worth keeping only when it carries
context the next maintainer cannot recover from the code, its names, its types or its tests.

Verdicts:
- keep: earns its place as written.
- trim: has a real kernel (a why, a constraint) but is padded: history, stats, narration,
  repetition, or several lines where one sentence would do.
- delete: carries nothing the code does not already say, or does not belong in code at all.

keep when the comment states:
- why, not what: a constraint, invariant, external quirk (OS, API, protocol, tool bug) or an
  ordering requirement that the code cannot express, stated as a present-tense fact;
- a non-obvious consequence of changing the line ("must run before X or Y deadlocks");
- a safety argument (Rust `// SAFETY:`), units or format of external data, a regex or bit
  layout that would take minutes to decode;
- doc comments on exported/public items (JSDoc on an exported function or interface, Rust `///`
  on pub items, Go doc on exported identifiers) that describe the contract: what callers must
  pass, what they get, errors, side effects. These are expected even when short;
- a TODO/FIXME that names an owner or ticket.

delete when the comment:
- restates the code or the identifier ("increment the counter", "// Foo returns a Foo");
- narrates steps ("First we...", "Now parse the config", "Step 2:");
- records history or process: what the code used to do, what changed, which review or codex
  round asked for it, "fixed X", "previously", "the old version", "no longer", dates of
  incidents, counts of past failures. That belongs in the commit message or PR, not the code;
- is an escape hatch: "for now", "placeholder", "simplified", "in a real implementation",
  "would need to", untracked TODO, or an excuse next to a stub instead of an implementation;
- is commented-out code, a banner/section divider, or emphatic noise (IMPORTANT!!, emoji);
- is a doc comment that adds no information beyond the signature.

trim when a keep-worthy kernel is wrapped in any of the delete material above; give the
one-line replacement.

Calibration (decided cases):
- A short doc on an exported/public item is keep if it adds anything beyond the identifier's
  words: when to call it, what a nil/false/empty result means, units, scope ("WithClock is for
  tests" is keep). It is delete only when it merely re-spells the name ("Gets a value.",
  "NewStore creates a new Store.", "Closes the open popover.").
- Plan unit labels (C2b, U6, WU3), plan file paths (docs/plans/...), review-round tags are process
  noise: trim. ADR, decision and ticket numbers are durable references: fine.
- Test comments that narrate the next step ("Now the list cannot be read", "the next key is
  timed") are delete; a test comment stating a non-obvious property being proven is keep.
- A file/module header: one or two lines of purpose is keep; a multi-paragraph tour of features
  or design history is trim.
- A why that is already a sentence or two is keep even if you could word it shorter. Reserve trim
  for comments with real padding.

Judge the comment in its context. Long is not automatically bad: a five-line explanation of a
real protocol quirk is keep. Short is not automatically good.
