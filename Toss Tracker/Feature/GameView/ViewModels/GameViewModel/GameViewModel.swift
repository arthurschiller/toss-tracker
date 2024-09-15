//
//  GameViewModel.swift
//  Toss Tracker
//
//  Created by Arthur Schiller on 14.09.24.
//

enum GameEntityResource {
    case ballParticle
    case trophy
    case confettiOne
    case confettiTwo
}

enum GameAudioResource {
    case backgroundMusic
    case pop
    case ping
    case highscore
}

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
        case gameOver(GameOverData)
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
    
    var enableDebugging = false
    
    private var content: RealityViewContent?
    private weak var scene: RealityKit.Scene?
    private(set) var gameManager: GameManager = .init()
    private(set) var speechSynthesizer: SpeechSynthesizer = .init()
    
    private(set) var viewState: ViewState = .initializing
    private(set) var predictions: [ObjectDetectionManager.PredictionResult]?
    private(set) var error: Error?
    
    private(set) var gameEntityResources: [GameEntityResource: Entity] = [:]
    private(set) var gameAudioResources: [GameAudioResource: AudioResource] = [:]
//    private(set) var currentPixelBuffer: CVPixelBuffer?
    
    private var lastBallThrowDirection: BallThrowDirection?
    
    private var arkitSession: ARKitSession?
    private var worldTrackingProvider: WorldTrackingProvider?
    private var cameraFrameProvider: CameraFrameProvider?
    
    private var sceneUpdateSubscription: EventSubscription?
    private var objectDetectionManager: ObjectDetectionManager?
    private var objectDetectionPredictionSubscription: AnyCancellable?
    
    private var scoreChangeSubscription: AnyCancellable?
    
    private var ballVisualizationTimer: AnyCancellable?
    private var bgAudioController: AudioPlaybackController?
    
    init() {
        self.objectDetectionManager = .init()
        
        gameManager.onGameOver = { [weak self] gameOverData in
            self?.endGame(data: gameOverData)
        }
        
        scoreChangeSubscription = gameManager.scoreChangeSubject
            .sink(receiveValue: { [weak self] score in
                guard let self else {
                    return
                }
                guard self.viewState == .playing else {
                    return
                }
                self.handleScoreChange(score: score)
            })
        
        objectDetectionPredictionSubscription = objectDetectionManager?.predictionsSubject
            .receive(on: DispatchQueue.main)
            .throttle(for: .seconds(0.025), scheduler: RunLoop.main, latest: true)
            .sink(receiveValue: { predictions in
                self.predictions = predictions
                self.gameManager.update(predictions: predictions)
            })
        
        #if !targetEnvironment(simulator)
        guard enableDebugging else { return }
        cameraFeedVisualizationEntity.position.y = -0.15
        cameraFeedVisualizationEntity.orientation = .init(angle: Float(Angle(degrees: -10).radians), axis: [1, 0, 0])
        contentContainerEntity.addChild(cameraFeedVisualizationEntity)
        #endif
    }
    
    @MainActor
    func loadResources() async {
        do {
            // load entities
            let ballParticleEntity = try await Entity(
                named: "Particles",
                in: realityKitContentBundle
            ).findEntity(named: "ParticleEmitter")!
            self.gameEntityResources[.ballParticle] = ballParticleEntity
            
            let trophyEntity = try await Entity(
                named: "trophy"
            )
            self.gameEntityResources[.trophy] = trophyEntity
            
            let confettiOneEntity = try await Entity(
                named: "confetti_1"
            )
            self.gameEntityResources[.confettiOne] = confettiOneEntity
            
            let confettiTwoEntity = try await Entity(
                named: "confetti_2"
            )
            self.gameEntityResources[.confettiTwo] = confettiTwoEntity
            
            // load audio resources
            let popAudioResource = try await AudioFileResource(named: "pop.mp3")
            self.gameAudioResources[.pop] = popAudioResource
            
            let backgroundAudioResource = try await AudioFileResource(
                named: "afternoonhype.wav",
                configuration: .init(
                    loadingStrategy: .preload,
                    shouldLoop: true
                )
            )
            self.gameAudioResources[.backgroundMusic] = backgroundAudioResource
            
            let pingAudioResource = try await AudioFileResource(named: "ping.mp3")
            self.gameAudioResources[.ping] = pingAudioResource
            
            let highscoreAudioResource = try await AudioFileResource(named: "highscore.mp3")
            self.gameAudioResources[.highscore] = highscoreAudioResource
        } catch {
            print(error)
            fatalError("Could not load assets.")
        }
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let bgAudioController = self.contentContainerEntity.prepareAudio(self.getAudioResource(ofKind: .backgroundMusic))
            bgAudioController.gain = AudioPlaybackController.volumeInDecibels(volume: 0)
            bgAudioController.play()
            bgAudioController.fade(to: -30, duration: 4)
            self.bgAudioController = bgAudioController
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.startBallVisualization()
        }
        
