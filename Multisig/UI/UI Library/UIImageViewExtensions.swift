//
//  IdenticonView.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 21.10.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit
import Kingfisher
import CoreImage

extension UIImageView {

    /// Sets the image to a blockies pattern generated from the `value`.
    /// - Parameter value: address to use. Must be hexadecimal and lowercased.
    func setAddress(_ value: String, width: CGFloat = 250, height: CGFloat = 250) {
        applyPlaceholderIdenticon(grayscale: false)
    }
    
    /// Sets a grayscale placeholder for the address.
    func setAddressGrayscale(_ value: String, width: CGFloat = 250, height: CGFloat = 250) {
        applyPlaceholderIdenticon(grayscale: true)
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

    /// Sets the image from URL or uses placeholder for the address if image can't be loaded
    func setCircleImage(url: URL?, placeholderName: String? = nil, address: Address) {
        let imageStart = Date()
        VaultLogger.debug("[IMAGE] setCircleImage called for address \(address.hexadecimal.prefix(10))... with URL: \(url?.absoluteString ?? "nil")")

        let circleProcessor = RoundCornerImageProcessor(radius: .widthFraction(0.5))
        let placeholderImage = (placeholderName.flatMap { UIImage(named: $0) } ?? UIImage(named: "ico-safe-bar-logo"))?
            .circleShape()

        // If we have a URL, try to load it first, fallback to placeholder if it fails
        if let url = url {
            VaultLogger.debug("[IMAGE] Attempting to load image from URL: \(url.absoluteString)")
            kf.setImage(with: url,
                        placeholder: placeholderImage,
                        options: [.processor(circleProcessor)]) { [weak self] result in
                let urlLoadTime = Date().timeIntervalSince(imageStart)
                switch result {
                case .success:
                    VaultLogger.debug("[IMAGE] URL image loaded successfully in \(String(format: "%.3f", urlLoadTime))ms")
                case .failure(let error):
                    VaultLogger.debug("[IMAGE] URL image failed (\(String(format: "%.3f", urlLoadTime))ms), using placeholder. Error: \(error)")
                    self?.image = placeholderImage
                }
            }
        } else {
            VaultLogger.debug("[IMAGE] No URL provided, using placeholder directly")
            image = placeholderImage
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
    
    private func applyPlaceholderIdenticon(grayscale: Bool) {
        guard let baseImage = UIImage(named: "ico-safe-bar-logo") else {
            image = nil
            return
        }
        var processedImage = baseImage.circleShape() ?? baseImage
        if grayscale {
            processedImage = processedImage.grayscale() ?? processedImage
            alpha = 0.3
        } else {
            alpha = 1.0
        }
        image = processedImage
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
    
    func grayscale() -> UIImage? {
        guard let ciImage = CIImage(image: self) else { return nil }
        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(0.0, forKey: kCIInputSaturationKey)
        
        guard let outputImage = filter?.outputImage,
              let cgImage = CIContext().createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
    
    func scaled(to targetSize: CGSize) -> UIImage {
        guard targetSize.width > 0, targetSize.height > 0 else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resizedImage = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resizedImage.withRenderingMode(renderingMode)
    }
}

// Blockies support removed in favor of static placeholders.

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
