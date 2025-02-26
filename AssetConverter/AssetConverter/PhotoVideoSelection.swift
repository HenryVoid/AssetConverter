//
//  PhotoVideoSelection.swift
//  AssetConverter
//
//  Created by 송형욱 on 2/26/25.
//

import UIKit
import Foundation

// 비디오 앨범 외부 모델
class PhotoVideoSelection: Codable, Hashable {
    static func == (lhs: PhotoVideoSelection, rhs: PhotoVideoSelection) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    var id: String
    var url: URL
    var thumbnailImage: UIImage?
    var thumbnailData: Data?
    var data: Data?
    var duration: String?
    
    init(id: String = UUID().uuidString, url: URL) {
        self.id = id + ".mp4"
        self.url = url.saveVideoToLocal() ?? url
        self.data = try? Data(contentsOf: url)
        self.thumbnailImage = url.generateThumbnail()
    }
    
    private enum CodingKeys: String, CodingKey {
        case id
        case data
        case url
        case duration
        case thumbnailData
    }
    
    required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? values.decode(String.self, forKey: .id)) ?? UUID().uuidString
        if let data = try? values.decode(Data.self, forKey: .data) {
            self.data = data
        }
        if let thumbnailData = try? values.decode(Data.self, forKey: .thumbnailData) {
            self.thumbnailData = thumbnailData
            thumbnailImage = UIImage(data: thumbnailData)
        }
        url = URL(string: (try? values.decode(String.self, forKey: .url)) ?? "") ?? URL(fileURLWithPath: "")
        duration = try? values.decode(String.self, forKey: .duration)
    }
    
    func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<PhotoVideoSelection.CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(data, forKey: .data)
        try container.encodeIfPresent(thumbnailImage?.pngData(), forKey: .thumbnailData)
        try container.encodeIfPresent(url.absoluteString, forKey: .url)
        try container.encodeIfPresent(duration, forKey: .duration)
    }
}

extension PhotoVideoSelection {
    static var mock: PhotoVideoSelection {
        return .init(url: URL(string: "https://d77ciwg3j0241.cloudfront.net/video/card/67bc44dde83ed5642fc1cd5e/MP4_20250224_190721_8768573206367597235.mp4")!)
    }
}
