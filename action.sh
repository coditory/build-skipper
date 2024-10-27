#!/usr/bin/env bash
set -euf -o pipefail

# List of all default env variables:
# https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/store-information-in-variables#default-environment-variables

declare -r PREV_SHA="$(git rev-parse HEAD~1 2>/dev/null || true)"

function noSkipIfInitCommit() {
  if [ "$PREV_SHA" == "HEAD~1" ]; then
    echo "Not skipping: It's an initial commit." | tee -a $GITHUB_STEP_SUMMARY
    echo "skip=false" | tee -a $GITHUB_OUTPUT
    exit 0
  fi
  echo "It's not an init commit."
}

function noSkipIfActionFailedForPrevCommit() {
  local -r runs="$(gh api \
    -H "Accept: application/vnd.github+json" \
    /repos/$GITHUB_REPOSITORY/actions/runs?head_sha=$PREV_SHA)"
  local -r buildSuccess="$(echo "$runs" \
    | jq -r "limit(1; .workflow_runs[] | select(.name == \"$GITHUB_WORKFLOW\" and (.conclusion == \"success\" or .conclusion == \"skipped\"))) | .conclusion")"
  if [ -z "$buildSuccess"  ]; then
    echo "Not skipping. Last commit did not pass $GITHUB_WORKFLOW." | tee -a $GITHUB_STEP_SUMMARY
    echo "skip=false" | tee -a $GITHUB_OUTPUT
    exit 0
  fi
  echo "Last commit passed $GITHUB_WORKFLOW workflow."
}

function skipCommitMessages() {
  local -r commitMessage="$(git log -1 --pretty=format:'%s%n%b' 2>/dev/null)"
  while IFS= read -r SKIP_MSG; do
    if [[ "$commitMessage" =~ "$SKIP_MSG" ]]; then
      echo -e "Skipping. Detected commit skip message:\n$commitMessage." | tee -a $GITHUB_STEP_SUMMARY
      echo "skip=true" | tee -a $GITHUB_OUTPUT
      exit 0
    fi
  done <<< "$SKIP_MESSAGES"
  echo "No skip commit message detected."
}

function changedFiles() {
  if [ "$GITHUB_EVENT_NAME" == "pull_request" ]; then
      git diff --name-only --diff-filter=d "$PR_BASE_SHA" "$PR_HEAD_SHA"
  else
      local -r shas=($PUSH_SHAS)
      git diff --name-only --diff-filter=d "${shas[0]}~1" "${shas[-1]}"
  fi
}

function grepCmd() {
  declare cmd=(grep "$1")
  while IFS= read -r line; do
    trimmed="$(echo "$line" | sed -s -e "s|^ *||" -e "s| *$||")"
    if [ -n "$trimmed" ]; then
      cmd+=('-e')
      cmd+=("$trimmed")
    fi
  done <<< "$2"
  echo "${cmd[@]}"
}

function checkFiles() {
  local -r changedFiles="$(changedFiles)"
  local -r grepCmd="$(grepCmd "" "$FILES")"
  echo -e "\nUsing grep command to filter files:\n${grepCmd}\n"
  local -r foundFiles="$(echo "$changedFiles" | ${grepCmd} || true)"
  if [ -z "$foundFiles" ]; then
    echo -e "Not skipping: Important files detected." | tee -a $GITHUB_STEP_SUMMARY
    echo -e "\nImportant files:"
    echo "$(echo "$foundFiles" | head -n 10)"
    if [ "$(echo "$foundFiles" | wc -l)" -gt 10 ]; then
      echo "..."
    fi
    echo "skip=false" | tee -a $GITHUB_OUTPUT
  else
    echo "Skipping: No important files detected." | tee -a $GITHUB_STEP_SUMMARY
    echo "skip=true" >> $GITHUB_OUTPUT
    echo -e "\nChanged files:"
    echo -e "$(echo "$changedFiles" | head -n 10)"
    if [ "$(echo $changedFiles | wc -l)" -gt 10 ]; then
      echo "..."
    fi
  fi
  exit 0
}

function checkSkipFiles() {
  local -r changedFiles="$(changedFiles)"
  local -r grepCmd="$(grepCmd "-v" "$SKIP_FILES")"
  echo -e "\nUsing grep command to filter skip-files:\n${grepCmd}\n"
  local -r foundFiles="$(echo "$changedFiles" | ${grepCmd} || true)"
  if [ -z "$foundFiles" ]; then
    echo "Skipping: No important files detected." | tee -a $GITHUB_STEP_SUMMARY
    echo "skip=true" >> $GITHUB_OUTPUT
    echo -e "\nChanged files:"
    echo -e "$(echo "$changedFiles" | head -n 10)"
    if [ "$(echo $changedFiles | wc -l)" -gt 10 ]; then
      echo "..."
    fi
  else
    echo -e "Not skipping: Important files detected." | tee -a $GITHUB_STEP_SUMMARY
    echo -e "\nImportant files:"
    echo "$(echo "$foundFiles" | head -n 10)"
    if [ "$(echo $foundFiles | wc -l)" -gt 10 ]; then
      echo "..."
    fi
    echo "skip=false" | tee -a $GITHUB_OUTPUT
  fi
  exit 0
}

if [ -z "$FILES" ] && [ -z "$SKIP_FILES" ]; then
  echo "Error: Expected 'skip-files' or 'files' action params defined. Got none." | tee -a $GITHUB_STEP_SUMMARY
  exit 1
elif [ -n "$FILES" ] && [ -n "$SKIP_FILES" ]; then
  echo "Error: Expected 'skip-files' or 'files' action params defined. Got both." | tee -a $GITHUB_STEP_SUMMARY
  exit 1
fi

if [ "$CHECK_PREV_WORKFLOW_STATUS" == "true" ]; then
  noSkipIfInitCommit
  noSkipIfActionFailedForPrevCommit
fi
if [ -z "$SKIP_MESSAGES" ]; then
  skipCommitMessages
fi

if [ -z "$FILES" ]; then
  checkFiles
else
  checkSkipFiles
fi
