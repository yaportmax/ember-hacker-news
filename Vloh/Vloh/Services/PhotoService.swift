import UIKit
import Foundation

enum PhotoService {
    static func save(_ data: Data, to url: URL) async throws {
        let encoded = try await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { throw VlohError.message("Choose a valid photo.") }
            let side: CGFloat = 480
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let result = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
                UIColor.systemGray5.setFill(); context.fill(CGRect(x: 0, y: 0, width: side, height: side))
                let scale = max(side / image.size.width, side / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
            }
            guard let jpeg = result.jpegData(compressionQuality: 0.8) else { throw VlohError.message("Couldn't save this photo.") }
            return jpeg
        }.value
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded.write(to: url, options: .atomic)
    }
}
