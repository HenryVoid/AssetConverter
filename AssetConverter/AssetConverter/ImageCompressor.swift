//
//  ImageCompressor.swift
//  AssetConverter
//
//  Created by 송형욱 on 2/28/25.
//

import Foundation
import UIKit

enum ImageCompressor {
    static func downsample(data: Data, maxDimension: CGFloat = 2048) throws -> UIImage {
        // 다운샘플링을 위한 이미지 소스 옵션 설정
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            throw ServiceError(errorCode: .custom(.unknown("Failed to create image source")))
        }
        
        // 이미지 크기 정보 획득
        var width: CGFloat = 0
        var height: CGFloat = 0
        
        if let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] {
            width = CGFloat(properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0)
            height = CGFloat(properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0)
        }
        
        let scale = min(maxDimension / width, maxDimension / height, 1.0)
        
        // 다운샘플링 옵션 설정
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max(width, height) * scale)
        ] as [CFString: Any] as CFDictionary
        
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            throw ServiceError(errorCode: .custom(.unknown("Failed to create downsampled image")))
        }
        
        return UIImage(cgImage: downsampledImage)
    }
}

