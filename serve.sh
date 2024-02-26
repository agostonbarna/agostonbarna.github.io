#!/usr/bin/env bash

set -euo pipefail

trap exit INT # exit on [Ctrl+C]

cd "$(dirname "${BASH_SOURCE[0]}")"

hugo server -e dev
