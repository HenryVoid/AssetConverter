class VideoPrefetcher {
    private let cache = NSCache<NSString, AVAsset>()
    private let loader: VideoLoader
    
    init(loader: VideoLoader = VideoLoader()) {
        self.loader = loader
        cache.countLimit = 5 // 최대 5개 비디오만 캐시
    }
    
    func prefetchVideo(url: URL) async {
        do {
            let asset = try await loader.loadVideo(from: url)
            cache.setObject(asset, forKey: url.absoluteString as NSString)
        } catch {
            print("Prefetch failed: \(error)")
        }
    }
    
    func getCachedVideo(url: URL) -> AVAsset? {
        return cache.object(forKey: url.absoluteString as NSString)
    }
} 