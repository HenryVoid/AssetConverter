//
//  AssetConverter.swift
//  AssetConverter
//
//  Created by 송형욱 on 2/26/25.
//

import Photos
import UIKit
import AVFoundation

class AssetConverter {
  private func convertImage(asset: PHAsset) async throws -> PhotoImageSelection {
    return try await withCheckedThrowingContinuation { continuation in
      let options = PHImageRequestOptions()
      options.deliveryMode = .highQualityFormat
      options.isNetworkAccessAllowed = true
      options.version = .current
      
      PHImageManager.default().requestImageDataAndOrientation(
        for: asset,
        options: options
      ) { data, dataUTI, _, info in
        if let error = info?[PHImageErrorKey] as? Error {
          continuation.resume(throwing: error)
          return
        }
        
        guard let data = data,
              let image = UIImage(data: data) else {
          continuation.resume(throwing: AssetError.conversionFailed)
          return
        }
        
        let selection = PhotoImageSelection(image: image)
        
        // 파일 타입 확인 및 처리
        if let dataUTI = dataUTI as String? {
          switch dataUTI {
          case "public.webp":
            selection.id = selection.id + ".webp"
            selection.imageData = data // 원본 데이터 유지
          case "com.compuserve.gif":
            if let gifImage = UIImage.gifImageWithData(data) {
              selection.image = gifImage
              selection.id = selection.id + ".gif"
              selection.imageData = data // 원본 데이터 유지
            }
          default:
            // WebP 시그니처 확인
            if data.count > 12 {
              let webpSignature = data.prefix(4) + data[8..<12]
              if webpSignature.elementsEqual("RIFF".data(using: .utf8)! + "WEBP".data(using: .utf8)!) {
                selection.id = selection.id + ".webp"
                selection.imageData = data // 원본 데이터 유지
                break
              }
            }
            // JPEG로 처리
            selection.id = selection.id + ".jpg"
            selection.imageData = image.jpegData(compressionQuality: 1.0)
          }
        } else {
          // 기본값으로 JPEG 처리
          selection.id = selection.id + ".jpg"
          selection.imageData = image.jpegData(compressionQuality: 1.0)
        }
        
        CacheManager.shared.set(image: image, key: selection.id)
        continuation.resume(returning: selection)
      }
    }
  }
  
  private func convertVideo(asset: PHAsset) async throws -> PhotoVideoSelection {
    return try await withCheckedThrowingContinuation { continuation in
      let options = PHVideoRequestOptions()
      options.version = .current
      options.deliveryMode = .highQualityFormat
      options.isNetworkAccessAllowed = true
      
      // 썸네일 이미지를 위한 이미지 옵션
      let imageOptions = PHImageRequestOptions()
      imageOptions.deliveryMode = .highQualityFormat
      imageOptions.isNetworkAccessAllowed = true
      imageOptions.version = .current
      
      // 비디오 에셋 요청
      PHImageManager.default().requestAVAsset(
        forVideo: asset,
        options: options
      ) { [weak self] avAsset, _, info in
        if let error = info?[PHImageErrorKey] as? Error {
          continuation.resume(throwing: error)
          return
        }
        
        guard let urlAsset = avAsset as? AVURLAsset else {
          continuation.resume(throwing: AssetError.conversionFailed)
          return
        }
        
        // 썸네일 이미지 요청
        PHImageManager.default().requestImage(
          for: asset,
          targetSize: PHImageManagerMaximumSize,
          contentMode: .aspectFit,
          options: imageOptions
        ) { thumbnailImage, _ in
          Task {
            let selection = PhotoVideoSelection(id: asset.localIdentifier, url: urlAsset.url)
            
            // 비디오 파일을 로컬에 저장
            if let localURL = urlAsset.url.saveVideoToLocal() {
              selection.url = localURL
              selection.data = try? Data(contentsOf: localURL)
            }
            
            // 썸네일 이미지 설정 및 캐싱
            selection.thumbnailImage = thumbnailImage
            selection.duration = await selection.url.generateFormattedDuration()
            
            if let thumbnailImage {
              selection.thumbnailData = thumbnailImage.jpegData(compressionQuality: 1.0)
              // 썸네일 이미지 캐싱
              CacheManager.shared.set(
                image: thumbnailImage,
                assetType: .jpeg,
                key: selection.id
              )
            }
            
            continuation.resume(returning: selection)
          }
        }
      }
    }
  }
  
  func convert(asset: PHAsset) async throws -> Any {
    switch asset.mediaType {
    case .image:
      return try await convertImage(asset)
    case .video:
      return try await convertVideo(asset)
    default:
      throw AssetError.unsupportedType
    }
  }
}
