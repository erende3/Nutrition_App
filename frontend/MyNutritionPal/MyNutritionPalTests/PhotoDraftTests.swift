//
//  PhotoDraftTests.swift
//  MyNutritionPalTests
//

import Testing
import UIKit
@testable import MyNutritionPal

/// A photo load the test finishes by hand, like a slow library download.
@MainActor
private final class PendingLoad {
    private var continuation: CheckedContinuation<UIImage?, Never>?

    var isWaiting: Bool { continuation != nil }

    func load() async -> UIImage? {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish(_ image: UIImage?) {
        continuation?.resume(returning: image)
        continuation = nil
    }
}

private func image(width: CGFloat) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: 10), format: format)
        .image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: 10))
        }
}

/// Polls until `condition` holds (at most 2 s).
@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// Picking, preparing, cancelling and replacing the meal photo.
@MainActor
struct PhotoDraftTests {

    /// Prepares a photo `width` px wide and waits for it.
    private func prepared(_ draft: PhotoDraft, width: CGFloat) async {
        await draft.prepare { image(width: width) }.value
    }

    @Test func pickedPhotoIsPrepared() async {
        let draft = PhotoDraft()

        await prepared(draft, width: 20)

        #expect(draft.photo?.preview.size.width == 20)
        #expect(!draft.isPreparing)
        #expect(draft.error == nil)
    }

    @Test func isPreparingUntilTheLoadFinishes() async {
        let draft = PhotoDraft()
        let load = PendingLoad()

        let task = draft.prepare { await load.load() }
        await waitUntil { load.isWaiting }
        #expect(draft.isPreparing)

        load.finish(image(width: 20))
        await task.value
        #expect(!draft.isPreparing)
    }

    @Test func newestPickWins() async {
        let draft = PhotoDraft()
        let first = PendingLoad()
        let second = PendingLoad()

        let firstTask = draft.prepare { await first.load() }
        let secondTask = draft.prepare { await second.load() }
        await waitUntil { first.isWaiting && second.isWaiting }

        second.finish(image(width: 20))
        await secondTask.value
        first.finish(image(width: 30))
        await firstTask.value

        #expect(draft.photo?.preview.size.width == 20)
        #expect(!draft.isPreparing)
    }

    @Test func cancelKeepsThePreviousPhotoWithoutAnError() async {
        let draft = PhotoDraft()
        await prepared(draft, width: 20)
        let slow = PendingLoad()

        draft.prepare { await slow.load() }
        await waitUntil { slow.isWaiting }
        draft.cancel()

        #expect(!draft.isPreparing)
        #expect(draft.photo?.preview.size.width == 20)
        #expect(draft.error == nil)
        slow.finish(nil)
    }

    @Test func cancelWithNothingPreparedLeavesNoPhoto() async {
        let draft = PhotoDraft()
        let slow = PendingLoad()

        draft.prepare { await slow.load() }
        await waitUntil { slow.isWaiting }
        draft.cancel()

        #expect(draft.photo == nil)
        #expect(!draft.isPreparing)
        #expect(draft.error == nil)
        slow.finish(nil)
    }

    @Test func lateResultAfterCancelIsIgnored() async {
        let draft = PhotoDraft()
        await prepared(draft, width: 20)
        let slow = PendingLoad()

        let task = draft.prepare { await slow.load() }
        await waitUntil { slow.isWaiting }
        draft.cancel()
        slow.finish(image(width: 30))
        await task.value

        #expect(draft.photo?.preview.size.width == 20)
        #expect(!draft.isPreparing)
        #expect(draft.error == nil)
    }

    @Test func failedLoadKeepsThePreviousPhotoAndSaysSo() async {
        let draft = PhotoDraft()
        await prepared(draft, width: 20)

        await draft.prepare { nil }.value

        #expect(draft.photo?.preview.size.width == 20)
        #expect(draft.error == "Couldn't load that photo. Try another one.")
    }

    @Test func newPickClearsTheOldError() async {
        let draft = PhotoDraft()
        await draft.prepare { nil }.value
        let slow = PendingLoad()

        draft.prepare { await slow.load() }

        #expect(draft.error == nil)
        await waitUntil { slow.isWaiting }
        slow.finish(nil)
    }

    @Test func removeClearsThePhotoAndError() async {
        let draft = PhotoDraft()
        await prepared(draft, width: 20)
        await draft.prepare { nil }.value

        draft.remove()

        #expect(draft.photo == nil)
        #expect(draft.error == nil)
    }

    @Test func clearAfterEstimateClearsTheSentPhoto() async {
        let draft = PhotoDraft()
        await prepared(draft, width: 20)
        let sent = draft.photoPick

        draft.clearAfterEstimate(sentPick: sent)

        #expect(draft.photo == nil)
    }

    @Test func clearAfterEstimateKeepsANewerPick() async {
        let draft = PhotoDraft()
        await prepared(draft, width: 20)
        let sent = draft.photoPick
        await prepared(draft, width: 30)

        draft.clearAfterEstimate(sentPick: sent)

        #expect(draft.photo?.preview.size.width == 30)
    }

    /// A text-only estimate leaves a photo picked while it ran.
    @Test func clearAfterTextOnlyEstimateKeepsAPhotoPickedMeanwhile() async {
        let draft = PhotoDraft()
        let sent = draft.photoPick
        await prepared(draft, width: 20)

        draft.clearAfterEstimate(sentPick: sent)

        #expect(draft.photo?.preview.size.width == 20)
    }
}
