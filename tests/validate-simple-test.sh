#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
output_file=$(mktemp)
trap 'rm -f "$output_file"' EXIT

if ! (cd /tmp && "$repo_root/setup/validate-simple.sh") >"$output_file" 2>&1; then
    cat "$output_file"
    echo "validator failed when invoked outside the repository" >&2
    exit 1
fi

if grep -q '(not found)' "$output_file"; then
    cat "$output_file"
    echo "validator looked outside its own repository" >&2
    exit 1
fi

grep -q 'Invalid:.*0' "$output_file"
