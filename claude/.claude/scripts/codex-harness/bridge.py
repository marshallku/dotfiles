"""Adapt Codex events to the existing Claude command hooks; policies stay shared."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys


CLAUDE = Path(__file__).resolve().parents[2]
SUPPORTED = {
    "careful-with-judge.sh", "pre-commit-gate.sh", "commit-policy-gate.sh", "block-raw-git.sh",
    "protect-secrets.sh", "freeze.sh", "plan-ssot-gate.sh", "session-start.sh",
    "surface-open-loops.sh", "pre-compact.sh", "remind-cross-review.sh", "contract-inject.sh",
    "verification-gate.sh", "auto-cross-review.sh", "auto-handoff.sh", "track-edit.sh",
    "post-typecheck.sh", "ssot-check-mark.sh",
}
READ_ONLY_HOOKS = {"careful-with-judge.sh", "protect-secrets.sh", "freeze.sh"}


def normalized_events(payload):
    """A patch can edit/delete/move many files. Check both ends of every move."""
    tool = payload.get("tool_name", "")
    if tool in {"exec_command", "shell", "shell_command"}:
        args = payload.get("tool_input", {})
        command = args.get("command", args.get("cmd", ""))
        if isinstance(command, list):
            import shlex
            command = shlex.join(command)
        return [{**payload, "tool_name": "Bash", "tool_input": {"command": command}}]
    if tool == "update_plan":
        return [{**payload, "tool_name": "ExitPlanMode"}]
    if tool != "apply_patch":
        return [payload]
    args = payload.get("tool_input", {})
    patch = args if isinstance(args, str) else args.get("command", args.get("input", ""))
    paths = re.findall(r"^\*\*\* (?:Add File|Update File|Delete File|Move to): (.+)$", patch, re.MULTILINE)
    if not paths:
        raise ValueError("apply_patch contains no recognized file paths")
    checked_paths = []
    for path in paths:
        original = Path(payload["cwd"]) / path
        logical = Path(os.path.abspath(original))
        checked_paths.extend((str(logical), str(original.resolve())))
    return [
        {**payload, "tool_name": "Edit", "tool_input": {
            "file_path": path,
        }} for path in dict.fromkeys(checked_paths)
    ]


def configured_hooks(payload):
    settings = json.loads((CLAUDE / "settings.json").read_text())
    for group in settings.get("hooks", {}).get(payload["hook_event_name"], []):
        matcher = group.get("matcher")
        if matcher and not re.search(matcher, payload.get("tool_name", "")):
            continue
        for hook in group["hooks"]:
            name = hook.get("command", "").rsplit("/", 1)[-1]
            if name in SUPPORTED:
                yield name, hook.get("timeout", 30)


def run_hook(name, payload, timeout):
    result = subprocess.run(
        ["bash", str(CLAUDE / "hooks" / name)], input=json.dumps(payload),
        text=True, capture_output=True, cwd=payload["cwd"], timeout=timeout,
    )
    if result.stderr:
        print(result.stderr, file=sys.stderr, end="")
    if result.returncode:
        raise RuntimeError(f"{name} exited {result.returncode}: {result.stderr.strip()}")
    output = json.loads(result.stdout or "{}")
    # Some existing Claude hooks use a legacy, top-level decision shape.
    decision = output.get("permissionDecision")
    if decision in {"deny", "ask"}:
        reason = output.get("message", name)
        if decision == "ask":
            reason += " [Codex cannot implement hook 'ask'; run this operation manually if intended.]"
        return {"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason,
        }}
    return output


def command_ledger(payload):
    """Feed the shared verifier executed commands, without parsing unstable Codex transcripts."""
    ledger = Path.home() / ".claude/state/codex-commands" / f"{payload['session_id']}.jsonl"
    if payload["hook_event_name"] == "PostToolUse" and payload.get("tool_name") == "Bash":
        ledger.parent.mkdir(parents=True, exist_ok=True)
        record = {"type": "tool_use", "name": "Bash", "input": payload["tool_input"]}
        with ledger.open("a") as stream:
            stream.write(json.dumps(record) + "\n")
    return ledger


def dispatch(payload):
    session = payload.get("session_id", "")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", session):
        raise ValueError("Missing or invalid session_id")
    event = payload["hook_event_name"]
    outputs = []
    for normalized in normalized_events(payload):
        ledger = command_ledger(normalized)
        for name, timeout in configured_hooks(normalized):
            if os.environ.get("HARNESS_READ_ONLY_CHILD") == "1" and name not in READ_ONLY_HOOKS:
                continue
            hook_input = normalized
            if name == "verification-gate.sh":
                hook_input = {**normalized, "transcript_path": str(ledger)}
            outputs.append(run_hook(name, hook_input, timeout))
    for output in outputs:
        if output.get("hookSpecificOutput", {}).get("permissionDecision") == "deny":
            return output
    blocked = [output["reason"] for output in outputs if output.get("decision") == "block"]
    if blocked:
        return {"decision": "block", "reason": "\n\n".join(blocked)}
    context = [output.get("hookSpecificOutput", {}).get("additionalContext", "") for output in outputs]
    if event == "SessionStart" and os.environ.get("HARNESS_READ_ONLY_CHILD") != "1":
        context.append(f"Shared harness session ID: {session}. Use this exact ID with codex-review.sh --session. "
                       "Read ~/.codex/harness.md for Codex adaptations before using shared skills.")
    if any(context):
        return {"hookSpecificOutput": {"hookEventName": event, "additionalContext": "\n\n".join(filter(None, context))}}
    return {}


if __name__ == "__main__":
    try:
        print(json.dumps(dispatch(json.load(sys.stdin))))
    except (ValueError, KeyError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"[codex-harness] {error}", file=sys.stderr)
        sys.exit(2)
