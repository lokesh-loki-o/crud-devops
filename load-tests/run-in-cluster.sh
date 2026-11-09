#!/usr/bin/env bash
# Runs the k6 test inside Minikube and saves results to load-tests/results/<label>/.
# Usage: ./load-tests/run-in-cluster.sh [label]
set -euo pipefail

cd "$(dirname "$0")/.."
LABEL="${1:-baseline}"
OUT="load-tests/results/$LABEL"
NS=crud-app
mkdir -p "$OUT"

kubectl -n "$NS" create configmap k6-script --from-file=load-tests/k6-load-test.js \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" delete pod k6-runner --ignore-not-found --wait=true
kubectl apply -f load-tests/k6-runner.yaml
kubectl -n "$NS" wait --for=condition=Ready pod/k6-runner --timeout=180s

# Sample per-pod CPU and memory every 5 seconds during the run.
(
  while true; do
    echo "--- $(date +%H:%M:%S)"
    kubectl -n "$NS" top pod --no-headers 2>&1 || true
    sleep 5
  done
) > "$OUT/kubectl-top.txt" &
SAMPLER=$!
trap 'kill $SAMPLER 2>/dev/null || true' EXIT

kubectl -n "$NS" get pods > "$OUT/pods-before.txt"

# Exact counters from the container's cgroup: kubectl top refreshes too slowly
# to show short peaks. usage_usec / run time gives real CPU use; nr_throttled
# shows whether the CPU limit was hit; memory.peak is the high-water mark.
cgroup() {
  kubectl -n "$NS" exec deploy/crud-web -c web -- sh -c \
    'date +%s; cat /sys/fs/cgroup/cpu.stat /sys/fs/cgroup/memory.peak /sys/fs/cgroup/memory.current'
}
cgroup > "$OUT/cgroup-before.txt"

set +e
kubectl -n "$NS" exec k6-runner -- k6 run -e HOLD="${HOLD:-60s}" \
  --out csv=/tmp/metrics.csv --summary-export=/tmp/summary.json \
  /scripts/k6-load-test.js | tee "$OUT/k6-output.txt"
K6_STATUS=${PIPESTATUS[0]}
set -e
cgroup > "$OUT/cgroup-after.txt"

kubectl -n "$NS" exec k6-runner -- cat /tmp/summary.json > "$OUT/summary.json"
kubectl -n "$NS" exec k6-runner -- sh -c \
  'head -1 /tmp/metrics.csv; grep -E "^(http_req_duration|http_req_failed|http_reqs)," /tmp/metrics.csv' \
  > "$OUT/metrics.csv"
kubectl -n "$NS" get pods > "$OUT/pods-after.txt"
kubectl -n "$NS" delete pod k6-runner --wait=false

python3 load-tests/analyze.py "$OUT"
echo "k6 exit status: $K6_STATUS (99 means a threshold was missed)"
