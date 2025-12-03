#!/usr/bin/env bash
set -euo pipefail

# entrypoint.sh
# Args:
#  $1 -> type ("commit"|"branch"|"label")
#  $2 -> map (JSON)
TYPE="${1:-label}"
MAP="${2:-{}}"

# Paths
WORKDIR="/github/workspace"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/github/workflow/output}" # fallback for testing (not used on runner)

# Use mounted workspace if available
if [ -d "$WORKDIR" ]; then
  cd "$WORKDIR"
fi

log() { echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"; }

# Helpers ---------------------------------------------------------------------

get_last_version() {
  # find latest tag like vX.Y.Z or X.Y.Z, sort by version if possible, fallback to creatordate
  local lastTag
  lastTag=$(git tag --list --sort=-creatordate 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null | head -n1 || true)
  if [ -z "$lastTag" ]; then
    lastTag=$(git tag --list --sort=-creatordate '[0-9]*.[0-9]*.[0-9]*' 2>/dev/null | head -n1 || true)
  fi
  if [ -z "$lastTag" ]; then
    echo "0.0.0"
  else
    # strip leading v if present
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
  # prefer GITHUB_REF_NAME if set, otherwise git
  local branchName prefix
  branchName="${GITHUB_REF_NAME:-}"
  if [ -z "$branchName" ]; then
    branchName=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  fi
  if [ -z "$branchName" ]; then
    log "No branch name found."
    return 1
  fi
  # capture text before first '/'
  prefix=$(echo "$branchName" | awk -F'/' '{print $1}')
  if [ -z "$prefix" ] || [ "$prefix" = "$branchName" ]; then
    log "Branch prefix not found in: $branchName"
    return 1
  fi
  echo "$prefix"
}

get_type_from_labels() {
  # Use GITHUB_EVENT_PATH (runner provides) to read PR labels
  if [ -n "${GITHUB_EVENT_PATH:-}" ] && [ -f "${GITHUB_EVENT_PATH}" ]; then
    # collect labels names; jq returns array or empty
    local label
    label=$(jq -r '[.pull_request.labels[].name] | join(" ")' "${GITHUB_EVENT_PATH}" 2>/dev/null || echo "")
    if [ -n "$label" ]; then
      # return first matching label (space separated)
      for l in $label; do
        echo "$l"
        return 0
      done
    fi
  fi

  # fallback: read GITHUB_REF or env var LABELS
  if [ -n "${INPUT_LABELS:-}" ]; then
    echo "${INPUT_LABELS}"
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
  # $1 = change token (e.g., "feature" or "breaking")
  # MAP is available globally
  local token="$1"
  # Use jq to search the map JSON
  local bump
  bump=$(jq -r --arg t "$token" 'to_entries[] | select(.value | index($t)) | .key' 2>/dev/null <<<"$MAP" || true)
  if [ -z "$bump" ]; then
    echo "none"
  else
    echo "$bump"
  fi
}

# Main ------------------------------------------------------------------------

log "Semantic version action started. mode=${TYPE}"

if [ -z "$MAP" ] || [ "$MAP" = "{}" ]; then
  log "Error: map input is required."
  echo "version=" >> "$GITHUB_OUTPUT"
  echo "release_needed=false" >> "$GITHUB_OUTPUT"
  echo "release_id=" >> "$GITHUB_OUTPUT"
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
    echo "version=" >> "$GITHUB_OUTPUT"
    echo "release_needed=false" >> "$GITHUB_OUTPUT"
    echo "release_id=" >> "$GITHUB_OUTPUT"
    exit 1
    ;;
esac

if [ -z "$detected" ]; then
  log "No change token detected — skipping version bump."
  echo "version=" >> "$GITHUB_OUTPUT"
  echo "release_needed=false" >> "$GITHUB_OUTPUT"
  echo "release_id=" >> "$GITHUB_OUTPUT"
  exit 0
fi

bump=$(map_to_bump "$detected")
if [ "$bump" = "none" ] || [ -z "$bump" ]; then
  log "Mapping returned none for token: $detected. No bump."
  echo "version=" >> "$GITHUB_OUTPUT"
  echo "release_needed=false" >> "$GITHUB_OUTPUT"
  echo "release_id=" >> "$GITHUB_OUTPUT"
  exit 0
fi

lastVer=$(get_last_version)
log "Last version: $lastVer"
nextVer=$(next_version "$bump" "$lastVer")
if [ $? -ne 0 ]; then
  log "Failed to calculate next version."
  echo "version=" >> "$GITHUB_OUTPUT"
  echo "release_needed=false" >> "$GITHUB_OUTPUT"
  echo "release_id=" >> "$GITHUB_OUTPUT"
  exit 1
fi

log "New version computed: v${nextVer}"

# Write outputs
echo "version=v${nextVer}" >> "$GITHUB_OUTPUT"
echo "release_needed=true" >> "$GITHUB_OUTPUT"
echo "release_id=${nextVer}" >> "$GITHUB_OUTPUT"

# Also print JSON for easier human parsing
jq -n --arg v "v${nextVer}" --arg id "${nextVer}" --arg rn "true" \
  '{version:$v, release_needed:$rn, release_id:$id}' || true

exit 0
