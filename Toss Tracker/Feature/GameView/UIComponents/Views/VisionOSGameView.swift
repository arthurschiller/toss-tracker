//
//  VisionOSGameView.swift
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

struct VisionOSGameView: View {
    enum ViewAttachment: String {
        case mainView
        case debugView
    }
    
    @State var viewModel: GameViewModel = .init()
    
    @Environment(\.realityKitScene) var scene: RealityKit.Scene?
    
    var body: some View {
        RealityView { content, attachments in
            let cameraFeedVisualizationEntity = viewModel.cameraFeedVisualizationEntity
            
            #if !targetEnvironment(simulator)
            if let debugViewEntity = attachments.entity(for: ViewAttachment.debugView.rawValue) {
                cameraFeedVisualizationEntity.addChild(debugViewEntity)
                debugViewEntity.position = [0, -0.08, 0.05]
            }
            #endif
            
            if let mainViewEntity = attachments.entity(for: ViewAttachment.mainView.rawValue) {
                viewModel.contentContainerEntity.addChild(mainViewEntity)
            }
            
            guard let scene else {
                return
            }
            viewModel.prepare(withContent: content, andScene: scene)
        } update: { _, _ in
        } attachments: {
            Attachment(id: ViewAttachment.mainView.rawValue) {
                mainView
            }
            
            Attachment(id: ViewAttachment.debugView.rawValue) {
                debugView
            }
        }
        .onAppear {
            viewModel.handleViewDidAppear()
        }
    }
    
    @ViewBuilder
    var mainView: some View {
        switch viewModel.viewState {
        case .initializing:
            EmptyView()
        case .preGrame, .gameOver:
            PreGameView(viewModel: viewModel)
//            VStack {
//                Text("Toss Tracker")
//                    .font(.largeTitle)
//                    .fontDesign(.rounded)
//                
//                if viewModel.viewState == .gameOver {
//                    Text("Game Over with Score: \(viewModel.gameManager.score)")
//                }
//                
//                Button("Start Game") {
//                    viewModel.startGame()
//                }
//            }
        case .playing:
            VStack {
                Text("\(viewModel.gameManager.score)")
                    .contentTransition(.numericText())
                    .font(.largeTitle)
                
                Button {
                    viewModel.gameManager.reset()
                } label: {
                    Text("Reset Score")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .animation(.spring, value: viewModel.gameManager.score)
            .padding()
    //        .glassBackgroundEffect(in: Capsule())
        }
    }
    
    func formattedPercentage(_ value: Float) -> String {
        let percentage = value * 100  // Convert to percentage
        return String(format: "%.2f%%", percentage)  // Format as percentage with two decimal places
    }
    
    @ViewBuilder
    var predictionsView: some View {
        let shape = Capsule()
        
        VStack {
            ZStack {
                if let predictions = viewModel.predictions, !predictions.isEmpty {
                    VStack {
                        ForEach(predictions, id: \.id) { prediction in
                            Text("\(prediction.label.description) – \(formattedPercentage(prediction.confidence))")
                        }
                    }
                }
            }
            .foregroundStyle(.primary)
            .padding()
            .frame(width: 400)
            .background {
                if let predictions = viewModel.predictions, predictions.contains(where: { $0.isBallInAir && $0.confidence > 0.6 }) {
                    Color(uiColor: .systemGreen).opacity(0.5)
                        .blendMode(.overlay)
                        .clipShape(shape)
                }
            }
            .glassBackgroundEffect(in: shape)
        }
    }
    
    @ViewBuilder
    var debugView: some View {
        switch viewModel.viewState {
        case .initializing:
            VStack {
                ProgressView("Initializing")
            }
        case .playing:
            makeStatusContainerView {
                predictionsView
                
                if let error = viewModel.error {
                    HStack {
                        Image(systemName: "exclamationmark.bubble.fill")
                        Text("Error: \(error.localizedDescription)")
                    }
                    .foregroundStyle(Color(uiColor: .systemRed))
                }
            }
        case .preGrame, .gameOver:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func makeStatusContainerView(
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        VStack {
            content()
                .padding()
        }
    }
}

//#Preview(immersionStyle: .mixed) {
//    ImmersiveView()
//        .environment(AppModel())
//}
#endif

class BallEntity: Entity, HasModel, HasPhysics {
    deinit {
        print("Deinit BallEntity")
    }
    
    required init() {
        super.init()
        commonInit()
    }
    
    private func commonInit() {
        let colors: [UIColor] = [
            .systemRed,
            .systemBlue,
            .systemOrange,
            .systemGreen,
            .systemYellow,
            .systemPink
        ]
        
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: colors.randomElement()!)
        mat.metallic = 0.2
        mat.roughness = 0.8
        
        let sphereRadius: Float = 0.02
        
        model = .init(
            mesh: .generateSphere(radius: sphereRadius),
            materials: [
                mat
            ]
        )
        
        let shape = ShapeResource.generateSphere(radius: sphereRadius)
        collision = CollisionComponent(shapes: [shape])
        physicsBody = PhysicsBodyComponent(
            shapes: [shape],
            mass: 0.2,
            mode: .dynamic
        )
    }
}
