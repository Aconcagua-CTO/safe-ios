//
//  IdenticonView.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 21.10.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit
import BlockiesSwift
import Kingfisher

extension UIImageView {

    /// Sets the image to a blockies pattern generated from the `value`.
    /// - Parameter value: address to use. Must be hexadecimal and lowercased.
    func setAddress(_ value: String, width: CGFloat = 250, height: CGFloat = 250) {
        let provider = BlockiesImageProvider(seed: value, width: width, height: height)
        let processor = RoundCornerImageProcessor(radius: .widthFraction(0.5))
        kf.setImage(with: provider, options: [.processor(processor)])
        self.alpha = 1.0
    }
    
    /// Sets the image to a blockies pattern generated from the `value`.
    /// - Parameter value: address to use. Must be hexadecimal and lowercased.
    func setAddressGrayscale(_ value: String, width: CGFloat = 250, height: CGFloat = 250) {
        let provider = BlockiesImageProvider(seed: value, width: width, height: height)
        let processor = RoundCornerImageProcessor(radius: .widthFraction(0.5)) |> BlackWhiteProcessor()
        kf.setImage(with: provider, options: [.processor(processor)])
        self.alpha = 0.3
    }

    /// Loads the image from URL or sets a placeholder image instead.
    /// The image will be cropped as a circle.
    ///
    /// - Parameters:
    ///   - url: url to load image from
    ///   - placeholder: placeholder image
    func setCircleShapeImage(url: URL?, placeholder: UIImage?) {
        kf.setImage(with: url,
                    placeholder: placeholder,
                    options: [.processor(RoundCornerImageProcessor(radius: .widthFraction(0.5)))])
    }

    /// Sets the image from URL or uses blocky for the address if image can't be loaded
    func setCircleImage(url: URL?, placeholderName: String? = nil, address: Address) {
        let imageStart = Date()
        VaultLogger.debug("[IMAGE] setCircleImage called for address \(address.hexadecimal.prefix(10))... with URL: \(url?.absoluteString ?? "nil")")

        let blockyProvider = BlockiesImageProvider(seed: address.hexadecimal)
        let circleProcessor = RoundCornerImageProcessor(radius: .widthFraction(0.5))

        // If we have a URL, try to load it first, fallback to blocky if it fails
        if let url = url {
            VaultLogger.debug("[IMAGE] Attempting to load image from URL: \(url.absoluteString)")
            kf.setImage(with: url, options: [.processor(circleProcessor)]) { [weak self] result in
                let urlLoadTime = Date().timeIntervalSince(imageStart)
                switch result {
                case .success:
                    VaultLogger.debug("[IMAGE] URL image loaded successfully in \(String(format: "%.3f", urlLoadTime))ms")
                case .failure(let error):
                    VaultLogger.debug("[IMAGE] URL image failed (\(String(format: "%.3f", urlLoadTime))ms), falling back to Blockies")
                    self?.kf.setImage(with: blockyProvider, options: [.processor(circleProcessor)])
                }
            }
        } else {
            VaultLogger.debug("[IMAGE] No URL provided, using Blockies directly")
            // No URL, use blocky directly
            kf.setImage(with: blockyProvider, options: [.processor(circleProcessor)])
        }

        let setupTime = Date().timeIntervalSince(imageStart)
        VaultLogger.debug("[IMAGE] setCircleImage setup completed in \(String(format: "%.3f", setupTime))ms")
    }

    func setImage(url: URL?, placeholder: UIImage?, failedImage: UIImage?) {
        kf.setImage(with: url, placeholder: placeholder) { [weak self, weak placeholder] result in
            do {
                _ = try result.get()
            } catch {
                self?.image = placeholder
            }
        }

    }
}

extension UIImage {
    func circleShape() -> UIImage? {
        // https://stackoverflow.com/questions/7705879/ios-create-a-uiimage-or-uiimageview-with-rounded-corners
        let imageLayer = CALayer()
        imageLayer.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        imageLayer.contents = cgImage
        imageLayer.masksToBounds = true
        imageLayer.cornerRadius = min(size.width, size.height) / 2
        UIGraphicsBeginImageContext(size)
        imageLayer.render(in: UIGraphicsGetCurrentContext()!)
        let roundedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return roundedImage
    }
}

/// Generates a blockies image from a seed and provides for use in kingfisher.
/// This allows to use Kingfisher's caching and image processing features.
struct BlockiesImageProvider: ImageDataProvider {
    var seed: String
    var blockSize: UInt = 8
    var width: CGFloat = 250
    var height: CGFloat = 250
    var cacheKey: String { "\(seed)@\(blockSize)-\(width)x\(height)" }

    private static var imageCache = [String: UIImage]()

    func data(handler: @escaping (Result<Data, Error>) -> Void) {
        let blockiesStart = Date()
        VaultLogger.debug("[BLOCKIES] Starting Blockies generation for seed \(seed.prefix(10))...")

        // Generate image on background thread to avoid blocking main thread
        DispatchQueue.global(qos: .userInitiated).async {
            let imageGenStart = Date()
            if let image = self.image(), let data = image.pngData() {
                let imageGenTime = Date().timeIntervalSince(imageGenStart)
                VaultLogger.debug("[BLOCKIES] Blockies image generated successfully in \(String(format: "%.3f", imageGenTime))ms")
                DispatchQueue.main.async {
                    let totalTime = Date().timeIntervalSince(blockiesStart)
                    VaultLogger.debug("[BLOCKIES] Blockies generation completed in \(String(format: "%.3f", totalTime))ms total")
                    handler(.success(data))
                }
            } else {
                let imageGenTime = Date().timeIntervalSince(imageGenStart)
                VaultLogger.debug("[BLOCKIES] Blockies image generation failed after \(String(format: "%.3f", imageGenTime))ms")
                DispatchQueue.main.async {
                    let totalTime = Date().timeIntervalSince(blockiesStart)
                    VaultLogger.debug("[BLOCKIES] Blockies generation failed in \(String(format: "%.3f", totalTime))ms total")
                    handler(.failure(NSError(domain: "BlockiesImageProvider", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create blockies for \(seed)"])))
                }
            }
        }
    }

    func image() -> UIImage? {
        let cacheKey = self.cacheKey

        // Check cache first
        if let cachedImage = BlockiesImageProvider.imageCache[cacheKey] {
            return cachedImage
        }

        // Generate image
        let size = blockSize == 0 ? 8 : blockSize
        let blockies = Blockies(
            seed: seed,
            size: Int(size),
            scale: Int(min(width, height) / CGFloat(size))
        )

        if let image = blockies.createImage() {
            // Cache the image
            BlockiesImageProvider.imageCache[cacheKey] = image
            return image
        }

        return nil
    }
}

extension UIImage {
    static func generateQRCode(value: String, size: CGSize = .init(width: 150, height: 150)) -> UIImage {
        let data = Data(value.utf8)
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")

        if let outputImage = filter.outputImage {
            let scaleX = size.width / outputImage.extent.size.width;
            let scaleY = size.height / outputImage.extent.size.height;
            let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            if let cgimg = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return UIImage(cgImage: cgimg)
            }
        }
        return UIImage(systemName: "xmark.circle") ?? UIImage()
    }
}
