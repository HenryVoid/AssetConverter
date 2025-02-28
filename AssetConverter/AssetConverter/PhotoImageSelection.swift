//
//  PhotoImageSelection.swift
//  AssetConverter
//
//  Created by 송형욱 on 2/26/25.
//

import Foundation
import UIKit

// 카메라에서 찍힌 이미지와 사진앨범을 핸들링하는 UIImage기반 외부 모델
struct PhotoImageSelection: Sendable, Codable, Hashable {
    
    static func == (lhs: PhotoImageSelection, rhs: PhotoImageSelection) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    var image: UIImage?
    var imageData: Data?
    var id: String = UUID().uuidString
    // 카드 수정시점에서 추가된 이미지인지 판별
    var isAdded: Bool = false
    // 카드 수정 서버가 제공해준 이미지
    var serverImage: DTO.Image?
    // 카드 수정 앨범 pathURL
    var albumPath: String?
    
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
    
    init(from decoder: Decoder) throws {
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
