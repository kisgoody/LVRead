import UIKit

final class ZodiacCoverOverlay {
    static let shared = ZodiacCoverOverlay()
    private init() {}

    /// Overlay zodiac image onto a cover image and return the combined image
    func overlayZodiac(_ zodiac: ZodiacAnimal, onto coverImage: UIImage, size: CGSize? = nil) -> UIImage? {
        guard let zodiacImage = zodiac.loadImageCompat() else { return nil }

        let targetSize = size ?? coverImage.size
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { ctx in
            // Draw original cover
            coverImage.draw(in: CGRect(origin: .zero, size: targetSize))

            let scale = max(targetSize.width / zodiacImage.size.width, targetSize.height / zodiacImage.size.height)
            let imageSize = CGSize(width: zodiacImage.size.width * scale, height: zodiacImage.size.height * scale)
            let imageRect = CGRect(
                x: (targetSize.width - imageSize.width) / 2,
                y: (targetSize.height - imageSize.height) / 2,
                width: imageSize.width,
                height: imageSize.height
            )
            zodiacImage.draw(in: imageRect, blendMode: .softLight, alpha: 0.55)
        }
    }

    /// Regenerate the book's cover image with zodiac overlay and save it
    func regenerateCover(for book: Book, zodiac: ZodiacAnimal) {
        let image: UIImage
        if let coverPath = book.resolvedCoverPath(),
           let coverImage = UIImage(contentsOfFile: coverPath) {
            image = coverImage
        } else {
            image = generatePlaceholder(for: book)
        }

        guard let combined = overlayZodiac(zodiac, onto: image) else { return }

        let coversDir = BookImportManager.shared.coversDirectory()
        let fileName = "\(book.id)_zodiac.png"
        let filePath = (coversDir as NSString).appendingPathComponent(fileName)
        if let data = combined.pngData() {
            try? data.write(to: URL(fileURLWithPath: filePath))
            let relativePath = "LVReadCovers/\(fileName)"
            BookRepository.shared.updateCover(bookId: book.id, coverPath: relativePath)
            if let oldPath = book.resolvedCoverPath() {
                ImageCacheManager.shared.removeImage(forKey: oldPath)
            }
        }
    }

    private func generatePlaceholder(for book: Book) -> UIImage {
        let size = CGSize(width: 200, height: 270)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors: [CGColor]
            switch book.fileFormat {
            case .epub: colors = [UIColor.lvPrimary.cgColor, UIColor.lvPrimaryLight.cgColor]
            case .pdf: colors = [UIColor.lvSecondary.cgColor, UIColor.lvSecondaryLight.cgColor]
            case .txt: colors = [UIColor.lvAccent.cgColor, UIColor.lvAccentLight.cgColor]
            case .mobi, .azw3: colors = [UIColor.categoryNovelStart.cgColor, UIColor.categoryNovelEnd.cgColor]
            }
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
    }
}
