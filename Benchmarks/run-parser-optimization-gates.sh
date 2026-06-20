#!/usr/bin/env bash
set -euo pipefail

print_usage() {
    cat <<'USAGE'
Usage: Benchmarks/run-parser-optimization-gates.sh [quick|precommit|benchmark|compare]

Modes:
  quick      Run deterministic parser correctness lanes in parallel.
  precommit  Run quick, full correctness without benchmark suites, then standalone Release parse timings.
  benchmark  Run the standalone parser-only Release benchmark.
  compare    Run the external Markdown parser comparison benchmark serially.

Environment:
  GLIMMER_GATE_DESTINATIONS       Comma-separated simulator UUIDs for parallel lanes.
  GLIMMER_GATE_DESTINATION        Fallback xcodebuild destination.
  GLIMMER_GATE_LOG_DIR            Directory for lane logs and result bundles.
  GLIMMER_COMPARE_*               Passed through to run-markdown-parser-comparison.sh.
USAGE
}

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-quick}"

case "$MODE" in
    quick|precommit|benchmark|compare)
        ;;
    -h|--help|help)
        print_usage
        exit 0
        ;;
    *)
        print_usage >&2
        exit 2
        ;;
esac

STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_DIR="${GLIMMER_GATE_LOG_DIR:-$ROOT_DIR/.tmp/parser-gates/$STAMP}"
mkdir -p "$LOG_DIR"
LOG_DIR="$(cd "$LOG_DIR" && pwd)"

DESTINATION_IDS=()
if [[ -n "${GLIMMER_GATE_DESTINATIONS:-}" ]]; then
    IFS=',' read -r -a DESTINATION_IDS <<< "$GLIMMER_GATE_DESTINATIONS"
else
    while IFS= read -r device_id; do
        DESTINATION_IDS+=("$device_id")
    done < <(
        {
            xcrun simctl list devices available | sed -n '/iPhone.*(Booted)/s/.*(\([0-9A-F-]\{36\}\)) (Booted).*/\1/p'
            xcrun simctl list devices available | sed -n '/iPhone.*(Shutdown)/s/.*(\([0-9A-F-]\{36\}\)) (Shutdown).*/\1/p'
        } | awk '!seen[$0]++' | head -n 4
    )
fi

fallback_destination="${GLIMMER_GATE_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"

