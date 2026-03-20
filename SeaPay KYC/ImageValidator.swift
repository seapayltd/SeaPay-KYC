//
//  ImageValidator.swift
//  SeaPay KYC
//
//  Validates images before upload
//

import UIKit

enum ImageValidator {
    struct ValidationResult {
        let isValid: Bool
        let error: AppError?
        let compressedData: Data?
    }

    static func validate(_ data: Data) -> ValidationResult {
        // Check format
        guard isJPEGOrPNG(data) else {
            return ValidationResult(isValid: false, error: .invalidImageFormat, compressedData: nil)
        }

        // Check dimensions
        guard let image = UIImage(data: data) else {
            return ValidationResult(isValid: false, error: .invalidImageFormat, compressedData: nil)
        }

        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)

        if width < AppConfiguration.minImageWidth || height < AppConfiguration.minImageHeight {
            return ValidationResult(
                isValid: false,
                error: .imageTooSmall(AppConfiguration.minImageWidth, AppConfiguration.minImageHeight),
                compressedData: nil
            )
        }

        // Compress to JPEG if needed to stay under size limit
        var quality: CGFloat = 0.85
        var compressed = image.jpegData(compressionQuality: quality) ?? data

        while compressed.count > AppConfiguration.maxImageSizeBytes && quality > 0.1 {
            quality -= 0.1
            compressed = image.jpegData(compressionQuality: quality) ?? data
        }

        if compressed.count > AppConfiguration.maxImageSizeBytes {
            return ValidationResult(
                isValid: false,
                error: .imageTooLarge(AppConfiguration.maxImageSizeMB),
                compressedData: nil
            )
        }

        return ValidationResult(isValid: true, error: nil, compressedData: compressed)
    }

    private static func isJPEGOrPNG(_ data: Data) -> Bool {
        guard data.count > 4 else { return false }
        let header = [UInt8](data.prefix(4))

        // JPEG: FF D8 FF
        if header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF {
            return true
        }

        // PNG: 89 50 4E 47
        if header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47 {
            return true
        }

        // HEIC images from PhotosPicker will be converted via UIImage
        // Accept anything UIImage can decode
        return UIImage(data: data) != nil
    }
}
