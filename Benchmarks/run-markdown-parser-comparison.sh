#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${GLIMMER_COMPARE_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
CONFIGURATION="${GLIMMER_COMPARE_CONFIGURATION:-Release}"
SECTIONS="${GLIMMER_COMPARE_MARKDOWN_SECTIONS:-40}"
REPEATS="${GLIMMER_COMPARE_MARKDOWN_REPEATS:-5}"
WARMUPS="${GLIMMER_COMPARE_MARKDOWN_WARMUPS:-1}"
CORPORA="${GLIMMER_COMPARE_MARKDOWN_CORPORA:-all}"

RUN_FLAG="/tmp/glimmer-run-markdown-parser-comparison"
SECTIONS_FILE="/tmp/glimmer-compare-markdown-sections"
REPEATS_FILE="/tmp/glimmer-compare-markdown-repeats"
WARMUPS_FILE="/tmp/glimmer-compare-markdown-warmups"
CORPORA_FILE="/tmp/glimmer-compare-markdown-corpora"

cleanup() {
    rm -f "$RUN_FLAG" "$SECTIONS_FILE" "$REPEATS_FILE" "$WARMUPS_FILE" "$CORPORA_FILE"
}

trap cleanup EXIT INT TERM

touch "$RUN_FLAG"
printf "%s" "$SECTIONS" > "$SECTIONS_FILE"
printf "%s" "$REPEATS" > "$REPEATS_FILE"
printf "%s" "$WARMUPS" > "$WARMUPS_FILE"
printf "%s" "$CORPORA" > "$CORPORA_FILE"

printf "Running Markdown parser comparison: configuration=%s, destination=%s, sections=%s, repeats=%s, warmups=%s, corpora=%s\n" \
    "$CONFIGURATION" "$DESTINATION" "$SECTIONS" "$REPEATS" "$WARMUPS" "$CORPORA"

cd "$ROOT_DIR/Benchmarks/MarkdownParserComparison"
xcodebuild -scheme MarkdownParserComparison-Package \
    -destination "$DESTINATION" \
    -configuration "$CONFIGURATION" \
    test

cd "$ROOT_DIR/Benchmarks/DownMarkdownParserComparison"
xcodebuild -scheme DownMarkdownParserComparison-Package \
    -destination "$DESTINATION" \
    -configuration "$CONFIGURATION" \
    test
