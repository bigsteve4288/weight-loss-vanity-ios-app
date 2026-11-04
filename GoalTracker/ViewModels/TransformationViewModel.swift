import Foundation
import Observation
import PhotosUI
import SwiftData
import SwiftUI

@MainActor
@Observable
final class TransformationViewModel {
    var isImporting = false
    var errorMessage: String?

    func importPhoto(from item: PhotosPickerItem, asBaseline: Bool, weight: Double?, existing: [ProgressPhoto], context: ModelContext) async {
        isImporting = true
        defer { isImporting = false }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self),
                  let data = ImageProcessing.downscaledJPEG(raw, maxDimension: 1600)
            else {
                errorMessage = "That photo couldn't be loaded."
                return
            }
            if asBaseline {
                existing.filter(\.isBaseline).forEach { $0.isBaseline = false }
            }
            context.insert(ProgressPhoto(imageData: data, isBaseline: asBaseline, weightLbs: weight))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func makeBaseline(_ photo: ProgressPhoto, among photos: [ProgressPhoto]) {
        photos.forEach { $0.isBaseline = ($0 == photo) }
    }
}
