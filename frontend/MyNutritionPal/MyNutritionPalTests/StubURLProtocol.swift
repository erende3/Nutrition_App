//
//  StubURLProtocol.swift
//  MyNutritionPalTests
//

import Foundation
import Testing

/// Every suite that uses StubURLProtocol is nested in this one, so those
/// suites run one test at a time and never share the stub's state.
@Suite(.serialized) enum StubbedNetwork {}

/// Answers every request of a stubbed URLSession with `handler`, and records
/// the requests. Shared state: suites that use it must be nested in
/// `StubbedNetwork`. The handler runs on URLSession's loading thread, so it
/// may block (to hold a response back) without blocking the test.
///
/// Note: inside a URLProtocol, `request.httpBody` is nil (URLSession moves it
/// to `httpBodyStream`); use `bodyData(of:)` to read it.
final class StubURLProtocol: URLProtocol {
    // Requests can load concurrently, so the shared state is locked.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) private static var _requests: [URLRequest] = []

    static var handler: ((URLRequest) throws -> (Int, Data))? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    static var requests: [URLRequest] {
        get { lock.withLock { _requests } }
        set { lock.withLock { _requests = newValue } }
    }

    static func session() -> URLSession {
        handler = nil
        requests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.withLock { Self._requests.append(request) }

        do {
            guard let handler = Self.handler else {
                throw URLError(.unknown)
            }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
