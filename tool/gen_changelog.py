#!/usr/bin/env python3
"""Generate the Play release notes for the version being released.

Ported from klutch-app's tool/gen_changelog.py. **The source is the code, not
the commit log**: this reads the diff between the last *released* tag and this
one, asks Google Gemini what a person using the app would notice, and writes
the file `fastlane supply` uploads with the release:

    android/fastlane/metadata/android/en-US/changelogs/<versionCode>.txt

Run from the repo root (`make changelog`). CI runs it in `publish_internal`
just before the upload; see .circleci/config.yml and docs/release.md.

What the model is shown: `lib/**`, the hand-written Dart. Tests, docs, CI,
tooling, lockfiles, platform scaffolding, the design file and binary assets are
dropped: none of it changes what a user sees, and all of it would crowd out the
code that does.

Three deliberate behaviours, because a release must not hinge on this:

  * **A committed changelog wins.** If the file for this versionCode exists,
    it is kept. Hand-write one when the release deserves better words than a
    model will find. `--force` overrides.
  * **A failure never fails the release.** No key, a refusal, a 500: it warns
    loudly, writes a neutral line and exits 0. `--strict` inverts that.
  * **Nothing is invented.** The prompt forbids claiming anything the diff
    doesn't show. Read the output before testers do; CI prints it and keeps it
    as an artifact.

No third-party Python packages: the publishing job has python3 and git, and
deliberately no Flutter toolchain.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

# Play's cap on release notes, per language, in characters.
MAX_CHARS = 500
MAX_LINES = 4

# Pinned, not an alias: an alias rolls forward to a model that may want a
# different request shape (klutch-app learned this when Gemini 3 Flash refused
# `thinkingBudget: 0`). Bump deliberately, and read the notes it writes.
DEFAULT_MODEL = "gemini-3.6-flash"
THINKING_LEVEL = "minimal"
API_HOST = "https://generativelanguage.googleapis.com"

MAX_DIFF_CHARS = 240_000
MAX_FILE_DIFF_CHARS = 12_000
MAX_FILES = 120

NOTHING_USER_VISIBLE = "Stability and performance improvements."

# The last versionCode issued by hand before the tag count took over. There
# was none: 1.0.0 was uploaded by hand as versionCode 1 and tagged v1.0.0, so
# the count and Play agree from the start.
LEGACY_VERSION_CODE_MAX = 0

# Paths whose diff cannot change what a user sees. First match wins and names
# the reason, which is printed rather than silently applied.
SKIP_RULES: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"\.(g|freezed|mocks)\.dart$"), "generated"),
    (re.compile(r"^(test|integration_test)/"), "tests"),
    (re.compile(r"^docs/|(^|/)[^/]*\.md$"), "docs"),
    (re.compile(r"^\.circleci/|^\.github/|^tool/|^Makefile$|^\.vscode/"), "tooling"),
    (re.compile(r"\.lock$"), "lockfiles"),
    (re.compile(r"^(android|ios|web|macos|linux|windows)/"), "platform"),
    (re.compile(r"\.pen$|^images/|^fonts/"), "design"),
    (
        re.compile(
            r"\.(png|jpg|jpeg|gif|webp|svg|ttf|otf|woff2?|ico|pdf|zip|jks|"
            r"keystore|aab|apk|mp4)$"
        ),
        "assets",
    ),
    # The version reaches the model separately, and a page of dependency bumps
    # invites notes about dependencies.
    (re.compile(r"^pubspec\.yaml$|^analysis_options\.yaml$|^\."), "config"),
]

# The only app-specific part of this file: what the app is and who reads its
# notes. Another app changes these two and nothing else.
APP_NAME = "PowerPilot"
APP_DESCRIPTION = (
    "an Android app for watching and controlling a UPS (uninterruptible power "
    "supply) from anywhere, through the owner's own PowerPilot server: battery "
    "charge and runtime, power cuts, alarms, self-tests, outlet shutdown, trends "
    "and an event log. Your readers are the people who own and look after the "
    "UPS, not developers."
)

SYSTEM_INSTRUCTION = f"""\
You write Google Play release notes for {APP_NAME}, {APP_DESCRIPTION}

