#!/usr/bin/env bash
# Runs every supabase/tests/*.sql fixture against the local Supabase database.
# Each fixture wraps itself in a transaction and rolls back, so the database is
# left unchanged. Requires a running local stack (`supabase start` or
# `supabase db start`). Usage: scripts/run_sql_tests.sh [fixture.sql ...]
set -uo pipefail

container="${SUPABASE_DB_CONTAINER:-$(docker ps --format '{{.Names}}' | grep -m1 '^supabase_db_')}"
if [ -z "$container" ]; then
  echo "No running supabase_db_* container. Run 'supabase start' first." >&2
  exit 2
fi

cd "$(dirname "$0")/.."
files=("$@")
[ ${#files[@]} -eq 0 ] && files=(supabase/tests/*.sql)

failed=0
for file in "${files[@]}"; do
  if output=$(docker exec -i "$container" psql -X -q -U postgres -d postgres \
      -v ON_ERROR_STOP=1 < "$file" 2>&1); then
    echo "PASS $file"
  else
    echo "FAIL $file"
    echo "$output" | grep -E "ERROR|DETAIL|CONTEXT|HINT" | head -8 | sed 's/^/    /'
    failed=$((failed + 1))
  fi
done

echo "${#files[@]} fixtures, $failed failed"
[ "$failed" -eq 0 ]
