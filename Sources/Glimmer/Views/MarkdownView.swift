import SwiftUI

#if DEBUG
public struct URLStreamingMarkdownView: View {
    let markdownURL: URL
    @State private var blocks: [MarkdownParser.BlockNode] = []
    @State private var isLoading = true
    @State private var loadTask: Task<Void, Never>?

    let configuration: MarkdownConfiguration

    public init(
        markdownURL: URL,
        configuration: MarkdownConfiguration = .default
    ) {
        self.markdownURL = markdownURL
        self.configuration = configuration
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(MarkdownBlockStableID.pairs(for: blocks), id: \.id) { pair in
                    MarkdownBlockView(block: pair.block, configuration: configuration, depth: 0)
                }

                if isLoading {
                    ProgressView()
                        .padding()
                }
            }
            .padding()
        }
        .task {
            loadTask = Task {
                await loadMarkdownStreaming()
            }
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }

    private func loadMarkdownStreaming() async {
        let parser = StreamingMarkdownParser(configuration: configuration)

        do {
            let (stream, _) = try await URLSession.shared.bytes(from: markdownURL)
            var buffer = ""
            let chunkSize = 1024 * 64 // 64KB chunks

            for try await byte in stream {
                buffer.append(Character(UnicodeScalar(byte)))

                if buffer.count >= chunkSize {
                    let newBlocks = parser.parseChunk(buffer)
                    buffer = ""

                    if Task.isCancelled { break }

                    await MainActor.run {
                        blocks.append(contentsOf: newBlocks)
                    }
                }
            }

            // Process remaining buffer
            if !buffer.isEmpty && !Task.isCancelled {
                let newBlocks = parser.parseChunk(buffer)
                await MainActor.run {
                    blocks.append(contentsOf: newBlocks)
                }
            }

            // Get final blocks
            let finalBlocks = parser.finish()
            await MainActor.run {
                blocks.append(contentsOf: finalBlocks)
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
        }
    }
}
#endif

public struct MarkdownView: View {
    let markdown: String
    let configuration: MarkdownConfiguration
    let interactive: Bool
    let onLinkTap: ((URL) -> Void)?
    let onMentionTap: ((String) -> Void)?
    let onIssueTap: ((Int) -> Void)?
    let enableStreaming: Bool
    
    @State private var blocks: [MarkdownParser.BlockNode] = []
    @State private var isLoading = false
    @State private var parseTask: Task<Void, Never>?
    @State private var selectedFootnote: (label: String, content: [MarkdownParser.BlockNode])? = nil
    @State private var showFootnoteSheet = false
    @State private var footnoteDefinitions: [String: [MarkdownParser.BlockNode]] = [:]
    @State private var lastParsedMarkdown: String = ""
    @State private var isStreamingMode = false
    @State private var streamingParser: StreamingMarkdownParser?
    @Environment(\.openURL) private var openURL
    
    public init(
        markdown: String,
        configuration: MarkdownConfiguration = .default,
        interactive: Bool = true,
        onLinkTap: ((URL) -> Void)? = nil,
        onMentionTap: ((String) -> Void)? = nil,
        onIssueTap: ((Int) -> Void)? = nil,
        enableStreaming: Bool = false
    ) {
        self.markdown = markdown
        self.configuration = configuration
        self.interactive = interactive
        self.onLinkTap = onLinkTap
        self.onMentionTap = onMentionTap
        self.onIssueTap = onIssueTap
        self.enableStreaming = enableStreaming
    }
    
    
    public var body: some View {
        return Group {
            if isLoading && blocks.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .onAppear {
                    }
            } else if blocks.isEmpty && !isLoading {
                Text("No content to display")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView {
                    if interactive {
                        InteractiveMarkdownContent(
                            blocks: blocks,
                            configuration: configuration,
                            onLinkTap: handleLinkTap,
                            onMentionTap: onMentionTap,
                            onIssueTap: onIssueTap,
                            onFootnoteTap: handleFootnoteTap
                        )
                        .animation(enableStreaming ? nil : .default, value: blocks.count)
                    } else {
                        MarkdownContentView(
                            blocks: blocks,
                            configuration: configuration
                        )
                        .animation(enableStreaming ? nil : .default, value: blocks.count)
                    }
                }
            }
        }
        .task(id: markdown) {
            await parseMarkdown()
        }
        .onDisappear {
            parseTask?.cancel()
            parseTask = nil
            streamingParser = nil
            // Ensure isLoading is reset when view disappears
            isLoading = false
        }
        .sheet(isPresented: $showFootnoteSheet) {
            if let footnote = selectedFootnote {
                NavigationStack {
                    FootnoteDetailView(
                        label: footnote.label,
                        content: footnote.content,
                        configuration: configuration
                    )
                }
            }
        }
    }
    
    @MainActor
    private func parseMarkdown() async {
        
        // Cancel any existing parse task to prevent multiple concurrent parses
        parseTask?.cancel()
        parseTask = nil
        
        // Skip if markdown hasn't changed
        guard markdown != lastParsedMarkdown else {
            return
        }
        
        // Detect if we're in streaming mode (markdown is growing)
        let isStreaming = enableStreaming && 
                          !lastParsedMarkdown.isEmpty && 
                          markdown.hasPrefix(lastParsedMarkdown) && 
                          markdown.count > lastParsedMarkdown.count
        
        if enableStreaming {
            isStreamingMode = true
            if isStreaming && !blocks.isEmpty {
                await parseIncrementally()
            } else {
                await parseStreamingDocument()
            }
        } else {
            // Full parse for new content or major changes
            isStreamingMode = false
            await parseFullDocument()
        }
        
        lastParsedMarkdown = markdown
    }
    
    @MainActor
    private func parseIncrementally() async {
        guard let parser = streamingParser,
              markdown.hasPrefix(lastParsedMarkdown),
              markdown.count >= lastParsedMarkdown.count else {
            await parseStreamingDocument()
            return
        }

        let delta = String(markdown.dropFirst(lastParsedMarkdown.count))
        if !delta.isEmpty {
            _ = parser.parseChunk(delta)
        }

        if !Task.isCancelled {
            let snapshot = parser.snapshotBlocks()
            blocks = snapshot
            footnoteDefinitions = extractFootnoteDefinitions(from: snapshot)
        }
    }

    @MainActor
    private func parseStreamingDocument() async {
        guard !markdown.isEmpty else {
            if !blocks.isEmpty {
                blocks.removeAll(keepingCapacity: false)
            }
            footnoteDefinitions = [:]
            streamingParser = StreamingMarkdownParser(configuration: configuration)
            isLoading = false
            return
        }

        if blocks.isEmpty {
            isLoading = true
        }

        defer {
            isLoading = false
        }

        let parser = StreamingMarkdownParser(configuration: configuration)
        _ = parser.parseChunk(markdown)
        let snapshot = parser.snapshotBlocks()

        guard !Task.isCancelled else {
            return
        }

        streamingParser = parser
        blocks = snapshot
        footnoteDefinitions = extractFootnoteDefinitions(from: snapshot)
    }
    
    @MainActor
    private func parseFullDocument() async {
        streamingParser = nil
        // Skip parsing if markdown is empty
        guard !markdown.isEmpty else {
            // Markdown is empty, skipping parse
            // Only clear blocks if markdown is empty
            if !blocks.isEmpty {
                blocks.removeAll(keepingCapacity: false)
            }
            isLoading = false
            return
        }
        
        // Only show loading if blocks are empty (initial load)
        if blocks.isEmpty {
            isLoading = true
            
            // Set a timeout to reset loading state
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                if isLoading {
                    // WARNING: Loading timeout - forcing isLoading = false
                    isLoading = false
                }
            }
        }
        
        defer {
            // Always reset isLoading at the end
            isLoading = false
            // parseFullDocument completed
        }
        
        let configCopy = configuration
        let markdownCopy = markdown
        
        // Parse in background
        let parsed = await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                // Parsing markdown
                let result = Glimmer.parse(markdownCopy, configuration: configCopy)
                // Parsed blocks
                return result
            }
        }.value
        
        // Check if task was cancelled
        guard !Task.isCancelled else {
            // Task was cancelled, not updating blocks
            return
        }
        
        // Update blocks
        blocks = parsed
        
        // Extract footnote definitions
        footnoteDefinitions = extractFootnoteDefinitions(from: parsed)
        
    }
    
    private func handleLinkTap(_ url: URL) {
        if let onLinkTap = onLinkTap {
            onLinkTap(url)
        } else {
            openURL(url)
        }
    }
    
    private func handleFootnoteTap(_ label: String) {
        guard configuration.enableFootnotes,
              let content = footnoteDefinitions[label] else { return }
        
        selectedFootnote = (label: label, content: content)
        showFootnoteSheet = true
    }
    
    private func extractFootnoteDefinitions(from blocks: [MarkdownParser.BlockNode]) -> [String: [MarkdownParser.BlockNode]] {
        var definitions: [String: [MarkdownParser.BlockNode]] = [:]
        
        for block in blocks {
            extractFootnoteDefinitionsFromBlock(block, into: &definitions)
        }
        
        return definitions
    }
    
    private func extractFootnoteDefinitionsFromBlock(_ block: MarkdownParser.BlockNode, into definitions: inout [String: [MarkdownParser.BlockNode]]) {
        switch block {
        case .footnoteDefinition(let label, let children):
            definitions[label] = children
        case .blockquote(let children):
            for child in children {
                extractFootnoteDefinitionsFromBlock(child, into: &definitions)
            }
        case .list(_, _, let items):
            for item in items {
                for content in item.content {
                    extractFootnoteDefinitionsFromBlock(content, into: &definitions)
                }
            }
        default:
            break
        }
    }
}

