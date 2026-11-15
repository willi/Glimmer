import UIKit
import XCTest
@testable import Glimmer

/// The same answer for every image.
private struct Answer: GlimmerImagePolicy {
    var answer: GlimmerImageDecision
    func decision(for image: GlimmerImageCandidate) -> GlimmerImageDecision { answer }
}

/// Loads images from the given hosts and shows the alt text of the rest.
private struct AllowHosts: GlimmerImagePolicy {
    var hosts: Set<String>
    func decision(for image: GlimmerImageCandidate) -> GlimmerImageDecision {
        hosts.contains(image.url.host() ?? "") ? .load : .showAltText
    }
}

/// Remembers what it was asked and can change its answer, which a real policy must never do.
private final class PolicyState: @unchecked Sendable {
    private let lock = NSLock()
    private var current: GlimmerImageDecision
    private var asked: [GlimmerImageCandidate] = []

    init(answer: GlimmerImageDecision) { current = answer }

    var answer: GlimmerImageDecision {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    var seen: [GlimmerImageCandidate] { lock.withLock { asked } }

    func record(_ image: GlimmerImageCandidate) -> GlimmerImageDecision {
        lock.withLock {
            asked.append(image)
            return current
        }
    }
}

private struct Scripted: GlimmerImagePolicy {
    let state: PolicyState
    static func == (lhs: Scripted, rhs: Scripted) -> Bool { lhs.state === rhs.state }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(state)) }
    func decision(for image: GlimmerImageCandidate) -> GlimmerImageDecision { state.record(image) }
}

/// Stands in for the network: any image a view asks for is recorded here.
private final class RecordingLoader: GlimmerImageLoader, @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    var requested: [URL] { lock.withLock { urls } }
    func loadImage(from url: URL) async throws -> UIImage {
        lock.withLock { urls.append(url) }
        return UIImage()
    }
}

/// Asks each request a view makes whether its policy would follow a redirect to either of two URLs.
private final class RedirectProbeLoader: GlimmerImageLoader, @unchecked Sendable {
    struct Probe: Equatable {
        let image: String
        let followsAllowed: Bool
        let followsRefused: Bool
    }

    private let lock = NSLock()
    private var recorded: [Probe] = []
    private let allowed: URL
    private let refused: URL

    init(allowed: URL, refused: URL) {
        self.allowed = allowed
        self.refused = refused
    }

    var probes: [Probe] { lock.withLock { recorded } }

    func loadImage(from url: URL) async throws -> UIImage { throw URLError(.unsupportedURL) }

    func loadImage(for request: GlimmerImageRequest) async throws -> UIImage {
        let probe = Probe(image: request.url.lastPathComponent, followsAllowed: request.permitsRedirect(to: allowed),
                          followsRefused: request.permitsRedirect(to: refused))
        lock.withLock { recorded.append(probe) }
        return UIImage()
    }
}

/// The host's image policy: a blocked image is ordinary text or nothing, and is never requested.
@MainActor
final class GlimmerImagePolicyTests: XCTestCase {
    private let u = "https://a.example/i.png"
    private let hide = Answer(answer: .hide)
    private let alt = Answer(answer: .showAltText)

    private let everyKind = """
    Inline ![one](https://a.example/1.png) and [![two](https://a.example/2.png)](https://a.example/page).

    - item ![three](https://a.example/3.png)

    > quote ![four](https://a.example/4.png)

    | Head |
    |---|
    | ![five](https://a.example/5.png) |

    Reference ![six][ref] and :octocat:

    ![seven](https://a.example/7.png)

    [ref]: https://a.example/6.png
    """
    private let everyLabel = ["one", "two", "three", "four", "five", "six", "seven", ":octocat:"]

    override func setUp() async throws {
        GlimmerDocumentCache.shared.removeAll()
    }

    private func compose(
        _ markdown: String, policy: (any GlimmerImagePolicy)?, extensions: [any GlimmerExtension] = []
    ) -> NSAttributedString {
        GlimmerComposer(theme: .default, imagePolicy: policy, extensions: extensions).compose(GlimmerParser.parse(markdown))
    }

