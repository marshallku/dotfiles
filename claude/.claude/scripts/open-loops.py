#!/usr/bin/env python3
"""Open-loops note grammar (AIDE WU39) — the Python twin of aide/plugins/internal/loops/grammar.go.

The registry lives in the AIDE note `loops/open` (mirror: ~/docs/loops/open.md):

    # Open loops                      <- anything above the first "## " is kept verbatim

    ## <domain>
    - **<title>** · <status>[ · review YYYY-MM-DD] · `<id>`
      - <next action line>

Commands:
    open-loops.py parse <note.md|->            note → JSON {"items": [...]} (exit 1 + message if off-grammar)
    open-loops.py render <items.json|->        JSON {"items": [...]} → note (preamble "# Open loops")
    open-loops.py from-json <open-loops.json>  migrate the old registry: normalize titles, render, report changes
    open-loops.py overdue <note.md|-> [today]  active/incubating items past review_after, oldest first
    open-loops.py apply <note.md> <changes.json>
                                               the note with {id: {field: value}} applied (preamble kept);
                                               prints nothing and exits 1 unless every id survives and it parses
    open-loops.py selftest                     the grammar cases shared with the Go tests
"""
import datetime
import json
import re
import sys

STATUSES = {"active", "in_progress", "incubating", "closed"}
ITEM = re.compile(r"^- \*\*(.+?)\*\* · ([a-z_]+)(?: · review (\d{4}-\d{2}-\d{2}))? · `([a-z0-9][a-z0-9-]*)`$")
ID = re.compile(r"^[a-z0-9][a-z0-9-]*$")
DEFAULT_PREAMBLE = "# Open loops\n\n"


class GrammarError(ValueError):
    pass


def _valid_date(value):
    try:
        datetime.date.fromisoformat(value)
        return re.fullmatch(r"\d{4}-\d{2}-\d{2}", value) is not None
    except ValueError:
        return False


def check(item):
    title = item["title"]
    if not item.get("domain"):
        raise GrammarError("item outside a domain heading")
    if not ID.match(item["id"]):
        raise GrammarError(f"bad id {item['id']!r}")
    if item["status"] not in STATUSES:
        raise GrammarError(f"bad status {item['status']!r}")
    if item.get("review_after") and not _valid_date(item["review_after"]):
        raise GrammarError(f"bad review date {item['review_after']!r}")
    if not title or "`" in title or "\n" in title or "**" in title or " · " in title:
        raise GrammarError(f"bad title {title!r}")
    action = item.get("next_action") or ""
    if action and any(not line.strip() for line in action.split("\n")):
        raise GrammarError("empty next-action line")


def parse(body):
    lines = body.rstrip("\n").split("\n")
    i = 0
    while i < len(lines) and not lines[i].startswith("## "):
        i += 1
    for n, line in enumerate(lines[:i]):
        if ITEM.match(line) or line.startswith("  - "):
            raise GrammarError(f"line {n + 1}: item outside a domain heading")
    if i == len(lines):
        return {"preamble": body, "items": []}
    preamble = "\n".join(lines[:i]) + "\n" if i > 0 else ""
    items, seen, domain, current = [], set(), "", None
    for n, line in enumerate(lines[i:], start=i + 1):
        if not line.strip():
            current = None
        elif line.startswith("## ") and line[3:].strip():
            domain, current = line[3:].strip(), None
        elif line.startswith("  - ") and current is not None:
            text = line[len("  - "):]
            current["next_action"] = (current["next_action"] + "\n" + text) if current["next_action"] else text
        elif ITEM.match(line):
            title, status, review, item_id = ITEM.match(line).groups()
            item = {"id": item_id, "title": title, "domain": domain, "status": status,
                    "next_action": "", "review_after": review or ""}
            try:
                check(item)
            except GrammarError as e:
                raise GrammarError(f"line {n}: {e}")
            if item_id in seen:
                raise GrammarError(f"line {n}: duplicate id {item_id}")
            seen.add(item_id)
            items.append(item)
            current = item
        else:
            raise GrammarError(f"line {n}: {line!r}")
    return {"preamble": preamble, "items": items}


def render(doc):
    preamble = doc.get("preamble") or DEFAULT_PREAMBLE
    out = [preamble]
    if doc["items"] and not preamble.endswith("\n"):
        out.append("\n")
    order, by_domain = [], {}
    for item in doc["items"]:
        check(item)
        if item["domain"] not in by_domain:
            order.append(item["domain"])
            by_domain[item["domain"]] = []
        by_domain[item["domain"]].append(item)
    for n, domain in enumerate(order):
        if n:
            out.append("\n")
        out.append(f"## {domain}\n")
        for item in by_domain[domain]:
            review = f" · review {item['review_after']}" if item.get("review_after") else ""
            out.append(f"- **{item['title']}** · {item['status']}{review} · `{item['id']}`\n")
            for line in (item.get("next_action") or "").split("\n") if item.get("next_action") else []:
                out.append(f"  - {line}\n")
    return "".join(out)


SUBSTITUTIONS = [("**", "*"), ("`", "'"), (" · ", " - ")]


def normalize(item):
    """The old registry's free text → grammar-safe values, and a list of what changed."""
    changes = []
    title = " ".join(item.get("title", "").split("\n")).strip()
    for old, new in SUBSTITUTIONS:
        if old in title:
            changes.append(f"{item['id']}: title {old!r} → {new!r}")
            title = title.replace(old, new)
    action_lines = [line.rstrip() for line in (item.get("next_action") or "").split("\n") if line.strip()]
    if (item.get("next_action") or "") != "\n".join(action_lines):
        changes.append(f"{item['id']}: next_action blank lines/trailing spaces dropped")
    out = {"id": item["id"], "title": title, "domain": item.get("domain") or "misc",
           "status": item["status"], "next_action": "\n".join(action_lines),
           "review_after": item.get("review_after") or ""}
    if not item.get("domain"):
        changes.append(f"{item['id']}: no domain → misc")
    return out, changes