// MARK: - Static Content Rendering (from original MarkdownView)

/// View that renders parsed markdown blocks without interactivity
public struct MarkdownContentView: View {
    let blocks: [MarkdownParser.BlockNode]
    let configuration: MarkdownConfiguration
    private let identifiedBlocks: [MarkdownBlockStableID.Pair]
    
    public init(blocks: [MarkdownParser.BlockNode], configuration: MarkdownConfiguration) {
        self.blocks = blocks
        self.configuration = configuration
        self.identifiedBlocks = MarkdownBlockStableID.pairs(for: blocks)
    }
    
    public var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(identifiedBlocks, id: \.id) { pair in
                MarkdownBlockView(block: pair.block, configuration: configuration, depth: 0)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// View that renders individual markdown blocks
struct MarkdownBlockView: View {
    let block: MarkdownParser.BlockNode
    let configuration: MarkdownConfiguration
    let depth: Int
    
    init(block: MarkdownParser.BlockNode, configuration: MarkdownConfiguration, depth: Int = 0) {
        self.block = block
        self.configuration = configuration
        self.depth = depth
    }
    
    var body: some View {
        switch block {
        case .heading(let level, let children, _):
            let headingFont = level > 0 && level <= configuration.headingFonts.count ? configuration.headingFonts[level - 1] : .headline
            Text(renderHeadingInlineNodes(children, font: headingFont))
            
        case .paragraph(let children):
            MarkdownInlineView(
                nodes: children,
                configuration: configuration
            )
            
        case .blockquote(let children):
            HStack(spacing: 12) {
                Rectangle()
                    .fill(configuration.blockquoteColor)
                    .frame(width: 4)
                
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(MarkdownBlockStableID.pairs(for: children), id: \.id) { pair in
                        MarkdownBlockView(
                            block: pair.block,
                            configuration: configuration,
                            depth: depth
                        )
                        .foregroundColor(configuration.blockquoteColor)
                    }
                }
            }
            .padding(.leading, 8)
            
        case .codeBlock(let language, let content):
            VStack(alignment: .leading, spacing: 8) {
                if let language = language, !language.isEmpty {
                    Text(language)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(SyntaxHighlighter(theme: configuration.codeBlockTheme).highlight(code: content, language: language))
                        .font(configuration.codeFont)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(configuration.codeBackgroundColor)
                        .cornerRadius(8)
                }
            }
            
        case .list(let ordered, _, let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        if item.isTask {
                            Image(systemName: item.isChecked == true ? "checkmark.square.fill" : "square")
                                .foregroundColor(item.isChecked == true ? .green : .secondary)
                                .font(.system(size: 16))
                        } else {
                            Text(ListFormatting.listMarker(ordered: ordered, index: index, depth: depth))
                                .font(ListFormatting.listMarkerFont(ordered: ordered, depth: depth, baseFont: configuration.baseFont))
                                .foregroundColor(.primary)
                                .frame(minWidth: 20, alignment: ordered ? .trailing : .center)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(MarkdownBlockStableID.pairs(for: item.content), id: \.id) { pair in
                                MarkdownBlockView(
                                    block: pair.block,
                                    configuration: configuration,
                                    depth: depth + 1
                                )
                            }
                        }
                    }
                }
            }
            
        case .taskList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.isChecked ? "checkmark.square.fill" : "square")
                            .foregroundColor(item.isChecked ? .green : .secondary)
                            .font(.system(size: 16))
                        
                        MarkdownInlineView(
                            nodes: item.content,
                            configuration: configuration
                        )
                    }
                }
            }
            
        case .table(let header, let rows):
            MarkdownTableView(header: header, rows: rows, configuration: configuration)
            
        case .horizontalRule:
            Divider()
                .padding(.vertical, 8)
            
        case .html(let content):
            Text(content)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
            
        case .footnoteDefinition(_, _):
            // Footnote definitions are collected and displayed separately
            EmptyView()
        }
    }
    
    private func headingFont(for level: Int) -> Font {
        if level - 1 < configuration.headingFonts.count {
            return configuration.headingFonts[level - 1]
        } else {
            return .headline // Fallback
        }
    }
    
    private func renderInlineNodes(_ nodes: [MarkdownParser.InlineNode]) -> AttributedString {
        let renderer = MarkdownRenderer()
        return renderer.renderInlines(nodes, configuration: configuration)
    }
    
    private func renderHeadingInlineNodes(_ nodes: [MarkdownParser.InlineNode], font: Font) -> AttributedString {
        let renderer = MarkdownRenderer()
        return renderer.renderInlines(nodes, configuration: configuration, baseFont: font)
    }
}

/// View that renders markdown tables with wrapping cell widths.
struct MarkdownTableView: View {
    let header: [MarkdownParser.TableCell]
    let rows: [[MarkdownParser.TableCell]]
    let configuration: MarkdownConfiguration

    @State private var availableWidth: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let columnWidths = resolvedColumnWidths
        let maxColumns = max(header.count, rows.map { $0.count }.max() ?? 0)

        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(0..<header.count, id: \.self) { index in
                        MarkdownTableCell(
                            cell: header[index],
                            isHeader: true,
                            configuration: configuration,
                            width: cellWidth(index: index, cellCount: header.count, maxColumns: maxColumns, columnWidths: columnWidths),
                            isLastColumn: index == header.count - 1,
                            isLastRow: false
                        )
                        .gridCellColumns(index == header.count - 1 ? maxColumns - header.count + 1 : 1)
                    }
                }
                .background(Color.secondary.opacity(0.1))

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(0..<row.count, id: \.self) { cellIndex in
                            MarkdownTableCell(
                                cell: row[cellIndex],
                                isHeader: false,
                                configuration: configuration,
                                width: cellWidth(index: cellIndex, cellCount: row.count, maxColumns: maxColumns, columnWidths: columnWidths),
                                isLastColumn: cellIndex == row.count - 1,
                                isLastRow: rowIndex == rows.count - 1
                            )
                            .gridCellColumns(cellIndex == row.count - 1 ? maxColumns - row.count + 1 : 1)
                        }
                    }
                }
            }
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onGeometryChange(for: CGFloat.self) { proxy in
                ceil(proxy.size.height)
            } action: { newHeight in
                updateContentHeight(newHeight)
            }
        }
        .frame(height: contentHeight > 0 ? contentHeight : nil)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            if newWidth > 0 {
                availableWidth = newWidth
            }
        }
    }

    private var resolvedColumnWidths: [CGFloat] {
        let measuredWidths = TextMeasurement.calculateColumnWidths(
            header: header,
            rows: rows,
            baseFont: configuration.baseFont
        )
        return TextMeasurement.constrainColumnWidthsForWrapping(
            measuredWidths,
            availableWidth: availableWidth
        )
    }

    private func cellWidth(
        index: Int,
        cellCount: Int,
        maxColumns: Int,
        columnWidths: [CGFloat]
    ) -> CGFloat? {
        if index == cellCount - 1 && cellCount < maxColumns {
            return nil
        }
        return index < columnWidths.count ? columnWidths[index] : nil
    }

    private func updateContentHeight(_ newHeight: CGFloat) {
        guard newHeight.isFinite, newHeight > 0 else { return }
        if abs(contentHeight - newHeight) > 0.5 {
            contentHeight = newHeight
        }
    }
}

/// View that renders table cells
struct MarkdownTableCell: View {
    let cell: MarkdownParser.TableCell
    let isHeader: Bool
    let configuration: MarkdownConfiguration
    let width: CGFloat?
    let isLastColumn: Bool
    let isLastRow: Bool
    
    init(cell: MarkdownParser.TableCell, isHeader: Bool, configuration: MarkdownConfiguration, width: CGFloat? = nil, isLastColumn: Bool = false, isLastRow: Bool = false) {
        self.cell = cell
        self.isHeader = isHeader
        self.configuration = configuration
        self.width = width
        self.isLastColumn = isLastColumn
        self.isLastRow = isLastRow
    }
    