    /// A window tall enough that everything is in the rendered band.
    private func hosted(
        policy: (any GlimmerImagePolicy)?, loader: (any GlimmerImageLoader)?, extensions: [any GlimmerExtension] = []
    ) -> (GlimmerView, UIWindow) {
        let view = GlimmerView(configuration: GlimmerConfiguration(
            extensions: extensions, imageLoader: loader, imagePolicy: policy, reveal: .none
        ))
        return (view, hostInWindow(view, width: 390, height: 3000))
    }

    private func shown(
        _ markdown: String, policy: (any GlimmerImagePolicy)?, loader: (any GlimmerImageLoader)?,
        extensions: [any GlimmerExtension] = []
    ) -> (GlimmerView, UIWindow) {
        let (view, window) = hosted(policy: policy, loader: loader, extensions: extensions)
        view.update(markdown: markdown)
        settle(view)
        return (view, window)
    }

    /// Inline image attachments and standalone image attachments, including those inside table cells.
    private func imageAttachments(in text: NSAttributedString) -> [NSTextAttachment] {
        var found: [NSTextAttachment] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let inline = value as? GlimmerInlineImageAttachment { found.append(inline) }
            guard let block = value as? GlimmerBlockAttachment else { return }
            switch block.embed {
            case .image:
                found.append(block)
            case .table(let header, let rows, _):
                for cell in header + rows.flatMap({ $0 }) { found += imageAttachments(in: cell) }
            default:
                break
            }
        }
        return found
    }

    private func attributes(of substring: String, in text: NSAttributedString) -> [NSAttributedString.Key: Any] {
        let range = (text.string as NSString).range(of: substring)
        guard range.location != NSNotFound else {
            XCTFail("missing \(substring.debugDescription) in \(text.string.debugDescription)")
            return [:]
        }
        return text.attributes(at: range.location, effectiveRange: nil)
    }

    private func markdown(of text: NSAttributedString) -> String {
        GlimmerMarkdownSerializer.markdown(from: text, range: NSRange(location: 0, length: text.length))
    }

    // MARK: - No request

    func testABlockingPolicyLoadsNothingForAnyKindOfImage() {
        let loader = RecordingLoader()
        let (view, window) = shown(everyKind, policy: alt, loader: loader, extensions: [GlimmerEmojiShortcodes()])
        XCTAssertEqual(loader.requested, [])
        XCTAssertEqual(imageAttachments(in: view.textView.textStorage).count, 0)
        let plain = view.plainText()
        for label in everyLabel { XCTAssertTrue(plain.contains(label), "\(label) shows as text in \(plain.debugDescription)") }
        _ = window
    }

    func testABlockingPolicyLoadsNothingWhileStreaming() async {
        let loader = RecordingLoader()
        let (view, window) = hosted(policy: alt, loader: loader, extensions: [GlimmerEmojiShortcodes()])
        for end in stride(from: 40, to: everyKind.count, by: 40) {
            view.update(markdown: String(everyKind.prefix(end)), isStreaming: true)
            settle(view)
        }
        view.update(markdown: everyKind, isStreaming: false)
        let finished = await waitUntil { view.plainText().contains("seven") }
        XCTAssertTrue(finished)
        settle(view)
        XCTAssertEqual(loader.requested, [])
        XCTAssertEqual(imageAttachments(in: view.textView.textStorage).count, 0)
        let plain = view.plainText()
        for label in everyLabel { XCTAssertTrue(plain.contains(label), "\(label) shows as text in \(plain.debugDescription)") }
        _ = window
    }

    func testOnlyAllowedURLsAreRequested() async throws {
        let loader = RecordingLoader()
        let (view, window) = shown(
            "Inline ![a](https://ok.example/a.png) and ![b](https://bad.example/b.png).\n\n"
                + "![c](https://ok.example/c.png)\n\n![d](https://bad.example/d.png)",
            policy: AllowHosts(hosts: ["ok.example"]), loader: loader
        )
        let loaded = await waitUntil { loader.requested.count >= 2 }
        XCTAssertTrue(loaded)
        settle(view)
        XCTAssertEqual(loader.requested.count, 2)
        XCTAssertEqual(Set(loader.requested), [
            try XCTUnwrap(URL(string: "https://ok.example/a.png")), try XCTUnwrap(URL(string: "https://ok.example/c.png")),
        ])
        _ = window
    }

    func testWithNoPolicyImagesStillLoad() async throws {
        let loader = RecordingLoader()
        let (_, window) = shown(
            "Inline ![a](https://a.example/a.png).\n\n![b](https://a.example/b.png)", policy: nil, loader: loader
        )
        let loaded = await waitUntil { loader.requested.count >= 2 }
        XCTAssertTrue(loaded)
        XCTAssertEqual(Set(loader.requested), [
            try XCTUnwrap(URL(string: "https://a.example/a.png")), try XCTUnwrap(URL(string: "https://a.example/b.png")),
        ])
        _ = window
    }

    func testSettingAPolicyOnALiveViewRemovesItsImages() async {
        let loader = RecordingLoader()
        let (view, window) = shown(
            "Inline ![a](https://a.example/a.png).\n\n![b](https://a.example/b.png)", policy: nil, loader: loader
        )
        let loaded = await waitUntil { loader.requested.count >= 2 }
        XCTAssertTrue(loaded)
        view.configuration.imagePolicy = alt
        settle(view)
        XCTAssertEqual(imageAttachments(in: view.textView.textStorage).count, 0)
        XCTAssertEqual(view.plainText(), "Inline a.\nb")
        XCTAssertEqual(loader.requested.count, 2, "nothing is requested again")
        _ = window
    }

    // MARK: - Asked again before the load

    func testARefusingGateNeverCallsTheLoader() async throws {
        let loader = RecordingLoader()
        let url = try XCTUnwrap(URL(string: u))
        let gate = GlimmerImageGate(policy: hide, candidate: GlimmerImageCandidate(url: url, alt: "", origin: .markdown))
        let viewLoader = GlimmerImageViewLoader(source: url, loader: loader, contentMode: .aspectFit, gate: gate)
        var result: Result<UIImage, Error>?
        viewLoader.load(size: CGSize(width: 10, height: 10), scale: 2) { result = $0 }
        let finished = await waitUntil { result != nil }
        XCTAssertTrue(finished)
        XCTAssertThrowsError(try result?.get())
        XCTAssertEqual(loader.requested, [])
    }

    /// Both image views pass their policy on: an answer that changes after composing still stops the load.
    func testThePolicyIsAskedAgainBeforeTheLoad() {
        let state = PolicyState(answer: .load)
        let loader = RecordingLoader()
        let view = GlimmerView(configuration: GlimmerConfiguration(
            imageLoader: loader, imagePolicy: Scripted(state: state), reveal: .none
        ))
        view.update(markdown: "Inline ![a](https://a.example/a.png).\n\n![b](https://a.example/b.png)")
        // Composed, but not in a window: no attachment view exists yet.
        state.answer = .hide
        let window = hostInWindow(view, width: 390, height: 800)
        settle(view)
        XCTAssertEqual(imageAttachments(in: view.textView.textStorage).count, 2)
        XCTAssertEqual(loader.requested, [])
        _ = window
    }

    /// The load-time check does not rest on the composer: an image view that reached a policed host any other way
    /// has nothing to show the policy allowed it, and is refused even when the policy would say yes.
    func testAnImageThatSkippedTheComposerIsNotLoadedUnderAPolicy() throws {
        let loader = RecordingLoader()
        let url = try XCTUnwrap(URL(string: u))
        let host = GlimmerView(configuration: GlimmerConfiguration(
            imageLoader: nil, imagePolicy: Answer(answer: .load), reveal: .none
        ))
        let window = hostInWindow(host, width: 390, height: 400)
        let inline = GlimmerInlineImageView(source: url, alt: "", theme: .default, loader: loader)
        inline.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        host.addSubview(inline)
        let embed = GlimmerImageEmbedView(source: url, alt: "", theme: .default, loader: loader)
        embed.frame = CGRect(x: 0, y: 40, width: 200, height: 100)
        host.addSubview(embed)
        settle(host)
        XCTAssertEqual(loader.requested, [])
        _ = window
    }

    /// The redirect check reaches production requests: both image views hand their policy to the loader.
    func testRequestsFromViewsCarryThePolicyForRedirects() async throws {
        let loader = RedirectProbeLoader(
            allowed: try XCTUnwrap(URL(string: "https://ok.example/elsewhere.png")),
            refused: try XCTUnwrap(URL(string: "https://bad.example/?d=secret"))
        )
        let (_, window) = shown(
            "Inline ![a](https://ok.example/a.png).\n\n![b](https://ok.example/b.png)",
            policy: AllowHosts(hosts: ["ok.example"]), loader: loader
        )
        let loaded = await waitUntil { loader.probes.count >= 2 }
        XCTAssertTrue(loaded)
        XCTAssertEqual(Set(loader.probes.map(\.image)), ["a.png", "b.png"])
        XCTAssertTrue(loader.probes.allSatisfy { $0.followsAllowed && !$0.followsRefused }, "\(loader.probes)")
        _ = window
    }

    // MARK: - What the policy sees

    func testThePolicySeesEveryImageWithItsURLAltTitleAndOrigin() throws {
        let state = PolicyState(answer: .load)
        _ = compose("![Alt](\(u) \"Title\") ![Dog](dog) :octocat:", policy: Scripted(state: state),
                    extensions: [GlimmerEmojiShortcodes()])
        let written = GlimmerImageCandidate(url: try XCTUnwrap(URL(string: u)), alt: "Alt", title: "Title", origin: .markdown)
        XCTAssertTrue(state.seen.contains(written), "\(state.seen)")
        XCTAssertTrue(state.seen.contains { $0.url.absoluteString == "dog" && $0.alt == "Dog" }, "a URL with no scheme is asked about too")
        XCTAssertTrue(state.seen.contains { $0.alt == ":octocat:" && $0.origin == .extensionToken(kind: "emoji") }, "\(state.seen)")
    }

    // MARK: - What a blocked image shows

    func testAltTextRendersAsTheTextAroundIt() throws {
        let text = compose("**See ![the chart](\(u)) now** and [![docs](\(u))](https://a.example/page)", policy: alt)
        XCTAssertEqual(text.string, "See the chart now and docs")
        XCTAssertEqual(imageAttachments(in: text).count, 0)
        let shown = attributes(of: "the chart", in: text)
        let around = attributes(of: "See", in: text)
        XCTAssertEqual(shown[.font] as? UIFont, around[.font] as? UIFont)
        XCTAssertEqual(shown[.foregroundColor] as? UIColor, around[.foregroundColor] as? UIColor)
        XCTAssertNil(shown[.glimmerSource])
        XCTAssertEqual(attributes(of: "docs", in: text)[.link] as? URL, try XCTUnwrap(URL(string: "https://a.example/page")))
    }

    func testEmptyAltTextRendersNothing() {
        let text = compose("A ![](\(u)) b", policy: alt)
        XCTAssertEqual(text.string, "A  b")
        XCTAssertEqual(imageAttachments(in: text).count, 0)
    }

    func testHiddenImagesLeaveNoBlankLine() {
        assertEquivalent(
            compose("Before\n\n![a](\(u)) ![b](\(u))\n\nAfter", policy: hide), compose("Before\n\nAfter", policy: hide),
            "a paragraph of hidden images"
        )
    }

    func testALeadingBlockedImageLeavesNoGapAboveAHeading() {
        let heading = compose("# Title", policy: hide)
        assertEquivalent(compose("![x](\(u))\n\n# Title", policy: hide), heading, "composed whole")
        let document = GlimmerStreamingDocument(composer: GlimmerComposer(theme: .default, imagePolicy: hide))
        _ = document.update(markdown: "![x](\(u))\n\n# Title", isStreaming: false)
        assertEquivalent(document.text, heading, "composed block by block")
    }

    func testABlockedStandaloneImageIsAnOrdinaryParagraph() {
        assertEquivalent(compose("![Chart](\(u))", policy: alt), compose("Chart", policy: alt), "a standalone image's alt text")
    }

    func testABlockedListItemKeepsItsMarker() {
        XCTAssertEqual(compose("- ![](\(u))\n- two", policy: hide).string, compose("-\n- two", policy: hide).string)
    }

    func testAHiddenImageLeavesAnEmptyTableCell() throws {
        let text = compose("| a | b |\n|---|---|\n| ![](\(u)) | x |", policy: hide)
        let attachment = try XCTUnwrap(blockAttachments(in: text).first)
        guard case .table(_, let rows, _) = attachment.embed else { return XCTFail("expected a table") }
        XCTAssertEqual(rows.first?.count, 2)
        XCTAssertEqual(rows.first?.first?.length, 0)
    }

    func testABlockedEmojiImageShowsItsShortcode() {
        let text = compose("Hi :octocat:!", policy: alt, extensions: [GlimmerEmojiShortcodes()])
        XCTAssertEqual(text.string, "Hi :octocat:!")
        XCTAssertEqual(imageAttachments(in: text).count, 0)
        XCTAssertEqual(markdown(of: text), "Hi :octocat:!")
    }

    func testAnUnparseableURLUnderAPolicyShowsItsAltText() {
        let text = compose("See ![the chart]() now", policy: Answer(answer: .load))
        XCTAssertEqual(text.string, "See the chart now")
        XCTAssertEqual(attributes(of: "the chart", in: text)[.foregroundColor] as? UIColor,
                       attributes(of: "See", in: text)[.foregroundColor] as? UIColor)
    }

    func testABlockedImageCopiesAsWhatIsShown() {
        let text = compose("See ![the chart](\(u)).", policy: alt)
        XCTAssertEqual(markdown(of: text), "See the chart.")
        assertEquivalent(compose(markdown(of: text), policy: alt), text, "copied and composed again")
    }

    func testCopyAnswerNeverHandsOutARefusedURL() {
        let (view, window) = shown("See ![the chart](https://attacker.example/?d=secret).", policy: alt, loader: nil)
        XCTAssertEqual(view.markdownSource(), "See the chart.")
        _ = window
    }

    // MARK: - Settled answers shared between views

    /// Feed cells show settled text from the cache: its images must still carry the policy that allowed them.
    func testSettledTextFromTheCacheKeepsThePolicyOnItsImages() throws {
        let policy = AllowHosts(hosts: ["ok.example"])
        let text = compose("Inline ![a](https://ok.example/a.png).\n\n![b](https://ok.example/b.png)", policy: policy)
        let cache = GlimmerDocumentCache()
        let key = GlimmerDocumentCache.Key(
            source: "answer", theme: .default, extensions: [], highlighter: "none", imageLoader: nil,
            imagePolicy: GlimmerImagePolicyKey(policy: policy)
        )
        cache.store(text, for: key)
        let cached = try XCTUnwrap(cache.text(for: key))
        let gates = imageAttachments(in: cached).map { attachment in
            (attachment as? GlimmerInlineImageAttachment)?.gate ?? (attachment as? GlimmerBlockAttachment)?.imageGate
        }
        XCTAssertEqual(gates.count, 2)
        let allowed = try XCTUnwrap(URL(string: "https://ok.example/elsewhere.png"))
        let refused = try XCTUnwrap(URL(string: "https://bad.example/?d=secret"))
        for gate in gates {
            XCTAssertEqual(gate?.permits(allowed), true)
            XCTAssertEqual(gate?.permits(refused), false)
        }
    }

    func testAViewWithAPolicyDoesNotReuseTextComposedWithoutOne() {
        let first = GlimmerView(configuration: .init(imageLoader: nil))
        first.update(markdown: "![Photo](https://example.com/photo.png)")
        XCTAssertEqual(blockAttachments(in: first.textView.textStorage).count, 1)
        let second = GlimmerView(configuration: .init(imageLoader: nil, imagePolicy: alt))
        second.update(markdown: "![Photo](https://example.com/photo.png)")
        XCTAssertEqual(blockAttachments(in: second.textView.textStorage).count, 0)
        XCTAssertEqual(second.plainText(), "Photo")
    }

    func testEqualPoliciesShareSettledText() {
        let hits = GlimmerDocumentCache.shared.hits
        for _ in 0..<2 {
            let view = GlimmerView(configuration: .init(imageLoader: nil, imagePolicy: AllowHosts(hosts: ["ok.example"])))
            view.update(markdown: "A ![photo](https://ok.example/photo.png) and ![ad](https://bad.example/ad.png).")
        }
        XCTAssertEqual(GlimmerDocumentCache.shared.hits, hits + 1)
    }
}
