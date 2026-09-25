//
//  APIError.swift
//  MyNutritionPal
//

import Foundation

/// Why an API call failed, with a message the app can show as is
/// (`error.localizedDescription`).
enum APIError: Error, Equatable, LocalizedError {
    /// No server address is set (Config/Local.xcconfig).
    case notConfigured
    /// The request didn't get a response, e.g. the server is down or unreachable.
    case transport(URLError, server: String)
    /// The server answered with a non-2xx status. `message` is its `detail`.
    case server(status: Int, message: String?)
    /// A 2xx response the app couldn't decode.
    case decoding

    /// The error for a non-2xx response. The backend sends
    /// {"detail": "<message>"}, or a list of problems for 422 validation errors.
    static func from(status: Int, data: Data) -> APIError {
        struct Body: Decodable {
            let detail: String
        }

        if status == 422 {
            return .server(status: status, message: "Some of the information sent wasn't valid.")
        }

        let detail = (try? JSONDecoder().decode(Body.self, from: data))?.detail
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return .server(status: status, message: detail?.isEmpty == false ? detail : nil)
    }

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "No server address is set. Copy Config/Local.xcconfig.example to Config/Local.xcconfig, set your Mac's address, and rebuild."
        case .transport(let error, _) where error.code == .notConnectedToInternet:
            "You're offline. Check your connection and try again."
        case .transport(let error, _) where error.code == .cancelled:
            "The request was cancelled. Please try again."
        case .transport(_, let server):
            "Can't reach the server at \(server). Check that it's running, that your iPhone and Mac are on the same network, and that Local Network access is allowed in Settings."
        case .server(let status, let message):
            message ?? "The server returned an error (\(status))."
        case .decoding:
            "The server sent a response the app couldn't read."
        }
    }
}