    var body: some View {
        // Split content by line breaks to handle multiline cells
        let lines = splitIntoLines(cell.content)
        
        // Use ZStack to ensure proper positioning and prevent clipping
        ZStack(alignment: alignment(for: cell.alignment)) {
            // Background for debugging (can be removed)
            Color.clear
            
            if lines.count > 1 {
                VStack(alignment: alignmentHorizontal(for: cell.alignment), spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, nodes in
                        MarkdownInlineView(
                            nodes: nodes,
                            configuration: configuration,
                            baseFont: isHeader ? configuration.baseFont.bold() : configuration.baseFont
                        )
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(textAlignment(for: cell.alignment))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            } else {
                MarkdownInlineView(
                    nodes: cell.content,
                    configuration: configuration,
                    baseFont: isHeader ? configuration.baseFont.bold() : configuration.baseFont
                )
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(textAlignment(for: cell.alignment))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
        .frame(width: width, alignment: alignment(for: cell.alignment))
        .clipped() // Ensure content doesn't overflow bounds
        .overlay(
            GeometryReader { geometry in
                Path { path in
                    let rect = geometry.frame(in: .local)
                    
                    // Right border (except for last column)
                    if !isLastColumn {
                        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                    }
                    
                    // Bottom border (except for last row)
                    if !isLastRow {
                        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                    }
                }
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
            }
        )
            }
    
    private func splitIntoLines(_ nodes: [MarkdownParser.InlineNode]) -> [[MarkdownParser.InlineNode]] {
        var lines: [[MarkdownParser.InlineNode]] = [[]]
        var currentLine: [MarkdownParser.InlineNode] = []
        
        for node in nodes {
            switch node {
            case .html(let tag):
                if tag.lowercased() == "<br>" || tag.lowercased() == "<br/>" || tag.lowercased() == "<br />" {
                    // Start a new line
                    if !currentLine.isEmpty {
                        lines.append(currentLine)
                        currentLine = []
                    }
                } else {
                    currentLine.append(node)
                }
            case .lineBreak, .softBreak:
                // Start a new line
                if !currentLine.isEmpty {
                    lines.append(currentLine)
                    currentLine = []
                }
            default:
                currentLine.append(node)
            }
        }
        
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        
        // Remove empty lines and ensure at least one line
        lines = lines.filter { !$0.isEmpty }
        if lines.isEmpty {
            lines = [[]]
        }
        
        return lines
    }
    
    private func alignmentHorizontal(for tableAlignment: MarkdownParser.TableAlignment) -> HorizontalAlignment {
        switch tableAlignment {
        case .left, .none:
            return .leading
        case .center:
            return .center
        case .right:
            return .trailing
        }
    }
    
    private func alignment(for tableAlignment: MarkdownParser.TableAlignment) -> Alignment {
        switch tableAlignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        case .none: return .leading
        }
    }
    
    private func textAlignment(for tableAlignment: MarkdownParser.TableAlignment) -> TextAlignment {
        switch tableAlignment {
        case .left, .none: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}

/// Recursively reports whether any inline node is an image, descending into the
/// children of links, emphasis, strong, and strikethrough. A linked image such as
/// `[![avatar](img)](href)` is a top-level `.link` whose `.image` child must route
/// to the inline-image (NSTextAttachment) renderer rather than degrading to literal
/// `[Image: …]` text.
private func inlineNodesContainImage(_ nodes: [MarkdownParser.InlineNode]) -> Bool {
    nodes.contains { node in
        switch node {
        case .image:
            return true
        case let .link(_, _, children),
             let .emphasis(children),
             let .strong(children),
             let .strikethrough(children):
            return inlineNodesContainImage(children)
        default:
            return false
        }
    }
}

/// View that renders inline markdown elements
struct MarkdownInlineView: View {
    let nodes: [MarkdownParser.InlineNode]
    let configuration: MarkdownConfiguration
    let baseFont: Font

    @Environment(\.openURL) private var openURL

    init(nodes: [MarkdownParser.InlineNode], configuration: MarkdownConfiguration, baseFont: Font? = nil) {
        self.nodes = nodes
        self.configuration = configuration
        self.baseFont = baseFont ?? configuration.baseFont
    }
    
    var body: some View {
        
        // Check if we have any images (including images nested inside links/emphasis)
        let hasImages = inlineNodesContainImage(nodes)

        if hasImages {
            // For content with images, we need a custom layout that properly handles inline flow
            createInlineContentWithImages()
        } else {
            // Use AttributedString for text-only content
            Text(createAttributedString())
                .textSelection(.enabled)
        }
    }
    
    @ViewBuilder
    private func createInlineContentWithImages() -> some View {
        // Use NSAttributedString with NSTextAttachment for true inline images on iOS
        AttributedTextView(
            nodes: nodes,
            configuration: configuration,
            baseFont: baseFont,
            onImageTap: configuration.onImageTap,
            // A tap on a linked attachment (e.g. a linked avatar) opens the link target.
            onLinkTap: { openURL($0) }
        )
    }
    
    // Helper to group consecutive text nodes
    private func groupNodes(_ nodes: [MarkdownParser.InlineNode]) -> [(isText: Bool, nodes: [MarkdownParser.InlineNode])] {
        var groups: [(isText: Bool, nodes: [MarkdownParser.InlineNode])] = []
        var currentGroup: [MarkdownParser.InlineNode] = []
        // no-op flag removed (was unused)
        
        for node in nodes {
            if case .image = node {
                // End current text group if any
                if !currentGroup.isEmpty {
                    groups.append((isText: true, nodes: currentGroup))
                    currentGroup = []
                }
                // Add image as its own group
                groups.append((isText: false, nodes: [node]))
            } else {
                // Add to current text group
                currentGroup.append(node)
            }
        }
        
        // Add remaining text group
        if !currentGroup.isEmpty {
            groups.append((isText: true, nodes: currentGroup))
        }
        
        return groups
    }
    
    @ViewBuilder
    private func renderInlineImage(url: URL, alt: String, title: String?) -> some View {
        let isTinyImage = url.absoluteString.contains("/16/")
        let isSmallImage = alt.contains("icon") || alt.contains("small") || 
                          url.absoluteString.contains("/20/") ||
                          url.absoluteString.contains("/16/")
        
        let imageHeight: CGFloat = isTinyImage ? 14 : (isSmallImage ? 18 : 24)
        
        let imageContent = AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: imageHeight)
                    .frame(maxWidth: imageHeight * 2) // Reasonable max width
            case .failure(_):
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
                    .frame(width: imageHeight, height: imageHeight)
            case .empty:
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: imageHeight, height: imageHeight)
            @unknown default:
                EmptyView()
            }
        }
        .accessibilityLabel(alt.isEmpty ? "Image" : alt)
        
        if let onImageTap = configuration.onImageTap {
            Button {
                onImageTap(url, alt)
            } label: {
                imageContent
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            imageContent
        }
    }
    
    private func renderInlineNodes(_ nodes: [MarkdownParser.InlineNode]) -> AttributedString {
        let renderer = MarkdownRenderer()
        return renderer.renderInlines(nodes, configuration: configuration, baseFont: baseFont)
    }
    
    private func checkForProcessedEmojiImages() -> Bool {
        if !configuration.enableEmojiShortcodes { return false }
        
        let fullText = nodes.compactMap { node in
            if case .text(let string) = node {
                return string
            } else {
                return nil
            }
        }.joined()
        
        let emojiPattern = #":([a-zA-Z0-9_+-]+):"#
        let regex = try? NSRegularExpression(pattern: emojiPattern)
        let hasEmojiPatterns = regex?.firstMatch(in: fullText, range: NSRange(fullText.startIndex..., in: fullText)) != nil
        
        if hasEmojiPatterns {
            let processedFullText = fullText
            let imagePattern = #"!\[:([^:]+):\]\((https://[^)]+)\)"#
            let imageRegex = try? NSRegularExpression(pattern: imagePattern)
            return imageRegex?.firstMatch(in: processedFullText, range: NSRange(processedFullText.startIndex..., in: processedFullText)) != nil
        }
        
        return false
    }
    
    private func getProcessedNodes() -> [MarkdownParser.InlineNode] {
        if !configuration.enableEmojiShortcodes { return nodes }
        
        let fullText = nodes.compactMap { node in
            if case .text(let string) = node {
                return string
            } else {
                return nil
            }
        }.joined()
        
        let emojiPattern = #":([a-zA-Z0-9_+-]+):"#
        let regex = try? NSRegularExpression(pattern: emojiPattern)
        let hasEmojiPatterns = regex?.firstMatch(in: fullText, range: NSRange(fullText.startIndex..., in: fullText)) != nil
        
        if hasEmojiPatterns {
            let processedFullText = fullText
            if processedFullText != fullText {
                // Parse the processed text to extract any image markdown
                return parseProcessedTextToNodes(processedFullText)
            }
        }
        
        return nodes
    }
    
    private func parseProcessedTextToNodes(_ processedText: String) -> [MarkdownParser.InlineNode] {
        // Parse image markdown patterns and convert to nodes
        let imagePattern = #"!\[:([^:]+):\]\((https://[^)]+)\)"#
        let imageRegex = try? NSRegularExpression(pattern: imagePattern)
        
        guard let imageRegex = imageRegex else {
            return [.text(processedText)]
        }
        
        var result: [MarkdownParser.InlineNode] = []
        var lastEnd = processedText.startIndex
        let matches = imageRegex.matches(in: processedText, range: NSRange(processedText.startIndex..., in: processedText))
        
        for match in matches {
            if let range = Range(match.range, in: processedText),
               let altRange = Range(match.range(at: 1), in: processedText),
               let urlRange = Range(match.range(at: 2), in: processedText) {
                
                // Add text before image
                if lastEnd < range.lowerBound {
                    let textBefore = String(processedText[lastEnd..<range.lowerBound])
                    if !textBefore.isEmpty {
                        result.append(.text(textBefore))
                    }
                }
                
                // Add image node
                let alt = String(processedText[altRange])
                let urlString = String(processedText[urlRange])
                if let url = URL(string: urlString) {
                    result.append(.image(url: url, alt: alt, title: nil))
                }
                
                lastEnd = range.upperBound
            }
        }
        
        // Add remaining text
        if lastEnd < processedText.endIndex {
            let remainingText = String(processedText[lastEnd...])
            if !remainingText.isEmpty {
                result.append(.text(remainingText))
            }
        }
        
        return result
    }
    
    private func createAttributedString() -> AttributedString {
        guard configuration.enableRenderCaching else {
            return createAttributedStringUncached()
        }

        let key = MarkdownInlineAttributedCache.key(
            nodes: nodes,
            configuration: configuration,
            baseFont: baseFont,
            mode: .plain
        )
        if let cached = MarkdownInlineAttributedCache.value(for: key) {
            return cached
        }

        let rendered = createAttributedStringUncached()
        MarkdownInlineAttributedCache.insert(rendered, for: key)
        return rendered
    }

    private func createAttributedStringUncached() -> AttributedString {
        // First, collect all text content to handle split emoji shortcodes
        if configuration.enableEmojiShortcodes {
            let fullText = nodes.compactMap { node in
                if case .text(let string) = node {
                    return string
                } else {
                    return nil
                }
            }.joined()
            
            // Check if we have any emoji patterns that might be split
            let emojiPattern = #":([a-zA-Z0-9_+-]+):"#
            let regex = try? NSRegularExpression(pattern: emojiPattern)
            let hasEmojiPatterns = regex?.firstMatch(in: fullText, range: NSRange(fullText.startIndex..., in: fullText)) != nil
            
            if hasEmojiPatterns {
                // Process emojis on the full text first
                let processedFullText = fullText
                
                // If emoji processing changed the text, we need to rebuild with processed content
                if processedFullText != fullText {
                    return createAttributedStringWithProcessedEmojis(processedFullText)
                }
            }
        }
        
        // Fall back to normal processing if no emoji patterns found or processing didn't change anything
        var result = AttributedString()
        
        for node in nodes {
            result += renderInlineNode(node)
        }
        
        return result
    }
    
    private func createAttributedStringWithProcessedEmojis(_ processedText: String) -> AttributedString {
        // Check if the processed text contains image markdown for GitHub-exclusive emojis
        let imagePattern = #"!\[:([^:]+):\]\((https://[^)]+)\)"#
        let imageRegex = try? NSRegularExpression(pattern: imagePattern)
        
        if let imageRegex = imageRegex,
           imageRegex.firstMatch(in: processedText, range: NSRange(processedText.startIndex..., in: processedText)) != nil {
            
            // The processed text contains image markdown, this method shouldn't be called
            // Return simple text as fallback
            var result = AttributedString(processedText)
            result.font = baseFont
            return result
        } else {
            // Simple text with Unicode emojis, just apply basic formatting
            var result = AttributedString(processedText)
            result.font = baseFont
            return result
        }
    }
    
    @ViewBuilder
    private func renderInlineNodeAsView(_ node: MarkdownParser.InlineNode) -> some View {
        switch node {
        case .image(let url, let alt, let title):
            MarkdownImageView(
                url: url,
                alt: alt,
                title: title,
                configuration: configuration
            )
            
        default:
            Text(renderInlineNode(node))
        }
    }
    
    private func renderInlineNode(_ node: MarkdownParser.InlineNode, isBold: Bool = false, isItalic: Bool = false, isStrikethrough: Bool = false) -> AttributedString {
        switch node {
        case .text(let string):
            // Note: Emoji processing is now handled at the collection level in createAttributedString()
            // to properly handle split emoji shortcodes across text nodes
            var text = AttributedString(string)
            if isBold && isItalic {
                text.font = baseFont.bold().italic()
            } else if isBold {
                text.font = baseFont.bold()
            } else if isItalic {
                text.font = baseFont.italic()
            } else {
                text.font = baseFont
            }
            if isStrikethrough {
                text.strikethroughStyle = .single
            }
            return text
            
        case .emphasis(let children):
            var result = AttributedString()
            for child in children {
                result += renderInlineNode(child, isBold: isBold, isItalic: true, isStrikethrough: isStrikethrough)
            }
            return result
            
        case .strong(let children):
            var result = AttributedString()
            for child in children {
                result += renderInlineNode(child, isBold: true, isItalic: isItalic, isStrikethrough: isStrikethrough)
            }
            return result
            
        case .strikethrough(let children):
            var result = AttributedString()
            for child in children {
                result += renderInlineNode(child, isBold: isBold, isItalic: isItalic, isStrikethrough: true)
            }
            return result
            
        case .code(let code):
            var text = AttributedString(code)
            // Apply code font with bold/italic modifiers if needed
            if isBold && isItalic {
                text.font = configuration.codeFont.bold().italic()
            } else if isBold {
                text.font = configuration.codeFont.bold()
            } else if isItalic {
                text.font = configuration.codeFont.italic()
            } else {
                text.font = configuration.codeFont
            }
            if isStrikethrough {
                text.strikethroughStyle = .single
            }
            text.foregroundColor = .primary
            text.backgroundColor = configuration.codeBackgroundColor
            return text
            
        case .link(let url, _, let children):
            var result = AttributedString()
            for child in children {
                result += renderInlineNode(child, isBold: isBold, isItalic: isItalic, isStrikethrough: isStrikethrough)
            }
            result.link = url
            result.foregroundColor = configuration.linkColor
            if configuration.linkUnderline {
                result.underlineStyle = .single
            }
            return result
            
        case .image(let url, let alt, _):
            // For AttributedString rendering, show placeholder with alt text
            let displayText = alt.isEmpty ? url.absoluteString : alt
            var text = AttributedString("[Image: \(displayText)]")
            text.font = baseFont
            text.foregroundColor = .secondary
            return text
            
        case .autolink(let url, _, let originalText):
            // Show the original text exactly as it appeared
            var text = AttributedString(originalText)
            text.font = baseFont
            text.link = url
            text.foregroundColor = configuration.linkColor
            if configuration.linkUnderline {
                text.underlineStyle = .single
            }
            if isStrikethrough {
                text.strikethroughStyle = .single
            }
            return text
            
        case .mention(let username):
            var text = AttributedString("@\(username)")
            text.font = configuration.baseFont.bold()
            text.foregroundColor = .mint
            return text
            
        case .issueReference(let number):
            var text = AttributedString("#\(number)")
            text.font = configuration.baseFont.bold()
            text.foregroundColor = .orange
            return text
            
        case .commitSHA(_, let short):
            var text = AttributedString(short)
            text.font = .system(.body, design: .monospaced)
            text.foregroundColor = configuration.linkColor
            return text
            
        case .repositoryReference(let owner, let repo):
            var text = AttributedString("\(owner)/\(repo)")
            text.font = configuration.baseFont.bold()
            text.foregroundColor = configuration.linkColor
            return text
            
        case .pullRequestReference(let owner, let repo, let number):
            var text = AttributedString("\(owner)/\(repo)#\(number)")
            text.font = configuration.baseFont.bold()
            text.foregroundColor = configuration.linkColor
            return text
            
        case .lineBreak, .softBreak:
            return AttributedString("\n")
            
        case .html(let tag):
            // Handle <br> tags as line breaks
            if tag.lowercased() == "<br>" || tag.lowercased() == "<br/>" || tag.lowercased() == "<br />" {
                return AttributedString("\n")
            }
            // Other HTML tags are rendered as plain text for safety
            return AttributedString(tag)
            
        case .footnoteReference(let label):
            // Use [*] for inline footnotes, [label] for regular ones
            let displayLabel = label.starts(with: "inline-") ? "*" : label
            var attrs = AttributedString("[\(displayLabel)]")
            attrs.font = .system(.caption2)
            attrs.baselineOffset = 6 // Superscript effect
            attrs.foregroundColor = configuration.linkColor
            return attrs

        case .extensionInline(let node):
            // Render through the registered extension (mirrors MarkdownRenderer);
            // only fall back to the raw literal when no handler claims the node.
            if var rendered = configuration.markdownExtensions
                .first(where: { $0.id == node.namespace })?
                .renderInline(node) {
                if rendered.font == nil { rendered.font = baseFont }
                return rendered
            }
            var text = AttributedString(node.literal)
            text.font = baseFont
            text.foregroundColor = configuration.textColor
            return text
        }
    }
}

// MARK: - Interactive Content

/// Content view that renders interactive markdown blocks
struct InteractiveMarkdownContent: View {
    let blocks: [MarkdownParser.BlockNode]
    let configuration: MarkdownConfiguration
    let onLinkTap: (URL) -> Void
    let onMentionTap: ((String) -> Void)?
    let onIssueTap: ((Int) -> Void)?
    let onFootnoteTap: ((String) -> Void)?
    private let identifiedBlocks: [MarkdownBlockStableID.Pair]

