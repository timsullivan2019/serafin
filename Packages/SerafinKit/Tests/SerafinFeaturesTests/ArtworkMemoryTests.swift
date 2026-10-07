import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import SerafinFeatures

/// One run, since the memory is shared by the whole app and one test fills it past its limit.
@MainActor @Suite(.serialized) struct ArtworkMemoryTests {
    private func itemID() -> String {
        UUID().uuidString
    }

    /// A small image of one colour, like a loaded backdrop.
    private func backdrop(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: 16, height: 9, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 9))
        return try #require(context.makeImage())
    }

    @Test func aDetailScreenStartsWithTheTintAlreadyMeasured() {
        let id = itemID()
        #expect(ItemDetailModel(id: id).tint == nil)
        ArtworkMemory.remember(.red, for: id)
        #expect(ItemDetailModel(id: id).tint == .red)
    }

    @Test func measuringABackdropRemembersItsTint() throws {
        let id = itemID()
        let model = ItemDetailModel(id: id)
        model.backdropLoaded(try backdrop(red: 0.8, green: 0.1, blue: 0.1))
        let tint = try #require(model.tint)
        #expect(ArtworkMemory.tint(for: id) == tint)
        #expect(ItemDetailModel(id: id).tint == tint)
    }

    @Test func aBackdropAlreadyLoadedIsUsedWhenItIsNearlyBigEnough() {
        let id = itemID()
        // A phone's hero: 402 points wide, its height asking for a backdrop 16:9 of it.
        let home = ArtworkMemory.backdropWidth(for: id, filling: CGSize(width: 402, height: 490))
        let needed: CGFloat = 490 * 16 / 9
        #expect(abs(home - needed) < 0.001)
        // The detail screen, laid out a little taller while it zooms in, takes the same image.
        #expect(ArtworkMemory.backdropWidth(for: id, filling: CGSize(width: 402, height: 541)) == home)
        // A smaller hero takes it too.
        #expect(ArtworkMemory.backdropWidth(for: id, filling: CGSize(width: 402, height: 300)) == home)
    }

    @Test func aMuchBiggerHeroAsksForABiggerBackdrop() {
        let id = itemID()
        let phone = ArtworkMemory.backdropWidth(for: id, filling: CGSize(width: 402, height: 490))
        let tablet = ArtworkMemory.backdropWidth(for: id, filling: CGSize(width: 1194, height: 600))
        #expect(tablet == 1194)
        #expect(tablet > phone * ArtworkMemory.tolerance)
        #expect(ArtworkMemory.backdropWidth(for: id, filling: CGSize(width: 1100, height: 600)) == tablet)
    }

    @Test func nothingIsAskedForBeforeTheHeroHasASize() {
        #expect(ArtworkMemory.backdropWidth(for: itemID(), filling: .zero) == 0)
    }

    @Test func theOldestItemsAreForgottenFirst() {
        let oldest = itemID()
        ArtworkMemory.remember(.blue, for: oldest)
        let recent = itemID()
        ArtworkMemory.remember(.green, for: recent)
        for _ in 1..<ArtworkMemory.limit {
            ArtworkMemory.remember(.gray, for: itemID())
        }
        #expect(ArtworkMemory.tint(for: oldest) == nil)
        #expect(ArtworkMemory.tint(for: recent) == .green)
    }
}
