#!/usr/bin/env python3
"""Keep plugins.html in step with the awac-ai-agent-plugins marketplace manifests.

Rewrites the facts that are mechanical (version numbers, Claude Code / Codex target
tags). Everything else on the page is hand-written prose in three languages, so the
script does not touch it — it *verifies* it instead and fails loudly when the page
and the manifests disagree about which plugins exist or how many there are.

Usage:
    python3 scripts/sync-plugins.py            # fetch manifests from GitHub, rewrite
    python3 scripts/sync-plugins.py --check    # verify only, non-zero exit on drift
    python3 scripts/sync-plugins.py --local ../awac-ai-agent-plugins
"""

import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

REPO = "IvanLutsenko/awac-ai-agent-plugins"
BRANCH = "main"
CLAUDE_MANIFEST = ".claude-plugin/marketplace.json"
CODEX_MANIFEST = ".agents/plugins/marketplace.json"

ROOT = Path(__file__).resolve().parent.parent
PAGES = [ROOT / "plugins.html", ROOT / "index.html"]

TARGET_LABELS = {
    # data-lang -> (dual target, Claude Code only)
    "en": ("Claude Code + Codex", "Claude Code only"),
    "uk": ("Claude Code + Codex", "Лише Claude Code"),
    "ru": ("Claude Code + Codex", "Только Claude Code"),
}

# Word forms of the plugin count that appear in prose and meta tags. The script only
# checks these — rewriting Russian and Ukrainian numerals is not worth the machinery.
COUNT_WORDS = {
    8: ["eight plugins", "Eight plugins", "8 plugins",
        "восьми плагинов", "восьми плагінів", "Восемь плагинов", "Вісім плагінів",
        "8 плагинов", "8 плагінів"],
}


def load_manifests(local: str | None) -> tuple[dict, dict]:
    def read(rel: str) -> dict:
        if local:
            return json.loads((Path(local) / rel).read_text(encoding="utf-8"))
        url = f"https://raw.githubusercontent.com/{REPO}/{BRANCH}/{rel}"
        with urllib.request.urlopen(url, timeout=30) as r:
            return json.loads(r.read().decode("utf-8"))

    return read(CLAUDE_MANIFEST), read(CODEX_MANIFEST)


def plugin_facts(claude: dict, codex: dict) -> dict[str, dict]:
    dual = {p["name"] for p in codex["plugins"]}
    facts = {}
    for p in claude["plugins"]:
        name = p["name"]
        facts[name] = {"version": p["version"], "dual": name in dual}
    return facts


def rewrite(html: str, facts: dict[str, dict]) -> tuple[str, list[str]]:
    """Rewrite version and target tag bodies in place. Returns (html, changes)."""
    changes = []

    def version_sub(m):
        pid, body = m.group("pid"), m.group("body")
        want = "v" + facts[pid]["version"] if pid in facts else body
        if body != want:
            changes.append(f"{pid}: версия {body} -> {want}")
        return m.group(0).replace(f">{body}<", f">{want}<")

    html = re.sub(
        r'<span class="tag tag-ver" data-plugin="(?P<pid>[a-z-]+)">(?P<body>[^<]*)</span>',
        version_sub, html)

    def target_sub(m):
        pid, lang, body = m.group("pid"), m.group("lang"), m.group("body")
        if pid not in facts:
            return m.group(0)
        dual_label, only_label = TARGET_LABELS[lang]
        want = dual_label if facts[pid]["dual"] else only_label
        if body != want:
            changes.append(f"{pid}/{lang}: таргет {body!r} -> {want!r}")
        return m.group(0).replace(f">{body}<", f">{want}<")

    html = re.sub(
        r'<span class="tag tag-target(?: active)?" data-plugin="(?P<pid>[a-z-]+)"'
        r' data-lang="(?P<lang>en|uk|ru)">(?P<body>[^<]*)</span>',
        target_sub, html)

    return html, changes


def verify(html: str, path: Path, facts: dict[str, dict]) -> list[str]:
    """Checks the script deliberately does not auto-fix, because each needs prose."""
    problems = []
    on_page = set(re.findall(r'<article class="plugin" id="([a-z-]+)">', html))
    if on_page:
        missing = sorted(set(facts) - on_page)
        extra = sorted(on_page - set(facts))
        if missing:
            problems.append(
                f"{path.name}: в манифесте есть, на странице нет: {', '.join(missing)} "
                f"— нужна карточка с описанием на трёх языках")
        if extra:
            problems.append(
                f"{path.name}: на странице есть, в манифесте нет: {', '.join(extra)} "
                f"— плагин удалён или переименован")

    expected = len(facts)
    for count, words in COUNT_WORDS.items():
        if count == expected:
            continue
        for w in words:
            if w in html:
                problems.append(
                    f"{path.name}: текст говорит про {count} плагинов ({w!r}), "
                    f"а в манифесте их {expected}")
                break
    return problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="только проверка, без записи")
    ap.add_argument("--local", help="путь к локальному клону репы плагинов")
    args = ap.parse_args()

    try:
        claude, codex = load_manifests(args.local)
    except Exception as e:  # сеть, 404, битый json — всё это должно валить прогон
        print(f"не удалось прочитать манифесты: {e}", file=sys.stderr)
        return 2

    facts = plugin_facts(claude, codex)
    print(f"манифест: {len(facts)} плагинов, dual-target {sum(f['dual'] for f in facts.values())}")

    all_changes, all_problems = [], []
    for path in PAGES:
        html = path.read_text(encoding="utf-8")
        new_html, changes = rewrite(html, facts)
        all_problems += verify(new_html, path, facts)
        if changes:
            all_changes += [f"{path.name}: {c}" for c in changes]
            if not args.check:
                path.write_text(new_html, encoding="utf-8")

    for c in all_changes:
        print(("[drift] " if args.check else "[fixed] ") + c)
    for p in all_problems:
        print("[!] " + p, file=sys.stderr)

    if not all_changes and not all_problems:
        print("всё сходится")

    if all_problems:
        return 1
    if args.check and all_changes:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