    init(
        blocks: [MarkdownParser.BlockNode],
        configuration: MarkdownConfiguration,
        onLinkTap: @escaping (URL) -> Void,
        onMentionTap: ((String) -> Void)?,
        onIssueTap: ((Int) -> Void)?,
        onFootnoteTap: ((String) -> Void)?
    ) {
        self.blocks = blocks
        self.configuration = configuration
        self.onLinkTap = onLinkTap
        self.onMentionTap = onMentionTap
        self.onIssueTap = onIssueTap
        self.onFootnoteTap = onFootnoteTap
        self.identifiedBlocks = MarkdownBlockStableID.pairs(for: blocks)
    }
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(identifiedBlocks, id: \.id) { pair in
                InteractiveBlockView(
                    block: pair.block,
                    configuration: configuration,
                    onLinkTap: onLinkTap,
                    onMentionTap: onMentionTap,
                    onIssueTap: onIssueTap,
                    onFootnoteTap: onFootnoteTap,
                    depth: 0
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// View that renders individual interactive markdown blocks
struct InteractiveBlockView: View {
    let block: MarkdownParser.BlockNode
    let configuration: MarkdownConfiguration
    let onLinkTap: (URL) -> Void
    let onMentionTap: ((String) -> Void)?
    let onIssueTap: ((Int) -> Void)?
    let onFootnoteTap: ((String) -> Void)?
    let depth: Int
    
    init(
        block: MarkdownParser.BlockNode, 
        configuration: MarkdownConfiguration,
        onLinkTap: @escaping (URL) -> Void, 
        onMentionTap: ((String) -> Void)?,
        onIssueTap: ((Int) -> Void)?,
        onFootnoteTap: ((String) -> Void)?,
        depth: Int = 0
    ) {
        self.block = block
        self.configuration = configuration
        self.onLinkTap = onLinkTap
        self.onMentionTap = onMentionTap
        self.onIssueTap = onIssueTap
        self.onFootnoteTap = onFootnoteTap
        self.depth = depth
    }
    
    var body: some View {
        switch block {
        case .heading(let level, let children, _):
            let headingFont = level > 0 && level <= configuration.headingFonts.count ? configuration.headingFonts[level - 1] : .headline
            InteractiveInlineView(
                nodes: children,
                configuration: configuration,
                onLinkTap: onLinkTap,
                onMentionTap: onMentionTap,
                onIssueTap: onIssueTap,
                onFootnoteTap: onFootnoteTap,
                baseFont: headingFont
            )
            
        case .paragraph(let children):
            InteractiveInlineView(
                nodes: children,
                configuration: configuration,
                onLinkTap: onLinkTap,
                onMentionTap: onMentionTap,
                onIssueTap: onIssueTap,
                onFootnoteTap: onFootnoteTap
            )
            
        case .blockquote(let children):
            HStack(spacing: 12) {
                Rectangle()
                    .fill(configuration.blockquoteColor)
                    .frame(width: 4)
                
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        InteractiveBlockView(
                            block: child,
                            configuration: configuration,
                            onLinkTap: onLinkTap,
                            onMentionTap: onMentionTap,
                            onIssueTap: onIssueTap,
                            onFootnoteTap: onFootnoteTap,
                            depth: depth
                        )
                        .foregroundColor(configuration.blockquoteColor)
                    }
                }
            }
            .padding(.leading, 8)
            
        case .codeBlock(let language, let content):
            VStack(alignment: .leading, spacing: 8) {
                if let language = language, !language.isEmpty {
                    Text(language)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(SyntaxHighlighter(theme: configuration.codeBlockTheme).highlight(code: content, language: language))
                        .font(configuration.codeFont)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(configuration.codeBackgroundColor)
                        .cornerRadius(8)
                }
            }
            
        case .list(let ordered, _, let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        if item.isTask {
                            Image(systemName: item.isChecked == true ? "checkmark.square.fill" : "square")
                                .foregroundColor(item.isChecked == true ? .green : .secondary)
                                .font(.system(size: 16))
                        } else {
                            Text(ListFormatting.listMarker(ordered: ordered, index: index, depth: depth))
                                .font(ListFormatting.listMarkerFont(ordered: ordered, depth: depth, baseFont: configuration.baseFont))
                                .foregroundColor(.primary)
                                .frame(minWidth: 20, alignment: ordered ? .trailing : .center)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(item.content.enumerated()), id: \.offset) { _, contentBlock in
                                InteractiveBlockView(
                                    block: contentBlock,
                                    configuration: configuration,
                                    onLinkTap: onLinkTap,
                                    onMentionTap: onMentionTap,
                                    onIssueTap: onIssueTap,
                                    onFootnoteTap: onFootnoteTap,
                                    depth: depth + 1
                                )
                            }
                        }
                    }
                }
            }
            
