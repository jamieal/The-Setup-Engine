#!/usr/bin/env python3
"""Refresh the app catalog snapshot bundled with The Setup Engine.

The app reads Homebrew's public cask catalog (formulae.brew.sh/api/cask.json)
for download links and checksums. A snapshot of the entries for our curated
apps ships inside the app, so the first launch works even offline.

Usage:
    scripts/update-catalog-snapshot.py           # rewrite the snapshot
    scripts/update-catalog-snapshot.py --check   # exit 1 if any curated app is
                                                 # missing, deprecated or disabled
    scripts/update-catalog-snapshot.py --probe   # also try each download link the
                                                 # way the app does (Apple Silicon
                                                 # and Intel) and report refusals
"""
import json
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "The Setup Engine"
SNAPSHOT = SOURCES / "CatalogSnapshot.json"
API = "https://formulae.brew.sh/api/cask.json"

# Only the fields CaskParser reads.
KEEP = [
    "token", "name", "desc", "homepage", "version", "url", "sha256", "url_specs",
    "artifacts", "container", "depends_on", "auto_updates", "deprecated",
    "disabled", "deprecation_reason", "disable_reason", "variations",
]


def curated_tokens():
    """Every app token in the catalog, read from AppStore.swift (apps only)."""
    text = (SOURCES / "AppStore.swift").read_text()
    tokens = set()
    for line in text.splitlines():
        m = re.search(r'caskName: "([^"]+)"', line)
        if m and "kind: .commandLine" not in line:
            tokens.add(m.group(1))
    return sorted(tokens)


# Mirrors DirectInstaller's user agents.
CURL_UA = "TheSetupEngine/1.0 (Macintosh; arm64 Mac OS X 15.0) curl/8.7.1"
SAFARI_UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
             "(KHTML, like Gecko) Version/18.0 Safari/605.1.15")


def homebrew_only():
    text = (SOURCES / "AppStore.swift").read_text()
    m = re.search(r"homebrewOnly: Set<String> = \[([^\]]*)\]", text)
    return set(re.findall(r'"([^"]+)"', m.group(1))) if m else set()


def probe(cask):
    """Requests the first bytes of each download (Apple Silicon and Intel)."""
    urls = {"arm64": cask["url"]}
    intel = cask.get("variations", {}).get("sequoia", {}).get("url")
    if intel and intel != cask["url"]:
        urls["intel"] = intel
    ua = (cask.get("url_specs") or {}).get("user_agent")
    agent = SAFARI_UA if ua in (":fake", ":browser") else (ua or CURL_UA)
    problems = []
    for arch, url in urls.items():
        req = urllib.request.Request(url, headers={"User-Agent": agent, "Range": "bytes=0-1023"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                if r.headers.get_content_type() == "text/html":
                    problems.append(f"{arch}: got a web page instead of the app")
        except Exception as e:  # noqa: BLE001 — report every failure the same way
            problems.append(f"{arch}: {e}")
    return problems


def trim(cask):
    out = {k: cask[k] for k in KEEP if k in cask}
    out["artifacts"] = [a for a in cask.get("artifacts", []) if "app" in a or "pkg" in a]
    out["variations"] = {
        k: {f: v[f] for f in ("url", "sha256", "version", "artifacts", "depends_on", "container") if f in v}
        for k, v in cask.get("variations", {}).items()
        if not k.endswith("_linux")
    }
    return out


def main():
    probing = "--probe" in sys.argv
    check = "--check" in sys.argv or probing
    with urllib.request.urlopen(API, timeout=120) as r:
        by_token = {c["token"]: c for c in json.load(r)}

    problems = []
    snapshot = []
    for token in curated_tokens():
        cask = by_token.get(token)
        if cask is None:
            problems.append(f"{token}: no longer in Homebrew's catalog")
            continue
        if cask.get("disabled"):
            problems.append(f"{token}: disabled ({cask.get('disable_reason')})")
        elif cask.get("deprecated"):
            problems.append(f"{token}: deprecated ({cask.get('deprecation_reason')})")
        if not any("app" in a or "pkg" in a for a in cask.get("artifacts", [])):
            problems.append(f"{token}: has no app or installer package to install")
        if probing and token not in homebrew_only():
            problems += [f"{token}: download {p}" for p in probe(cask)]
        snapshot.append(trim(cask))

    for p in problems:
        print(f"::warning::{p}" if check else f"warning: {p}")

    if check:
        print(f"Checked {len(snapshot)} curated apps; {len(problems)} problem(s).")
        sys.exit(1 if problems else 0)

    SNAPSHOT.write_text(json.dumps(snapshot, indent=1, sort_keys=True) + "\n")
    print(f"Wrote {len(snapshot)} apps to {SNAPSHOT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
