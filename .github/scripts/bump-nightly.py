#!/usr/bin/env python3
"""Pin the OpenMS formulae to an OpenMS commit (normally the tip of the `nightly` branch).

libopenms and openms are built from OpenMS/OpenMS. openms-gui is built from
OpenMS/OpenMS-TOPP-GUI (the Qt GUI moved there from OpenMS 3.7 on), pinned to the tip
of its `develop` branch, which is tested against OpenMS develop.

Everything OpenMS would otherwise download at configure time (FetchContent
dependencies, PeptDeep ONNX models) is read from OpenMS's own CMake files at that
commit and rendered as Homebrew `resource` blocks, so the build runs offline and
the pins always match what OpenMS expects.

All formulae get the same version (the application layers require the exact
libopenms version they are built from, and a new commit of either repository
rebuilds all three, so openms-gui always matches the libopenms it was built
against). Resource blocks are only rendered into formulae that have the
nightly-resources markers (libopenms).

Usage: bump-nightly.py [--sha SHA] [--gui-sha SHA] [--formula PATH ...]
Prints `changed=`, `version=`, `sha=` and `gui_sha=` lines suitable for $GITHUB_OUTPUT.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

REPO = "OpenMS/OpenMS"
BRANCH = "nightly"
GUI_REPO = "OpenMS/OpenMS-TOPP-GUI"
GUI_BRANCH = "develop"
FORMULAE = ["Formula/libopenms.rb", "Formula/openms.rb", "Formula/openms-gui.rb"]
# formulae built from GUI_REPO instead of REPO
GUI_FORMULAE = {"openms-gui.rb"}
# FetchContent names handed to CMake via FETCHCONTENT_SOURCE_DIR_<NAME>.
FETCHCONTENT_DEPS = ["opentims", "pylmcf", "wnet", "wnetalign"]


def http_get(url: str) -> bytes:
    headers = {"User-Agent": "homebrew-openms-bump"}
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=600) as r:
        return r.read()


def sha256_of(url: str) -> str:
    return hashlib.sha256(http_get(url)).hexdigest()


def raw(sha: str, path: str, repo: str = REPO) -> str:
    return http_get(f"https://raw.githubusercontent.com/{repo}/{sha}/{path}").decode()


def resolve_commit(ref: str, repo: str = REPO) -> tuple[str, datetime]:
    data = json.loads(http_get(f"https://api.github.com/repos/{repo}/commits/{ref}"))
    date = datetime.fromisoformat(data["commit"]["committer"]["date"].replace("Z", "+00:00"))
    return data["sha"], date.astimezone(timezone.utc)


def cmake_set(text: str, var: str) -> str:
    m = re.search(rf'set\(\s*{var}\s+"?([^")\s]*)"?', text)
    if not m:
        sys.exit(f"could not find {var} in the CMake files")
    return m.group(1)


def cmake_list(text: str, var: str) -> list[str]:
    m = re.search(rf"set\(\s*{var}\s+(.*?)\s+CACHE", text, re.S)
    if not m:
        sys.exit(f"could not find list {var} in OpenMS CMake files")
    return m.group(1).split()


def fetchcontent_pins(text: str) -> dict[str, tuple[str, str]]:
    pins = {}
    for m in re.finditer(r"FetchContent_Declare\(\s*(\w+)(.*?)\n\s*\)", text, re.S):
        name, body = m.group(1).lower(), m.group(2)
        repo = re.search(r"GIT_REPOSITORY\s+(\S+)", body)
        tag = re.search(r"GIT_TAG\s+(\S+)", body)
        if repo and tag:
            pins[name] = (repo.group(1).removesuffix(".git"), tag.group(1))
    return pins


def formula_field(text: str, field: str) -> str | None:
    m = re.search(rf'^\s*{field} "([^"]+)"', text, re.M)
    return m.group(1) if m else None


def has_markers(text: str, begin: str) -> bool:
    return re.search(rf"^[ \t]*# {re.escape(begin)}", text, re.M) is not None


def replace_between(text: str, begin: str, end: str, lines: list[str]) -> str:
    pattern = re.compile(
        rf"(^([ \t]*)# {re.escape(begin)}[^\n]*\n).*?(^[ \t]*# {re.escape(end)}[^\n]*\n)", re.S | re.M
    )
    m = pattern.search(text)
    if not m:
        sys.exit(f"markers '{begin}'/'{end}' not found in formula")
    indent = m.group(2)
    body = "".join(f"{indent}{l}\n" if l else "\n" for l in lines)
    return text[: m.start()] + m.group(1) + body + m.group(3) + text[m.end() :]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sha", default="", help=f"OpenMS commit to pin (default: tip of {BRANCH})")
    ap.add_argument("--gui-sha", default="", help=f"{GUI_REPO} commit to pin (default: tip of {GUI_BRANCH})")
    ap.add_argument("--formula", action="append", help=f"formula to update (default: {' '.join(FORMULAE)})")
    args = ap.parse_args()

    sha, date = resolve_commit(args.sha or BRANCH)
    gui_sha, gui_date = resolve_commit(args.gui_sha or GUI_BRANCH, GUI_REPO)
    formulae = {Path(f): Path(f).read_text() for f in (args.formula or FORMULAE)}
    first = next(iter(formulae.values()))

    def pinned_sha(path: Path) -> str:
        return gui_sha if path.name in GUI_FORMULAE else sha

    if all(pinned_sha(p) in (formula_field(t, "url") or "") for p, t in formulae.items()):
        print("changed=false")
        print(f"version={formula_field(first, 'version')}")
        print(f"sha={sha}")
        print(f"gui_sha={gui_sha}")
        return

    top = raw(sha, "CMakeLists.txt")
    ext = raw(sha, "cmake/cmake_findExternalLibs.cmake")
    lib = raw(sha, "src/openms/CMakeLists.txt")

    base = ".".join(cmake_set(top, f"OPENMS_PACKAGE_VERSION_{p}") for p in ("MAJOR", "MINOR", "PATCH"))
    # The GUI layer requires an OpenMS of exactly its own version (find_package(OpenMS EXACT)).
    gui_base = cmake_set(raw(gui_sha, "CMakeLists.txt", GUI_REPO), "OPENMS_GUI_VERSION")
    if any(p.name in GUI_FORMULAE for p in formulae) and gui_base != base:
        sys.exit(f"{GUI_REPO}@{gui_sha} is version {gui_base}, but {REPO}@{sha} is {base}; "
                 f"the GUI layer needs an OpenMS of exactly its version (pass --gui-sha)")
    # The newer of both commits dates the version, so a new GUI commit usually gives a new
    # version too.
    date = max(date, gui_date)
    existing = {formula_field(t, "version") or "" for t in formulae.values()}
    version = f"{base}-pre.{date:%Y%m%d}"
    if any(v.startswith(version) for v in existing):
        # More than one build on the same day: disambiguate with the commit time.
        version = f"{base}-pre.{date:%Y%m%d.%H%M}"
    # A new pin must always change the version, or `brew upgrade` would not pick it up. The
    # commit time stays the same when only a commit older than the other one changed (e.g. a
    # GUI commit dated before the pinned OpenMS commit): count up in that case.
    counters = [int(m.group(1)) for v in existing if (m := re.fullmatch(rf"{re.escape(version)}\.(\d+)", v))]
    if version in existing or counters:
        version = f"{version}.{max(counters, default=0) + 1}"

    def source_block(repo: str, commit: str) -> list[str]:
        url = f"https://github.com/{repo}/archive/{commit}.tar.gz"
        return [f'url "{url}"', f'version "{version}"', f'sha256 "{sha256_of(url)}"']

    source = source_block(REPO, sha)
    gui_source = source_block(GUI_REPO, gui_sha)

    pins = fetchcontent_pins(ext)
    res: list[str] = []
    for name in FETCHCONTENT_DEPS:
        if name not in pins:
            sys.exit(f"FetchContent dependency '{name}' is no longer declared by OpenMS; update FETCHCONTENT_DEPS")
        repo, tag = pins[name]
        ref = tag if re.fullmatch(r"[0-9a-f]{40}", tag) else f"refs/tags/{tag}"
        r_url = f"{repo}/archive/{ref}.tar.gz"
        res += [f'resource "{name}" do', f'  url "{r_url}"', f'  sha256 "{sha256_of(r_url)}"', "end", ""]

    model_url = cmake_set(lib, "OPENMS_PEPTDEEP_MODEL_URL").replace("http://", "https://", 1)
    models = cmake_list(lib, "OPENMS_PEPTDEEP_MODELS")
    hashes = cmake_list(lib, "OPENMS_PEPTDEEP_MODEL_SHA256S")
    if len(models) != len(hashes):
        sys.exit("PeptDeep model and checksum lists differ in length")
    for model, digest in zip(models, hashes):
        res += [f'resource "{model}" do', f'  url "{model_url}/{model}"', f'  sha256 "{digest}"', "end", ""]

    for path, text in formulae.items():
        text = replace_between(text, "BEGIN nightly-source", "END nightly-source",
                               gui_source if path.name in GUI_FORMULAE else source)
        if has_markers(text, "BEGIN nightly-resources"):
            text = replace_between(text, "BEGIN nightly-resources", "END nightly-resources", res[:-1])
        # Bottles belong to the previous commit; pr-upload writes a fresh block.
        text = re.sub(r"^  bottle do\n.*?^  end\n\n", "", text, count=1, flags=re.S | re.M)
        path.write_text(text)

    print("changed=true")
    print(f"version={version}")
    print(f"sha={sha}")
    print(f"gui_sha={gui_sha}")


if __name__ == "__main__":
    main()
