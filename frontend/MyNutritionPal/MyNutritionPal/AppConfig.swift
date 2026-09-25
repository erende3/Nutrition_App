//
//  AppConfig.swift
//  MyNutritionPal
//

import Foundation

/// Build-time settings. The server address is the API_BASE_URL build setting
/// (Config/*.xcconfig, set per developer in Config/Local.xcconfig), copied
/// into the APIBaseURL Info.plist key.
enum AppConfig {
    static let baseURL = baseURL(from: Bundle.main.infoDictionary)

    /// The server address, or nil when it's unset or not an http(s) URL with
    /// a host. Any trailing slash is dropped, so paths can start with "/".
    static func baseURL(from info: [String: Any]?) -> URL? {
        guard var value = (info?["APIBaseURL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return nil
        }

        while value.hasSuffix("/") {
            value.removeLast()
        }

        guard let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased()),
              let host = url.host, !host.isEmpty
        else {
            return nil
        }

        return url
    }
}
