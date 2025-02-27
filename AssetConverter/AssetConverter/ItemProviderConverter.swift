//
//  ItemProviderConverter.swift
//  AssetConverter
//
//  Created by 송형욱 on 2/27/25.
//

import Photos
import UIKit
import AVFoundation

enum MimeType {
  case webp
  case gif
  case jpeg
  case png
  case unknown
  
  var identifier: String {
    switch self {
    case .webp: return "image/webp"
    case .gif: return "image/gif"
    case .jpeg: return "image/jpeg"
    case .png: return "image/png"
    case .unknown: return "application/octet-stream"
    }
  }
  
  var fileExtension: String {
    switch self {
    case .webp: return "webp"
    case .gif: return "gif"
    case .jpeg: return "jpg"
    case .png: return "png"
    case .unknown: return ""
    }
  }
  
  init(url: URL) {
    let pathExtension = url.pathExtension.lowercased()
    switch pathExtension {
    case "webp": self = .webp
    case "gif": self = .gif
    case "jpg", "jpeg": self = .jpeg
    case "png": self = .png
    default:
      // WebP 시그니처 확인
      if let data = try? Data(contentsOf: url),
         data.count > 12 {
        let webpSignature = data.prefix(4) + data[8..<12]
        if webpSignature.elementsEqual("RIFF".data(using: .utf8)! + "WEBP".data(using: .utf8)!) {
          self = .webp
          return
        }
      }
      self = .unknown
    }
  }
}

actor ItemProviderConverter {
  private static func createTempURL(from url: URL) throws -> URL {
    let fileName = "\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString).\(url.pathExtension)"
    let newUrl = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    
    // 기존 파일이 있다면 삭제
    if FileManager.default.fileExists(atPath: newUrl.path) {
      try FileManager.default.removeItem(at: newUrl)
    }
    
    // 파일 복사
    try FileManager.default.copyItem(at: url, to: newUrl)
    return newUrl
  }
  
  @MainActor
  static func loadVideoURL(_ item: NSItemProvider) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      item.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { (url, err) in
        handleURLLoading(url: url, error: err, continuation: continuation)
      }
    }
  }
  
  @MainActor
  static func loadPickerImageURL(_ item: NSItemProvider) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      item.loadItem(forTypeIdentifier: UTType.image.identifier) { (image, error) in
        handleURLLoading(url: image as? URL, error: error, continuation: continuation)
      }
    }
  }
  
  private static func handleURLLoading(
    url: URL?,
    error: Error?,
    continuation: CheckedContinuation<URL, Error>
  ) {
    if let error = error {
      continuation.resume(throwing: error)
      return
    }
    
    guard let url = url else {
      continuation.resume(throwing: ServiceError(errorCode: .custom(.unknown("Failed to load URL"))))
      return
    }
    
    do {
      let newUrl = try createTempURL(from: url)
      continuation.resume(returning: newUrl)
    } catch {
      continuation.resume(throwing: error)
    }
  }
  
  static func convertVideoFromURL(_ url: URL) async throws -> PhotoVideoSelection {
    let (duration, thumbnailImage) = await Task.detached {
      let duration = await url.generateFormattedDuration()
      let thumbnailImage = url.generateThumbnail()
      return (duration, thumbnailImage)
    }.value
    
    return await MainActor.run {
      let selection = PhotoVideoSelection(url: url)
      selection.duration = duration
      
      if let thumbnailImage {
        selection.thumbnailImage = thumbnailImage
        selection.thumbnailData = thumbnailImage.jpegData(compressionQuality: 1.0)
        CacheManager.shared.set(image: thumbnailImage, key: url.absoluteString)
      }
      
      return selection
    }
  }
  
  static func convertImageFromURL(_ url: URL) async throws -> PhotoImageSelection {
    let (data, uiImage) = try await Task.detached {
      let data = try Data(contentsOf: url)
      
      guard let uiImage = UIImage(data: data) else {
        throw ServiceError(errorCode: .custom(.unknown("Failed to create image from data")))
      }
      
      return (data, uiImage)
    }.value
    
    return await MainActor.run {
      let selection = PhotoImageSelection(image: uiImage)
      let mimeType = MimeType(url: url)
      
      switch mimeType {
      case .webp:
        selection.id = selection.id + ".webp"
        selection.imageData = data
      case .gif:
        if let gifImage = UIImage.gifImageWithData(data) {
          selection.image = gifImage
          selection.id = selection.id + ".gif"
          selection.imageData = data
        }
      case .jpeg, .png, .unknown:
        selection.id = selection.id + ".jpg"
        selection.imageData = uiImage.jpegData(compressionQuality: 1.0)
      }
      
      selection.albumPath = url.absoluteString
      CacheManager.shared.set(image: uiImage, key: selection.id)
      
      return selection
    }
  }
}