You are given the source diff of one release: the hand-written code that \
changed between the previous release and this one. Tests, documentation, CI and \
build files have already been removed. Read the diff and work out what a person \
using the app would actually notice.

How to read it:
- Added or changed user-facing strings in widgets are the strongest evidence of \
what a user will see. Trust them over anything else.
- A new screen, list, filter, button, setting or chart is a change a user \
notices. So is a changed default, a new warning, or a fixed calculation or \
reading.
- Renames, extracted methods, moved files, reordered code, type changes, added \
comments and formatting are invisible to users. Ignore them completely, however \
large the diff.

Rules for what you write:
- Plain text only. No markdown, no bullet or dash characters, no emoji, no \
headings, no preamble, no closing line.
- At most 4 lines. One user-visible change per line. At most 500 characters in \
total, so prefer short lines.
- Describe what the change means for the person using the app. Never mention \
code, files, classes, widgets, refactors, dependencies, tests or builds.
- Claim only what the diff shows. Never describe a feature, screen or fix you \
cannot point to in the diff. Say less rather than guess.
- If nothing in the diff changes what a user sees or can do, reply with exactly \
this line and nothing else: Stability and performance improvements.
- British English spelling. Present tense. Sentence case.
- No version numbers, dates, issue numbers or ticket ids.\
"""


def run_git(args: list[str], cwd: Path) -> str:
    """git, or the empty string if the command fails (a shallow clone, no tags)."""
    try:
        out = subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True, errors="replace")
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""
    return out.stdout


def repo_root() -> Path:
    here = Path(__file__).resolve().parent.parent
    root = run_git(["rev-parse", "--show-toplevel"], here).strip()
    return Path(root) if root else here


def release_tags(root: Path) -> list[str]:
    """Every release tag, oldest first, by version (lightweight tags carry the
    commit's date, which reorders the moment a release tags an older commit)."""
    return run_git(["tag", "--list", "v[0-9]*", "--sort=v:refname"], root).split()


def pubspec_version(root: Path) -> tuple[str, str]:
    """('1.0.1', '2'): the name from the pubspec, the code from the tag count,
    the same number the Makefile passes as --build-number."""
    text = (root / "pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"^version:\s*(\S+)", text, re.MULTILINE)
    if not match:
        sys.exit("pubspec.yaml has no 'version:' line.")
    return match.group(1).partition("+")[0], str(len(release_tags(root)))


def tag_for_version_code(root: Path, code: str) -> str | None:
    """The tag Play's `code` came from: the release users actually received.
    The versionCode is a count of release tags, so this is the code-th tag."""
    try:
        position = int(str(code).strip())
    except ValueError:
        print(f"note: '{code}' is not a versionCode.")
        return None
    if position <= LEGACY_VERSION_CODE_MAX:
        return None
    tags = release_tags(root)
    return tags[position - 1] if position <= len(tags) else None


def diff_range(root: Path, since: str | None, until: str | None, since_version_code: str | None = None) -> str:
    """The `A...B` range this release introduces. `since` is the release users
    actually got (Play's versionCode, read by the `released_version_code` lane),
    not simply the previous tag: a tag whose upload failed is still in git, and
    taking it as the baseline would drop its changes from every later changelog.
    Three dots, so the comparison is against the merge base."""
    until = until or os.environ.get("CIRCLE_TAG") or "HEAD"
    if not since and since_version_code:
        since = tag_for_version_code(root, since_version_code)
        if since:
            print(f"Play holds versionCode {since_version_code} → since {since}")
        else:
            print(f"note: no v* tag carries versionCode {since_version_code}; falling back to the previous tag.")
    if not since:
        since = run_git(["describe", "--tags", "--abbrev=0", "--match", "v[0-9]*", f"{until}^"], root).strip()
    if not since:
        # First release: everything up to here is new.
        roots = run_git(["rev-list", "--max-parents=0", until], root).split()
        since = roots[-1] if roots else until
    return f"{since}...{until}"


def skip_reason(path: str) -> str | None:
    for pattern, reason in SKIP_RULES:
        if pattern.search(path):
            return reason
    return None


def priority(path: str) -> int:
    """Lower sorts first, so the strongest evidence survives the budget."""
    if path.startswith("lib/ui/screens/"):
        return 0  # the screens themselves
    if path.startswith("lib/ui/"):
        return 1  # shared widgets and wording
    if path.startswith("lib/"):
        return 2  # data and state, occasionally user-visible
    return 3


def changed_files(root: Path, spec: str) -> tuple[list[tuple[tuple[str, ...], int]], dict[str, int]]:
    """Files whose diff could matter, plus a count of what was skipped and why.
    A rename carries both its paths, or -M can't pair them and the file reads
    as brand new."""
    raw = run_git(["diff", "-M", "-z", "--numstat", spec], root)
    if not raw:
        return [], {}
    fields = raw.split("\0")
    kept: list[tuple[tuple[str, ...], int]] = []
    skipped: dict[str, int] = {}
    index = 0
    while index < len(fields):
        record = fields[index]
        index += 1
        parts = record.split("\t") if record else []
        if len(parts) < 3:
            continue
        added, deleted, path = parts[0], parts[1], "\t".join(parts[2:])
        paths: tuple[str, ...] = (path,)
        if path == "":
            if index + 1 >= len(fields):
                continue
            paths = (fields[index], fields[index + 1])
            index += 2
        if added == "-" or deleted == "-":
            skipped["binary"] = skipped.get("binary", 0) + 1
            continue
        churn = sum(int(n) for n in (added, deleted) if n.isdigit())
        if churn == 0:
            skipped["moved only"] = skipped.get("moved only", 0) + 1
            continue
        reason = skip_reason(paths[-1])
        if reason:
            skipped[reason] = skipped.get(reason, 0) + 1
            continue
        kept.append((paths, churn))
    kept.sort(key=lambda item: (priority(item[0][-1]), item[0][-1]))
    return kept, skipped


def build_diff_context(root: Path, spec: str, files: list[tuple[tuple[str, ...], int]]) -> str:
    """The prompt's evidence: a stat summary, then the patches, within budget."""
    included = files[:MAX_FILES]
    if len(files) > MAX_FILES:
        print(f"note: {len(files) - MAX_FILES} file(s) beyond the {MAX_FILES}-file cap were left out")
    every_path = [p for paths, _ in included for p in paths]
    stat = run_git(["diff", "-M", "--stat=200", spec, "--", *every_path], root).strip()
    chunks = [f"Files changed:\n{stat}\n" if stat else ""]
    budget = MAX_DIFF_CHARS - len(chunks[0])
    truncated = omitted = 0
    for paths, _ in included:
        if budget <= 0:
            omitted += 1
            continue
        patch = run_git(["diff", "-M", "-U2", "--no-color", spec, "--", *paths], root).strip()
        if not patch:
            continue
        cap = min(MAX_FILE_DIFF_CHARS, budget)
        if len(patch) > cap:
            patch = patch[:cap] + f"\n[... {len(patch) - cap} more characters ...]"
            truncated += 1
        chunks.append(patch)
        budget -= len(patch)
    if truncated:
        print(f"note: truncated the diff of {truncated} large file(s)")
    if omitted:
        print(f"note: {omitted} file(s) did not fit the {MAX_DIFF_CHARS:,}-character budget")
    return "\n\n".join(chunk for chunk in chunks if chunk)


def request_body(prompt: str, thinking_level: str | None) -> bytes:
    """generateContent's payload. Without a thinking level the model thinks at
    its default, so the output budget must cover the reasoning too."""
    config: dict = {"temperature": 0.3}
    if thinking_level:
        config["maxOutputTokens"] = 2048
        config["thinkingConfig"] = {"thinkingLevel": thinking_level}
    else:
        config["maxOutputTokens"] = 4096
    return json.dumps(
        {
            "systemInstruction": {"parts": [{"text": SYSTEM_INSTRUCTION}]},
            "contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "generationConfig": config,
        }
    ).encode("utf-8")


def call_gemini(api_key: str, model: str, version_name: str, diff_context: str, timeout: int, attempts: int) -> str:
    """The generated notes, or raise RuntimeError. Never logs the key."""
    prompt = f"This is the source diff for release {version_name} of the {APP_NAME} app.\n\n{diff_context}\n\nWrite the release notes."
    url = f"{API_HOST}/v1beta/models/{model}:generateContent"
    last_error = "no attempt made"
    thinking_level: str | None = THINKING_LEVEL
    for attempt in range(1, attempts + 1):
        request = urllib.request.Request(
            url,
            data=request_body(prompt, thinking_level),
            method="POST",
            # The key in a header, not ?key=: a URL carrying it ends up in logs.
            headers={"Content-Type": "application/json", "x-goog-api-key": api_key},
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return extract_text(json.load(response))
        except urllib.error.HTTPError as error:
            last_error = f"HTTP {error.code}: {error.read().decode('utf-8', 'replace')[:400]}"
            if error.code == 400 and thinking_level:
                # A 400 doesn't name the field it objected to; the thinking
                # setting is the likely one, so ask again without it.
                print(f"note: the model rejected thinkingLevel '{thinking_level}'; asking again without it.")
                thinking_level = None
                continue
            if error.code not in (408, 429) and error.code < 500:
                break
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
            last_error = f"{type(error).__name__}: {error}"
        except RuntimeError as error:
            last_error = str(error)
            break
        if attempt < attempts:
            time.sleep(2 * attempt)
    raise RuntimeError(last_error)


def extract_text(payload: dict) -> str:
    candidates = payload.get("candidates") or []
    if not candidates:
        raise RuntimeError(f"no candidates (promptFeedback={payload.get('promptFeedback', {})})")
    parts = (candidates[0].get("content") or {}).get("parts") or []
    text = "".join(part.get("text", "") for part in parts).strip()
    if not text:
        raise RuntimeError(f"empty text (finishReason={candidates[0].get('finishReason')})")
    return text


def clean(text: str) -> str:
    """Strip the formatting the prompt forbids but a model still sometimes emits."""
    lines: list[str] = []
    for raw in text.splitlines():
        line = re.sub(r"^[-*•‣●·]+\s*", "", raw.strip())
        line = re.sub(r"^#{1,6}\s*", "", line)
        line = re.sub(r"^\d+[.)]\s+", "", line)
        line = re.sub(r"`+", "", line.replace("**", "").replace("__", ""))
        line = re.sub(r"\s{2,}", " ", line).strip()
        if line:
            lines.append(line)
    return "\n".join(lines[:MAX_LINES])


def fit(text: str) -> str:
    """Bring the notes inside Play's 500-character cap, whole lines first."""
    lines = text.splitlines()
    while lines and len("\n".join(lines)) > MAX_CHARS:
        if len(lines) == 1:
            single = lines[0][: MAX_CHARS - 1]
            single = single[: single.rfind(" ")] if " " in single else single
            return single.rstrip(" ,;:.") + "."
        lines.pop()
    return "\n".join(lines)


def fail(message: str) -> int:
    print(f"error: {message}", file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Write the Play release notes from the code changed since the last released tag.")
    parser.add_argument("--version-code", help="versionCode the file is named after (default: the v* tag count).")
    parser.add_argument("--since", help="Start ref (default: the release Play holds, else the previous v* tag).")
    parser.add_argument("--since-version-code", help="versionCode Play already holds; its tag becomes the start ref.")
    parser.add_argument("--until", help="End ref (default: $CIRCLE_TAG, else HEAD).")
    parser.add_argument("--locale", default="en-US", help="Listing locale folder.")
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"Gemini model id (default: {DEFAULT_MODEL}).")
    parser.add_argument("--force", action="store_true", help="Overwrite an existing changelog for this versionCode.")
    parser.add_argument("--dry-run", action="store_true", help="Print the notes, write nothing.")
    parser.add_argument("--print-diff", action="store_true", help="Also print the diff being sent.")
    parser.add_argument("--strict", action="store_true", help="Exit non-zero instead of falling back when Gemini is unusable.")
    parser.add_argument("--timeout", type=int, default=90)
    parser.add_argument("--attempts", type=int, default=3)
    args = parser.parse_args()

    root = repo_root()
    version_name, build_number = pubspec_version(root)
    version_code = args.version_code or build_number

    # The tag count is this release's code only on the tag build itself. A dry
    # run writes nothing, so its name doesn't matter (and a branch before the
    # first tag must still pass).
    if not args.version_code and int(build_number) <= LEGACY_VERSION_CODE_MAX and not args.dry_run:
        sys.exit(
            f"counted {build_number} release tags, so this isn't a release's versionCode.\n"
            "Either the tags are missing ('git fetch --tags'), or this commit isn't tagged yet: "
            "release notes are written on the 'v*' tag. Pass --version-code to write them early."
        )

    out = root / "android/fastlane/metadata/android" / args.locale / "changelogs" / f"{version_code}.txt"
    relative = out.relative_to(root)
    if out.exists() and out.read_text(encoding="utf-8").strip() and not args.force:
        print(f"{relative} already exists: keeping it. Use --force to replace.")
        print(out.read_text(encoding="utf-8").rstrip())
        return 0

    spec = diff_range(root, args.since, args.until, args.since_version_code)
    files, skipped = changed_files(root, spec)
    print(f"versionCode {version_code} ({version_name})  {spec}")
    detail = ", ".join(f"{count} {reason}" for reason, count in sorted(skipped.items()))
    print(f"{len(files)} file(s) of interest" + (f"; skipped {detail}" if detail else ""))

    diff_context = build_diff_context(root, spec, files) if files else ""
    if args.print_diff and diff_context:
        print("--- diff sent to the model ---")
        print(diff_context)
        print("--- end diff ---")

    api_key = os.environ.get("GEMINI_API_KEY", "").strip()
    if not diff_context:
        print("No user-facing code changed in that range. On CI, check the previous tag was fetched ('git fetch --tags').")
        notes = NOTHING_USER_VISIBLE
    elif not api_key:
        message = "GEMINI_API_KEY is not set, so the code could not be read."
        if args.strict:
            return fail(message)
        print(f"WARNING: {message}\nWARNING: writing '{NOTHING_USER_VISIBLE}' instead.")
        notes = NOTHING_USER_VISIBLE
    else:
        print(f"sending {len(diff_context):,} characters of diff to {args.model}")
        try:
            notes = fit(clean(call_gemini(api_key, args.model, version_name, diff_context, args.timeout, args.attempts)))
        except RuntimeError as error:
            message = f"Gemini ({args.model}) failed: {error}"
            if args.strict:
                return fail(message)
            print(f"WARNING: {message}\nWARNING: writing '{NOTHING_USER_VISIBLE}' instead. Hand-write {relative} if this release deserves better.")
            notes = NOTHING_USER_VISIBLE

    notes = notes.strip() or NOTHING_USER_VISIBLE
    print(f"--- release notes ({len(notes)}/{MAX_CHARS} chars) ---\n{notes}\n--- end ---")
    if args.dry_run:
        print("--dry-run: nothing written.")
        return 0
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(notes + "\n", encoding="utf-8")
    print(f"wrote {relative}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
