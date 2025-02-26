//
//  PhotoImageSelection.swift
//  AssetConverter
//
//  Created by 송형욱 on 2/26/25.
//

import UIKit
import Photos
import AVFoundation
import Kingfisher

// 사진앨범을 핸들링하는 PhotoSelection PHAsset기반 내부 모델
class PhotoAssetSelection: Equatable {
  
  static func == (lhs: PhotoAssetSelection, rhs: PhotoAssetSelection) -> Bool {
    lhs.id == rhs.id
  }
  
  var asset: PHAsset?
  var id: String {
    get {
      return asset?.localIdentifier ?? _id
    }
    set {
      _id = newValue
    }
  }
  
  var isEditing: Bool = false
  
  var isAdded: Bool = false
  
  private var _id: String = ""
  
  var completion: VoidHandler?
  
  func update(asset: PHAsset?, id: String? = nil, isEditing: Bool = false) {
    self.asset = asset
    self.isEditing = isEditing
    
    if let id {
      self.id = id
    }
  }
  
  func getImage(type: PHPhotosImageType, completion: @escaping PHImageHandler) {
    asset?.getAssetImage(type: type, completion: { image, finish in
      completion(image, finish)
    })
  }
}

// 카메라에서 찍힌 이미지와 사진앨범을 핸들링하는 UIImage기반 외부 모델
final class PhotoImageSelection: Equatable, Codable, Hashable {
  
  static func == (lhs: PhotoImageSelection, rhs: PhotoImageSelection) -> Bool {
    lhs.id == rhs.id
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
  
  private(set) var image: UIImage?
  
  var imageData: Data?
  
  var id: String = UUID().uuidString
  
  // 카드 수정시점에서 추가된 이미지인지 판별
  var isAdded: Bool = false
  // 카드 수정 서버가 제공해준 이미지
  var serverImage: DTO.Image?
  // 카드 수정 앨범 pathURL
  var albumPath: String?
  
  var completion: VoidHandler?
  
  init(image: DTO.Image) {
    self.serverImage = image
    self.id = image.fileName
  }
  
  init(image: UIImage, id: String = UUID().uuidString) {
    if let data = image.generateData() {
      self.image = UIImage.gifImageWithData(data) ?? image
    } else {
      self.image = image
    }
    self.imageData = image.generateData()
    self.id = id
  }
  
  private enum CodingKeys: String, CodingKey {
    case imageData
    case id
    case isAdded
  }
  
  required init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    
    imageData = try? values.decode(Data.self, forKey: .imageData)
    if let data = imageData {
      image = UIImage(data: data)
    }
    
    id = (try? values.decode(String.self, forKey: .id)) ?? UUID().uuidString
    isAdded = (try? values.decode(Bool.self, forKey: .isAdded)) ?? false
  }
  
  func encode(to encoder: Encoder) throws {
    var container: KeyedEncodingContainer<PhotoImageSelection.CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encodeIfPresent(imageData, forKey: .imageData)
    try container.encodeIfPresent(isAdded, forKey: .isAdded)
  }
}

extension [PhotoImageSelection] {
  func toDictionary() -> [String: Data] {
    return Dictionary(uniqueKeysWithValues: self.compactMap {
      if let data = $0.imageData,
         let _ = UIImage.gifImageWithData(data) {
        return ($0.id, data)
      }
      if let compressed = $0.image?.compress(targetSizeMB: 0.5) {
        return ($0.id , compressed)
      }
      if let serverImage = $0.serverImage {
        return (serverImage.fileName, Data())
      }
      return nil
    })
  }
  
  func saveImageCaches() -> Self {
    self.forEach { selection in
      if let image = selection.image {
        CacheManager.shared.set(image: image, key: selection.id)
      }
    }
    return self
  }
}

struct PhotoAlbumTitle {
  var name: String
  var count: Int
  var asset: PHAsset?
  var id: String = ""
}
