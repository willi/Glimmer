#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${GLIMMER_PARSER_BENCH_BUILD_DIR:-$ROOT_DIR/.tmp/parser-release-benchmark}"
mkdir -p "$BUILD_DIR"

OUTPUT="$BUILD_DIR/parser-release-benchmark"

sources=(
    "$ROOT_DIR/Sources/Glimmer/MarkdownConfiguration.swift"
    "$ROOT_DIR/Sources/Glimmer/MarkdownConfigurationBuilder.swift"
    "$ROOT_DIR/Sources/Glimmer/MarkdownExtension.swift"
    "$ROOT_DIR/Sources/Glimmer/Utilities/CodeHighlightingTheme.swift"
    "$ROOT_DIR/Sources/Glimmer/Parser/ParserState.swift"
    "$ROOT_DIR/Sources/Glimmer/Utilities/ParsingHelpers.swift"
    "$ROOT_DIR/Sources/Glimmer/Parser/MarkdownParser.swift"
    "$ROOT_DIR/Sources/Glimmer/Parser/MarkdownParserTypes.swift"
    "$ROOT_DIR/Sources/Glimmer/Parser/BlockParser.swift"
    "$ROOT_DIR/Sources/Glimmer/Parser/InlineParser.swift"
    "$ROOT_DIR/Sources/Glimmer/Parser/GFMExtensions.swift"
)

if [[ "${GLIMMER_PARSER_BENCH_REAL_EMOJI:-0}" == "1" ]]; then
    sources+=(
        "$ROOT_DIR/Sources/Glimmer/Parser/GitHubEmojis.swift"
        "$ROOT_DIR/Sources/Glimmer/Parser/GitHubEmojiLookup.swift"
    )
else
    sources+=("$ROOT_DIR/Benchmarks/ParserReleaseBenchmark/EmojiStub.swift")
fi

sources+=(
    "$ROOT_DIR/Benchmarks/ParserReleaseBenchmark/RendererStub.swift"
    "$ROOT_DIR/Benchmarks/ParserReleaseBenchmark/main.swift"
)

swiftc -O "${sources[@]}" -o "$OUTPUT"

"$OUTPUT"
