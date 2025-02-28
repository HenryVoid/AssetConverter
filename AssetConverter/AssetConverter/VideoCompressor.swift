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
  
  func compressVideoToVideo(maxBitrateMbps: Float = 4) async throws -> DTO.Video {
    let compressedURL = try await compressVideoWithBitrateOnly(maxBitrateMbps: maxBitrateMbps)
    
    // 실제 비디오 크기 계산
    let naturalSize = try await targetSize(url)
    let targetSize = calculateTargetSize(originalSize: naturalSize)
    
    // PhotoVideoSelection 생성
    let data = try? Data(contentsOf: compressedURL)
    let selection = PhotoVideoSelection(url: compressedURL, data: data)
    
    return selection.toDTO(
      width: Int(targetSize.width),
      height: Int(targetSize.height)
    )
  }
  
  private func compressVideoWithBitrateOnly(maxBitrateMbps: Float = 4) async throws -> URL {
    let asset = AVAsset(url: url)
    let outputURL = createOutputURL()
    
    // 비디오 트랙 가져오기
    guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
      throw ServiceError(errorCode: .custom(.unknown("No video track found")))
    }
    
    // 비디오 크기 가져오기
    let naturalSize = try await targetSize(url)
    let targetSize = calculateTargetSize(originalSize: naturalSize)
    
    // Writer & Reader 설정
    let writer = try configureWriter(outputURL: outputURL, targetSize: targetSize, bitrate: maxBitrateMbps)
    let reader = try configureReader(asset: asset, videoTrack: videoTrack)
    
    // 압축 실행
    try await compress(reader: reader, writer: writer)
    
    return outputURL
  }
  
  private func createOutputURL() -> URL {
    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("mp4")
    try? FileManager.default.removeItem(at: outputURL)
    return outputURL
  }
  
  private func configureWriter(outputURL: URL, targetSize: CGSize, bitrate: Float) throws -> AVAssetWriter {
    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    
    // 세로 방향으로 크기 조정
    let isLandscape = targetSize.width > targetSize.height
    let finalSize = isLandscape ?
    CGSize(width: targetSize.height, height: targetSize.width) :
    targetSize
    
    let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: finalSize.width,
      AVVideoHeightKey: finalSize.height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: Int(bitrate * 1_000_000),
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoMaxKeyFrameIntervalKey: 30,
        AVVideoExpectedSourceFrameRateKey: 30,
        AVVideoMaxKeyFrameIntervalDurationKey: 2
      ]
    ])
    
    // 가로 영상일 경우 세로로 회전
    if isLandscape {
      writerInput.transform = CGAffineTransform(rotationAngle: .pi/2)
    }
    
    writerInput.expectsMediaDataInRealTime = false
    writer.add(writerInput)
    return writer
  }
  
  private func configureReader(asset: AVAsset, videoTrack: AVAssetTrack) throws -> AVAssetReader {
    let reader = try AVAssetReader(asset: asset)
    let readerSettings: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    ]
    let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerSettings)
    reader.add(readerOutput)
    return reader
  }
  
  private func compress(reader: AVAssetReader, writer: AVAssetWriter) async throws {
    guard reader.startReading() else {
      throw ServiceError(errorCode: .custom(.unknown("Failed to start reading")))
    }
    
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    
    guard let writerInput = writer.inputs.first else {
      throw ServiceError(errorCode: .custom(.unknown("No writer input")))
    }
    
    guard let readerOutput = reader.outputs.first else {
      throw ServiceError(errorCode: .custom(.unknown("No reader output")))
    }
    
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
  }
  
  private func targetSize(_ url: URL) async throws -> CGSize {
    let asset = AVAsset(url: url)
    guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
      throw ServiceError(errorCode: .custom(.unknown("No video track found")))
    }
    return try await videoTrack.load(.naturalSize)
  }
  
  private func calculateTargetSize(originalSize: CGSize) -> CGSize {
    let width: CGFloat = 720
    let height: CGFloat = (originalSize.height / originalSize.width) * width
    return CGSize(width: width, height: height)
  }
}
