#!/usr/bin/env bash
set -euf -o pipefail

# List of all default env variables:
# https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/store-information-in-variables#default-environment-variables

declare -r PREV_SHA="$(git rev-parse HEAD~1 2>/dev/null || true)"

function exitIfInitCommit() {
  if [ "$PREV_SHA" == "HEAD~1" ]; then
    echo "Not skipping. It's an initial commit."
    echo "skip=false" >> $GITHUB_OUTPUT
    exit 0
  fi
}

function exitIfActionFailedForPrevCommit() {
  local -r runs="$(gh api \
    -H "Accept: application/vnd.github+json" \
    /repos/$GITHUB_REPOSITORY/actions/runs?head_sha=$PREV_SHA)"
  local -r buildSuccess="$(echo "$runs" \
    | jq -r "limit(1; .workflow_runs[] | select(.name == \"$GITHUB_WORKFLOW\" and (.conclusion == \"success\" or .conclusion == \"skipped\"))) | .conclusion")"
  if [ -z "$buildSuccess"  ]; then
    echo "Not skipping. Last commit did not pass $GITHUB_WORKFLOW."
    echo "skip=false" >> $GITHUB_OUTPUT
    exit 0
  fi
  echo "Last commit passed $GITHUB_WORKFLOW."
}

function exitIfNoSkipFilesDefined() {
  if [ -z "$SKIP_FILES" ]; then
    echo "Not skipping. No files patterns to skip defined."
    echo "skip=false" >> $GITHUB_OUTPUT
    exit 0
  fi
}

function checkFiles() {
  case "$GITHUB_EVENT_NAME" in
    push)
      SHAS=($PUSH_SHAS)
      CHANGED_FILES="$(git diff --name-only --diff-filter=d "${SHAS[0]}~1" "${SHAS[-1]}")"
      ;;
    pull_request)
      CHANGED_FILES="$(git diff --name-only --diff-filter=d "$PR_BASE_SHA" "$PR_HEAD_SHA")"
      ;;
    *)
      echo "Not skipping. Event "GITHUB_EVENT_NAME" should not be skipped."
      echo "skip=false" >> $GITHUB_OUTPUT
      exit 0
  esac
  declare GREP_CMD=(grep -v)
  while IFS= read -r line; do
    GREP_CMD+=('-e')
    GREP_CMD+=("$line")
  done <<< "$SKIP_FILES"
  echo -e "\nUsing grep cmd:\n${GREP_CMD[@]}\n"
  NOT_SKIPPED="$(echo "$CHANGED_FILES" | "${GREP_CMD[@]}" || true)"
  if [ -z "$NOT_SKIPPED" ]; then
    echo "Skipping. No important files detected."
    echo "skip=true" >> $GITHUB_OUTPUT
    echo -e "\nChanged files:"
    echo -e "$(echo "$CHANGED_FILES" | head -n 10)"
    if [ "$(echo $CHANGED_FILES | wc -l)" -gt 10 ]; then
      echo "..."
    fi
  else
    echo -e "Not skipping. Important files detected."
    echo -e "\nImportant files:"
    echo "$NOT_SKIPPED"
    if [ "$(echo $NOT_SKIPPED | wc -l)" -gt 10 ]; then
      echo "..."
    fi
    echo "skip=false" >> $GITHUB_OUTPUT
  fi
}

exitIfInitCommit
exitIfActionFailedForPrevCommit
exitIfNoSkipFilesDefined
checkFiles
