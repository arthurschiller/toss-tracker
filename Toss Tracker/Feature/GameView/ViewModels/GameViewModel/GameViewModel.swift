//
//  GameViewModel.swift
//  Toss Tracker
//
//  Created by Arthur Schiller on 14.09.24.
//

#if os(visionOS)
import SwiftUI
import ARKit
import RealityKit
import RealityKitContent
import Combine

@Observable
class GameViewModel {
    enum ViewState: Equatable {
        case initializing
        case preGrame
        case playing
        case gameOver
    }
    
    enum BallThrowDirection: CaseIterable {
        case right
        case left
        
        var opposite: BallThrowDirection {
            switch self {
            case .right:
                return .left
            case .left:
                return .right
            }
        }
    }
    
    let contentContainerEntity = Entity()
    let ballsContainerEntity = Entity()
    let cameraFeedVisualizationEntity: CameraFeedVisualizationEntity = {
        CameraFeedVisualizationComponent.registerComponent()
        return .init()
    }()
    
    private var content: RealityViewContent?
    private weak var scene: RealityKit.Scene?
    private(set) var gameManager: GameManager = .init()
    
    private(set) var viewState: ViewState = .initializing
    private(set) var predictions: [ObjectDetectionManager.PredictionResult]?
    private(set) var error: Error?
//    private(set) var currentPixelBuffer: CVPixelBuffer?
    
    private var lastBallThrowDirection: BallThrowDirection?
    
    private var arkitSession: ARKitSession?
    private var worldTrackingProvider: WorldTrackingProvider?
    private var cameraFrameProvider: CameraFrameProvider?
    
    private var sceneUpdateSubscription: EventSubscription?
    private var objectDetectionManager: ObjectDetectionManager?
    private var objectDetectionPredictionSubscription: AnyCancellable?
    
    private var ballVisualizationTimer: AnyCancellable?
    
    init() {
        self.objectDetectionManager = .init()
        
        gameManager.onGameOver = { [weak self] in
            self?.endGame()
        }
        
        objectDetectionPredictionSubscription = objectDetectionManager?.predictionsSubject
            .receive(on: DispatchQueue.main)
            .throttle(for: .seconds(0.025), scheduler: RunLoop.main, latest: true)
            .sink(receiveValue: { predictions in
                self.predictions = predictions
                self.gameManager.update(predictions: predictions)
            })
        
        #if !targetEnvironment(simulator)
        cameraFeedVisualizationEntity.position.y = -0.15
        cameraFeedVisualizationEntity.orientation = .init(angle: Float(Angle(degrees: -10).radians), axis: [1, 0, 0])
        contentContainerEntity.addChild(cameraFeedVisualizationEntity)
        #endif
    }
    
    func prepare(withContent content: RealityViewContent, andScene scene: RealityKit.Scene) {
        self.content = content
        self.scene = scene
        
        cameraFeedVisualizationEntity.isEnabled = false
        
        contentContainerEntity.position = [0, 1.2, -0.5]
        content.add(contentContainerEntity)
        
        content.add(ballsContainerEntity)
        
        runTrackingProviders()
        
        sceneUpdateSubscription?.cancel()
        sceneUpdateSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.handleSceneUpdate(event: event)
        }
    }
    
    func startBallVisualization() {
        ballVisualizationTimer = Timer.publish(every: 1, tolerance: 0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] time in
                self?.addBall()
            }
    }
    
    func stopBallVisualization() {
        ballVisualizationTimer?.cancel()
    }
    
    func startGame() {
        guard
            viewState == .preGrame || viewState == .gameOver
        else {
            return
        }
        viewState = .playing
        gameManager.reset()
        cameraFeedVisualizationEntity.isEnabled = true
    }
    
    func addBall() {
        guard let scene else {
            return
        }
        
        let throwDirection: BallThrowDirection = {
            if let lastBallThrowDirection {
                return lastBallThrowDirection.opposite
            }
            return BallThrowDirection.allCases.randomElement()!
        }()
        
        lastBallThrowDirection = throwDirection
        
        let ballEntity = BallEntity()
        var targetPosition = contentContainerEntity.position(relativeTo: nil)
        targetPosition.z -= 0.1
        ballEntity.position = targetPosition
        
        ballsContainerEntity.addChild(ballEntity)
        
        var simulationComponent = PhysicsSimulationComponent()
        simulationComponent.gravity = [0, -1, 0]
        ballsContainerEntity.components.set(simulationComponent)
        
        let impulseXOffsetIntensity: Float = 0.025
        let impulseXOffset: Float = throwDirection == .right ? impulseXOffsetIntensity : -impulseXOffsetIntensity
        
        let ballXOffset: Float = 0.1
        ballEntity.position.x = throwDirection == .right ? -ballXOffset : ballXOffset
        ballEntity.applyImpulse([impulseXOffset, 0.1, 0], at: .zero, relativeTo: ballEntity.parent)
        
        ballEntity.opacity = 0
        
        Task { @MainActor in
            await ballEntity.fadeOpacity(
                to: 1,
                duration: 0.5,
                delay: 0,
                timing: .linear,
                scene: scene
            )
            await ballEntity.fadeOpacity(
                to: 0,
                duration: 0.5 ,
                delay: 0.5,
                timing: .linear,
                scene: scene
            )
            ballEntity.removeFromParent()
        }
    }
    
    func endGame() {
        viewState = .gameOver
        cameraFeedVisualizationEntity.isEnabled = false
    }
    
    func handleViewDidAppear() {
        guard viewState == .initializing else {
            return
        }
        viewState = .preGrame
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.startBallVisualization()
        }
    }
    
    private func handleSceneUpdate(event: SceneEvents.Update) {
//        print("worldTrackingProvider state: \(worldTrackingProvider?.state)")
        
        guard
//            viewState == .playing,
            let worldTrackingProvider,
            worldTrackingProvider.state == .running,
            let deviceTransform = worldTrackingProvider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())?.originFromAnchorTransform
        else {
//            print("Could not query device transform")
            contentContainerEntity.isEnabled = false
            return
        }
        
