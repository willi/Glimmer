import CryptoKit
import Foundation
import XCTest
@testable import Glimmer

final class CachedParserKeyOptimizationTests: XCTestCase {
    func testLargeContentCacheKeyUsesStableDigestSemantics() {
        var configuration = MarkdownConfiguration()
        configuration.enableCaching = true

        let markdown = String(repeating: "# Title\n\n", count: 7_000)
        let sameMarkdown = String(markdown)
        let modifiedSameLength = "!" + String(markdown.dropFirst())
        XCTAssertEqual(markdown.count, modifiedSameLength.count)
        XCTAssertGreaterThan(markdown.count, 50_000)

        let key = CachedMarkdownParser.cacheKey(for: markdown, configuration: configuration)
        let sameKey = CachedMarkdownParser.cacheKey(for: sameMarkdown, configuration: configuration)
        let modifiedKey = CachedMarkdownParser.cacheKey(for: modifiedSameLength, configuration: configuration)

        XCTAssertEqual(key, sameKey)
        XCTAssertNotEqual(key, modifiedKey)

        guard case .hashed(let length, let digest) = key.markdownKey,
              case .hashed(let modifiedLength, let modifiedDigest) = modifiedKey.markdownKey else {
            return XCTFail("Expected large markdown to use hashed cache keys")
        }

        XCTAssertEqual(length, markdown.count)
        XCTAssertEqual(modifiedLength, modifiedSameLength.count)
        XCTAssertNotEqual(digest, modifiedDigest)
    }

    func testOptimization65_LargeCacheKeyDigestAvoidsHexStringAllocation() throws {
        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let digests = makeBenchmarkDigests(count: 20_000)

        let hexString = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for digest in digests {
                    let hex = previousHexDigestString(digest)
                    checksum &+= hex.utf8.reduce(0) { $0 &+ Int($1) }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let fixedDigest = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for digest in digests {
                    let keyDigest = CachedMarkdownParser.CacheKey.ContentDigest(digest)
                    checksum &+= Int(truncatingIfNeeded: keyDigest.word0 ^ keyDigest.word1)
                    checksum &+= Int(truncatingIfNeeded: keyDigest.word2 ^ keyDigest.word3)
                }
                XCTAssertNotEqual(checksum, 0)
            }
        })

        print(
            "[BENCH] large cache key hex digest: \(formatMilliseconds(hexString)) ms " +
            "fixed digest: \(formatMilliseconds(fixedDigest)) ms " +
            "speedup: \(formatRatio(hexString / max(fixedDigest, 0.0001)))x"
        )

        XCTAssertLessThan(
            fixedDigest,
            hexString,
            "Large cached parser keys should store fixed digest words instead of allocating a SHA hex String."
        )
        #endif
    }

    private func makeBenchmarkDigests(count: Int) -> [SHA256.Digest] {
        var digests: [SHA256.Digest] = []
        digests.reserveCapacity(count)

        for index in 0..<count {
            let markdown = "large cache key digest benchmark \(index) " + String(repeating: "x", count: 128)
            digests.append(SHA256.hash(data: Data(markdown.utf8)))
        }

        return digests
    }

    private func previousHexDigestString(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private func timed(_ block: () -> Void) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        return CFAbsoluteTimeGetCurrent() - start
    }

    private func median(_ values: [TimeInterval]) -> TimeInterval {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private func formatMilliseconds(_ value: TimeInterval) -> String {
        String(format: "%.2f", value * 1000)
    }

    private func formatRatio(_ value: TimeInterval) -> String {
        String(format: "%.2f", value)
    }
}
