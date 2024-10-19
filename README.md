# GitHub Action Skipper

GitHub action that skips run if:

- Previous commit passed workflow
- and there are important files in the push/pull_request

Why should you use this action?

- [Standard GitHub file filtering](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions#onpushpull_requestpull_request_targetpathspaths-ignore) skips action but branch protection rules require action to success
- [Skip Duplicate Actions](https://github.com/marketplace/actions/skip-duplicate-actions) is great and very flexible. You should consider using it when you need more options.

## Sample usage

```yml
name: Build

on:
  workflow_dispatch:
  pull_request:
  push:
    branches-ignore:
      - 'dependabot/**'
      - 'gh-pages'

jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    # Skip duplicate build on pull_request if pull request uses branch from the same repository
    if: github.event_name != 'pull_request' || github.repository != github.event.pull_request.head.repo.full_name
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Skip build if not needed
        id: skipper
        uses: coditory/action-skipper@v1
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          skip-files: |-
            ^.gitignore
            ^[^/]*\.md
            ^.github/.*\.md
            ^docs/.*
            ^gradle.properties

      - name: Setup JDK
        uses: actions/setup-java@v4
        if: steps.skipper.outputs.skip != 'true'
        with:
          java-version: 21
          distribution: temurin
```
