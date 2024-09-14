//
//  DummyPixelBufferProvider.swift
//  Toss Tracker
//
//  Created by Arthur Schiller on 14.09.24.
//

import AVFoundation
import Combine
import CoreVideo

class DummyPixelBufferProvider: ObservableObject {
    
    // Combine subject to emit CVPixelBuffer
    let pixelBufferPublisher = PassthroughSubject<CVPixelBuffer, Never>()
    
    private var player: AVPlayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    private var currentItem: AVPlayerItem?
    
    // Function to load and loop video from a file URL
    func loadVideo(url: URL) {
        // Create an AVPlayerItem and AVPlayer
        let asset = AVURLAsset(url: url)
        currentItem = AVPlayerItem(asset: asset)
        
        // Create AVPlayerItemVideoOutput with pixel buffer attributes
        let outputSettings: [String: Any] = [
            String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA,
            String(kCVPixelBufferMetalCompatibilityKey): true
        ]
        
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        currentItem?.add(videoOutput!)
        
        // Create an AVPlayer and AVPlayerLooper for looping the video
        let player = AVPlayer(playerItem: currentItem)
        player.play()
        self.player = player
        
        // Set up CADisplayLink to check for new frames
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        displayLink?.add(to: .main, forMode: .common)
        
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            self?.player?.seek(to: CMTime.zero)
            self?.player?.play()
        }
    }
    
    // CADisplayLink callback to check for new pixel buffer
    @objc private func displayLinkFired() {
        guard let videoOutput = videoOutput, let player = player else { return }
        
        // Get the current time of the video item
        let currentTime = player.currentTime()
        
        // Check if there is a new pixel buffer available for the current time
        if videoOutput.hasNewPixelBuffer(forItemTime: player.currentTime()) {
            var presentationTime = CMTime()
            if let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: &presentationTime) {
                // Emit the pixel buffer via Combine subject
                pixelBufferPublisher.send(pixelBuffer)
            }
        }
    }
    
    // Function to cancel the video and CADisplayLink
    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        player?.pause()
        player = nil
    }
}
