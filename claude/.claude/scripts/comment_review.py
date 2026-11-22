# /// script
# requires-python = ">=3.9"
# dependencies = ["tree-sitter-language-pack==1.25.2"]
# ///
"""Review the comments a diff adds: rule hits from comment_guard, plus comments that Haiku and
Sonnet both judge trim or delete against comment-review-rubric.md.

    comment_review.py [--cached | REV_RANGE]

stdout: a markdown finding list. Exit 0 no findings, 1 findings, 2 could not review.
Usage per call goes to ~/.claude/state/comment-review-usage.jsonl.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Dict, List, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comment_guard  # noqa: E402

HERE = Path(__file__).resolve().parent
MODELS = ("haiku", "sonnet")
VERDICTS = ("keep", "trim", "delete")
BATCH = 10
WORKERS = 4
CALL_TIMEOUT_SECS = int(os.environ.get("COMMENT_REVIEW_CALL_TIMEOUT", "180"))
USAGE_LOG = Path.home() / ".claude/state/comment-review-usage.jsonl"
SCHEMA = {
    "type": "object",
    "properties": {
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "id": {"type": "integer"},
                    "verdict": {"type": "string", "enum": list(VERDICTS)},
                    "category": {"type": "string"},
                    "replacement": {"type": "string"},
                },
                "required": ["id", "verdict", "category"],
            },
        }
    },
    "required": ["items"],
}


class ReviewError(Exception):
    pass


def added_comments(mode: List[str]) -> List[dict]:
    out = subprocess.run([sys.executable, str(HERE / "comment_guard.py"), "diff", *mode],
                         capture_output=True, text=True)
    if out.returncode != 0:
        raise ReviewError(out.stderr.strip() or f"comment_guard diff exited {out.returncode}")
    items = [json.loads(line) for line in out.stdout.splitlines() if line.strip()]
    for i, item in enumerate(items):
        item["id"] = i
    return items


def prompt_for(rubric: str, batch: List[dict]) -> str:
    parts = [
        "You review code comments for a codebase whose owner wants self-documenting code and minimal comments.",
        rubric,
        "Judge each comment below. For trim, put the one-line replacement in `replacement`. Return one entry per id.",
    ]
    for item in batch:
        parts.append(
            f"--- id={item['id']} lang={item['lang']} path={item['path']} lines {item['start']}-{item['end']}\n"
            f"COMMENT:\n{item['text']}\nCONTEXT:\n{item['context']}"
        )
    return "\n\n".join(parts)


def judge(model: str, rubric: str, batch: List[dict]) -> Tuple[List[dict], dict]:
    cmd = [
        os.environ.get("COMMENT_REVIEW_CLAUDE", "claude"), "-p", "--model", model, "--setting-sources", "",
        "--tools", "", "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}', "--no-session-persistence",
        "--disable-slash-commands", "--output-format", "json", "--json-schema", json.dumps(SCHEMA),
    ]
    started = time.time()
    try:
        out = subprocess.run(cmd, input=prompt_for(rubric, batch), capture_output=True, text=True,
                             timeout=CALL_TIMEOUT_SECS)
        if out.returncode != 0:
            raise ReviewError(f"{model} exited {out.returncode}: {out.stderr.strip()[-300:]}")
        result = json.loads(out.stdout)
        verdicts = result["structured_output"]["items"]
    except subprocess.TimeoutExpired as exc:
        raise ReviewError(f"{model} timed out after {CALL_TIMEOUT_SECS}s") from exc
    except OSError as exc:
        raise ReviewError(f"cannot run {cmd[0]}: {exc}") from exc
    except (json.JSONDecodeError, KeyError, TypeError) as exc:
        raise ReviewError(f"{model} returned no verdicts: {out.stderr.strip()[-300:]}") from exc
    if not isinstance(verdicts, list) or not all(
        isinstance(v, dict) and v.get("verdict") in VERDICTS and isinstance(v.get("id"), int) for v in verdicts
    ):
        raise ReviewError(f"{model} returned a malformed verdict")
    returned = sorted(v["id"] for v in verdicts)
    if returned != sorted(item["id"] for item in batch):
        raise ReviewError(f"{model} judged ids {returned}, expected {[item['id'] for item in batch]}")
    usage = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "model": model, "comments": len(batch),
        "cost_usd": result.get("total_cost_usd"), "secs": round(time.time() - started, 1),
    }
    return verdicts, usage


def record_usage(entries: List[dict]) -> None:
    try:
        USAGE_LOG.parent.mkdir(parents=True, exist_ok=True)
        with USAGE_LOG.open("a") as fh:
            for entry in entries:
                fh.write(json.dumps(entry) + "\n")
    except OSError as exc:
        print(f"comment-review: could not record usage: {exc}", file=sys.stderr)


def run_models(items: List[dict]) -> Dict[int, Dict[str, dict]]:
    rubric = (HERE / "comment-review-rubric.md").read_text()
    batches = [items[i : i + BATCH] for i in range(0, len(items), BATCH)]
    verdicts: Dict[int, Dict[str, dict]] = {}
    usage: List[dict] = []
    with ThreadPoolExecutor(max_workers=WORKERS * len(MODELS)) as pool:
        futures = [(m, pool.submit(judge, m, rubric, b)) for m in MODELS for b in batches]
        failure = None
        for model, future in futures:
            try:
                found, spent = future.result()
            except ReviewError as exc:
                failure = failure or exc
                continue
            usage.append(spent)
            for v in found:
                verdicts.setdefault(v["id"], {})[model] = v
    record_usage(usage)
    if failure:
        raise failure
    return verdicts


def finding(item: dict, votes: Dict[str, dict]) -> str:
    rules = [h for h in item["hits"] if h in comment_guard.REASONS]
    sonnet = votes.get("sonnet", {})
    verdict = "delete" if rules and sonnet.get("verdict", "keep") == "keep" else sonnet.get("verdict", "delete")
    why = ", ".join(rules) or sonnet.get("category", "")
    first = item["text"].splitlines()[0].strip()[:100]
    line = f"- `{item['path']}:{item['start']}` **{verdict}** ({why}): `{first}`"
    if verdict == "trim" and sonnet.get("replacement"):
        line += f"\n  → `{sonnet['replacement'].splitlines()[0][:160]}`"
    return line


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cached", action="store_true", help="the staged index against HEAD (default)")
    parser.add_argument("rev_range", nargs="?")
    args = parser.parse_args(argv)
    mode = [args.rev_range] if args.rev_range else ["--cached"]
    try:
        items = added_comments(mode)
        if not items:
            print("comment-review: no added comments")
            return 0
        verdicts = run_models(items)
    except ReviewError as exc:
        print(f"comment-review: could not review: {exc}", file=sys.stderr)
        return 2
    flagged = []
    for item in items:
        votes = verdicts.get(item["id"], {})
        agreed = all(votes.get(m, {}).get("verdict", "keep") != "keep" for m in MODELS)
        if agreed or any(h in comment_guard.REASONS for h in item["hits"]):
            flagged.append(finding(item, votes))
    print(f"comment-review: {len(items)} added comments, {len(flagged)} findings")
    if flagged:
        print("\n".join(flagged))
    return 1 if flagged else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
