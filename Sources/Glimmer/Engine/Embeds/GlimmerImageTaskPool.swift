import Foundation

/// Shares active work, with independent cancellation for each consumer. Completed work lives in the caches.
actor GlimmerImageTaskPool<Key: Hashable & Sendable, Value: Sendable> {
    private struct Flight {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Value, Error>]
    }

    private var flights: [Key: Flight] = [:]
    private var retiring: [UUID: Task<Void, Never>] = [:]

    func value(for key: Key, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let consumer = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if var flight = flights[key] {
                    flight.waiters[consumer] = continuation
                    flights[key] = flight
                    return
                }
                let id = UUID()
                // Decoding and hashing must not inherit the caller's main-actor isolation.
                let task = Task.detached { [weak self] in
                    let result: Result<Value, Error>
                    do {
                        let value = try await operation()
                        try Task.checkCancellation()
                        result = .success(value)
                    } catch {
                        result = .failure(error)
                    }
                    await self?.finish(key: key, id: id, result: result)
                }
                flights[key] = Flight(id: id, task: task, waiters: [consumer: continuation])
            }
        } onCancel: {
            Task { await self.cancel(consumer: consumer, key: key) }
        }
    }

    private func finish(key: Key, id: UUID, result: Result<Value, Error>) {
        retiring[id] = nil
        guard let flight = flights[key], flight.id == id else { return }
        flights[key] = nil
        for waiter in flight.waiters.values { waiter.resume(with: result) }
    }

    private func cancel(consumer: UUID, key: Key) {
        guard var flight = flights[key], let waiter = flight.waiters.removeValue(forKey: consumer) else { return }
        if flight.waiters.isEmpty {
            flights[key] = nil
            flight.task.cancel()
            retiring[flight.id] = flight.task
        } else {
            flights[key] = flight
        }
        waiter.resume(throwing: CancellationError())
    }

    func cancelAll() async {
        let pending = Array(flights.values)
        let cancelled = Array(retiring.values)
        flights.removeAll()
        for flight in pending {
            flight.task.cancel()
            for waiter in flight.waiters.values { waiter.resume(throwing: CancellationError()) }
        }
        // Wait for URLSession to finish cancelling before its response cache is cleared.
        for flight in pending { await flight.task.value }
        for task in cancelled { await task.value }
    }
}
