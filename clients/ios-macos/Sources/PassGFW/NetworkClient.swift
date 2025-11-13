import Foundation

/// HTTP Response
struct HTTPResponse {
    let success: Bool
    let statusCode: Int
    let body: String
    let error: String?
}

/// Network Client for HTTP requests
class NetworkClient {
    private let timeout: TimeInterval
    
    init(timeout: TimeInterval = Config.requestTimeout) {
        self.timeout = timeout
    }
    
    /// POST request with raw binary data
    func post(url: String, body: Data) async -> HTTPResponse {
        guard let requestURL = URL(string: url) else {
            return HTTPResponse(success: false, statusCode: 0, body: "", error: "Invalid URL")
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("PassGFW/2.2 Swift", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return HTTPResponse(success: false, statusCode: 0, body: "", error: "Invalid response")
            }

            let body = String(data: data, encoding: .utf8) ?? ""
            let success = (200...299).contains(httpResponse.statusCode)

            return HTTPResponse(
                success: success,
                statusCode: httpResponse.statusCode,
                body: body,
                error: success ? nil : "HTTP \(httpResponse.statusCode)"
            )
        } catch {
            return HTTPResponse(success: false, statusCode: 0, body: "", error: error.localizedDescription)
        }
    }

    /// POST request with JSON string (deprecated, use post(url:body:) instead)
    func post(url: String, jsonBody: String) async -> HTTPResponse {
        guard let bodyData = jsonBody.data(using: .utf8) else {
            return HTTPResponse(success: false, statusCode: 0, body: "", error: "Invalid JSON string")
        }
        return await post(url: url, body: bodyData)
    }
    
    /// GET request
    func get(url: String) async -> HTTPResponse {
        guard let requestURL = URL(string: url) else {
            return HTTPResponse(success: false, statusCode: 0, body: "", error: "Invalid URL")
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("PassGFW/1.0 Swift", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return HTTPResponse(success: false, statusCode: 0, body: "", error: "Invalid response")
            }
            
            let body = String(data: data, encoding: .utf8) ?? ""
            let success = (200...299).contains(httpResponse.statusCode)
            
            return HTTPResponse(
                success: success,
                statusCode: httpResponse.statusCode,
                body: body,
                error: success ? nil : "HTTP \(httpResponse.statusCode)"
            )
        } catch {
            return HTTPResponse(success: false, statusCode: 0, body: "", error: error.localizedDescription)
        }
    }
}

