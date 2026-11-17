import Foundation

/// What identifies an extension, highlighter or image loader in a `GlimmerDocumentCache` key. Views whose
/// dependencies have equal identities share composed answers, so equal identities must render equally.
///
/// The stateless built-ins are identified by their type name. Anything else must be `Hashable`, and is identified by
/// its exact type and value the way `GlimmerImagePolicyKey` identifies a policy: values of different types never compare
/// equal, even with the same stored properties.
struct GlimmerCacheIdentity: Hashable, Sendable {
    /// A `Hashable` that came from a `Sendable` dependency. Swift cannot cast to `any Hashable & Sendable` (`Sendable`
    /// is a marker protocol), so the cast keeps `Hashable` only and this restores what the source already promised.
    private struct SendableHashable: @unchecked Sendable {
        let value: AnyHashable
    }

    private enum Storage: Sendable {
        case builtIn(String)
        case value(SendableHashable)
    }

    private let storage: Storage

    private init(_ storage: Storage) {
        self.storage = storage
    }

    static func == (lhs: GlimmerCacheIdentity, rhs: GlimmerCacheIdentity) -> Bool {
        switch (lhs.storage, rhs.storage) {
        case (.builtIn(let left), .builtIn(let right)): left == right
        // `AnyHashable` compares the dynamic types first, then the values with `==`.
        case (.value(let left), .value(let right)):
            // `AnyHashable` alone calls a class and its subclass, or `Int` and `Int8`, equal; the exact type must match.
            type(of: left.value.base) == type(of: right.value.base) && left.value == right.value
        default: false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch storage {
        case .builtIn(let name):
            hasher.combine(name)
        case .value(let value):
            // Two types with the same stored values are different identities, so they should not share a hash either.
            hasher.combine(ObjectIdentifier(type(of: value.value.base)))
            hasher.combine(value.value)
        }
    }

    /// `nil` when the extension is neither a stateless built-in nor `Hashable`.
    init?(extension value: any GlimmerExtension) {
        if value is GlimmerMentions || value is GlimmerEmojiShortcodes {
            self.init(.builtIn(String(reflecting: type(of: value))))
        } else {
            self.init(hashable: value)
        }
    }

    /// `nil` when the highlighter is neither the built-in one nor `Hashable`.
    init?(highlighter value: any GlimmerHighlighter) {
        if value is GlimmerBasicHighlighter {
            self.init(.builtIn(String(reflecting: type(of: value))))
        } else {
            self.init(hashable: value)
        }
    }

    /// `nil` when the loader is neither the built-in one on the shared cache nor `Hashable`.
    init?(imageLoader value: any GlimmerImageLoader) {
        if let builtIn = value as? GlimmerURLSessionImageLoader, builtIn.cache === GlimmerImageCache.shared {
            self.init(.builtIn(String(reflecting: type(of: value))))
        } else {
            self.init(hashable: value)
        }
    }

    /// `value` is already `Sendable` (every dependency protocol requires it), so only `Hashable` is checked at run time.
    private init?(hashable value: any Sendable) {
        guard let hashable = value as? any Hashable else { return nil }
        self.init(.value(SendableHashable(value: AnyHashable(hashable))))
    }
}
