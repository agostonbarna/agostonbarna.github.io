#!/usr/bin/env bash

set -euo pipefail

trap exit INT # exit on [Ctrl+C]

cd "$(dirname "${BASH_SOURCE[0]}")"

find public_prod -mindepth 1 -maxdepth 1 -not -path '*/.git*' -exec rm -rf {} +
hugo --gc --minify -e production -d public_prod

git -C public_prod add .

if [[ "${1:-}" == amend ]]; then
  git -C public_prod commit --amend -C HEAD
  git -C public_prod push --force-with-lease
else
  git -C public_prod commit
  git -C public_prod push
fi
