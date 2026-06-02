import Foundation
import CryptoKit
import os

/// Thread-safe cached wrapper around MarkdownParser with size limits and TTL
public final class CachedMarkdownParser: NSObject, @unchecked Sendable, NSCacheDelegate {
    
    /// Cache key combining markdown and configuration
    struct CacheKey: Hashable {
        enum MarkdownKey: Hashable {
            case inline(String)           // small content uses full text
            case hashed(length: Int, sha256: String) // large content uses hash
        }
        let markdownKey: MarkdownKey
        let configuration: MarkdownConfiguration
    }
    
    /// Cache entry with metadata for eviction policy
    struct CacheEntry {
        let blocks: [MarkdownParser.BlockNode]
        let size: Int
        let created: Date
        var lastAccess: Date
        
        func isExpired(ttl: TimeInterval) -> Bool {
            return Date().timeIntervalSince(created) > ttl
        }
    }
    
    private struct CacheState { var cache: [CacheKey: CacheEntry] = [:]; var currentSize = 0 }
    private let lock = OSAllocatedUnfairLock(initialState: CacheState())
    private let useNSCache: Bool
    private var nsCache: NSCache<WrappedKey, WrappedEntry>?
    
    // Performance metrics
    private struct MetricsState { var hits = 0; var misses = 0; var evictions = 0 }
    private let metricsLock = OSAllocatedUnfairLock(initialState: MetricsState())
    
    public init(useNSCache: Bool = false) {
        self.useNSCache = useNSCache
        self.nsCache = nil
        super.init()
        if useNSCache {
            let c = NSCache<WrappedKey, WrappedEntry>()
            c.delegate = self
            self.nsCache = c
        }
    }

    deinit {
        // Prevent asynchronous NSCache delegate callbacks from touching
        // lock-protected state while this object is deallocating.
        nsCache?.delegate = nil
        nsCache?.removeAllObjects()
    }
    
    private static let largeContentHashThreshold = 50_000 // chars
    
    public func parse(_ markdown: String, configuration: MarkdownConfiguration) -> [MarkdownParser.BlockNode] {
        let key: CacheKey = {
            if markdown.count > Self.largeContentHashThreshold {
                let data = Data(markdown.utf8)
                let digest = SHA256.hash(data: data)
                let hash = digest.compactMap { String(format: "%02x", $0) }.joined()
                return CacheKey(markdownKey: .hashed(length: markdown.count, sha256: hash), configuration: configuration)
            } else {
                return CacheKey(markdownKey: .inline(markdown), configuration: configuration)
            }
        }()
        
        // Check cache
        if useNSCache, let box = nsCache?.object(forKey: WrappedKey(key)) {
            var entry = box.entry
            if entry.isExpired(ttl: configuration.cacheTimeToLiveSeconds) {
                // Remove expired entry
                nsCache?.removeObject(forKey: WrappedKey(key))
                let sz = entry.size
                lock.withLock { state in state.currentSize = max(0, state.currentSize - sz) }
                metricsLock.withLock { $0.evictions += 1 }
            } else {
                entry.lastAccess = Date()
                // Replace updated entry to refresh access metadata
                let updated = WrappedEntry(entry: entry)
                nsCache?.setObject(updated, forKey: WrappedKey(key), cost: entry.size)
                metricsLock.withLock { $0.hits += 1 }
                return entry.blocks
            }
        } else if var entry = lock.withLock({ $0.cache[key] }) {
            // Check if entry is expired
            if entry.isExpired(ttl: configuration.cacheTimeToLiveSeconds) {
                // Remove expired entry
                let sz = entry.size
                lock.withLock { state in state.currentSize -= sz; state.cache.removeValue(forKey: key) }
                metricsLock.withLock { $0.evictions += 1 }
            } else {
                // Update last access time
                entry.lastAccess = Date()
                let updatedEntry = entry
                lock.withLock { state in state.cache[key] = updatedEntry }
                metricsLock.withLock { $0.hits += 1 }
                
                // Performance tracking disabled
                
                return entry.blocks
            }
        } else {
            metricsLock.withLock { $0.misses += 1 }
        }
        
        // Parse outside the lock
        let startTime = configuration.enablePerformanceTracking ? CFAbsoluteTimeGetCurrent() : 0
        let blocks = MarkdownParser.parse(markdown, configuration: configuration)
        
        if configuration.enablePerformanceTracking {
            _ = CFAbsoluteTimeGetCurrent() - startTime
            // Parse time tracking
        }
        
        // Estimate memory usage
        let estimatedSize = estimateMemoryUsage(markdown: markdown, blocks: blocks)
        
        // Only cache if enabled
        if configuration.enableCaching {
            if useNSCache, let c = nsCache {
                // Configure advisory cost limit per latest configuration
                c.totalCostLimit = configuration.maxCacheSizeMB * 1024 * 1024
                let now = Date()
                let entry = CacheEntry(blocks: blocks, size: estimatedSize, created: now, lastAccess: now)
                c.setObject(WrappedEntry(entry: entry), forKey: WrappedKey(key), cost: estimatedSize)
                lock.withLock { state in state.currentSize += estimatedSize }
            } else {
                let maxSizeBytes = configuration.maxCacheSizeMB * 1024 * 1024
                if estimatedSize < maxSizeBytes / 10 {
                    // Evict entries if needed to make room
                    ensureCacheSpace(needed: estimatedSize, maxSize: maxSizeBytes)
                    
                    // Add to cache
                    let now = Date()
                    let entry = CacheEntry(
                        blocks: blocks,
                        size: estimatedSize,
                        created: now,
                        lastAccess: now
                    )
                    lock.withLock { state in state.cache[key] = entry; state.currentSize += estimatedSize }
                    
                    // Perform periodic cleanup
                    if lock.withLock({ $0.cache.count % 100 == 0 }) {
                        cleanupExpiredEntries(ttl: configuration.cacheTimeToLiveSeconds)
                    }
                }
            }
        }
        
        return blocks
    }
    
