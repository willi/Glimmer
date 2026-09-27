# Vendored cmark-gfm

- Source: https://github.com/swiftlang/swift-cmark (branch `gfm`)
- Commit: 0c8947bbd58c491c54aae114aca40621cddc8357
- Version: 0.29.0.gfm.13
- Copied: `src/` → `Sources/cmark-gfm/`, `extensions/` → `Sources/cmark-gfm-extensions/`, `COPYING` into both.
- Local changes:
  - `iterator.c`, `cmark_consolidate_text_nodes`: a backslash-escaped character stays its own text node instead of
    merging into its neighbours, so `\@ada` is not a mention and `\:rocket:` not a shortcode (`GlimmerParser`).
    An escape is recognised as one punctuation character spanning two source columns. A punctuation character at the
    end of a line followed by trimmed spaces (`*foo*. `) matches too; it follows a non-text inline and precedes a break,
    so it has no text neighbour to merge with and nothing changes.
  - `cmark-gfm-extensions/tasklist.c`, `open_tasklist_item`: scans from the item's own marker, so tasks inside a
    block quote are tasks, and reads the checked state from the item's own brackets instead of anywhere on the line.
- To update, re-run the copy at a new commit, re-apply the local changes, and bump this file.
