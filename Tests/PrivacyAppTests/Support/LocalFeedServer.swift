import Foundation
import Network

/// 배포 서버 대역. 127.0.0.1의 임의 포트에서 모든 요청에 같은 appcast를 HTTP로 돌려줌.
/// Sparkle은 http와 https만 받으므로 파일 URL 대신 씀.
final class LocalFeedServer: Sendable {
    private let listener: NWListener
    private let body: Data
    private let queue = DispatchQueue(label: "LocalFeedServer")

    init(body: Data) throws {
        self.body = body
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    /// 연결을 받을 준비가 되면 appcast URL을 돌려줌.
    func start() async throws -> URL {
        let body = body
        let queue = queue
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            Self.answer(connection, body: body)
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let listener = listener
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        return URL(string: "http://127.0.0.1:\(port)/appcast.xml")!
    }

    func stop() { listener.cancel() }

    /// 요청 머리를 끝까지 읽은 뒤 응답하고 연결을 닫음.
    private static func answer(_ connection: NWConnection, body: Data, received: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, complete, error in
            let request = received + (data ?? Data())
            guard error == nil else { connection.cancel(); return }
            guard request.range(of: Data("\r\n\r\n".utf8)) != nil || complete else {
                answer(connection, body: body, received: request)
                return
            }
            let head = "HTTP/1.1 200 OK\r\nContent-Type: application/xml\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
