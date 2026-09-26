import QuartzCore

/// Time and wake-ups for the reveal. Tests substitute a manual clock.
@MainActor
protocol GlimmerRevealClock: AnyObject {
    var now: TimeInterval { get }
    /// Calls `action` at (or just after) `time`, replacing any earlier request.
    func wake(at time: TimeInterval, _ action: @escaping @MainActor () -> Void)
    func cancel()
}

/// Media time and a sleeping task. It wakes only for phrase starts and settles, never per frame.
@MainActor
final class GlimmerSystemRevealClock: GlimmerRevealClock {
    private var task: Task<Void, Never>?

    var now: TimeInterval { CACurrentMediaTime() }

    func wake(at time: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        let delay = max(0, time - now)
        task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// A released clock never wakes anyone.
    isolated deinit {
        task?.cancel()
    }
}
