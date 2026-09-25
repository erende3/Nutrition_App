//
//  AppConfigTests.swift
//  MyNutritionPalTests
//

import Foundation
import Testing
@testable import MyNutritionPal

/// The server address comes from the API_BASE_URL build setting, through the
/// APIBaseURL Info.plist key. A bad or missing value must give nil, so the app
/// shows "no server address" instead of calling a wrong URL.
struct AppConfigTests {

    private func baseURL(_ value: Any?) -> URL? {
        AppConfig.baseURL(from: value.map { ["APIBaseURL": $0] } ?? [:])
    }

    @Test func acceptsHTTPURLWithPort() {
        #expect(baseURL("http://Erics-Mac.local:8000")?.absoluteString
                == "http://Erics-Mac.local:8000")
    }

    @Test func acceptsHTTPS() {
        #expect(baseURL("https://api.example.com")?.absoluteString
                == "https://api.example.com")
    }

    @Test func dropsTrailingSlash() {
        #expect(baseURL("http://192.168.1.5:8000/")?.absoluteString
                == "http://192.168.1.5:8000")
    }

    @Test func trimsWhitespace() {
        #expect(baseURL("  http://192.168.1.5:8000 ")?.absoluteString
                == "http://192.168.1.5:8000")
    }

    @Test func emptyValueIsUnset() {
        #expect(baseURL("") == nil)
    }

    @Test func missingKeyIsUnset() {
        #expect(baseURL(nil) == nil)
        #expect(AppConfig.baseURL(from: nil) == nil)
    }

    @Test func nonStringValueIsUnset() {
        #expect(baseURL(8000) == nil)
    }

    /// In an xcconfig, `//` starts a comment, so `http://host` arrives as `http:`.
    @Test func valueTruncatedByXcconfigCommentIsUnset() {
        #expect(baseURL("http:") == nil)
    }

    @Test func urlWithoutHostIsUnset() {
        #expect(baseURL("http:///meals") == nil)
        #expect(baseURL("Erics-Mac.local:8000") == nil)
    }

    @Test func unsupportedSchemeIsUnset() {
        #expect(baseURL("ftp://Erics-Mac.local") == nil)
    }

    /// An unexpanded build setting means the xcconfig wasn't applied.
    @Test func unexpandedBuildSettingIsUnset() {
        #expect(baseURL("$(API_BASE_URL)") == nil)
    }
}
