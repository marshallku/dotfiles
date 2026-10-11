#!/usr/bin/env python3
"""Small, argument-only bridges for the desktop shell."""

import ast
import html
import json
import math
import operator
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


def run(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, timeout=5, **kwargs).stdout


def cliphist():
    binary = shutil.which("cliphist") or str(Path.home() / ".local/bin/cliphist")
    if not Path(binary).is_file():
        raise ValueError("Install cliphist to enable clipboard history")
    return binary


def plain_text(value):
    return html.unescape(re.sub(r"<[^>]*>", "", str(value)))


def notifications(payload, now, uptime):
    rows = []
    for group in payload.get("data", []):
        for item in group:
            def field(key, default=""):
                return item.get(key, {}).get("data", default)

            rows.append({
                "id": int(field("id", 0)),
                "app": plain_text(field("appname")),
                "summary": plain_text(field("summary")),
                "body": plain_text(field("body")),
                "critical": field("urgency") == "CRITICAL",
                "time": (now - uptime + int(field("timestamp", 0)) / 1_000_000) * 1000,
            })
    return sorted(rows, key=lambda row: row["time"], reverse=True)[:100]


def clipboard_rows(output):
    rows = []
    for line in output.splitlines():
        identifier, separator, preview = line.partition("\t")
        if separator and identifier.isdecimal():
            rows.append({"id": identifier, "text": preview})
    return rows[:100]


OPERATORS = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.Div: operator.truediv,
    ast.Mod: operator.mod,
    ast.Pow: operator.pow,
}


def calculate(expression):
    if len(expression) > 100:
        raise ValueError("Expression too long")
    tree = ast.parse(expression, mode="eval")
    if len(list(ast.walk(tree))) > 32:
        raise ValueError("Expression too complex")

    def evaluate(node):
        if isinstance(node, ast.Constant) and type(node.value) in (int, float):
            result = node.value
        elif isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
            result = evaluate(node.operand) * (-1 if isinstance(node.op, ast.USub) else 1)
        elif isinstance(node, ast.BinOp) and type(node.op) in OPERATORS:
            left, right = evaluate(node.left), evaluate(node.right)
            if isinstance(node.op, ast.Pow) and (abs(right) > 10 or left < 0 and right % 1):
                raise ValueError("Exponent out of range")
            result = OPERATORS[type(node.op)](left, right)
        else:
            raise ValueError("Only arithmetic is supported")
        if not isinstance(result, (int, float)) or not math.isfinite(result) or abs(result) > 1e100:
            raise ValueError("Result out of range")
        return result

    result = evaluate(tree.body)
    return str(result) if isinstance(result, int) else format(result, ".12g")


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    argument = sys.argv[2] if len(sys.argv) > 2 else ""
    if command == "notifications":
        payload = json.loads(run(["dunstctl", "history"]))
        return {
            "items": notifications(payload, time.time(), time.monotonic()),
            "paused": run(["dunstctl", "is-paused"]).strip() == b"true",
            "waiting": int(run(["dunstctl", "count", "waiting"])),
            "displayed": int(run(["dunstctl", "count", "displayed"])),
        }
    if command == "notification-action":
        if argument in ("history-pop", "history-rm") and len(sys.argv) == 4 and sys.argv[3].isdecimal():
            run(["dunstctl", argument, sys.argv[3]])
        elif argument == "pause":
            run(["dunstctl", "set-paused", "toggle"])
        else:
            raise ValueError("Unknown notification action")
        return {}
    if command == "clipboard":
        binary = cliphist()
        cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
        if not (cache / "cliphist/db").exists():
            return {"items": []}
        return {"items": clipboard_rows(run([binary, "list"]).decode("utf-8", "replace"))}
    if command in ("clipboard-copy", "clipboard-delete"):
        if not argument.isdecimal():
            raise ValueError("Invalid clipboard ID")
        operation = "decode" if command == "clipboard-copy" else "delete"
        data = run([cliphist(), operation], input=argument.encode())
        if operation == "decode":
            run(["wl-copy"], input=data)
        return {}
    if command == "clipboard-store":
        os.execv(cliphist(), [cliphist(), "store"])
    if command == "calculate":
        return {"result": calculate(argument)}
    if command == "copy-text":
        run(["wl-copy", "--type", "text/plain"], input=argument.encode())
        return {}
    raise ValueError("Unknown desktop command")


if __name__ == "__main__":
    try:
        print(json.dumps({"ok": True, **main()}, ensure_ascii=False))
    except (ValueError, SyntaxError, ArithmeticError, OSError, subprocess.SubprocessError) as error:
        print(json.dumps({"ok": False, "error": str(error)}))
        sys.exit(1)
