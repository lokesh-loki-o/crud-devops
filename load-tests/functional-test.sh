#!/usr/bin/env bash
# Functional check of every CRUD endpoint and the health endpoint.
# Usage: BASE_URL=http://localhost:3000 ./load-tests/functional-test.sh
set -u

BASE_URL="${BASE_URL:-http://localhost:3000}"
API="$BASE_URL/api/v1/tasks"
failures=0

check() { # name expected actual
  if [ "$2" = "$3" ]; then
    echo "PASS  $1 (HTTP $3)"
  else
    echo "FAIL  $1 (expected $2, got $3)"
    failures=$((failures + 1))
  fi
}

status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
json=(-H 'Content-Type: application/json')

check "GET /up" 200 "$(status "$BASE_URL/up")"
check "GET list" 200 "$(status "$API")"

created=$(curl -s "${json[@]}" -X POST "$API" -d '{"task":{"title":"functional test","description":"created by script"}}')
id=$(echo "$created" | sed -E 's/.*"id":([0-9]+).*/\1/')
case "$id" in
  ''|*[!0-9]*) echo "FAIL  POST create (response: $created)"; failures=$((failures + 1)); echo "FAILURES: $failures"; exit 1 ;;
  *) echo "PASS  POST create (id $id)" ;;
esac

check "GET one" 200 "$(status "$API/$id")"
check "PATCH update" 200 "$(status "${json[@]}" -X PATCH "$API/$id" -d '{"task":{"completed":true}}')"
check "PUT update" 200 "$(status "${json[@]}" -X PUT "$API/$id" -d '{"task":{"title":"functional test 2"}}')"

updated=$(curl -s "$API/$id")
case "$updated" in
  *'"completed":true'*'functional test 2'*|*'functional test 2'*'"completed":true'*) echo "PASS  update persisted" ;;
  *) echo "FAIL  update persisted ($updated)"; failures=$((failures + 1)) ;;
esac

check "POST invalid (blank title)" 422 "$(status "${json[@]}" -X POST "$API" -d '{"task":{"title":""}}')"
check "DELETE" 200 "$(status -X DELETE "$API/$id")"
check "GET deleted" 404 "$(status "$API/$id")"

echo "FAILURES: $failures"
[ "$failures" -eq 0 ]
