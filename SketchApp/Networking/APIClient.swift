import Foundation

struct APIClient {
    static let baseURL = URL(string: "http://ln-dsk-0hxrv.qu.tu-berlin.de")!
    static let endpoint = baseURL.appendingPathComponent("api_model/generate")

    /// Health/liveness/ready check. Returns (statusCode, bodyString) or throws URLSession error.
    func checkEndpoint(_ path: String) async throws -> (Int, String) {
        let url = APIClient.baseURL.appendingPathComponent(path)
        let request = URLRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        return (status, text)
    }

    func generateMesh(svgText: String) async throws -> Data {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 90
        let session = URLSession(configuration: configuration)

        var request = URLRequest(url: APIClient.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        let body: [String: String] = [
            "svg_text": svgText,
            "job_id": "tablet"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "No error details"
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        return decodeModelResponse(data)
    }

    /// Decode the backend response if it arrives as raw binary, a base64 string,
    /// or a JSON object containing a base64 string.
    private func decodeModelResponse(_ data: Data) -> Data {
        // Already binary GLB (or USDZ zip) – use as-is.
        if data.prefix(4) == Data([0x67, 0x6C, 0x54, 0x46]) {
            return data
        }

        if let text = String(data: data, encoding: .utf8) {
            // Plain base64 string.
            if let decoded = Data(base64Encoded: text) {
                print("[APIClient] decoded plain base64, \(decoded.count) bytes")
                return decoded
            }

            // JSON object containing a base64 field.
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for key in ["model", "glb", "data", "result", "mesh", "output"] {
                    if let value = json[key] as? String, let decoded = Data(base64Encoded: value) {
                        print("[APIClient] decoded base64 from JSON key '\(key)', \(decoded.count) bytes")
                        return decoded
                    }
                }
            }
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
