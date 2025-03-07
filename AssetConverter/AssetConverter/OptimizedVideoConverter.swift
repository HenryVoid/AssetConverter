import Foundation
import AVFoundation

protocol OptimizedVideoConverterDelegate: AnyObject {
    func videoConverterDidFinish(url: URL)
    func videoConverterDidFinish(data: Data)
    func videoConverterDidFail(with error: VideoConverterError)
}

enum VideoConverterError: String, Error {
    case inputFileError = "입력 파일 오류"
    case readerInitializationError = "리더 초기화 실패"
    case writerInitializationError = "작성자 초기화 실패"
    case compressionError = "압축 실패"
    case invalidAsset = "잘못된 에셋"
}

class OptimizedVideoConverter {
    weak var delegate: OptimizedVideoConverterDelegate?
    private let processingQueue = DispatchQueue(label: "video.processing.queue")
    private let compressionQueue = DispatchQueue(label: "video.compression.queue", qos: .userInitiated)
    
    enum VideoQuality {
        case low     // 540p, 1.5Mbps
        case medium  // 720p, 2.5Mbps
        case high    // 1080p, 4Mbps
        
        var resolution: CGFloat {
            switch self {
            case .low: return 540
            case .medium: return 720
            case .high: return 1080
            }
        }
        
        var bitrate: Float {
            switch self {
            case .low: return 1.5
            case .medium: return 2.5
            case .high: return 4.0
            }
        }
    }
    
    func compressVideo(at url: URL, quality: VideoQuality = .medium) {
        let asset = AVAsset(url: url)
        processingQueue.async { [weak self] in
            self?.startCompression(asset: asset, quality: quality)
        }
    }
    
    private func startCompression(asset: AVAsset, quality: VideoQuality) {
        guard asset.isReadable, asset.isPlayable else {
            delegate?.videoConverterDidFail(with: .invalidAsset)
            return
        }
        
        do {
            let reader = try configureReader(for: asset)
            let writer = try configureWriter(for: asset, quality: quality)
            
            try compress(reader: reader, writer: writer, quality: quality)
        } catch {
            delegate?.videoConverterDidFail(with: .compressionError)
        }
    }
    
    private func configureReader(for asset: AVAsset) throws -> AVAssetReader {
        let reader = try AVAssetReader(asset: asset)
        
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            throw VideoConverterError.inputFileError
        }
        
        let readerSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerSettings)
        videoOutput.alwaysCopiesSampleData = false
        
        if reader.canAdd(videoOutput) {
            reader.add(videoOutput)
        }
        
        return reader
    }
    
    private func configureWriter(for asset: AVAsset, quality: VideoQuality) throws -> AVAssetWriter {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            throw VideoConverterError.inputFileError
        }
        
        let size = calculateTargetSize(from: videoTrack.naturalSize, quality: quality)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(quality.bitrate * 1_000_000),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineLevel31,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoExpectedSourceFrameRateKey: 24,
                AVVideoAllowFrameReorderingKey: false
            ]
        ]
        
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.transform = videoTrack.preferredTransform
        videoInput.expectsMediaDataInRealTime = false
        
        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }
        
        return writer
    }
    
    private func compress(reader: AVAssetReader, writer: AVAssetWriter, quality: VideoQuality) throws {
        guard reader.startReading() else { throw VideoConverterError.compressionError }
        
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        guard let videoInput = writer.inputs.first else { throw VideoConverterError.compressionError }
        
        let group = DispatchGroup()
        group.enter()
        
        compressionQueue.async {
            while videoInput.isReadyForMoreMediaData {
                autoreleasepool {
                    guard let output = reader.outputs.first,
                          let sampleBuffer = output.copyNextSampleBuffer() else {
                        videoInput.markAsFinished()
                        group.leave()
                        return
                    }
                    videoInput.append(sampleBuffer)
                }
            }
        }
        
        group.wait()
        
        writer.finishWriting { [weak self] in
            guard let self = self else { return }
            if writer.status == .completed {
                self.delegate?.videoConverterDidFinish(url: writer.outputURL)
                if let data = try? Data(contentsOf: writer.outputURL) {
                    self.delegate?.videoConverterDidFinish(data: data)
                }
            } else {
                self.delegate?.videoConverterDidFail(with: .compressionError)
            }
        }
    }
    
    private func calculateTargetSize(from originalSize: CGSize, quality: VideoQuality) -> CGSize {
        let aspectRatio = originalSize.height / originalSize.width
        if originalSize.width > originalSize.height {
            let width = quality.resolution
            return CGSize(width: width, height: width * aspectRatio)
        } else {
            let height = quality.resolution
            return CGSize(width: height / aspectRatio, height: height)
        }
    }
} 