//        var offsetTransform = Transform(
//            translation: [0, -0.15, -0.75]
//        )
//        offsetTransform.rotation = .init(angle: Float(Angle(degrees: -10).radians), axis: [1, 0, 0])
        let offsetTransform = Transform(
            translation: [0, 0, -0.65]
        )
        let contentContainerEntityTransform = contentContainerEntity.transformMatrix(relativeTo: nil)
        let targetTransform = simd_mul(deviceTransform, offsetTransform.matrix)
        
        contentContainerEntity.setTransformMatrix(
            contentContainerEntityTransform.mix(with: targetTransform, t: 0.01),
            relativeTo: nil
        )
        contentContainerEntity.isEnabled = true
    }
    
    private func runTrackingProviders() {
        #if !targetEnvironment(simulator)
        guard CameraFrameProvider.isSupported else {
            print("CameraFrameProvider not supported.")
            return
        }
        let formats = CameraVideoFormat.supportedVideoFormats(for: .main, cameraPositions: [.left])
        #endif
        
        let arkitSession = ARKitSession()
        
        let authorizationTypes: [ARKitSession.AuthorizationType] = {
            #if targetEnvironment(simulator)
            return [.worldSensing]
            #else
            return [.cameraAccess, .worldSensing]
            #endif
        }()
        
        Task {
            let _ = await arkitSession.requestAuthorization(for: authorizationTypes)
            let authorizationResult = await arkitSession.queryAuthorization(for: authorizationTypes)
            
            for (authorizationType, authorizationStatus) in authorizationResult {
                print("Authorization Status for: \(authorizationType): \(authorizationStatus)")
                if authorizationStatus == .denied {
                    print("Authorization denied")
                    return
                }
            }
            
            self.arkitSession = arkitSession
            
            let worldTrackingProvider = WorldTrackingProvider()
            self.worldTrackingProvider = worldTrackingProvider
            
            do {
                #if !targetEnvironment(simulator)
                let cameraFrameProvider = CameraFrameProvider()
                self.cameraFrameProvider = cameraFrameProvider
                
                try await arkitSession.run([cameraFrameProvider, worldTrackingProvider])
                
                if let updates = cameraFrameProvider.cameraFrameUpdates(for: formats[0]) {
                    for await update in updates {
                        guard
                            viewState == .playing,
                            let mainCameraSample = update.sample(for: .left)
                        else {
                            continue
                        }
//                        currentPixelBuffer = mainCameraSample.pixelBuffer
                        objectDetectionManager?.predictUsingVision(
                            pixelBuffer: mainCameraSample.pixelBuffer,
                            isARKitBuffer: true
                        )
                        
                        Task { @MainActor in
                            cameraFeedVisualizationEntity.update(withCameraFramePixelBuffer: mainCameraSample.pixelBuffer)
                        }
                    }
                }
                #else
                try await arkitSession.run([worldTrackingProvider])
                #endif
            } catch {
                print("Error: \(error)")
                self.error = error
            }
        }
    }
}
#endif