destination_for_lane() {
    local index="$1"
    if (( ${#DESTINATION_IDS[@]} > index )); then
        printf "id=%s" "${DESTINATION_IDS[$index]}"
    else
        printf "%s" "$fallback_destination"
    fi
}

run_glimmer_xcode() {
    local lane="$1"
    local destination="$2"
    shift 2

    cd "$ROOT_DIR"
    xcodebuild \
        -scheme Glimmer \
        -destination "$destination" \
        -derivedDataPath "$LOG_DIR/DerivedData-$lane" \
        -resultBundlePath "$LOG_DIR/$lane.xcresult" \
        "$@"
}

run_apple_parity() {
    local lane="$1"
    local destination="$2"

    cd "$ROOT_DIR/Benchmarks/MarkdownParserComparison"
    xcodebuild \
        -scheme MarkdownParserComparison-Package \
        -destination "$destination" \
        -derivedDataPath "$LOG_DIR/DerivedData-$lane" \
        -resultBundlePath "$LOG_DIR/$lane.xcresult" \
        test \
        -only-testing:MarkdownParserComparisonTests/MarkdownSemanticParityTests
}

run_sync() {
    local lane="$1"
    shift
    local log="$LOG_DIR/$lane.log"

    printf '[%s] start\n' "$lane"
    if "$@" > "$log" 2>&1; then
        printf '[%s] passed (%s)\n' "$lane" "$log"
    else
        printf '[%s] failed (%s)\n' "$lane" "$log" >&2
        tail -n 120 "$log" >&2
        return 1
    fi
}

PIDS=()
NAMES=()
LOGS=()

start_async() {
    local lane="$1"
    shift
    local log="$LOG_DIR/$lane.log"

    printf '[%s] start\n' "$lane"
    ("$@" > "$log" 2>&1) &
    PIDS+=("$!")
    NAMES+=("$lane")
    LOGS+=("$log")
}

wait_async_lanes() {
    local failed=0

    for index in "${!PIDS[@]}"; do
        local pid="${PIDS[$index]}"
        local lane="${NAMES[$index]}"
        local log="${LOGS[$index]}"

        if wait "$pid"; then
            printf '[%s] passed (%s)\n' "$lane" "$log"
        else
            printf '[%s] failed (%s)\n' "$lane" "$log" >&2
            tail -n 120 "$log" >&2
            failed=1
        fi
    done

    PIDS=()
    NAMES=()
    LOGS=()
    return "$failed"
}

run_quick_correctness() {
    local parallel="${GLIMMER_GATE_PARALLEL:-1}"
    local core_destination
    local parser_destination
    local streaming_destination
    local parity_destination
    core_destination="$(destination_for_lane 0)"
    parser_destination="$(destination_for_lane 1)"
    streaming_destination="$(destination_for_lane 2)"
    parity_destination="$(destination_for_lane 3)"

    if [[ "$parallel" == "1" && ${#DESTINATION_IDS[@]} -ge 4 ]]; then
        start_async parser-core run_glimmer_xcode parser-core "$core_destination" test \
            -only-testing:GlimmerTests/ParserSemanticSnapshotTests \
            -only-testing:GlimmerTests/ParserOptimizationEquivalenceTests \
            -only-testing:GlimmerTests/ParserLocationTests

        start_async parser-surface run_glimmer_xcode parser-surface "$parser_destination" test \
            -only-testing:GlimmerTests/ParserFeatureCoverageTests \
            -only-testing:GlimmerTests/ParserFeatureToggleTests \
            -only-testing:GlimmerTests/MarkdownParserTests \
            -only-testing:GlimmerTests/InlineAutolinkTests \
            -only-testing:GlimmerTests/InlineRangeParserTests \
            -only-testing:GlimmerTests/LinkImageTitleTests \
            -only-testing:GlimmerTests/ListTableParserTests \
            -only-testing:GlimmerTests/MentionParsingTests \
            -only-testing:GlimmerTests/RepoReferenceTests \
            -only-testing:GlimmerTests/FootnotePreprocessTests

        start_async parser-streaming run_glimmer_xcode parser-streaming "$streaming_destination" test \
            -only-testing:GlimmerTests/ParallelSplitterTests \
            -only-testing:GlimmerTests/ParallelParserAsyncTests \
            -only-testing:GlimmerTests/StreamingParserTests \
            -only-testing:GlimmerTests/StreamingDemoPrefixParserTests \
            -only-testing:GlimmerTests/RevealSessionTests \
            -only-testing:GlimmerTests/RevealSettledParityTests

        start_async apple-parity run_apple_parity apple-parity "$parity_destination"
        wait_async_lanes
    else
        run_sync parser-core run_glimmer_xcode parser-core "$core_destination" test \
            -only-testing:GlimmerTests/ParserSemanticSnapshotTests \
            -only-testing:GlimmerTests/ParserOptimizationEquivalenceTests \
            -only-testing:GlimmerTests/ParserLocationTests

        run_sync parser-surface run_glimmer_xcode parser-surface "$core_destination" test \
            -only-testing:GlimmerTests/ParserFeatureCoverageTests \
            -only-testing:GlimmerTests/ParserFeatureToggleTests \
            -only-testing:GlimmerTests/MarkdownParserTests \
            -only-testing:GlimmerTests/InlineAutolinkTests \
            -only-testing:GlimmerTests/InlineRangeParserTests \
            -only-testing:GlimmerTests/LinkImageTitleTests \
            -only-testing:GlimmerTests/ListTableParserTests \
            -only-testing:GlimmerTests/MentionParsingTests \
            -only-testing:GlimmerTests/RepoReferenceTests \
            -only-testing:GlimmerTests/FootnotePreprocessTests

        run_sync parser-streaming run_glimmer_xcode parser-streaming "$core_destination" test \
            -only-testing:GlimmerTests/ParallelSplitterTests \
            -only-testing:GlimmerTests/ParallelParserAsyncTests \
            -only-testing:GlimmerTests/StreamingParserTests \
            -only-testing:GlimmerTests/StreamingDemoPrefixParserTests \
            -only-testing:GlimmerTests/RevealSessionTests \
            -only-testing:GlimmerTests/RevealSettledParityTests

        run_sync apple-parity run_apple_parity apple-parity "$core_destination"
    fi
}

run_precommit() {
    local destination
    destination="$(destination_for_lane 0)"

    git -C "$ROOT_DIR" diff --check
    run_quick_correctness
    run_sync full-correctness run_glimmer_xcode full-correctness "$destination" test \
        -skip-testing:GlimmerTests/PerformanceOptimizationTests \
        -skip-testing:GlimmerTests/ProfilingBenchmarkTests \
        -skip-testing:GlimmerTests/MarkdownDisplayProfilingTests

    if [[ "${GLIMMER_GATE_XCODE_PHASE_TIMINGS:-0}" == "1" ]]; then
        run_sync phase-timings run_glimmer_xcode phase-timings "$destination" \
            -configuration Release ENABLE_TESTABILITY=YES test \
            -only-testing:GlimmerTests/ProfilingBenchmarkTests/testPhaseTimings
    else
        run_sync standalone-parse-benchmark "$ROOT_DIR/Benchmarks/run-parser-release-benchmark.sh"
    fi
}

run_benchmark() {
    cd "$ROOT_DIR"
    sh Benchmarks/run-parser-release-benchmark.sh
}

run_compare() {
    cd "$ROOT_DIR"
    GLIMMER_COMPARE_DESTINATION="${GLIMMER_COMPARE_DESTINATION:-$(destination_for_lane 0)}" \
        sh Benchmarks/run-markdown-parser-comparison.sh
}

case "$MODE" in
    quick)
        run_quick_correctness
        ;;
    precommit)
        run_precommit
        ;;
    benchmark)
        run_benchmark
        ;;
    compare)
        run_compare
        ;;
esac

printf 'Logs: %s\n' "$LOG_DIR"
