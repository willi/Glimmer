import Foundation
import Network

/// Loopback HTTP lets URLSession exercise its real caching and revalidation rules.
final class ImageTestServer: @unchecked Sendable {
    struct Reply: Sendable {
        var data: Data
        var headers: [String: String] = ["Cache-Control": "max-age=3600"]
        var status = 200
        var delay: TimeInterval = 0
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "Glimmer.ImageTestServer")
    private let lock = NSLock()
    private var reply: Reply
    private var pathReplies: [String: Reply] = [:]
    private var requests: [String] = []
    private var connections: [NWConnection] = []

    init(reply: Reply) throws {
        self.reply = reply
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    var requestCount: Int { lock.withLock { requests.count } }
    var receivedRequests: [String] { lock.withLock { requests } }

    func setReply(_ reply: Reply) { lock.withLock { self.reply = reply } }

    /// Answers requests for `path` with `reply` instead of the default one, for example with a redirect.
    func setReply(_ reply: Reply, forPath path: String) { lock.withLock { pathReplies[path] = reply } }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.listener.stateUpdateHandler = nil
                    if let port = self.listener.port, let url = URL(string: "http://127.0.0.1:\(port.rawValue)/image.png") {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: URLError(.badURL))
                    }
                case .failed(let error):
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                self.lock.withLock { self.connections.append(connection) }
                connection.start(queue: self.queue)
                self.receive(connection, bytes: Data())
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        let pending = lock.withLock { connections }
        pending.forEach { $0.cancel() }
    }

    private func receive(_ connection: NWConnection, bytes: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { return }
            var bytes = bytes
            if let data { bytes.append(data) }
            guard let request = String(data: bytes, encoding: .utf8), request.contains("\r\n\r\n") else {
                if !complete && error == nil { self.receive(connection, bytes: bytes) }
                return
            }
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let reply = self.lock.withLock {
                self.requests.append(request)
                return self.pathReplies[path] ?? self.reply
            }
            self.queue.asyncAfter(deadline: .now() + reply.delay) {
                let reason = switch reply.status {
                case 200: "OK"
                case 301: "Moved Permanently"
                case 302: "Found"
                case 304: "Not Modified"
                default: "Error"
                }
                var response = "HTTP/1.1 \(reply.status) \(reason)\r\nContent-Length: \(reply.data.count)\r\nContent-Type: image/png\r\nConnection: close\r\n"
                for (name, value) in reply.headers { response += "\(name): \(value)\r\n" }
                response += "\r\n"
                var payload = Data(response.utf8)
                payload.append(reply.data)
                connection.send(content: payload, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }
}
