import Foundation

struct APIClient {
    static let endpoint = URL(string: "http://ln-dsk-0hxrv.qu.tu-berlin.de/api_model/generate")!

    func generateMesh(svgText: String) async throws -> Data {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 90
        let session = URLSession(configuration: configuration)

        var request = URLRequest(url: APIClient.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        let body: [String: String] = ["svg_text": svgText]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "No error details"
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        return data
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid response."
        case .serverError(let statusCode, let message):
            return "Server error \(statusCode): \(message)"
        }
    }
}