        case .taskList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.isChecked ? "checkmark.square.fill" : "square")
                            .foregroundColor(item.isChecked ? .green : .secondary)
                            .font(.system(size: 16))
                        
                        InteractiveInlineView(
                            nodes: item.content,
                            configuration: configuration,
                            onLinkTap: onLinkTap,
                            onMentionTap: onMentionTap,
                            onIssueTap: onIssueTap,
                            onFootnoteTap: onFootnoteTap
                        )
                    }
                }
            }
            
        case .table(let header, let rows):
            InteractiveMarkdownTableView(
                header: header,
                rows: rows,
                configuration: configuration,
                onLinkTap: onLinkTap,
                onMentionTap: onMentionTap,
                onIssueTap: onIssueTap,
                onFootnoteTap: onFootnoteTap
            )
            
        case .horizontalRule:
            Divider()
                .padding(.vertical, 8)
            
        case .html(let content):
            Text(content)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
            
        case .footnoteDefinition(_, _):
            // Footnote definitions are collected and displayed separately
            EmptyView()
        }
    }
    
    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .largeTitle.bold()
        case 2: return .title.bold()
        case 3: return .title2.bold()
        case 4: return .title3.bold()
        case 5: return .headline
        case 6: return .subheadline.bold()
        default: return .headline
        }
    }
    
    private func calculateHeaderWidth(index: Int, headerCount: Int, columnWidths: [CGFloat]) -> CGFloat {
        guard index < columnWidths.count else { return 100 }
        return columnWidths[index]
    }
}

/// Interactive markdown table with wrapping cell widths.
struct InteractiveMarkdownTableView: View {
    let header: [MarkdownParser.TableCell]
    let rows: [[MarkdownParser.TableCell]]
    let configuration: MarkdownConfiguration
    let onLinkTap: (URL) -> Void
    let onMentionTap: ((String) -> Void)?
    let onIssueTap: ((Int) -> Void)?
    let onFootnoteTap: ((String) -> Void)?

    @State private var availableWidth: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let columnWidths = resolvedColumnWidths
        let maxColumns = max(header.count, rows.map { $0.count }.max() ?? 0)

        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(0..<header.count, id: \.self) { index in
                        InteractiveTableCell(
                            cell: header[index],
                            isHeader: true,
                            configuration: configuration,
                            width: cellWidth(index: index, cellCount: header.count, maxColumns: maxColumns, columnWidths: columnWidths),
                            onLinkTap: onLinkTap,
                            onMentionTap: onMentionTap,
                            onIssueTap: onIssueTap,
                            onFootnoteTap: onFootnoteTap,
                            isLastColumn: index == header.count - 1,
                            isLastRow: false
                        )
                        .gridCellColumns(index == header.count - 1 ? maxColumns - header.count + 1 : 1)
                    }
                }
                .background(Color.secondary.opacity(0.1))

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(0..<row.count, id: \.self) { cellIndex in
                            InteractiveTableCell(
                                cell: row[cellIndex],
                                isHeader: false,
                                configuration: configuration,
                                width: cellWidth(index: cellIndex, cellCount: row.count, maxColumns: maxColumns, columnWidths: columnWidths),
                                onLinkTap: onLinkTap,
                                onMentionTap: onMentionTap,
                                onIssueTap: onIssueTap,
                                onFootnoteTap: onFootnoteTap,
                                isLastColumn: cellIndex == row.count - 1,
                                isLastRow: rowIndex == rows.count - 1
                            )
                            .gridCellColumns(cellIndex == row.count - 1 ? maxColumns - row.count + 1 : 1)
                        }
                    }
                }
            }
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onGeometryChange(for: CGFloat.self) { proxy in
                ceil(proxy.size.height)
            } action: { newHeight in
                updateContentHeight(newHeight)
            }
        }
        .frame(height: contentHeight > 0 ? contentHeight : nil)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            if newWidth > 0 {
                availableWidth = newWidth
            }
        }
    }

    private var resolvedColumnWidths: [CGFloat] {
        let measuredWidths = TextMeasurement.calculateColumnWidths(
            header: header,
            rows: rows,
            baseFont: configuration.baseFont
        )
        return TextMeasurement.constrainColumnWidthsForWrapping(
            measuredWidths,
            availableWidth: availableWidth
        )
    }

    private func cellWidth(
        index: Int,
        cellCount: Int,
        maxColumns: Int,
        columnWidths: [CGFloat]
    ) -> CGFloat? {
        if index == cellCount - 1 && cellCount < maxColumns {
            return nil
        }
        return index < columnWidths.count ? columnWidths[index] : nil
    }

    private func updateContentHeight(_ newHeight: CGFloat) {
        guard newHeight.isFinite, newHeight > 0 else { return }
        if abs(contentHeight - newHeight) > 0.5 {
            contentHeight = newHeight
        }
    }
}

