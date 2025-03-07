import SwiftUI
import AVKit

class OptimizedVideoPlayerController: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isLoading = false
    @Published private(set) var selection: PhotoVideoSelection?
    
    private let videoManager = VideoManager()
    private let bufferDuration: TimeInterval = 5
    
    func load(url: URL, quality: OptimizedVideoConverter.VideoQuality = .medium) {
        isLoading = true
        
        Task {
            do {
                cleanup()
                
                // VideoManager를 통해 최적화된 비디오와 메타데이터 로드
                let videoSelection = try await videoManager.loadVideoOptimized(from: url)
                
                await MainActor.run {
                    self.selection = videoSelection
                    setupPlayer(with: videoSelection)
                }
            } catch {
                print("비디오 로드 실패: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
    
    private func setupPlayer(with selection: PhotoVideoSelection) {
        let asset = AVURLAsset(url: selection.url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
            AVURLAssetAllowsAirPlayKey: false
        ])
        
        let playerItem = AVPlayerItem(asset: asset)
        configurePlayerItem(playerItem)
        
        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = true
        
        self.player = player
        self.isLoading = false
    }
    
    private func configurePlayerItem(_ playerItem: AVPlayerItem) {
        playerItem.preferredForwardBufferDuration = bufferDuration
        playerItem.preferredMaximumResolution = CGSize(width: 1280, height: 720)
        playerItem.preferredPeakBitRate = 2_000_000 // 2Mbps
    }
    
    private func cleanup() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        selection = nil
    }
    
    deinit {
        cleanup()
    }
}

struct OptimizedVideoPlayer: View {
    @StateObject private var controller = OptimizedVideoPlayerController()
    let url: URL
    let quality: OptimizedVideoConverter.VideoQuality
    let showThumbnail: Bool
    
    init(url: URL, 
         quality: OptimizedVideoConverter.VideoQuality = .medium,
         showThumbnail: Bool = true) {
        self.url = url
        self.quality = quality
        self.showThumbnail = showThumbnail
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
            } else if showThumbnail,
                      let selection = controller.selection,
                      let thumbnail = selection.thumbnailImage {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            
            if controller.isLoading {
                ProgressView()
            }
        }
        .overlay(alignment: .topTrailing) {
            if let duration = controller.selection?.duration {
                Text(duration)
                    .font(.caption)
                    .padding(4)
                    .background(.ultraThinMaterial)
                    .cornerRadius(4)
                    .padding(8)
            }
        }
        .onAppear {
            controller.load(url: url, quality: quality)
        }
    }
} 