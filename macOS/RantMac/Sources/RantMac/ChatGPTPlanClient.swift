import Foundation

struct ChatGPTModel: Decodable, Identifiable {
    let slug: String
    let displayName: String
    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug
        case displayName = "display_name"
    }
}

@MainActor
final class ChatGPTPlanClient {
    private let auth: ChatGPTOAuth
    private let session = URLSession.shared
    private(set) var models: [ChatGPTModel] = []
    private var selectedModel = UserDefaults.standard.string(forKey: "rant.openai.model")

    init(auth: ChatGPTOAuth) { self.auth = auth }

    func availableModels() async throws -> [ChatGPTModel] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(try await auth.accessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PlanAPIError.modelListFailed
        }
        let result = try JSONDecoder().decode(ModelList.self, from: data)
        models = result.models.filter { $0.visibility == "list" }.map { ChatGPTModel(slug: $0.slug, displayName: $0.displayName) }
        if selectedModel == nil || !models.contains(where: { $0.slug == selectedModel }) {
            selectedModel = models.first?.slug
            if let selectedModel { UserDefaults.standard.set(selectedModel, forKey: "rant.openai.model") }
        }
        return models
    }

    func setModel(_ slug: String) {
        selectedModel = slug
        UserDefaults.standard.set(slug, forKey: "rant.openai.model")
    }

    func rewrite(_ text: String, instructions: String) async throws -> String {
        let model: String
        if let selectedModel { model = selectedModel }
        else if let available = try await availableModels().first { model = available.slug }
        else { throw PlanAPIError.noModels }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(try await auth.accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ResponseRequest(
            model: model,
            instructions: instructions,
            input: [ResponseInput(role: "user", content: text)],
            store: false,
            stream: true
        ))

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PlanAPIError.responseFailed
        }
        var output = ""
        var completed = false
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard data != "[DONE]",
                  let event = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
                  let type = event["type"] as? String else { continue }
            if type == "response.output_text.delta", let delta = event["delta"] as? String {
                output += delta
            } else if type == "response.failed" {
                throw PlanAPIError.usageLimit
            } else if type == "response.incomplete" {
                throw PlanAPIError.incomplete
            } else if type == "response.completed" {
                completed = true
            }
        }
        guard completed, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlanAPIError.incomplete
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ModelList: Decodable {
    let models: [ModelRecord]
}

private struct ModelRecord: Decodable {
    let slug: String
    let displayName: String
    let visibility: String?
    enum CodingKeys: String, CodingKey {
        case slug, visibility
        case displayName = "display_name"
    }
}

private struct ResponseInput: Encodable {
    let role: String
    let content: String
}

private struct ResponseRequest: Encodable {
    let model: String
    let instructions: String
    let input: [ResponseInput]
    let store: Bool
    let stream: Bool
}

enum PlanAPIError: LocalizedError {
    case modelListFailed, noModels, responseFailed, usageLimit, incomplete
    var errorDescription: String? {
        switch self {
        case .modelListFailed: "Couldn’t load the models available to this ChatGPT account."
        case .noModels: "This ChatGPT account has no available text models."
        case .responseFailed: "GPT couldn’t process that text. Check the connection and try again."
        case .usageLimit: "The ChatGPT plan usage limit for Rant has been reached or is temporarily unavailable."
        case .incomplete: "GPT’s response stopped before it finished. Try again."
        }
    }
}
