class VideoLoader {
    private let session: URLSession
    private let cache = NSCache<NSString, NSData>()
    
    init() {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(memoryCapacity: 50_000_000, // 50MB
                                       diskCapacity: 100_000_000, // 100MB
                                       diskPath: "video_cache")
        self.session = URLSession(configuration: configuration)
    }
    
    func loadVideo(from url: URL) async throws -> AVAsset {
        // AVAsset 생성 시 로딩 옵션 설정
        let assetOptions = [
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
            AVURLAssetAllowsAirPlayKey: false
        ]
        
        let asset = AVURLAsset(url: url, options: assetOptions)
        
        // 필요한 트랙만 로드
        await asset.loadTracks(withMediaType: .video)
        
        return asset
    }
    
    func streamVideo(from url: URL) -> AVPlayerItem {
        let asset = AVURLAsset(url: url)
        
        // 버퍼링 설정
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 5 // 5초만 버퍼링
        
        return playerItem
    }
} 