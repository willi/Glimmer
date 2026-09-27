# Vendored cmark-gfm

- Source: https://github.com/swiftlang/swift-cmark (branch `gfm`)
- Commit: 0c8947bbd58c491c54aae114aca40621cddc8357
- Version: 0.29.0.gfm.13
- Copied: `src/` → `Sources/cmark-gfm/`, `extensions/` → `Sources/cmark-gfm-extensions/`, `COPYING` into both.
- Local changes:
  - `iterator.c`, `cmark_consolidate_text_nodes`: a backslash-escaped character stays its own text node instead of
    merging into its neighbours, so `\@ada` is not a mention and `\:rocket:` not a shortcode (`GlimmerParser`).
- To update, re-run the copy at a new commit, re-apply the local changes, and bump this file.