def apply_changes(body, changes):
    """Apply {id: {status|next_action|review_after|title|domain: value}} to a note; returns the new note."""
    doc = parse(body)
    by_id = {item["id"]: item for item in doc["items"]}
    unknown = sorted(set(changes) - set(by_id))
    if unknown:
        raise GrammarError(f"unknown id(s): {', '.join(unknown)}")
    allowed = {"status", "next_action", "review_after", "title", "domain"}
    for item_id, change in changes.items():
        extra = set(change) - allowed
        if extra:
            raise GrammarError(f"{item_id}: can't change {', '.join(sorted(extra))}")
        by_id[item_id].update({k: (v or "") for k, v in change.items()})
    out = render(doc)
    after = parse(out)["items"]
    if sorted(item["id"] for item in after) != sorted(by_id):  # a domain move may reorder; nothing may go
        raise GrammarError("items would be lost")
    return out


def _read(path):
    return sys.stdin.read() if path == "-" else open(path, encoding="utf-8").read()


def overdue(doc, today):
    rows = []
    for item in doc["items"]:
        if item["status"] in ("active", "incubating") and item["review_after"]:
            days = (today - datetime.date.fromisoformat(item["review_after"])).days
            if days > 0:
                rows.append((days, item))
    return sorted(rows, key=lambda row: -row[0])


SAMPLE = ("# Open loops\n\n## home-infra\n- **CF 토큰 IP 필터** · active · review 2026-10-12 · `cf-token`\n"
          "  - 필터 갱신\n  - A 레코드 확인\n- **오래된 일** · closed · `old-thing`\n\n## projects\n"
          "- **aide 푸시** · in_progress · `aide-push`\n")


def selftest():
    doc = parse(SAMPLE)
    assert len(doc["items"]) == 3 and doc["items"][0]["next_action"] == "필터 갱신\nA 레코드 확인", doc
    assert render(doc) == SAMPLE
    for body in ["# x\n- **a** · active · `a`\n", "## d\n- **a** · done · `a`\n", "## d\n- **a** · active · `A_b`\n",
                 "## d\n- **a** · active · `a`\n- **b** · active · `a`\n", "## d\n- **a** · active · `a`\nprose\n",
                 "## d\n\n  - next\n", "## d\n- **a** · active · review 2026-02-30 · `a`\n"]:
        try:
            parse(body)
        except GrammarError:
            continue
        raise AssertionError(f"accepted {body!r}")
    verbatim = "# Open loops  \n\n> 저녁마다 갱신됨\n\n\n## d\n- **a** · active · `a`\n"
    assert render(parse(verbatim)) == verbatim
    bare = parse("# Open loops")
    bare["items"].append({"id": "a", "title": "a", "domain": "d", "status": "active", "next_action": "", "review_after": ""})
    assert render(bare) == "# Open loops\n## d\n- **a** · active · `a`\n"
    item, changes = normalize({"id": "x", "title": "a **b** `c` · d", "domain": "d", "status": "active",
                               "next_action": "one\n\ntwo  "})
    assert item["title"] == "a *b* 'c' - d" and item["next_action"] == "one\ntwo" and len(changes) == 4, (item, changes)
    applied = apply_changes(SAMPLE, {"cf-token": {"status": "closed", "next_action": "갱신 완료", "review_after": None}})
    assert "· closed · `cf-token`\n  - 갱신 완료\n" in applied and applied.startswith("# Open loops\n\n## home-infra"), applied
    for bad in ({"nope": {"status": "closed"}}, {"cf-token": {"status": "done"}}, {"cf-token": {"id": "x"}}):
        try:
            apply_changes(SAMPLE, bad)
        except GrammarError:
            continue
        raise AssertionError(f"applied {bad}")
    print("ok")


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    command = argv[1]
    try:
        if command == "parse":
            doc = parse(_read(argv[2]))
            json.dump({"items": doc["items"]}, sys.stdout, ensure_ascii=False, indent=2)
            print()
        elif command == "render":
            sys.stdout.write(render({"items": json.loads(_read(argv[2]))["items"]}))
        elif command == "from-json":
            data = json.loads(_read(argv[2]))
            items, report = [], []
            for raw in data.get("items", []):
                item, changes = normalize(raw)
                items.append(item)
                report += changes
            body = render({"items": items})
            # Rendering groups items by domain, so compare by id, not by position.
            by_id = lambda rows: {row["id"]: row for row in rows}
            if by_id(parse(body)["items"]) != by_id(items) or len(parse(body)["items"]) != len(items):
                raise GrammarError("round trip differs from the normalized registry")
            sys.stdout.write(body)
            for line in report:
                print("normalized:", line, file=sys.stderr)
        elif command == "overdue":
            today = datetime.date.fromisoformat(argv[3]) if len(argv) > 3 else datetime.date.today()
            for days, item in overdue(parse(_read(argv[2])), today):
                print(f"[{days}d] {item['id']} · {item['domain']} · {item['status']} · review_after={item['review_after']}")
                print(f"      next_action: {item['next_action'][:200]}")
        elif command == "apply":
            out = apply_changes(_read(argv[2]), json.loads(_read(argv[3])))
            sys.stdout.write(out)
        elif command == "selftest":
            selftest()
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except GrammarError as e:
        print(f"open-loops: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
