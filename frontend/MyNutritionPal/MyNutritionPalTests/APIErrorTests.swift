//
//  APIErrorTests.swift
//  MyNutritionPalTests
//

import Foundation
import Testing
@testable import MyNutritionPal

/// API v1 error bodies are {"error": {"code": ..., "message": ...}}, plus
/// "fields" for validation_failed (pinned by backend/tests/test_v1_errors.py).
struct APIErrorTests {

    private func body(_ json: String) -> Data { Data(json.utf8) }

    @Test func messageIsShownAsIsAndCodeKept() {
        let error = APIError.from(
            status: 504,
            data: body(#"{"error": {"code": "estimation_timeout", "message": "Meal estimation timed out. Please try again."}}"#)
        )

        #expect(error == .server(status: 504, code: "estimation_timeout", message: "Meal estimation timed out. Please try again."))
        #expect(error.errorDescription == "Meal estimation timed out. Please try again.")
    }

    /// A code the app doesn't know yet still shows the server's message.
    @Test func unknownCodeStillShowsTheMessage() {
        let error = APIError.from(
            status: 429,
            data: body(#"{"error": {"code": "something_new", "message": "Slow down."}}"#)
        )

        #expect(error == .server(status: 429, code: "something_new", message: "Slow down."))
    }

    @Test func validationBecomesGenericMessage() {
        let error = APIError.from(
            status: 422,
            data: body(#"{"error": {"code": "validation_failed", "message": "Some of the information sent wasn't valid.", "fields": [{"field": "body.age", "message": "Input should be greater than or equal to 13"}]}}"#)
        )

        #expect(error == .server(status: 422, code: "validation_failed", message: "Some of the information sent wasn't valid."))
    }

    /// The unversioned API's shape isn't read: the app only talks to v1.
    @Test func unversionedDetailBodyFallsBackToStatus() {
        let error = APIError.from(status: 404, data: body(#"{"detail": "Not Found"}"#))

        #expect(error == .server(status: 404, code: nil, message: nil))
        #expect(error.errorDescription == "The server returned an error (404).")
    }

    @Test func nonJSONBodyFallsBackToStatus() {
        let error = APIError.from(status: 500, data: body("<html>Internal Server Error</html>"))

        #expect(error == .server(status: 500, code: nil, message: nil))
        #expect(error.errorDescription == "The server returned an error (500).")
    }

    @Test func emptyBodyFallsBackToStatus() {
        #expect(APIError.from(status: 502, data: Data()).errorDescription
                == "The server returned an error (502).")
    }

    @Test func blankMessageFallsBackToStatus() {
        #expect(APIError.from(status: 400, data: body(#"{"error": {"code": "bad_request", "message": "  "}}"#)).errorDescription
                == "The server returned an error (400).")
    }

    @Test func cannotConnectNamesTheServer() {
        let error = APIError.transport(URLError(.cannotConnectToHost), server: "Erics-Mac.local:8000")
        let message = error.errorDescription ?? ""

        #expect(message.hasPrefix("Can't reach the server at Erics-Mac.local:8000."))
        #expect(!message.contains("NSURLErrorDomain"))
    }

    @Test func timeoutNamesTheServer() {
        let error = APIError.transport(URLError(.timedOut), server: "192.168.1.5:8000")

        #expect(error.errorDescription?.hasPrefix("Can't reach the server at 192.168.1.5:8000.") == true)
    }

    @Test func offlineHasItsOwnMessage() {
        let error = APIError.transport(URLError(.notConnectedToInternet), server: "Erics-Mac.local:8000")

        #expect(error.errorDescription == "You're offline. Check your connection and try again.")
    }

    @Test func decodingHasItsOwnMessage() {
        #expect(APIError.decoding.errorDescription
                == "The server sent a response the app couldn't read.")
    }

    @Test func notConfiguredExplainsTheFix() {
        #expect(APIError.notConfigured.errorDescription?.contains("Config/Local.xcconfig") == true)
    }

    /// Views show `error.localizedDescription`, which must be our message.
    @Test func localizedDescriptionUsesTheMessage() {
        let error: Error = APIError.server(status: 503, code: "estimation_unavailable", message: "Meal estimation is not available right now.")

        #expect(error.localizedDescription == "Meal estimation is not available right now.")
    }

    // MARK: - Cancellation (never shown to the user)

    @Test func cancelledURLErrorIsCancellation() {
        #expect(APIError.isCancellation(APIError.transport(URLError(.cancelled), server: "Mac.local:8000")))
    }

    @Test func swiftCancellationErrorIsCancellation() {
        #expect(APIError.isCancellation(CancellationError()))
    }

    @Test func timeoutIsNotCancellation() {
        #expect(!APIError.isCancellation(APIError.transport(URLError(.timedOut), server: "Mac.local:8000")))
    }

    @Test func serverErrorIsNotCancellation() {
        #expect(!APIError.isCancellation(APIError.server(status: 503, code: nil, message: nil)))
    }
}

struct MultipartBodyTests {

    private func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    @Test func textOnlyHasOneMessagePart() {
        let body = text(APIClient.multipartBody(message: "2 eggs", imageData: nil, boundary: "B"))

        #expect(body == "--B\r\nContent-Disposition: form-data; name=\"message\"\r\n\r\n2 eggs\r\n--B--\r\n")
    }

    @Test func imageAddsAJPEGPartWithTheExactBytes() {
        let image = Data([0xFF, 0xD8, 0xFF, 0x00, 0xD9])
        let body = APIClient.multipartBody(message: "lunch", imageData: image, boundary: "B")

        var expected = Data(
            ("--B\r\nContent-Disposition: form-data; name=\"message\"\r\n\r\nlunch\r\n"
             + "--B\r\nContent-Disposition: form-data; name=\"image\"; filename=\"meal.jpg\"\r\n"
             + "Content-Type: image/jpeg\r\n\r\n").utf8
        )
        expected.append(image)
        expected.append(Data("\r\n--B--\r\n".utf8))

        #expect(body == expected)
    }

    /// A photo meal without text sends no message part at all.
    @Test func noMessageSendsOnlyTheImage() {
        let image = Data([0xFF, 0xD8])
        let body = APIClient.multipartBody(message: nil, imageData: image, boundary: "B")

        var expected = Data(
            ("--B\r\nContent-Disposition: form-data; name=\"image\"; filename=\"meal.jpg\"\r\n"
             + "Content-Type: image/jpeg\r\n\r\n").utf8
        )
        expected.append(image)
        expected.append(Data("\r\n--B--\r\n".utf8))

        #expect(body == expected)
    }

    @Test func nonASCIIMessageIsUTF8() {
        let body = APIClient.multipartBody(message: "crème brûlée 🍮", imageData: nil, boundary: "B")

        #expect(text(body).contains("\r\n\r\ncrème brûlée 🍮\r\n"))
    }
}
