//
//  MealPhotoTests.swift
//  MyNutritionPalTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import MyNutritionPal

/// Meal photos are uploaded at most 1536 px on the long edge, upright, as
/// JPEG, and without the original's metadata (no location).
struct MealPhotoTests {

    private func cgImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(red: 0.8, green: 0.4, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private func pixelSize(of data: Data) throws -> CGSize {
        let props = try properties(of: data)
        let width = try #require(props[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(props[kCGImagePropertyPixelHeight] as? Int)
        return CGSize(width: width, height: height)
    }

    // MARK: - targetSize

    @Test func landscapeCameraPhotoFitsTheLongEdge() {
        #expect(MealPhoto.targetSize(for: CGSize(width: 4032, height: 3024))
                == CGSize(width: 1536, height: 1152))
    }

    @Test func portraitCameraPhotoFitsTheLongEdge() {
        #expect(MealPhoto.targetSize(for: CGSize(width: 3024, height: 4032))
                == CGSize(width: 1152, height: 1536))
    }

    @Test func smallImageIsNotUpscaled() {
        #expect(MealPhoto.targetSize(for: CGSize(width: 800, height: 600))
                == CGSize(width: 800, height: 600))
    }

    @Test func imageAtTheLimitIsUnchanged() {
        #expect(MealPhoto.targetSize(for: CGSize(width: 1536, height: 1024))
                == CGSize(width: 1536, height: 1024))
    }

    @Test func extremeAspectRatiosNeverReachZero() {
        #expect(MealPhoto.targetSize(for: CGSize(width: 12000, height: 200))
                == CGSize(width: 1536, height: 26))
        #expect(MealPhoto.targetSize(for: CGSize(width: 20000, height: 1))
                == CGSize(width: 1536, height: 1))
    }

    // MARK: - uploadJPEG

    @Test func outputIsAJPEGWithinTheLimitKeepingTheAspectRatio() throws {
        let image = UIImage(cgImage: cgImage(width: 4032, height: 3024))
        let data = try #require(MealPhoto.uploadJPEG(from: image))

        #expect(data.starts(with: [0xFF, 0xD8, 0xFF]))
        #expect(try pixelSize(of: data) == CGSize(width: 1536, height: 1152))
    }

    /// The renderer's default scale is the screen's (3x), which would
    /// silently produce 4608 px images.
    @Test func outputIsSizedInPixelsNotScreenPoints() throws {
        let image = UIImage(cgImage: cgImage(width: 1800, height: 1200), scale: 3, orientation: .up)
        let data = try #require(MealPhoto.uploadJPEG(from: image))

        #expect(try pixelSize(of: data) == CGSize(width: 1536, height: 1024))
    }

    /// Camera photos are often stored landscape with an orientation flag.
    @Test func rotatedPhotoComesOutUpright() throws {
        let image = UIImage(cgImage: cgImage(width: 400, height: 300), scale: 1, orientation: .right)
        let data = try #require(MealPhoto.uploadJPEG(from: image))

        #expect(try pixelSize(of: data) == CGSize(width: 300, height: 400))
        #expect(try properties(of: data)[kCGImagePropertyOrientation] as? Int ?? 1 == 1)
    }

    @Test func locationMetadataIsNotUploaded() throws {
        let original = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(original, UTType.jpeg.identifier as CFString, 1, nil)
        )
        let gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 40.7,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 74.0,
            kCGImagePropertyGPSLongitudeRef: "W",
        ]
        CGImageDestinationAddImage(
            destination, cgImage(width: 200, height: 100),
            [kCGImagePropertyGPSDictionary: gps] as CFDictionary
        )
        #expect(CGImageDestinationFinalize(destination))
        #expect(try properties(of: original as Data)[kCGImagePropertyGPSDictionary] != nil)

        let image = try #require(UIImage(data: original as Data))
        let data = try #require(MealPhoto.uploadJPEG(from: image))

        #expect(try properties(of: data)[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func tinyImageStillProducesAJPEG() throws {
        let data = try #require(MealPhoto.uploadJPEG(from: UIImage(cgImage: cgImage(width: 100, height: 100))))

        #expect(data.starts(with: [0xFF, 0xD8, 0xFF]))
        #expect(try pixelSize(of: data) == CGSize(width: 100, height: 100))
    }
}