/// Table cell with interactive elements
struct InteractiveTableCell: View {
    let cell: MarkdownParser.TableCell
    let isHeader: Bool
    let configuration: MarkdownConfiguration
    let width: CGFloat?
    let onLinkTap: (URL) -> Void
    let onMentionTap: ((String) -> Void)?
    let onIssueTap: ((Int) -> Void)?
    let onFootnoteTap: ((String) -> Void)?
    let isLastColumn: Bool
    let isLastRow: Bool

    init(
        cell: MarkdownParser.TableCell,
        isHeader: Bool,
        configuration: MarkdownConfiguration,
        width: CGFloat? = nil,
        onLinkTap: @escaping (URL) -> Void,
        onMentionTap: ((String) -> Void)?,
        onIssueTap: ((Int) -> Void)?,
        onFootnoteTap: ((String) -> Void)?,
        isLastColumn: Bool = false,
        isLastRow: Bool = false
    ) {
        self.cell = cell
        self.isHeader = isHeader
        self.configuration = configuration
        self.width = width
        self.onLinkTap = onLinkTap
        self.onMentionTap = onMentionTap
        self.onIssueTap = onIssueTap
        self.onFootnoteTap = onFootnoteTap
        self.isLastColumn = isLastColumn
        self.isLastRow = isLastRow
    }
    
