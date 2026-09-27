"""Install links only. Never replace independently managed skills or user config."""
from pathlib import Path
import sys


CLAUDE = Path(__file__).resolve().parents[2]


def links():
    home = Path.home()
    codex = home / ".codex"
    for name in ("AGENTS.md", "harness.md", "hooks.json"):
        yield CLAUDE.parent / ".codex" / name, codex / name
    for skill in sorted((CLAUDE / "skills").iterdir()):
        if not (skill / "SKILL.md").is_file():
            continue
        legacy = codex / "skills" / skill.name
        if legacy.exists():
            print(f"Keep existing Codex skill: {legacy}")
            continue
        yield skill, home / ".agents/skills" / skill.name


def install():
    planned = list(links())
    conflicts = [target for source, target in planned
                 if (target.exists() or target.is_symlink()) and target.resolve() != source.resolve()]
    if conflicts:
        raise RuntimeError("Refusing to replace existing paths: " + ", ".join(map(str, conflicts)))
    for source, target in planned:
        if not source.exists():
            raise RuntimeError(f"Missing source: {source}")
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_symlink() or target.exists():
            continue
        target.symlink_to(source)
        print(f"Link: {target} -> {source}")
    print("Restart Codex and review/trust the hooks in /hooks. Until trusted, hooks are skipped.")


if __name__ == "__main__":
    try:
        install()
    except (OSError, RuntimeError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
