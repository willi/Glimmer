import SwiftUI
import os

enum MarkdownInlineRenderMode: Int, Hashable, Sendable {
    case plain
    case interactive
}

enum MarkdownInlineAttributedCache {
    struct Key: Hashable, Sendable {
        let inlineHash: Int
        let styleHash: Int
        let mode: MarkdownInlineRenderMode
    }

    private final class Node: @unchecked Sendable {
        let key: Key
        var value: AttributedString
        weak var prev: Node?
        var next: Node?

        init(key: Key, value: AttributedString) {
            self.key = key
            self.value = value
        }
    }

    private struct State: @unchecked Sendable {
        var dict: [Key: Node] = [:]
        var head: Node?
        var tail: Node?
        var hits = 0
        var misses = 0
    }

    private static let capacity = 4096
    private static let lock = OSAllocatedUnfairLock(initialState: State())

    static func key(
        nodes: [MarkdownParser.InlineNode],
        configuration: MarkdownConfiguration,
        baseFont: Font?,
        mode: MarkdownInlineRenderMode
    ) -> Key {
        var inlineHasher = Hasher()
        hashInlines(nodes, into: &inlineHasher)

        var styleHasher = Hasher()
        configuration.hash(into: &styleHasher)
        styleHasher.combine(baseFont == nil)
        if let baseFont {
            styleHasher.combine(baseFont)
        }

        return Key(
            inlineHash: inlineHasher.finalize(),
            styleHash: styleHasher.finalize(),
            mode: mode
        )
    }

    static func value(for key: Key) -> AttributedString? {
        lock.withLock { state in
            guard let node = state.dict[key] else {
                state.misses += 1
                return nil
            }
            moveToTail(&state, node)
            state.hits += 1
            return node.value
        }
    }

    static func insert(_ value: AttributedString, for key: Key) {
        lock.withLock { state in
            if let existing = state.dict[key] {
                existing.value = value
                moveToTail(&state, existing)
            } else {
                let node = Node(key: key, value: value)
                state.dict[key] = node
                appendToTail(&state, node)
            }

            while state.dict.count > capacity, let evict = state.head {
                detach(&state, evict)
                state.dict.removeValue(forKey: evict.key)
            }
        }
    }

    static func clearForTesting() {
        lock.withLock { state in
            state.dict.removeAll()
            state.head = nil
            state.tail = nil
            state.hits = 0
            state.misses = 0
        }
    }

    static func statsForTesting() -> (hits: Int, misses: Int, entries: Int) {
        lock.withLock { state in
            (state.hits, state.misses, state.dict.count)
        }
    }

    private static func appendToTail(_ state: inout State, _ node: Node) {
        node.prev = state.tail
        node.next = nil
        if let tail = state.tail {
            tail.next = node
        } else {
            state.head = node
        }
        state.tail = node
    }

    private static func detach(_ state: inout State, _ node: Node) {
        let prev = node.prev
        let next = node.next
        if let prev {
            prev.next = next
        } else {
            state.head = next
        }
        if let next {
            next.prev = prev
        } else {
            state.tail = prev
        }
        node.prev = nil
        node.next = nil
    }

    private static func moveToTail(_ state: inout State, _ node: Node) {
        guard state.tail !== node else { return }
        detach(&state, node)
        appendToTail(&state, node)
    }

    private static func hashInlines(_ nodes: [MarkdownParser.InlineNode], into hasher: inout Hasher) {
        hasher.combine(nodes.count)
        for node in nodes {
            switch node {
            case .text(let text):
                hasher.combine(0); hasher.combine(text)
            case .emphasis(let children):
                hasher.combine(1); hashInlines(children, into: &hasher)
            case .strong(let children):
                hasher.combine(2); hashInlines(children, into: &hasher)
            case .strikethrough(let children):
                hasher.combine(3); hashInlines(children, into: &hasher)
            case .code(let code):
                hasher.combine(4); hasher.combine(code)
            case .link(let url, let title, let children):
                hasher.combine(5)
                hasher.combine(url.absoluteString)
                hasher.combine(title ?? "")
                hashInlines(children, into: &hasher)
            case .image(let url, let alt, let title):
                hasher.combine(6)
                hasher.combine(url.absoluteString)
                hasher.combine(alt)
                hasher.combine(title ?? "")
            case .autolink(let url, let kind, let originalText):
                hasher.combine(7)
                hasher.combine(url.absoluteString)
                hasher.combine(originalText)
                switch kind {
                case .url: hasher.combine(0)
                case .www: hasher.combine(1)
                case .email: hasher.combine(2)
                }
            case .mention(let username):
                hasher.combine(8); hasher.combine(username)
            case .issueReference(let number):
                hasher.combine(9); hasher.combine(number)
            case .commitSHA(let sha, let short):
                hasher.combine(10); hasher.combine(sha); hasher.combine(short)
            case .repositoryReference(let owner, let repo):
                hasher.combine(11); hasher.combine(owner); hasher.combine(repo)
            case .pullRequestReference(let owner, let repo, let number):
                hasher.combine(12)
                hasher.combine(owner)
                hasher.combine(repo)
                hasher.combine(number)
            case .lineBreak:
                hasher.combine(13)
            case .softBreak:
                hasher.combine(14)
            case .html(let tag):
                hasher.combine(15); hasher.combine(tag)
            case .footnoteReference(let label):
                hasher.combine(16); hasher.combine(label)
            case .extensionInline(let node):
                hasher.combine(17); hasher.combine(node)
            }
        }
    }
}
