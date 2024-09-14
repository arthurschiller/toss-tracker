//
//  GameManager.swift
//  Toss Tracker
//
//  Created by Arthur Schiller on 14.09.24.
//

import UIKit
import Combine
import Vision

// MARK: - GameManager
@Observable
class GameManager {
    private(set) var score: Int = 0
    private var wasBallPreviouslyInAir: Bool = false
    private var timestampOfLastCount: Date?
    
    var onGameOver: (() -> Void)?
    
    // Call this function to update the manager with the latest predictions
    func update(predictions: [ObjectDetectionManager.PredictionResult]) {
        
        let currentTimeStamp = Date()
        
        // Check if the ball is currently detected in the air
        let isBallCurrentlyInAir: Bool = {
            guard let ballInAirPrediction = predictions.first(where: { $0.isBallInAir }) else {
                return false
            }
            return ballInAirPrediction.confidence > 0.65
        }()
        
        let timeSinceLastCatch: TimeInterval? = {
            if let timestampOfLastCount {
                return currentTimeStamp.timeIntervalSince(timestampOfLastCount)
            }
            return nil
        }()
        
//        print("timeSinceLastCatch: \(timeSinceLastCatch)")
        
        if let timeSinceLastCatch, timeSinceLastCatch > 1.5 {
            print("Game Over!")
            onGameOver?()
            return
        }
        
        if isBallCurrentlyInAir, let timeSinceLastCatch {
            guard timeSinceLastCatch > 0.05 else {
                print("Too short of a time difference. Ignoring...")
                return
            }
        }
        
        // Handle state transitions: air -> ground
        if wasBallPreviouslyInAir && !isBallCurrentlyInAir {
            // Ball was in the air and now it's not -> count this as a successful throw
            score += 1
            print("Throw detected! Current score: \(score)")
            timestampOfLastCount = currentTimeStamp
        }
        
        // Update previous state
        wasBallPreviouslyInAir = isBallCurrentlyInAir
    }
    
    func reset() {
        timestampOfLastCount = nil
        wasBallPreviouslyInAir = false
        score = 0
    }
}
