#!/usr/bin/env bash
# One command for the single-UE baseline of the current PLATFORM:
#   health check -> RTT -> throughput (with CPU/RAM sampled throughout)
# Then run 12_measure_attach.sh and 20_run_scaling.sh separately
# (they restart UEs, so they are kept out of this script).
source "$(dirname "$0")/common.sh"
TAG=${1:-$(run_tag)}
"$BENCH_ROOT/scripts/00_healthcheck.sh" || { fail "Fix the health check first."; exit 1; }

mkdir -p "$RESULTS_ROOT/$TAG"
python3 "$BENCH_ROOT/scripts/resource_sampler.py" "$RESULTS_ROOT/$TAG/resources_baseline.csv" &
SAMPLER=$!; trap 'kill -TERM $SAMPLER 2>/dev/null' EXIT

"$BENCH_ROOT/scripts/10_measure_rtt.sh" "$TAG"
"$BENCH_ROOT/scripts/11_measure_throughput.sh" "$TAG"

kill -TERM $SAMPLER; wait $SAMPLER 2>/dev/null
cat "$RESULTS_ROOT/$TAG"/*/VALIDITY.txt 2>/dev/null && warn "Some tests above did not use the user plane - rerun them in namespace mode."
pass "Baseline done: $RESULTS_ROOT/$TAG"
info "Next: python3 $BENCH_ROOT/analysis/analyze.py"
