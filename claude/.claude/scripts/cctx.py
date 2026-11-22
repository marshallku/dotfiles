#!/usr/bin/env python3
"""cctx — find and read Claude Code and Codex sessions from their transcripts.

  cctx.py sessions [--since DAYS] [--cwd TEXT] [--limit N] [--all] [--json]
      recent sessions, newest first: last activity, tool, id, folder, prompt count, first prompt
  cctx.py find TEXT [--since DAYS] [--all] [--json]
      sessions whose typed prompts contain TEXT (a PR URL, a ticket id, a phrase), with the
      matching prompt and the command that resumes the session
  cctx.py prompts ID [--json]
      every prompt the owner typed in one session (ID or a unique prefix)

Only what a person typed counts: tool results, system reminders, hook feedback, command wrappers
and sidechains are skipped, and sessions a program started (`claude -p`, `codex exec`: reviews,
plugins) are left out unless --all. Reads ~/.claude/projects/*/*.jsonl and
~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl, files modified within --since days (default 14).

Why: agents re-wrote a transcript parser 195 times in 75 sessions on the work Mac, and 22 prompts
were "which session was doing this?". Linux and macOS, Python 3.8+, no dependencies.
"""
import argparse
import json
import os
from pathlib import Path
import sys
import time

DAY = 86400
EXCERPT = 70
NOISE_PREFIXES = (
    "<system-reminder>", "<task-notification>", "<command-message>", "<command-name>",
    "<local-command-stdout>", "<local-command-caveat>", "Stop hook feedback:", "[auto-review]",
    "Caveat: The messages below", "[Request interrupted by user", "Respond ONLY 'allow' or 'deny'.",
    "# AGENTS.md instructions", "<permissions instructions>", "<user_instructions>",
    "<system_instructions>", "<environment_context>", "<turn_aborted>",
    "Base directory for this skill:",  # a skill's body injected after /skill or the Skill tool
    "A session-scoped Stop hook is now active",  # /goal activation; typed_text() keeps its goal
)


def home():
    return Path(os.environ.get("HOME", str(Path.home())))


GOAL_PREFIX = "A session-scoped Stop hook is now active with condition: \""
GOAL_SUFFIX = "\". Briefly acknowledge the goal"


def typed_text(text):
    """What the owner typed, or "" for harness text. A /goal activation message wraps the goal the
    owner typed in harness prose: keep only the quoted condition."""
    stripped = text.strip()
    if stripped.startswith(GOAL_PREFIX):
        end = stripped.find(GOAL_SUFFIX, len(GOAL_PREFIX))
        return stripped[len(GOAL_PREFIX):end].strip() if end > 0 else ""
    if not stripped or stripped.startswith(NOISE_PREFIXES):
        return ""
    return stripped


def claude_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        # Text blocks only; tool_result blocks carry tool output, not typing. Injected text that
        # rides along (reminders, hook feedback) is dropped later by its prefix.
        return "\n".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
    return ""


def read_jsonl(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as stream:
            for line in stream:
                try:
                    yield json.loads(line)
                except ValueError:
                    continue
    except OSError:
        return


def claude_session(path, include_all):
    session = {"tool": "claude", "id": path.stem, "cwd": "", "prompts": [], "automated": False,
               "path": str(path), "last": path.stat().st_mtime}
    for record in read_jsonl(path):
        if record.get("type") != "user" or record.get("isSidechain"):
            continue
        session["cwd"] = session["cwd"] or record.get("cwd", "")
        if record.get("entrypoint") not in (None, "cli"):
            session["automated"] = True
        text = typed_text(claude_text((record.get("message") or {}).get("content")))
        if text:
            session["prompts"].append({"ts": record.get("timestamp", ""), "text": text})
    if session["automated"] and not include_all:
        return None
    return session


def codex_session(path, include_all):
    session = {"tool": "codex", "id": "", "cwd": "", "prompts": [], "automated": False,
               "path": str(path), "last": path.stat().st_mtime}
    for record in read_jsonl(path):
        kind, payload = record.get("type"), record.get("payload") or {}
        if kind == "session_meta":
            session["id"] = payload.get("id", "")
            session["cwd"] = payload.get("cwd", "")
            session["automated"] = payload.get("source") == "exec" or payload.get("originator") == "codex_exec"
            if session["automated"] and not include_all:
                return None
        elif kind == "response_item" and payload.get("role") == "user":
            if str(record.get("turn_id", "")).startswith("external-import-"):
                continue
            for part in payload.get("content") or []:
                # Only what was typed: input_text blocks (images, tool output and others are not).
                if not isinstance(part, dict) or part.get("type") != "input_text":
                    continue
                text = typed_text(part.get("text", ""))
                if text:
                    session["prompts"].append({"ts": record.get("timestamp", ""), "text": text})
    if not session["id"]:
        # rollout-<date>T<time>-<uuid>: the uuid is the last five dash groups.
        session["id"] = "-".join(path.stem.split("-")[-5:])
    return session


def transcripts(since_days, name_contains=""):
    """(path, reader) for transcripts modified within since_days (None = any age) whose file name
    contains name_contains (session ids are in both CLIs' file names)."""
    cutoff = None if since_days is None else time.time() - since_days * DAY
    roots = [(home() / ".claude/projects", f"*/*{name_contains}*.jsonl", claude_session),
             (home() / ".codex/sessions", f"*/*/*/rollout-*{name_contains}*.jsonl", codex_session)]
    for root, pattern, reader in roots:
        if not root.is_dir():
            continue
        for path in root.glob(pattern):
            try:
                if cutoff is None or path.stat().st_mtime >= cutoff:
                    yield path, reader
            except OSError:
                continue


def load(since_days, include_all, name_contains=""):
    sessions = []
    for path, reader in transcripts(since_days, name_contains):
        session = reader(path, include_all)
        if session and (session["prompts"] or include_all):
            sessions.append(session)
    sessions.sort(key=lambda s: s["last"], reverse=True)
    return sessions


def resume_command(session):
    return f"claude --resume {session['id']}" if session["tool"] == "claude" else f"codex resume {session['id']}"


def one_line(text, width=EXCERPT):
    flat = " ".join(text.split())
    return flat if len(flat) <= width else flat[: width - 1] + "…"


CONTEXT_CHARS = 45


def around(text, needle):
    """A one-line excerpt centred on the first case-insensitive occurrence of needle."""
    flat = " ".join(text.split())
    at = flat.lower().find(needle)
    if at < 0:
        return one_line(flat, 100)
    start, end = max(0, at - CONTEXT_CHARS), min(len(flat), at + len(needle) + CONTEXT_CHARS)
    return ("…" if start else "") + flat[start:end] + ("…" if end < len(flat) else "")


def stamp(epoch):
    return time.strftime("%m-%d %H:%M", time.localtime(epoch))


def summary(session):
    return {"tool": session["tool"], "id": session["id"], "cwd": session["cwd"],
            "last": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(session["last"])),
            "prompts": len(session["prompts"]), "first": session["prompts"][0]["text"] if session["prompts"] else "",
            "resume": resume_command(session)}