//        #if targetEnvironment(simulator)
//        self.endGame(data: .init(score: 24, isNewHighscore: true))
//        #endif
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
            viewState != .playing
        else {
            return
        }
        viewState = .playing
        gameManager.reset()
        cameraFeedVisualizationEntity.isEnabled = true
        adjustBGAudioController(isGameRunning: true)
    }
    
    func handleScoreChange(score: Int) {
        // List of motivational phrases
        let motivationalPhrases = [
            "Well done!",
            "Keep it up!",
            "You're on fire!",
            "Awesome job!",
            "Great toss!",
            "You're unstoppable!",
            "Nice work!",
            "You're crushing it!",
            "Fantastic throw!",
            "Amazing!",
            "Way to go!",
            "Keep juggling like a pro!"
        ]
        
        // Check for specific milestones (e.g., every 5 points)
        if score % 5 == 0 {
            // Randomly select a phrase from the list
            let randomPhrase = motivationalPhrases.randomElement() ?? "Keep going!"
            speechSynthesizer.speakText(randomPhrase)
        }
        
        let audioResource = getAudioResource(ofKind: .ping)
        let audioController = contentContainerEntity.prepareAudio(audioResource)
//        audioController.gain = -50
        audioController.play()
    }
    
    func adjustBGAudioController(isGameRunning: Bool) {
        bgAudioController?.fade(to: isGameRunning ? 0 : -30, duration: 3)
    }
    
    func toggle(entity: Entity, isEnabled: Bool, animated: Bool = true) {
        if isEnabled {
            entity.isEnabled = true
        }
    }
    
    func getEntityResource(ofKind kind: GameEntityResource) -> Entity {
        guard let entity = gameEntityResources[kind] else {
            fatalError("Entity Assets not yet loaded.")
        }
        return entity.clone(recursive: true)
    }
    
    func getAudioResource(ofKind kind: GameAudioResource) -> AudioResource {
        guard let resource = gameAudioResources[kind] else {
            fatalError("AudioResources not yet loaded.")
        }
        return resource
    }
    
    func addBall() {
        guard
            let scene,
            viewState == .preGrame
        else {
            return
        }
        
        let throwDirection: BallThrowDirection = {
            if let lastBallThrowDirection {
                return lastBallThrowDirection.opposite
            }
            return BallThrowDirection.allCases.randomElement()!
        }()
        
        lastBallThrowDirection = throwDirection
        
        let ballEntity = BallEntity(
            particleEntity: getEntityResource(ofKind: .ballParticle),
            popAudioResouce: getAudioResource(ofKind: .pop)
        )
//        var targetPosition = contentContainerEntity.position(relativeTo: nil)
//        targetPosition.z -= 0.1
//        print("Target pos: \(targetPosition)")
//        ballEntity.worldPosition = targetPosition
        
        ballEntity.position.z = -0.1
        
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
    
    func endGame(data: GameOverData) {
        viewState = .gameOver(data)
        cameraFeedVisualizationEntity.isEnabled = false
        
        adjustBGAudioController(isGameRunning: false)
        
        var trophy: TrophyEntity?
        
        if data.isNewHighscore {
            let trophyEntity = TrophyEntity(
                sourceEntity: getEntityResource(ofKind: .trophy),
                confettiOneEntity: getEntityResource(ofKind: .confettiOne),
                confettiTwoEntity: getEntityResource(ofKind: .confettiTwo),
                audioResource: getAudioResource(ofKind: .highscore)
            )
            contentContainerEntity.addChild(trophyEntity)
            trophyEntity.reveal()
            trophy = trophyEntity
        }
        
        let waitTime: TimeInterval = data.isNewHighscore ? 5 : 3
        DispatchQueue.main.asyncAfter(deadline: .now() + waitTime) {
            if let trophy {
                trophy.remove()
            }
            self.viewState = .preGrame
        }
    }
    
    func handleViewDidAppear() {
        guard viewState == .initializing else {
            return
        }
        viewState = .preGrame
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
            translation: [0, 0, -0.35]
        )
        let contentContainerEntityTransform = contentContainerEntity.transformMatrix(relativeTo: nil)
        let targetTransform = simd_mul(deviceTransform, offsetTransform.matrix)
        
        contentContainerEntity.setTransformMatrix(
            contentContainerEntityTransform.mix(with: targetTransform, t: 0.01),
            relativeTo: nil
        )
        ballsContainerEntity.worldTransform = contentContainerEntity.worldTransform
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
