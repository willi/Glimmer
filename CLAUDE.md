# CLAUDE.md

Guidance for Claude Code in this repository. The repository guidelines, architecture and commands are in AGENTS.md:

@AGENTS.md

## Working notes

- Run one xcodebuild at a time. Two at once fight over the simulator and DerivedData.
- Check free disk space before long builds. Put scratch DerivedData under `.build/` (ignored) and delete it when done.
- Verify rendering changes with simulator screenshots, and accessibility changes with an XCUITest query. `axe
  describe-ui` sometimes returns an empty tree.
