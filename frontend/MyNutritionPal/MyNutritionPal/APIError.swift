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
    /// The server answered with a non-2xx status. `code` and `message` come
    /// from its error body; `code` is stable, `message` is for the user.
    case server(status: Int, code: String?, message: String?)
    /// A 2xx response the app couldn't decode.
    case decoding

    /// The error for a non-2xx response. The backend (API v1) sends
    /// {"error": {"code": "...", "message": "..."}}.
    static func from(status: Int, data: Data) -> APIError {
        struct Body: Decodable {
            struct Problem: Decodable {
                let code: String
                let message: String
            }

            let error: Problem
        }

        let problem = (try? JSONDecoder().decode(Body.self, from: data))?.error

        if status == 422 {
            return .server(status: status, code: problem?.code, message: "Some of the information sent wasn't valid.")
        }

        let message = problem?.message.trimmingCharacters(in: .whitespacesAndNewlines)

        return .server(status: status, code: problem?.code, message: message?.isEmpty == false ? message : nil)
    }

    /// True when a request was cancelled (e.g. its task ended). Cancellation
    /// isn't a failure the user needs to hear about, so callers drop it.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if case .transport(let urlError, _) = error as? APIError {
            return urlError.code == .cancelled
        }
        return false
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
        case .server(let status, _, let message):
            message ?? "The server returned an error (\(status))."
        case .decoding:
            "The server sent a response the app couldn't read."
        }
    }
}