    var body: some View {
        // Split content by line breaks to handle multiline cells
        let lines = splitIntoLines(cell.content)
        
        // Use ZStack to ensure proper positioning and prevent clipping
        ZStack(alignment: alignment(for: cell.alignment)) {
            // Background for debugging (can be removed)
            Color.clear
            
            if lines.count > 1 {
                VStack(alignment: alignmentHorizontal(for: cell.alignment), spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, nodes in
                        InteractiveInlineView(
                            nodes: nodes,
                            configuration: configuration,
                            onLinkTap: onLinkTap,
                            onMentionTap: onMentionTap,
                            onIssueTap: onIssueTap,
                            onFootnoteTap: onFootnoteTap,
                            baseFont: isHeader ? configuration.baseFont.bold() : configuration.baseFont
                        )
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(textAlignment(for: cell.alignment))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            } else {
                InteractiveInlineView(
                    nodes: cell.content,
                    configuration: configuration,
                    onLinkTap: onLinkTap,
                    onMentionTap: onMentionTap,
                    onIssueTap: onIssueTap,
                    onFootnoteTap: onFootnoteTap,
                    baseFont: isHeader ? configuration.baseFont.bold() : configuration.baseFont
                )
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(textAlignment(for: cell.alignment))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
        .frame(width: width, alignment: alignment(for: cell.alignment))
        .clipped() // Ensure content doesn't overflow bounds
        .overlay(
            GeometryReader { geometry in
                Path { path in
                    let rect = geometry.frame(in: .local)
                    
                    // Right border (except for last column)
                    if !isLastColumn {
                        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                    }
                    
                    // Bottom border (except for last row)
                    if !isLastRow {
                        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                    }
                }
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
            }
        )
            }
    
    private func splitIntoLines(_ nodes: [MarkdownParser.InlineNode]) -> [[MarkdownParser.InlineNode]] {
        var lines: [[MarkdownParser.InlineNode]] = [[]]
        var currentLine: [MarkdownParser.InlineNode] = []
        
        for node in nodes {
            switch node {
            case .html(let tag):
                if tag.lowercased() == "<br>" || tag.lowercased() == "<br/>" || tag.lowercased() == "<br />" {
                    // Start a new line
                    if !currentLine.isEmpty {
                        lines.append(currentLine)
                        currentLine = []
                    }
                } else {
                    currentLine.append(node)
                }
            case .lineBreak, .softBreak:
                // Start a new line
                if !currentLine.isEmpty {
                    lines.append(currentLine)
                    currentLine = []
                }
            default:
                currentLine.append(node)
            }
        }
        
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        
        // Remove empty lines and ensure at least one line
        lines = lines.filter { !$0.isEmpty }
        if lines.isEmpty {
            lines = [[]]
        }
        
        return lines
    }
    
    private func alignmentHorizontal(for tableAlignment: MarkdownParser.TableAlignment) -> HorizontalAlignment {
        switch tableAlignment {
        case .left, .none:
            return .leading
        case .center:
            return .center
        case .right:
            return .trailing
        }
    }
    
    private func alignment(for tableAlignment: MarkdownParser.TableAlignment) -> Alignment {
        switch tableAlignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        case .none: return .leading
        }
    }
    
    private func textAlignment(for tableAlignment: MarkdownParser.TableAlignment) -> TextAlignment {
        switch tableAlignment {
        case .left, .none: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}

/// View that renders interactive inline markdown elements
struct InteractiveInlineView: View {
    let nodes: [MarkdownParser.InlineNode]
    let configuration: MarkdownConfiguration
    let onLinkTap: (URL) -> Void
    let onMentionTap: ((String) -> Void)?
    let onIssueTap: ((Int) -> Void)?
    let onFootnoteTap: ((String) -> Void)?
    let baseFont: Font?
    
    @Environment(\.openURL) private var openURL
    
    init(
        nodes: [MarkdownParser.InlineNode],
        configuration: MarkdownConfiguration,
        onLinkTap: @escaping (URL) -> Void,
        onMentionTap: ((String) -> Void)? = nil,
        onIssueTap: ((Int) -> Void)? = nil,
        onFootnoteTap: ((String) -> Void)? = nil,
        baseFont: Font? = nil
    ) {
        self.nodes = nodes
        self.configuration = configuration
        self.onLinkTap = onLinkTap
        self.onMentionTap = onMentionTap
        self.onIssueTap = onIssueTap
        self.onFootnoteTap = onFootnoteTap
        self.baseFont = baseFont
    }
    
    var body: some View {
        // Check if we have any images that need special rendering
        // (including images nested inside links/emphasis, e.g. a linked avatar).
        let hasImages = inlineNodesContainImage(nodes)

        if hasImages {
            // For content with images, we need to render them as actual views
            createInlineContent()
                .environment(\.openURL, OpenURLAction { url in
                    _ = handleURL(url)
                    return .handled
                })
        } else {
            // Use AttributedString for text-only content (more efficient)
            Text(createAttributedString())
                .environment(\.openURL, OpenURLAction { url in
                    _ = handleURL(url)
                    return .handled
                })
        }
    }
    
    @ViewBuilder
    private func createInlineContent() -> some View {
        // Use NSAttributedString with NSTextAttachment for true inline images on iOS
        AttributedTextView(
            nodes: nodes,
            configuration: configuration,
            baseFont: baseFont,
            onImageTap: { url, alt in
                onLinkTap(url)
            },
            // A tap on a linked attachment (e.g. a linked avatar) routes through the
            // same handler as text links, opening the link target (the profile).
            onLinkTap: { _ = handleURL($0) }
        )
    }
    
    @ViewBuilder
    private func renderInlineNodeAsView(_ node: MarkdownParser.InlineNode) -> some View {
        switch node {
        case .image(let url, let alt, let title):
            let isTinyImage = url.absoluteString.contains("/16/")
            let isSmallInlineImage = alt.contains("icon") || alt.contains("small") || 
                                   url.absoluteString.contains("/20/") ||
                                   url.absoluteString.contains("/16/")
            
            InteractiveMarkdownImageView(
                url: url,
                alt: alt,
                title: title,
                configuration: configuration,
                onImageTap: { imageUrl in
                    onLinkTap(imageUrl)
                }
            )
            .frame(maxHeight: isTinyImage ? 14 : (isSmallInlineImage ? 18 : 24)) // Match text line height
            
        default:
            // For all other inline nodes, use attributed string
            let attributedString = renderInlineNode(node, isBold: false, isItalic: false, isStrikethrough: false)
            Text(attributedString)
                .environment(\.openURL, OpenURLAction { url in
                    _ = handleURL(url)
                    return .handled
                })
        }
    }
    
    private func checkForProcessedEmojiImages() -> Bool {
        if !configuration.enableEmojiShortcodes { return false }
        
        let fullText = nodes.compactMap { node in
            if case .text(let string) = node {
                return string
            } else {
                return nil
            }
        }.joined()
        
        let emojiPattern = #":([a-zA-Z0-9_+-]+):"#
        let regex = try? NSRegularExpression(pattern: emojiPattern)
        let hasEmojiPatterns = regex?.firstMatch(in: fullText, range: NSRange(fullText.startIndex..., in: fullText)) != nil
        
        if hasEmojiPatterns {
            let processedFullText = fullText
            let imagePattern = #"![\:([^\:]+)\:]\((https://[^)]+)\)"#
            let imageRegex = try? NSRegularExpression(pattern: imagePattern)
            return imageRegex?.firstMatch(in: processedFullText, range: NSRange(processedFullText.startIndex..., in: processedFullText)) != nil
        }
        
        return false
    }
    
    private func getProcessedNodes() -> [MarkdownParser.InlineNode] {
        if !configuration.enableEmojiShortcodes { return nodes }
        
        let fullText = nodes.compactMap { node in
            if case .text(let string) = node {
                return string
            } else {
                return nil
            }
        }.joined()
        
        let emojiPattern = #":([a-zA-Z0-9_+-]+):"#
        let regex = try? NSRegularExpression(pattern: emojiPattern)
        let hasEmojiPatterns = regex?.firstMatch(in: fullText, range: NSRange(fullText.startIndex..., in: fullText)) != nil
        
        if hasEmojiPatterns {
            let processedFullText = fullText
            if processedFullText != fullText {
                // Parse the processed text to extract any image markdown
                return parseProcessedTextToNodes(processedFullText)
            }
        }
        
        return nodes
    }
    
    private func parseProcessedTextToNodes(_ processedText: String) -> [MarkdownParser.InlineNode] {
        // Parse image markdown patterns and convert to nodes
        let imagePattern = #"![\:([^\:]+)\:]\((https://[^)]+)\)"#
        let imageRegex = try? NSRegularExpression(pattern: imagePattern)
        
        guard let imageRegex = imageRegex else {
            return [.text(processedText)]
        }
        
        var result: [MarkdownParser.InlineNode] = []
        var lastEnd = processedText.startIndex
        let matches = imageRegex.matches(in: processedText, range: NSRange(processedText.startIndex..., in: processedText))
        
        for match in matches {
            if let range = Range(match.range, in: processedText),
               let altRange = Range(match.range(at: 1), in: processedText),
               let urlRange = Range(match.range(at: 2), in: processedText) {
                
                // Add text before image
                if lastEnd < range.lowerBound {
                    let textBefore = String(processedText[lastEnd..<range.lowerBound])
                    if !textBefore.isEmpty {
                        result.append(.text(textBefore))
                    }
                }
                
                // Add image node
                let alt = String(processedText[altRange])
                let urlString = String(processedText[urlRange])
                if let url = URL(string: urlString) {
                    result.append(.image(url: url, alt: alt, title: nil))
                }
                
                lastEnd = range.upperBound
            }
        }
        
        // Add remaining text
        if lastEnd < processedText.endIndex {
            let remainingText = String(processedText[lastEnd...])
            if !remainingText.isEmpty {
                result.append(.text(remainingText))
            }
        }
        
        return result
    }
    
    private func createAttributedString() -> AttributedString {
        guard configuration.enableRenderCaching else {
            return createAttributedStringUncached()
        }

        let key = MarkdownInlineAttributedCache.key(
            nodes: nodes,
            configuration: configuration,
            baseFont: baseFont,
            mode: .interactive
        )
        if let cached = MarkdownInlineAttributedCache.value(for: key) {
            return cached
        }

        let rendered = createAttributedStringUncached()
        MarkdownInlineAttributedCache.insert(rendered, for: key)
        return rendered
    }

    private func createAttributedStringUncached() -> AttributedString {
        var result = AttributedString()
        
        for node in nodes {
            result += renderInlineNode(node)
        }
        
        return result
    }
    
    private func createAttributedStringWithProcessedEmojis(_ processedText: String) -> AttributedString {
        // Check if the processed text contains image markdown for GitHub-exclusive emojis
        let imagePattern = #"![\:([^\:]+)\:]\((https://[^)]+)\)"#
        let imageRegex = try? NSRegularExpression(pattern: imagePattern)
        
        if let imageRegex = imageRegex,
           imageRegex.firstMatch(in: processedText, range: NSRange(processedText.startIndex..., in: processedText)) != nil {
            
            // The processed text contains image markdown, this method shouldn't be called
            // Return simple text as fallback
            var result = AttributedString(processedText)  
            result.font = baseFont ?? configuration.baseFont
            return result
        } else {
            // Simple text with Unicode emojis, just apply basic formatting
            var result = AttributedString(processedText)
            result.font = baseFont ?? configuration.baseFont
            return result
        }
    }
    
    private func renderInlineNode(_ node: MarkdownParser.InlineNode, isBold: Bool = false, isItalic: Bool = false, isStrikethrough: Bool = false) -> AttributedString {
        switch node {
        case .text(let string):
            // Note: Emoji processing is now handled at the collection level in createAttributedString()
            // to properly handle split emoji shortcodes across text nodes
            var text = AttributedString(string)
            applyStyles(&text, isBold: isBold, isItalic: isItalic, isStrikethrough: isStrikethrough)
            return text
            
        case .emphasis(let children):
            var result = AttributedString()
            for child in children {
                result += renderInlineNode(child, isBold: isBold, isItalic: true, isStrikethrough: isStrikethrough)
            }
            return result
            
        case .strong(let children):
            var result = AttributedString()
            for child in children {
                result += renderInlineNode(child, isBold: true, isItalic: isItalic, isStrikethrough: isStrikethrough)
            }
            return result
            
        case .strikethrough(let children):
            var result = AttributedString()
            for child in children {
                result += renderInlineNode(child, isBold: isBold, isItalic: isItalic, isStrikethrough: true)
            }
            return result
            
        case .code(let code):
            var text = AttributedString(code)
            // Apply code font with bold/italic modifiers if needed
            if isBold && isItalic {
                text.font = configuration.codeFont.bold().italic()
            } else if isBold {
                text.font = configuration.codeFont.bold()
            } else if isItalic {
                text.font = configuration.codeFont.italic()
            } else {
                text.font = configuration.codeFont
            }
            if isStrikethrough {
                text.strikethroughStyle = .single
            }
            text.foregroundColor = .primary
            text.backgroundColor = configuration.codeBackgroundColor
            return text
            
        case .link(let url, _, let children):
            var result = AttributedString()
            for child in children {
                result += renderInlineNode(child, isBold: isBold, isItalic: isItalic, isStrikethrough: isStrikethrough)
            }
            result.link = url
            result.foregroundColor = configuration.linkColor
            if configuration.linkUnderline {
                result.underlineStyle = .single
            }
            return result
            
        case .image(_, let alt, _):
            // This shouldn't be reached when using createInlineContentWithImages
            // But provide a fallback
            let displayText = alt.isEmpty ? "[Image]" : "[\(alt)]"
            var text = AttributedString(displayText)
            text.font = baseFont ?? configuration.baseFont
            text.foregroundColor = .secondary
            return text
            
        case .autolink(let url, _, let originalText):
            // Show the original text exactly as it appeared
            var text = AttributedString(originalText)
            text.link = url
            text.foregroundColor = configuration.linkColor
            if configuration.linkUnderline {
                text.underlineStyle = .single
            }
            applyStyles(&text, isBold: isBold, isItalic: isItalic, isStrikethrough: isStrikethrough)
            return text
            
        case .mention(let username):
            var text = AttributedString("@\(username)")
            text.link = URL(string: "mention://\(username)")
            text.font = (baseFont ?? configuration.baseFont).bold()
            text.foregroundColor = configuration.mentionColor
            return text
            
        case .issueReference(let number):
            var text = AttributedString("#\(number)")
            text.link = URL(string: "issue://\(number)")
            text.font = (baseFont ?? configuration.baseFont).bold()
            text.foregroundColor = configuration.issueColor
            return text
            
        case .commitSHA(let sha, let short):
            var text = AttributedString(short)
            text.link = URL(string: "commit://\(sha)")
            text.font = .system(.body, design: .monospaced)
            text.foregroundColor = configuration.linkColor
            return text
            
        case .repositoryReference(let owner, let repo):
            var text = AttributedString("\(owner)/\(repo)")
            text.link = URL(string: "https://github.com/\(owner)/\(repo)")
            text.font = (baseFont ?? configuration.baseFont).bold()
            text.foregroundColor = configuration.linkColor
            return text
            
        case .pullRequestReference(let owner, let repo, let number):
            var text = AttributedString("\(owner)/\(repo)#\(number)")
            text.link = URL(string: "https://github.com/\(owner)/\(repo)/pull/\(number)")
            text.font = (baseFont ?? configuration.baseFont).bold()
            text.foregroundColor = configuration.linkColor
            return text
            
        case .lineBreak, .softBreak:
            return AttributedString("\n")
            
        case .html(let tag):
            // Handle <br> tags as line breaks
            if tag.lowercased() == "<br>" || tag.lowercased() == "<br/>" || tag.lowercased() == "<br />" {
                return AttributedString("\n")
            }
            // Other HTML tags are rendered as plain text for safety
            return AttributedString(tag)
            
        case .footnoteReference(let label):
            // Use [*] for inline footnotes, [label] for regular ones
            let displayLabel = label.starts(with: "inline-") ? "*" : label
            var attrs = AttributedString("[\(displayLabel)]")
            attrs.font = .system(.caption2)
            attrs.baselineOffset = 6 // Superscript effect
            attrs.foregroundColor = configuration.linkColor
            attrs.link = URL(string: "footnote://\(label)")
            return attrs

        case .extensionInline(let node):
            // Render through the registered extension (mirrors MarkdownRenderer),
            // keeping its own color + .link; only fall back to the raw literal when
            // no handler claims the node.
            if var rendered = configuration.markdownExtensions
                .first(where: { $0.id == node.namespace })?
                .renderInline(node) {
                applyStyles(&rendered, isBold: isBold, isItalic: isItalic, isStrikethrough: isStrikethrough)
                return rendered
            }
            var text = AttributedString(node.literal)
            applyStyles(&text, isBold: isBold, isItalic: isItalic, isStrikethrough: isStrikethrough)
            text.foregroundColor = configuration.textColor
            return text
        }
    }
    
    private func applyStyles(_ text: inout AttributedString, isBold: Bool, isItalic: Bool, isStrikethrough: Bool) {
        let font = baseFont ?? configuration.baseFont
        
        if isBold && isItalic {
            text.font = font.bold().italic()
        } else if isBold {
            text.font = font.bold()
        } else if isItalic {
            text.font = font.italic()
        } else {
            text.font = font
        }
        
        if isStrikethrough {
            text.strikethroughStyle = .single
        }
    }
    
    @ViewBuilder
    private func renderInteractiveInlineNodeView(_ node: MarkdownParser.InlineNode) -> some View {
        switch node {
        case .image(let url, let alt, let title):
            InteractiveMarkdownImageView(
                url: url,
                alt: alt,
                title: title,
                configuration: configuration,
                onImageTap: { imageUrl in
                    onLinkTap(imageUrl)
                }
            )
            
        default:
            Text(renderInlineNode(node))
                .environment(\.openURL, OpenURLAction { url in
                    _ = handleURL(url)
                    return .handled
                })
        }
    }
    
    private func handleURL(_ url: URL) -> OpenURLAction.Result {
        switch url.scheme {
        case "mention":
            if let username = url.host {
                onMentionTap?(username)
            }
        case "issue":
            if let numberStr = url.host, let number = Int(numberStr) {
                onIssueTap?(number)
            }
        case "footnote":
            if let label = url.host {
                onFootnoteTap?(label)
            }
        default:
            onLinkTap(url)
        }
        return .handled
    }
}

// MARK: - Convenience Initializers

public extension MarkdownView {
    /// Creates a markdown view for displaying code blocks
    static func codeBlock(_ code: String, language: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let language = language {
                Text(language)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }
    
    /// Creates a markdown view for inline markdown
    static func inline(_ markdown: String) -> some View {
        Text(MarkdownParser.parseToAttributedString(markdown))
            .textSelection(.enabled)
    }
}

// MARK: - View Modifier for Sheet Presentation

public extension View {
    func markdownSheet(
        isPresented: Binding<Bool>,
        title: String? = nil,
        markdown: String,
        onLinkTap: ((URL) -> Void)? = nil
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            NavigationStack {
                MarkdownView(
                    markdown: markdown,
                    onLinkTap: onLinkTap
                )
                .navigationTitle(title ?? "")
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button("Done") {
                            isPresented.wrappedValue = false
                        }
                    }
                }
            }
        }
    }
    
    func releaseNotesSheet(
        isPresented: Binding<Bool>,
        releaseNotes: String,
        version: String? = nil
    ) -> some View {
        self.markdownSheet(
            isPresented: isPresented,
            title: version.map { "Release Notes - \($0)" } ?? "Release Notes",
            markdown: releaseNotes
        )
    }
}

// MARK: - Image Views

/// Helper function to detect if an image is a GitHub emoji
private func isGitHubEmoji(url: URL, alt: String) -> Bool {
    // Check if alt text matches emoji shortcode pattern (:emoji_name:)
    let isEmojiAlt = alt.hasPrefix(":") && alt.hasSuffix(":")
    
    // Check if URL is from GitHub's emoji assets
    let isGitHubEmojiURL = url.host?.contains("github") == true && 
                          url.path.contains("emoji")
    
    return isEmojiAlt && isGitHubEmojiURL
}

/// Non-interactive markdown image view
struct MarkdownImageView: View {
    let url: URL
    let alt: String
    let title: String?
    let configuration: MarkdownConfiguration
    
    @State private var isAnimating = false
    
    var body: some View {
        let isEmoji = isGitHubEmoji(url: url, alt: alt)
        
        let imageContent = AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                let isSmallInlineImage = !isEmoji && (alt.contains("icon") || alt.contains("small") || 
                                                     (configuration.imageMaxWidth == nil && configuration.imageMaxHeight == nil && 
                                                      url.absoluteString.contains("/20/")))
                image
                    .resizable()
                    .aspectRatio(contentMode: configuration.imageContentMode)
                    .frame(
                        maxWidth: isEmoji ? 20 : (isSmallInlineImage ? 20 : configuration.imageMaxWidth),
                        maxHeight: isEmoji ? 20 : (isSmallInlineImage ? 20 : configuration.imageMaxHeight)
                    )
                    .cornerRadius(isEmoji || isSmallInlineImage ? 0 : 8)
                    .shadow(color: isEmoji || isSmallInlineImage ? .clear : Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            case .failure(_):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text("Failed to load image")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            case .empty:
                if isEmoji {
                    Text(alt)
                        .font(configuration.baseFont)
                        .foregroundColor(.secondary)
                } else {
                    ZStack {
                        Color.secondary.opacity(0.1)
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    .frame(
                        width: min(configuration.imageMaxWidth ?? 200, 200),
                        height: min(configuration.imageMaxHeight ?? 150, 150)
                    )
                    .cornerRadius(8)
                }
            @unknown default:
                EmptyView()
            }
        }
        .accessibilityLabel(alt.isEmpty ? "Image" : alt)
        .accessibilityHint(title ?? "")
        
        if let onImageTap = configuration.onImageTap {
            Button {
                onImageTap(url, alt)
            } label: {
                imageContent
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            imageContent
        }
    }
}

/// Interactive markdown image view
struct InteractiveMarkdownImageView: View {
    let url: URL
    let alt: String
    let title: String?
    let configuration: MarkdownConfiguration
    let onImageTap: (URL) -> Void
    
    @State private var isAnimating = false
    
    var body: some View {
        let isEmoji = isGitHubEmoji(url: url, alt: alt)
        
        Button {
            onImageTap(url)
        } label: {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    let isSmallInlineImage = !isEmoji && (alt.contains("icon") || alt.contains("small") || 
                                                         (configuration.imageMaxWidth == nil && configuration.imageMaxHeight == nil && 
                                                          url.absoluteString.contains("/20/")))
                    image
                        .resizable()
                        .aspectRatio(contentMode: configuration.imageContentMode)
                        .frame(
                            maxWidth: isEmoji ? 20 : (isSmallInlineImage ? 20 : configuration.imageMaxWidth),
                            maxHeight: isEmoji ? 20 : (isSmallInlineImage ? 20 : configuration.imageMaxHeight)
                        )
                        .cornerRadius(isEmoji || isSmallInlineImage ? 0 : 8)
                        .shadow(color: isEmoji || isSmallInlineImage ? .clear : Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                case .failure(_):
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundColor(.orange)
                        Text("Failed to load image")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                case .empty:
                    if isEmoji {
                        Text(alt)
                            .font(configuration.baseFont)
                            .foregroundColor(.secondary)
                    } else {
                        ZStack {
                            Color.secondary.opacity(0.1)
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        .frame(
                            width: min(configuration.imageMaxWidth ?? 200, 200),
                            height: min(configuration.imageMaxHeight ?? 150, 150)
                        )
                        .cornerRadius(8)
                    }
                @unknown default:
                    EmptyView()
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(alt.isEmpty ? "Image" : alt)
        .accessibilityHint(isEmoji ? title ?? alt : (title ?? "Tap to view full size"))
    }
}

#Preview {
    MarkdownView(markdown: """
# GitHub Flavored Markdown Demo

This is a **comprehensive** example of _GitHub Flavored Markdown_ rendering in SwiftUI.

## Images
![Swift logo](https://swift.org/assets/images/swift.svg "Swift Programming Language")

## GitHub Emojis
Regular emoji: 😀
GitHub emoji: :accessibility: (if available)
Inline text with emoji :+1: and more text

## Task Lists
- [x] Completed task
- [ ] Pending task
- [x] Another completed task

## Links and Mentions
- Visit [GitHub](https://github.com)
- Thanks @apple!
- Fixes #12345
""")
}
