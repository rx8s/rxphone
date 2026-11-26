import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import RxPhone

/// Tests for exact-duplicate detection used by the "รูปซ้ำ" cleanup card.
@Suite("DuplicateMatcher")
struct DuplicateMatcherTests {

    // MARK: - Fingerprint and pixel comparison

    @Test("The same image always gives the same fingerprint")
    func identicalImages() throws {
        let a = try fingerprint(TestImage.make())
        let b = try fingerprint(TestImage.make())
        #expect(a.pixels == b.pixels)
        #expect(a.mean == b.mean)
        #expect(DuplicateMatcher.isSameImage(a.pixels, b.pixels))
    }

    @Test("A JPEG re-save of the same photo still counts as a duplicate")
    func reencodedCopy() throws {
        let original = TestImage.make()
        let copy = try TestImage.jpegRoundTrip(original, quality: 0.6)
        let a = try fingerprint(original), b = try fingerprint(copy)
        #expect(abs(a.mean - b.mean) <= DuplicateMatcher.meanTolerance)
        #expect(DuplicateMatcher.isSameImage(a.pixels, b.pixels))
        let groups = DuplicateMatcher.groups([
            item(0, original), item(1, copy),
        ])
        #expect(groups == [[0, 1]])
    }

    @Test("Photos that differ only in a small label are not duplicates")
    func smallDifference() throws {
        // Like burst shots or the simulator test frames: same scene, the
        // label in the corner changes.
        let a = TestImage.make(labelOffset: 0)
        let b = TestImage.make(labelOffset: 1)
        let printA = try fingerprint(a), printB = try fingerprint(b)
        #expect(!DuplicateMatcher.isSameImage(printA.pixels, printB.pixels))
        #expect(DuplicateMatcher.groups([item(0, a), item(1, b)]).isEmpty)
    }

    @Test("Unrelated photos are not duplicates")
    func differentImages() throws {
        let a = try fingerprint(TestImage.make(hueShift: 0))
        let b = try fingerprint(TestImage.make(hueShift: 3))
        #expect(!DuplicateMatcher.isSameImage(a.pixels, b.pixels))
    }

    // MARK: - isSameImage thresholds

    @Test("Up to 4 clearly different pixels are tolerated, 5 are not")
    func differingPixelThreshold() {
        let base = [UInt8](repeating: 100, count: 64 * 64)
        #expect(DuplicateMatcher.isSameImage(base, changing(base, count: 4, by: 200)))
        #expect(!DuplicateMatcher.isSameImage(base, changing(base, count: 5, by: 200)))
    }

    @Test("Small brightness noise on every pixel is tolerated")
    func toleranceBoundary() {
        let base = [UInt8](repeating: 100, count: 64 * 64)
        #expect(DuplicateMatcher.isSameImage(base, changing(base, count: base.count, by: 32)))
        #expect(!DuplicateMatcher.isSameImage(base, changing(base, count: base.count, by: 33)))
    }

    @Test("Pixel buffers of different sizes never match")
    func mismatchedSizes() {
        #expect(!DuplicateMatcher.isSameImage([1, 2, 3], [1, 2]))
    }

    // MARK: - Grouping

    @Test("Copies are grouped together, in input order, and singles are dropped")
    func groupsCopies() throws {
        let a = TestImage.make(hueShift: 0)
        let b = TestImage.make(hueShift: 2)
        let c = TestImage.make(hueShift: 4)
        let groups = DuplicateMatcher.groups([
            item("a1", a), item("b1", b), item("a2", a), item("c", c), item("b2", b), item("a3", a),
        ])
        #expect(groups == [["a1", "a2", "a3"], ["b1", "b2"]])
    }

    @Test("Re-saved copies mixed with other photos are still found")
    func reencodedAmongOthers() throws {
        let a = TestImage.make(hueShift: 0)
        let b = TestImage.make(hueShift: 2)
        let groups = DuplicateMatcher.groups([
            item(0, a),
            item(1, b),
            item(2, try TestImage.jpegRoundTrip(a, quality: 0.5)),
            item(3, TestImage.make(labelOffset: 1)),
            item(4, try TestImage.jpegRoundTrip(b, quality: 0.8)),
        ])
        #expect(groups == [[0, 2], [1, 4]])
    }

    @Test("Same content at different pixel sizes is not grouped")
    func differentDimensions() throws {
        let image = TestImage.make()
        let groups = DuplicateMatcher.groups([
            item(0, image, width: 800, height: 800),
            item(1, image, width: 400, height: 400),
        ])
        #expect(groups.isEmpty)
    }

    @Test("No input gives no groups")
    func emptyInput() {
        #expect(DuplicateMatcher.groups([(id: 0, width: 1, height: 1, print: .init(pixels: [], mean: 0))]).isEmpty)
        let none: [(id: Int, width: Int, height: Int, print: DuplicateMatcher.Fingerprint)] = []
        #expect(DuplicateMatcher.groups(none).isEmpty)
    }

    // MARK: - Helpers

    private func fingerprint(_ image: CGImage) throws -> DuplicateMatcher.Fingerprint {
        try #require(DuplicateMatcher.fingerprint(of: image))
    }

    private func item<ID>(_ id: ID, _ image: CGImage, width: Int = 800, height: Int = 800)
        -> (id: ID, width: Int, height: Int, print: DuplicateMatcher.Fingerprint) {
        (id, width, height, DuplicateMatcher.fingerprint(of: image)!)
    }

    private func changing(_ pixels: [UInt8], count: Int, by delta: Int) -> [UInt8] {
        var out = pixels
        for i in 0..<count { out[i] = UInt8(min(Int(out[i]) + delta, 255)) }
        return out
    }
}

/// Draws a test-card style photo: colored bars, a circle, and a dark label
/// box near the right edge (like a frame counter).
enum TestImage {
    static func make(side: Int = 800, labelOffset: Int = 0, hueShift: Int = 0) -> CGImage {
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        let colors: [(CGFloat, CGFloat, CGFloat)] = [
            (1, 1, 1), (0, 1, 1), (1, 0, 1), (0, 0, 1), (1, 1, 0), (0, 1, 0), (1, 0, 0), (0, 0, 0),
        ]
        let bar = CGFloat(side) / CGFloat(colors.count)
        for i in colors.indices {
            let (r, g, b) = colors[(i + hueShift) % colors.count]
            context.setFillColor(red: r, green: g, blue: b, alpha: 1)
            context.fill(CGRect(x: CGFloat(i) * bar, y: 0, width: bar, height: CGFloat(side)))
        }
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setLineWidth(CGFloat(side) / 40)
        context.strokeEllipse(in: CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: 60, dy: 60))

        // The "counter" box, about 10% of the width; its inner mark moves
        // with labelOffset like a changing digit.
        let box = CGRect(x: Double(side) * 0.68, y: Double(side) * 0.45,
                         width: Double(side) * 0.12, height: Double(side) * 0.1)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(box)
        context.setFillColor(gray: 1, alpha: 1)
        let mark = box.width / 3
        context.fill(CGRect(x: box.minX + CGFloat(labelOffset) * mark * 1.5 + mark * 0.25,
                            y: box.minY + box.height * 0.15, width: mark, height: box.height * 0.7))
        return context.makeImage()!
    }

    static func jpegRoundTrip(_ image: CGImage, quality: Double) throws -> CGImage {
        let data = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        let source = try #require(CGImageSourceCreateWithData(data, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }
}
