import Foundation
import AVFoundation

actor OptimizedVideoURLLoader {
    private let cache: URLCache
    private let session: URLSession
    private let prefetcher: VideoPrefetcher
    
    init(memoryCapacity: Int = 50_000_000, // 50MB
         diskCapacity: Int = 100_000_000) { // 100MB
        
        self.cache = URLCache(memoryCapacity: memoryCapacity,
                            diskCapacity: diskCapacity,
                            diskPath: "video_cache")
        
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = cache
        
        self.session = URLSession(configuration: configuration)
        self.prefetcher = VideoPrefetcher()
    }
    
    func loadVideo(from url: URL, quality: OptimizedVideoConverter.VideoQuality = .medium) async throws -> AVAsset {
        // 캐시된 에셋 확인
        if let cachedAsset = prefetcher.getCachedVideo(url: url) {
            return cachedAsset
        }
        
        // URL 최적화
        let optimizedURL = optimizeVideoURL(url, quality: quality)
        
        // 에셋 로딩 옵션 설정
        let assetOptions = [
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
            AVURLAssetAllowsAirPlayKey: false
        ]
        
        // 비디오 데이터 요청
        let (data, response) = try await downloadVideoData(from: optimizedURL)
        
        // 임시 파일 생성 및 저장
        let tempURL = try await saveTempVideo(data: data, response: response)
        
        // AVAsset 생성
        let asset = AVURLAsset(url: tempURL, options: assetOptions)
        
        // 필요한 트랙만 로드
        await asset.loadTracks(withMediaType: .video)
        
        // 캐시에 저장
        prefetcher.prefetchVideo(url: url)
        
        return asset
    }
    
    private func optimizeVideoURL(_ url: URL, quality: OptimizedVideoConverter.VideoQuality) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        
        // 품질 파라미터 추가
        let qualityValue = "\(Int(quality.resolution))p"
        let qualityQuery = URLQueryItem(name: "quality", value: qualityValue)
        
        // 추가 최적화 파라미터
        let optimizationQueries = [
            URLQueryItem(name: "optimize", value: "1"),
            URLQueryItem(name: "bitrate", value: String(quality.bitrate)),
            qualityQuery
        ]
        
        components?.queryItems = (components?.queryItems ?? []) + optimizationQueries
        return components?.url ?? url
    }
    
    private func downloadVideoData(from url: URL) async throws -> (Data, URLResponse) {
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        return try await session.data(for: request)
    }
    
    private func saveTempVideo(data: Data, response: URLResponse) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        
        try data.write(to: tempURL)
        return tempURL
    }
}

// 사용 예시를 위한 확장
extension OptimizedVideoURLLoader {
    func loadAndProcessVideo(from url: URL) async throws -> PhotoVideoSelection {
        let asset = try await loadVideo(from: url)
        
        return await MainActor.run {
            var selection = PhotoVideoSelection(id: UUID().uuidString, url: asset.url)
            
            // 썸네일 생성
            if let thumbnail = await asset.generateThumbnail() {
                selection.thumbnailImage = thumbnail
                selection.thumbnailData = thumbnail.jpegData(compressionQuality: 0.8)
            }
            
            // 재생 시간 설정
            selection.duration = await asset.generateFormattedDuration()
            
            return selection
        }
    }
} 