#!/usr/bin/env bash
set -euo pipefail

# entrypoint.sh
# Works with:
#  - positional args: $1 -> type, $2 -> map (repo action usage)
#  - INPUT_* env vars: INPUT_TYPE, INPUT_MAP (docker:// usage)

# Resolve inputs: prefer positional args, fallback to INPUT_ envs, then defaults
TYPE="${1:-${INPUT_TYPE:-label}}"
MAP="${2:-${INPUT_MAP:-}}"

# Paths
WORKDIR="/github/workspace"
# GITHUB_OUTPUT is a file path provided by runner. Fallback to a temp file for local testing.
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/github/workflow/output}"

# Use mounted workspace if available
if [ -d "$WORKDIR" ]; then
  cd "$WORKDIR"
fi

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }

# Helper: safe jq check
_has_jq() {
  command -v jq >/dev/null 2>&1
}

# Helpers ---------------------------------------------------------------------

get_last_version() {
  local lastTag
  lastTag=$(git tag --list --sort=-creatordate 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null | head -n1 || true)
  if [ -z "$lastTag" ]; then
    lastTag=$(git tag --list --sort=-creatordate '[0-9]*.[0-9]*.[0-9]*' 2>/dev/null | head -n1 || true)
  fi
  if [ -z "$lastTag" ]; then
    echo "0.0.0"
  else
    echo "${lastTag#v}"
  fi
}

get_type_from_commit_prefix() {
  local commitMsg
  commitMsg=$(git log -1 --format=%s 2>/dev/null || echo "")
  if [[ -z "$commitMsg" ]]; then
    log "No commit message found."
    return 1
  fi
  if [[ "$commitMsg" =~ ^\[([^]]+)\] ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  elif [[ "$commitMsg" =~ ^([^:]+): ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  log "Could not find commit prefix in: $commitMsg"
  return 1
}

get_type_from_branch_prefix() {
  local branchName prefix
  branchName="${GITHUB_REF_NAME:-}"
  if [ -z "$branchName" ]; then
    branchName=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  fi
  if [ -z "$branchName" ]; then
    log "No branch name found."
    return 1
  fi
  prefix=$(echo "$branchName" | awk -F'/' '{print $1}')
  if [ -z "$prefix" ] || [ "$prefix" = "$branchName" ]; then
    log "Branch prefix not found in: $branchName"
    return 1
  fi
  echo "$prefix"
}

get_type_from_labels() {
  # prefer GITHUB_EVENT_PATH payload
  if [ -n "${GITHUB_EVENT_PATH:-}" ] && [ -f "${GITHUB_EVENT_PATH}" ]; then
    if _has_jq; then
      # collect label names as array, return first if exists
      local first
      first=$(jq -r '.pull_request.labels[].name // empty' "${GITHUB_EVENT_PATH}" 2>/dev/null | head -n1 || true)
      if [ -n "$first" ]; then
        echo "$first"
        return 0
      fi
    else
      log "jq not found; cannot parse GITHUB_EVENT_PATH for labels."
    fi
  fi

  # fallback to INPUT_LABELS env (single token or space-separated)
  if [ -n "${INPUT_LABELS:-}" ]; then
    # return first token
    echo "${INPUT_LABELS}" | awk '{print $1}'
    return 0
  fi

  log "No labels found in event payload."
  return 1
}

next_version() {
  local bump="$1"
  local version="$2"
  version="${version#v}"
  IFS='.' read -r major minor patch <<< "$version"
  major=${major:-0}; minor=${minor:-0}; patch=${patch:-0}
  case "$(echo "$bump" | tr '[:upper:]' '[:lower:]')" in
    major)
      major=$((major + 1)); minor=0; patch=0
      ;;
    minor)
      minor=$((minor + 1)); patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    *)
      log "Invalid bump type: $bump"
      return 1
      ;;
  esac
  echo "${major}.${minor}.${patch}"
}

map_to_bump() {
  local token="$1"
  if ! _has_jq; then
    log "jq is required to parse MAP JSON but not found."
    echo "none"
    return 0
  fi

  # preserve MAP content and feed to jq safely
  local bump
  bump=$(printf '%s' "$MAP" | jq -r --arg t "$token" 'to_entries[] | select(.value | index($t)) | .key' 2>/dev/null || true)
  if [ -z "$bump" ]; then
    echo "none"
  else
    echo "$bump"
  fi
}

# Output helper
write_output() {
  local name="$1"
  local value="$2"
  # if GITHUB_OUTPUT file exists/usable append there, otherwise print to stdout
  if [ -n "${GITHUB_OUTPUT:-}" ] && [ -w "$(dirname "$GITHUB_OUTPUT")" ] 2>/dev/null; then
    echo "${name}=${value}" >> "$GITHUB_OUTPUT"
  else
    echo "GITHUB_OUTPUT not set or not writable; $name=$value"
  fi
}

# Main ------------------------------------------------------------------------

log "Semantic version action started. mode=${TYPE}"

# Normalize MAP: if it's empty string or equals "{}" treat as missing
MAP_TRIMMED="$(printf '%s' "$MAP" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
if [ -z "$MAP_TRIMMED" ] || [ "$MAP_TRIMMED" = "{}" ]; then
  log "Error: map input is required."
  write_output "version" ""
  write_output "release_needed" "false"
  write_output "release_id" ""
  exit 1
fi

detected=""
case "$TYPE" in
  commit)
    if detected=$(get_type_from_commit_prefix); then
      log "Detected token from commit: $detected"
    else
      log "Failed to detect change type from commit."
    fi
    ;;
  branch)
    if detected=$(get_type_from_branch_prefix); then
      log "Detected token from branch: $detected"
    else
      log "Failed to detect change type from branch."
    fi
    ;;
  label)
    if detected=$(get_type_from_labels); then
      log "Detected token from labels: $detected"
    else
      log "Failed to detect change type from labels."
    fi
    ;;
  *)
    log "Invalid type input: $TYPE"
    write_output "version" ""
    write_output "release_needed" "false"
    write_output "release_id" ""
    exit 1
    ;;
esac

if [ -z "$detected" ]; then
  log "No change token detected — skipping version bump."
  write_output "version" ""
  write_output "release_needed" "false"
  write_output "release_id" ""
  exit 0
fi

bump=$(map_to_bump "$detected")
if [ "$bump" = "none" ] || [ -z "$bump" ]; then
  log "Mapping returned none for token: $detected. No bump."
  write_output "version" ""
  write_output "release_needed" "false"
  write_output "release_id" ""
  exit 0
fi

lastVer=$(get_last_version)
log "Last version: $lastVer"
nextVer=$(next_version "$bump" "$lastVer") || {
  log "Failed to calculate next version."
  write_output "version" ""
  write_output "release_needed" "false"
  write_output "release_id" ""
  exit 1
}

log "New version computed: v${nextVer}"

# Write outputs
write_output "version" "v${nextVer}"
write_output "release_needed" "true"
write_output "release_id" "${nextVer}"

# Also print JSON for easier human parsing (do not fail if jq missing)
if _has_jq; then
  jq -n --arg v "v${nextVer}" --arg id "${nextVer}" --arg rn "true" \
    '{version:$v, release_needed:($rn|test("true")), release_id:$id}' || true
else
  echo "{\"version\":\"v${nextVer}\",\"release_needed\":true,\"release_id\":\"${nextVer}\"}"
fi

exit 0
