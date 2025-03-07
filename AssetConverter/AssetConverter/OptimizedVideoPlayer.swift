import SwiftUI
import AVKit

class OptimizedVideoPlayerController: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isLoading = false
    
    private let loader = VideoLoader()
    private let prefetcher = VideoPrefetcher()
    private let compressor = VideoCompressor(url: URL(fileURLWithPath: ""))
    private var playerItem: AVPlayerItem?
    
    // 메모리 관리를 위한 설정
    private let bufferDuration: TimeInterval = 5
    
    func load(url: URL, quality: OptimizedVideoConverter.VideoQuality = .medium) {
        isLoading = true
        
        Task {
            do {
                // 기존 플레이어 정리
                cleanup()
                
                // 최적화된 URL 생성
                let optimizedURL = url.optimizedVideoURL()
                
                // 캐시된 에셋 확인
                if let cachedAsset = prefetcher.getCachedVideo(url: optimizedURL) {
                    await MainActor.run {
                        setupPlayer(with: cachedAsset)
                    }
                    return
                }
                
                // 새로운 에셋 로드
                let asset = try await loader.loadVideo(from: optimizedURL)
                
                // 비디오 압축 (필요한 경우)
                if quality != .high {
                    let compressedVideo = try await compressor.compressVideoToVideo(
                        maxBitrateMbps: quality == .low ? 1.5 : 2.5
                    )
                    if let compressedURL = URL(string: compressedVideo.url) {
                        let compressedAsset = AVAsset(url: compressedURL)
                        await MainActor.run {
                            setupPlayer(with: compressedAsset)
                        }
                        return
                    }
                }
                
                await MainActor.run {
                    setupPlayer(with: asset)
                }
                
                // 캐시에 저장
                await prefetcher.prefetchVideo(url: optimizedURL)
                
            } catch {
                print("비디오 로드 실패: \(error)")
            }
            
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func setupPlayer(with asset: AVAsset) {
        let playerItem = loader.streamVideo(from: asset.url)
        playerItem.preferredForwardBufferDuration = bufferDuration
        
        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = true
        
        self.playerItem = playerItem
        self.player = player
        self.isLoading = false
    }
    
    private func cleanup() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerItem = nil
        player = nil
    }
    
    deinit {
        cleanup()
    }
}

struct OptimizedVideoPlayer: View {
    @StateObject private var controller = OptimizedVideoPlayerController()
    let url: URL
    let quality: OptimizedVideoConverter.VideoQuality
    
    init(url: URL, quality: OptimizedVideoConverter.VideoQuality = .medium) {
        self.url = url
        self.quality = quality
    }
    
    var body: some View {
        ZStack {
            if let player = controller.player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            }
            
            if controller.isLoading {
                ProgressView()
            }
        }
        .onAppear {
            controller.load(url: url, quality: quality)
        }
    }
} 