    /// Clear all cached entries
    public func clearCache() {
        lock.withLock { state in state.cache.removeAll(); state.currentSize = 0 }
        nsCache?.removeAllObjects()
        
        // Cache cleared
        
        // Reset metrics
        metricsLock.withLock {
            $0.hits = 0
            $0.misses = 0
            $0.evictions = 0
        }
    }
    
    /// Get current cache statistics
    public func getCacheStatistics() -> (hits: Int, misses: Int, evictions: Int, entries: Int, sizeBytes: Int) {
        // NSCache does not expose entry count; report 0 entries in NSCache mode
        let entries = useNSCache ? 0 : lock.withLock { $0.cache.count }
        let size = lock.withLock { $0.currentSize }
        let metrics = metricsLock.withLock { ($0.hits, $0.misses, $0.evictions) }
        return (metrics.0, metrics.1, metrics.2, entries, size)
    }
    
    // MARK: - Private Methods
    
    private func estimateMemoryUsage(markdown: String, blocks: [MarkdownParser.BlockNode]) -> Int {
        // Base size: markdown string
        var size = markdown.utf8.count
        
        // Add estimated AST node sizes
        size += blocks.count * MemoryLayout<MarkdownParser.BlockNode>.stride
        
        // Add estimated inline node sizes (rough estimate)
        size += blocks.count * 100 // Assume average 100 bytes per block for inline content
        
        return size
    }
    
    private func ensureCacheSpace(needed: Int, maxSize: Int) {
        // If adding this entry would exceed max size, evict entries
        while lock.withLock({ $0.currentSize + needed > maxSize && !$0.cache.isEmpty }) { evictLeastRecentlyUsed() }
    }
    
    private func evictLeastRecentlyUsed() {
        guard let oldestKey = lock.withLock({ $0.cache.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key }) else {
            return
        }
        
        if let entry = lock.withLock({ state in state.cache.removeValue(forKey: oldestKey) }) {
            lock.withLock { $0.currentSize -= entry.size }
            metricsLock.withLock { $0.evictions += 1 }
            
            // Evicted cache entry
        }
    }
    
    private func cleanupExpiredEntries(ttl: TimeInterval) {
        let evictedCount: Int = lock.withLock { state in
            var toRemove: [CacheKey] = []
            for (key, entry) in state.cache where entry.isExpired(ttl: ttl) {
                toRemove.append(key)
                state.currentSize -= entry.size
            }
            for key in toRemove { state.cache.removeValue(forKey: key) }
            return toRemove.count
        }
        if evictedCount > 0 {
            metricsLock.withLock { $0.evictions += evictedCount }
        }
    }
}

// MARK: - NSCache Support

private final class WrappedKey: NSObject {
    let key: CachedMarkdownParser.CacheKey
    init(_ key: CachedMarkdownParser.CacheKey) { self.key = key }
    override var hash: Int { key.hashValue }
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? WrappedKey else { return false }
        return self.key == other.key
    }
}

private final class WrappedEntry: NSObject {
    let entry: CachedMarkdownParser.CacheEntry
    init(entry: CachedMarkdownParser.CacheEntry) { self.entry = entry }
}

extension CachedMarkdownParser {
    public func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        if let box = obj as? WrappedEntry {
            lock.withLock { state in state.currentSize = max(0, state.currentSize - box.entry.size) }
        }
        metricsLock.withLock { $0.evictions += 1 }
    }

    /// Additional telemetry for NSCache mode
    public func getNSCacheInfo() -> (enabled: Bool, totalCostLimit: Int, approximateBytes: Int) {
        if useNSCache, let c = nsCache {
            let size = lock.withLock { $0.currentSize }
            return (true, c.totalCostLimit, size)
        } else {
            let size = lock.withLock { $0.currentSize }
            return (false, 0, size)
        }
    }
}

// MARK: - Memory Pressure Handling

public extension CachedMarkdownParser {
    /// Respond to memory pressure by reducing cache size
    func handleMemoryPressure(level: MemoryPressureLevel = .normal) {
        switch level {
        case .normal:
            // Remove expired entries
            cleanupExpiredEntries(ttl: 60) // Aggressive TTL during memory pressure
            
        case .warning:
            if useNSCache, let c = nsCache {
                // Reduce cost limit to half of current tracked usage to encourage eviction
                let current = lock.withLock { $0.currentSize }
                let target = max(current / 2, 1)
                c.totalCostLimit = target
            } else {
                // Remove 50% of least recently used entries
                let half = lock.withLock { $0.currentSize / 2 }
                while lock.withLock({ $0.currentSize > half && !$0.cache.isEmpty }) { evictLeastRecentlyUsed() }
            }
            
        case .critical:
            // Clear entire cache
            if useNSCache {
                nsCache?.removeAllObjects()
            }
            let evicted = lock.withLock { state in let c = state.cache.count; state.cache.removeAll(); state.currentSize = 0; return c }
            metricsLock.withLock { $0.evictions += evicted }
            
            // Memory pressure: cleared entire cache
        }
    }
}

/// Memory pressure levels for cache management
public enum MemoryPressureLevel {
    case normal
    case warning
    case critical
}
