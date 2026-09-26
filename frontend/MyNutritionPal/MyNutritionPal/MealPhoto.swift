//
//  MealPhoto.swift
//  MyNutritionPal
//

import UIKit

/// Meal photos as uploaded: at most 1536 px on the long edge, upright, JPEG
/// at 0.7, without the original's metadata (so no location). The model
/// downsamples larger images anyway, so this mainly cuts the upload size.
enum MealPhoto {
    static let maxPixelLength: CGFloat = 1536
    static let jpegQuality: CGFloat = 0.7

    /// The long edge capped at maxLength, aspect ratio kept, never upscaled,
    /// and never a zero dimension.
    static func targetSize(for size: CGSize, maxLength: CGFloat = maxPixelLength) -> CGSize {
        let scale = min(1, maxLength / max(size.width, size.height))
        return CGSize(
            width: max(1, (size.width * scale).rounded()),
            height: max(1, (size.height * scale).rounded())
        )
    }

    /// The JPEG to upload. Blocking: call it off the main thread.
    static func uploadJPEG(from image: UIImage) -> Data? {
        // image.size is in oriented points, and draw(in:) applies the
        // orientation, so the output is upright.
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let size = targetSize(for: pixels)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // pixels, not points times the screen scale
        format.opaque = true

        // ponytail: draws the fully decoded image; switch to ImageIO
        // thumbnailing if very large library photos cause memory pressure.
        return UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: jpegQuality)
    }
}
