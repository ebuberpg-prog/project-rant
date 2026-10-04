import Foundation
import Network

@MainActor
final class LocalCompanion {
    static let port: NWEndpoint.Port = 41739
    private weak var model: RantModel?
    private var listener: NWListener?
    private let queue = DispatchQueue.main
    private let allowedOrigins: Set<String> = [
        "https://ebuberpg-prog.github.io",
        "http://localhost:8080",
        "http://127.0.0.1:8080"
    ]

    init(model: RantModel) {
        self.model = model
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: Self.port)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    NSLog("Rant local companion stopped: %@", error.localizedDescription)
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            NSLog("Rant local companion could not start: %@", error.localizedDescription)
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, accumulated: Data())
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                var bytes = accumulated
                if let data { bytes.append(data) }
                if let request = Self.parseRequest(bytes) {
                    await self.respond(request, on: connection)
                } else if isComplete || error != nil || bytes.count > 1_000_000 {
                    connection.cancel()
                } else {
                    self.receive(connection, accumulated: bytes)
                }
            }
        }
    }

    private func respond(_ request: HTTPRequest, on connection: NWConnection) async {
        let origin = request.headers["origin"] ?? ""
        guard allowedOrigins.contains(origin) else {
            send(status: 403, body: ["error": "This page is not allowed to use the Rant companion."], origin: nil, on: connection)
            return
        }
        if request.method == "OPTIONS" {
            send(status: 204, body: [:], origin: origin, on: connection, preflight: true)
            return
        }

        guard let model else {
            send(status: 503, body: ["error": "Rant is not ready."], origin: origin, on: connection)
            return
        }
        let json = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
        switch (request.method, request.path) {
        case ("GET", "/v1/status"):
            send(status: 200, body: model.companionSnapshot(), origin: origin, on: connection)
        case ("POST", "/v1/sign-in"):
            model.companionSignIn()
            send(status: 202, body: ["accepted": true], origin: origin, on: connection)
        case ("POST", "/v1/record/start"):
            model.companionStartRecording(modeName: json["mode"] as? String)
            send(status: 202, body: ["accepted": true], origin: origin, on: connection)
        case ("POST", "/v1/record/stop"):
            model.companionStopRecording()
            send(status: 202, body: ["accepted": true], origin: origin, on: connection)
        case ("POST", "/v1/rewrite"):
            guard let text = json["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                send(status: 400, body: ["error": "Text is required."], origin: origin, on: connection)
                return
            }
            do {
                let result = try await model.companionRewrite(text, modeName: json["mode"] as? String, styleName: json["style"] as? String)
                send(status: 200, body: ["text": result], origin: origin, on: connection)
            } catch {
                send(status: 502, body: ["error": error.localizedDescription], origin: origin, on: connection)
            }
        default:
            send(status: 404, body: ["error": "Unknown Rant companion endpoint."], origin: origin, on: connection)
        }
    }

    private func send(status: Int, body: [String: Any], origin: String?, on connection: NWConnection, preflight: Bool = false) {
        let payload = (try? JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])) ?? Data("{}".utf8)
        let reason = status == 200 ? "OK" : status == 202 ? "Accepted" : status == 204 ? "No Content" : status == 400 ? "Bad Request" : status == 403 ? "Forbidden" : status == 404 ? "Not Found" : status == 502 ? "Bad Gateway" : "Service Unavailable"
        var headers = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n"
        if let origin {
            headers += "Access-Control-Allow-Origin: \(origin)\r\nVary: Origin\r\n"
            if preflight {
                headers += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nAccess-Control-Allow-Private-Network: true\r\nAccess-Control-Max-Age: 600\r\n"
            }
        }
        var response = Data((headers + "\r\n").utf8)
        if status != 204 { response.append(payload) }
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private static func parseRequest(_ bytes: Data) -> HTTPRequest? {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let range = bytes.range(of: delimiter),
              let headerText = String(data: bytes[..<range.lowerBound], encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let requestLine = first.split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        let bodyStart = range.upperBound
        let body = Data(bytes[bodyStart...])
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard body.count >= contentLength else { return nil }
        let path = String(requestLine[1]).split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
        return HTTPRequest(method: String(requestLine[0]), path: path, headers: headers, body: body.prefix(contentLength))
    }
}
