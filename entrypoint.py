#!/usr/bin/env python3
"""
entrypoint.py
GitHub Actions automatically converts inputs to INPUT_* environment variables.
For example: input "type" becomes INPUT_TYPE, input "map" becomes INPUT_MAP
"""

import json
import logging
import os
import subprocess
import sys
from datetime import datetime, timezone


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(
    format="[%(asctime)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%SZ",
    level=logging.DEBUG,
    stream=sys.stdout,
)
logging.Formatter.converter = lambda *_: datetime.now(timezone.utc).timetuple()
log = logging.getLogger()


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

TYPE = os.environ.get("INPUT_TYPE", "label")
MAP_RAW = os.environ.get("INPUT_MAP", "")
WORKDIR = "/github/workspace"
GITHUB_OUTPUT = os.environ.get("GITHUB_OUTPUT", "/github/workflow/output")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def write_output(name: str, value: str) -> None:
    line = f"{name}={value}"
    try:
        with open(GITHUB_OUTPUT, "a") as fh:
            fh.write(line + "\n")
    except OSError:
        log.warning("GITHUB_OUTPUT not writable; %s", line)


def write_empty_outputs() -> None:
    write_output("version", "")
    write_output("release_needed", "false")
    write_output("release_id", "")


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


# ---------------------------------------------------------------------------
# Version helpers
# ---------------------------------------------------------------------------

def get_last_version() -> str:
    for pattern in ("v[0-9]*.[0-9]*.[0-9]*", "[0-9]*.[0-9]*.[0-9]*"):
        result = run(["git", "tag", "--list", "--sort=-version:refname", pattern])
        tag = result.stdout.strip().splitlines()[0] if result.stdout.strip() else ""
        if tag:
            return tag.lstrip("v")
    return "0.0.0"


def next_version(bump: str, version: str) -> str:
    version = version.lstrip("v")
    parts = version.split(".")
    if len(parts) != 3:
        log.warning("Unexpected version format '%s', falling back to 0.0.0", version)
        parts = ["0", "0", "0"]
    major, minor, patch = int(parts[0]), int(parts[1]), int(parts[2])
    bump = bump.lower()
    if bump == "major":
        major += 1; minor = 0; patch = 0
    elif bump == "minor":
        minor += 1; patch = 0
    elif bump == "patch":
        patch += 1
    else:
        raise ValueError(f"Invalid bump type: {bump}")
    return f"{major}.{minor}.{patch}"


# ---------------------------------------------------------------------------
# Token detection
# ---------------------------------------------------------------------------

def get_type_from_commit_prefix() -> str | None:
    result = run(["git", "log", "-1", "--format=%s"])
    msg = result.stdout.strip()
    if not msg:
        log.warning("No commit message found.")
        return None
    if msg.startswith("[") and "]" in msg:
        return msg[1:msg.index("]")]
    if ":" in msg:
        prefix = msg.split(":")[0]
        if prefix:
            return prefix
    log.warning("Could not find commit prefix in: %s", msg)
    return None


def get_type_from_branch_prefix() -> str | None:
    branch = os.environ.get("GITHUB_REF_NAME", "")
    if not branch:
        result = run(["git", "rev-parse", "--abbrev-ref", "HEAD"])
        branch = result.stdout.strip()
    if not branch:
        log.warning("No branch name found.")
        return None
    parts = branch.split("/")
    if len(parts) < 2:
        log.warning("Branch prefix not found in: %s", branch)
        return None
    return parts[0]


def get_type_from_labels() -> str | None:
    event_path = os.environ.get("GITHUB_EVENT_PATH", "")
    if event_path and os.path.isfile(event_path):
        try:
            with open(event_path) as fh:
                payload = json.load(fh)
            labels = payload.get("pull_request", {}).get("labels", [])
            if labels:
                return labels[0]["name"]
        except (json.JSONDecodeError, KeyError, IndexError) as exc:
            log.warning("Could not parse event payload: %s", exc)

    fallback = os.environ.get("INPUT_LABELS", "").split()
    if fallback:
        return fallback[0]

    log.warning("No labels found in event payload.")
    return None


# ---------------------------------------------------------------------------
# Map lookup
# ---------------------------------------------------------------------------

def map_to_bump(token: str, mapping: dict) -> str:
    token_lower = token.lower()
    for bump_level, tokens in mapping.items():
        if token_lower in [t.lower() for t in tokens]:
            return bump_level
    return "none"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    log.info("Semantic version action started. mode=%s", TYPE)
    log.debug("INPUT_TYPE='%s' INPUT_MAP='%s'", os.environ.get("INPUT_TYPE", ""), MAP_RAW)

    map_str = MAP_RAW.replace("\n", "").replace("\r", "").replace("\t", "").strip()

    if not map_str or map_str == "{}":
        log.error("map input is required. Received: '%s'", map_str)
        log.error("Hint: set INPUT_MAP env variable, e.g.:")
        log.error('  INPUT_MAP: \'{"major":["breaking"],"minor":["feature"],"patch":["fix"]}\'')
        write_empty_outputs()
        return 1

    try:
        mapping: dict = json.loads(map_str)
    except json.JSONDecodeError as exc:
        log.error("MAP is not valid JSON: %s — %s", map_str, exc)
        write_empty_outputs()
        return 1

    log.debug("Parsed MAP: %s", mapping)

    detectors = {
        "commit": get_type_from_commit_prefix,
        "branch": get_type_from_branch_prefix,
        "label":  get_type_from_labels,
    }

    if TYPE not in detectors:
        log.error("Invalid type input: %s", TYPE)
        write_empty_outputs()
        return 1

    detected = detectors[TYPE]()

    if not detected:
        log.info("No change token detected — skipping version bump.")
        write_empty_outputs()
        return 0

    log.info("Detected token from %s: %s", TYPE, detected)

    bump = map_to_bump(detected, mapping)
    if bump == "none":
        log.info("Mapping returned none for token: %s. No bump.", detected)
        write_empty_outputs()
        return 0

    log.info("Bump level: %s", bump)

    last_ver = get_last_version()
    log.info("Last version: %s", last_ver)

    try:
        next_ver = next_version(bump, last_ver)
    except ValueError as exc:
        log.error("Failed to calculate next version: %s", exc)
        write_empty_outputs()
        return 1

    log.info("New version computed: v%s", next_ver)

    write_output("version", f"v{next_ver}")
    write_output("release_needed", "true")
    write_output("release_id", next_ver)

    result = {"version": f"v{next_ver}", "release_needed": True, "release_id": next_ver}
    print(json.dumps(result, indent=2))

    return 0


if __name__ == "__main__":
    if os.path.isdir(WORKDIR):
        os.chdir(WORKDIR)
    sys.exit(main())