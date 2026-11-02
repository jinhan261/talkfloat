import Foundation

public actor ASTClient {
    public nonisolated let events: AsyncThrowingStream<ASTEvent, Error>
    private let continuation: AsyncThrowingStream<ASTEvent, Error>.Continuation
    private var socket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var reader: Task<Void, Never>?
    private var started = false
    private var finished = false
    public nonisolated let sessionID = UUID().uuidString
    public init() {
        let pair = AsyncThrowingStream<ASTEvent, Error>.makeStream(bufferingPolicy: .bufferingOldest(200))
        events = pair.stream; continuation = pair.continuation
    }
    public func connect(_ credentials: Credentials) async throws {
        guard credentials.isValid else { throw SayError.message("请先填写豆包连接凭据") }
        var req = URLRequest(url: ASTProtocol.endpoint); req.timeoutInterval = 12
        req.setValue(ASTProtocol.resource, forHTTPHeaderField: "X-Api-Resource-Id")
        req.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Request-Id")
        if credentials.legacy {
            req.setValue(credentials.appID, forHTTPHeaderField: "X-Api-App-Id")
            req.setValue(credentials.accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        } else { req.setValue(credentials.apiKey, forHTTPHeaderField: "X-Api-Key") }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        let session = URLSession(configuration: config); urlSession = session
        let ws = session.webSocketTask(with: req); ws.maximumMessageSize = 2*1024*1024; socket = ws; ws.resume()
        let deadline = Task { try? await Task.sleep(for: .seconds(12)); if !Task.isCancelled { ws.cancel(with: .goingAway, reason: nil) } }
        defer { deadline.cancel() }
        do {
            try await ws.send(.data(ASTProtocol.request(event: 100, session: sessionID)))
            let event = try decode(await ws.receive())
            guard event.type == 150 else { throw SayError.message("豆包未接受会话（\(event.status)）：\(event.message)") }
            started = true; continuation.yield(event)
            reader = Task { [weak self] in await self?.readLoop(ws) }
        } catch {
            abort()
            if let response = ws.response as? HTTPURLResponse, response.statusCode != 101 {
                throw SayError.message("豆包连接被拒绝（HTTP \(response.statusCode)）。请检查凭据、同传 2.0 开通状态和余额。")
            }; throw error
        }
    }
    private func decode(_ message: URLSessionWebSocketTask.Message) throws -> ASTEvent {
        switch message {
        case .data(let data): return try ASTEvent(data: data)
        case .string: throw SayError.message("豆包返回了非 Protobuf 消息")
        @unknown default: throw SayError.message("无法识别服务消息")
        }
    }
    private func readLoop(_ ws: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let event = try decode(await ws.receive())
                guard event.sessionID.isEmpty || event.sessionID == sessionID else { continue }
                if event.type == 153 || event.type == 151 || (event.status != 0 && event.status != 20000000) {
                    throw SayError.service(event.status,event.message)
                }
                if case .dropped = continuation.yield(event) { throw SayError.message("字幕接收拥堵，请重新开始") }
                if event.type == 152 { finished = true; continuation.finish(); return }
            }
        } catch { if !finished { continuation.finish(throwing: error) } }
    }
    public func send(_ audio: Data) async throws {
        guard started, !finished, let socket else { throw SayError.message("翻译连接已关闭") }
        try await socket.send(.data(ASTProtocol.request(event: 200, session: sessionID, audio: audio)))
    }
    public func finish() async -> Bool {
        guard started, let socket else { abort(); return true }
        let deadline = Task { try? await Task.sleep(for: .seconds(3)); if !Task.isCancelled { socket.cancel(with: .goingAway, reason: nil) } }
        try? await socket.send(.data(ASTProtocol.request(event: 102, session: sessionID)))
        await reader?.value
        deadline.cancel(); let graceful = finished; abort(); return graceful
    }
    public func abort() {
        started = false; reader?.cancel(); reader = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        urlSession?.invalidateAndCancel(); urlSession = nil; continuation.finish()
    }
}
