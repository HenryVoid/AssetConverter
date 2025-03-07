class VideoManager {
    private let loader = VideoLoader()
    private let prefetcher = VideoPrefetcher()
    
    func loadVideoOptimized(from url: URL) async throws -> PhotoVideoSelection {
        let optimizedURL = url.optimizedVideoURL()
        
        // 캐시된 에셋이 있는지 확인
        if let cachedAsset = prefetcher.getCachedVideo(url: optimizedURL) {
            return try await processVideo(asset: cachedAsset)
        }
        
        // 없다면 새로 로드
        let asset = try await loader.loadVideo(from: optimizedURL)
        return try await processVideo(asset: asset)
    }
    
    private func processVideo(asset: AVAsset) async throws -> PhotoVideoSelection {
        let selection = PhotoVideoSelection(id: UUID().uuidString, url: asset.url)
        
        // 썸네일은 필요할 때만 생성
        selection.thumbnailImage = await asset.generateThumbnail()
        selection.duration = await asset.generateFormattedDuration()
        
        return selection
    }
} 