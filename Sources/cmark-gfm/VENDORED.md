# Vendored cmark-gfm

- Source: https://github.com/swiftlang/swift-cmark (branch `gfm`)
- Commit: 0c8947bbd58c491c54aae114aca40621cddc8357
- Version: 0.29.0.gfm.13
- Copied: `src/` → `Sources/cmark-gfm/`, `extensions/` → `Sources/cmark-gfm-extensions/`, `COPYING` into both.
- Local changes:
  - Backslash escapes: `inlines.c` (`handle_backslash`) flags the text node it makes with `CMARK_NODE__ESCAPED`, a
    new flag in `include/node.h` (custom flags now start one bit higher); `iterator.c` (`cmark_consolidate_text_nodes`)
    doesn't merge a flagged node into its neighbours; and `node.c` / `include/cmark-gfm.h` add
    `cmark_node_is_escaped_text`. So `\@ada` is not a mention and `\:rocket:` not a shortcode (`GlimmerParser`).
  - `cmark-gfm-extensions/tasklist.c`, `open_tasklist_item`: scans from the item's own marker, so tasks inside a
    block quote are tasks, and reads the checked state from the item's own brackets instead of anywhere on the line.
- To update, re-run the copy at a new commit, re-apply the local changes, and bump this file.
