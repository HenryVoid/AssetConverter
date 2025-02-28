//
//  VideoCompressor.swift
//  AssetConverter
//
//  Created by 송형욱 on 2/28/25.
//

import Foundation
import AVFoundation

actor VideoCompressor: Sendable {
    var url: URL
    
    init(url: URL) {
        self.url = url
    }
    
    func compressVideoWithBitrateOnly(maxBitrateMbps: Float = 4) async throws -> URL {
        let asset = AVAsset(url: url)
        
        // 임시 파일 URL 생성
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        
        // 기존 파일이 있다면 삭제
        try? FileManager.default.removeItem(at: outputURL)
        
        // 비디오 트랙 가져오기
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            throw ServiceError(errorCode: .custom(.unknown("No video track found")))
        }
        
        // 비디오 크기 가져오기
        let naturalSize = try await targetSize(url)
        let targetSize = calculateTargetSize(originalSize: naturalSize)
        
        // 비트레이트 설정 (Mbps to bps)
        let bitrate = Int(maxBitrateMbps * 1_000_000)
        
        // Writer 설정
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        
        // 비디오 설정
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: targetSize.width,
            AVVideoHeightKey: targetSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalDurationKey: 2
            ]
        ]
        
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)
        
        // Reader의 출력 설정 - 압축되지 않은 포맷 사용
        let readerSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        
        // Reader 설정
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerSettings)
        reader.add(readerOutput)
        
        // 압축 시작
        guard reader.startReading() else {
            throw ServiceError(errorCode: .custom(.unknown("Failed to start reading")))
        }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        // 비디오 데이터 처리
        while let buffer = readerOutput.copyNextSampleBuffer() {
            if writerInput.isReadyForMoreMediaData {
                writerInput.append(buffer)
            }
        }
        
        // 작업 완료
        writerInput.markAsFinished()
        await writer.finishWriting()
        
        // 결과 확인
        guard writer.status == .completed else {
            throw ServiceError(errorCode: .custom(.unknown("Video compression failed: \(writer.error?.localizedDescription ?? "")")))
        }
        
        return outputURL
    }
    
    func targetSize(_ url: URL) async throws -> CGSize {
        let asset = AVAsset(url: url)
        
        // 비디오 트랙 가져오기
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            throw ServiceError(errorCode: .custom(.unknown("No video track found")))
        }
        
        // 비디오 크기 가져오기
        let naturalSize = try await videoTrack.load(.naturalSize)
        return naturalSize
    }
    
    private func calculateTargetSize(originalSize: CGSize) -> CGSize {
        let maxWidth: CGFloat = 720
        let maxHeight: CGFloat = 1280
        
        var targetWidth: CGFloat = originalSize.width
        var targetHeight: CGFloat = originalSize.height
        
        // 최종 크기가 최대 제한을 넘지 않도록 보정
        targetWidth = min(targetWidth, maxWidth)
        targetHeight = min(targetHeight, maxHeight)
        
        return CGSize(width: targetWidth, height: targetHeight)
    }
}
