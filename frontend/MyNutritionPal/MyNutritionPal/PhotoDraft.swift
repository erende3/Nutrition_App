//
//  PhotoDraft.swift
//  MyNutritionPal
//

import Observation
import UIKit

/// A photo ready to upload, with a preview decoded from the same JPEG.
struct PreparedPhoto {
    let jpeg: Data
    let preview: UIImage
}

/// The meal photo on the Dashboard: picked, prepared off the main thread
/// (`MealPhoto`), cancelled or removed. The newest pick wins; if a pick
/// fails or is cancelled, any earlier photo stays.
@MainActor
@Observable
final class PhotoDraft {
    private(set) var photo: PreparedPhoto?
    private(set) var isPreparing = false
    /// Why the last pick failed. A cancelled pick isn't an error.
    private(set) var error: String?
    /// Which pick the current photo came from. An estimate records it, so
    /// afterwards it clears only the photo it sent.
    private(set) var photoPick = 0

    /// Bumped on every pick and cancel, so only the newest pick's result is kept.
    private var pick = 0
    private var task: Task<Void, Never>?

    /// Starts preparing a picked image, replacing any pick in progress.
    @discardableResult
    func prepare(_ load: @escaping () async -> UIImage?) -> Task<Void, Never> {
        task?.cancel()
        pick += 1
        let thisPick = pick
        isPreparing = true
        error = nil

        let task = Task {
            var prepared: PreparedPhoto?
            var failure = "Couldn't load that photo. Try another one."

            // Cancelling may not stop a library download; a late result is
            // dropped below either way.
            if let image = await load(), !Task.isCancelled {
                failure = "Couldn't prepare that photo. Try another one."
                let jpeg = await Task.detached(priority: .userInitiated) {
                    MealPhoto.uploadJPEG(from: image)
                }.value

                if let jpeg, let preview = UIImage(data: jpeg) {
                    prepared = PreparedPhoto(jpeg: jpeg, preview: preview)
                }
            }

            guard thisPick == pick else { return }
            isPreparing = false

            if let prepared {
                photo = prepared
                photoPick = thisPick
            } else {
                error = failure
            }
        }
        self.task = task
        return task
    }

    /// Stops the pick in progress at once, without an error. Any earlier
    /// photo stays.
    func cancel() {
        task?.cancel()
        task = nil
        pick += 1
        isPreparing = false
    }

    func remove() {
        photo = nil
        error = nil
    }

    /// After a successful estimate: clears the photo it sent, but keeps one
    /// picked while the estimate was running.
    func clearAfterEstimate(sentPick: Int) {
        guard photo != nil, photoPick == sentPick else { return }
        photo = nil
        error = nil
    }
}