def cmd_sessions(args):
    rows = [s for s in load(args.since, args.all) if not args.cwd or args.cwd in s["cwd"]][: args.limit]
    if args.json:
        print(json.dumps([summary(s) for s in rows], ensure_ascii=False, indent=1))
        return 0
    for s in rows:
        first = s["prompts"][0]["text"] if s["prompts"] else ""
        print(f"{stamp(s['last'])}  {s['tool']:<6} {s['id'][:8]}  {len(s['prompts']):>3}  "
              f"{one_line(s['cwd'].replace(str(home()), '~'), 32):<32}  {one_line(first, 60)}")
    return 0


def cmd_find(args):
    needle = args.text.lower()
    hits = []
    for s in load(args.since, args.all):
        matches = [p for p in s["prompts"] if needle in p["text"].lower()]
        if matches:
            hits.append((s, matches))
    if args.json:
        print(json.dumps([{**summary(s), "matches": [m["text"] for m in matches]} for s, matches in hits],
                         ensure_ascii=False, indent=1))
        return 0 if hits else 1
    for s, matches in hits:
        print(f"{stamp(s['last'])}  {s['tool']:<6} {s['id']}  {s['cwd'].replace(str(home()), '~')}")
        for m in matches:
            print(f"    {m['ts'][:16]}  {around(m['text'], needle)}")
        print(f"    → {resume_command(s)}")
    if not hits:
        print(f"no session in the last {args.since} days has a prompt containing {args.text!r}", file=sys.stderr)
    return 0 if hits else 1


def cmd_prompts(args):
    # Any age: an id found by `find --since 400` must open. The id is in the file name, so only
    # those files are read.
    matches = [s for s in load(None, True, args.id) if s["id"].startswith(args.id)]
    if len(matches) != 1:
        print(f"{len(matches)} sessions match {args.id!r}" + (": " + ", ".join(s["id"] for s in matches[:5]) if matches else ""),
              file=sys.stderr)
        return 1
    session = matches[0]
    if args.json:
        print(json.dumps({**summary(session), "all": session["prompts"]}, ensure_ascii=False, indent=1))
        return 0
    print(f"{session['tool']} {session['id']}  {session['cwd']}  → {resume_command(session)}")
    for p in session["prompts"]:
        print(f"{p['ts'][:16]}  {p['text']}\n")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(prog="cctx", description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("sessions", "find", "prompts"):
        p = sub.add_parser(name)
        if name != "prompts":
            p.add_argument("--since", type=int, default=14, help="days")
        p.add_argument("--json", action="store_true")
        if name != "prompts":
            p.add_argument("--all", action="store_true", help="include program-started sessions")
        if name == "sessions":
            p.add_argument("--cwd", default="")
            p.add_argument("--limit", type=int, default=30)
        if name == "find":
            p.add_argument("text")
        if name == "prompts":
            p.add_argument("id")
    args = parser.parse_args(argv)
    return {"sessions": cmd_sessions, "find": cmd_find, "prompts": cmd_prompts}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
