#!/usr/bin/env bash
# Fails when a hand-written Go file grows past the 300-line ceiling.
set -euo pipefail
cd "$(dirname "$0")/.."

limit=300
failed=0
checked=0

while IFS= read -r file; do
  checked=$((checked + 1))
  lines=$(wc -l < "$file" | tr -d ' ')
  if [ "$lines" -gt "$limit" ]; then
    echo "too long ($lines > $limit): $file"
    failed=1
  fi
done < <(find backend -name '*.go' -not -path 'backend/internal/store/*' -not -name '*.gen.go')

echo "size check: $checked files (limit $limit)"
exit "$failed"
