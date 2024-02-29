#!/usr/bin/env bash

set -euo pipefail

trap exit INT # exit on [Ctrl+C]

cd "$(dirname "${BASH_SOURCE[0]}")"

find public_prod -mindepth 1 -maxdepth 1 -not -path '*/.git*' -exec rm -rf {} +
hugo --gc --minify -e production -d public_prod

cd public_prod
git add .

if [[ "${1:-}" == amend ]]; then
  git commit --amend -C HEAD
  git push --force-with-lease
else
  git commit
  git push
fi
