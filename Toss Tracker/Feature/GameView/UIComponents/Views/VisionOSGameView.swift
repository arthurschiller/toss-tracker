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
    
    @Environment(AppModel.self) private var appModel
    @Environment(\.realityKitScene) var scene: RealityKit.Scene?
    
    var body: some View {
        RealityView { content, attachments in
            await viewModel.loadResources()
            
            let cameraFeedVisualizationEntity = viewModel.cameraFeedVisualizationEntity
            
            #if !targetEnvironment(simulator)
            if let debugViewEntity = attachments.entity(for: ViewAttachment.debugView.rawValue) {
                cameraFeedVisualizationEntity.addChild(debugViewEntity)
                debugViewEntity.position = [0, -0.08, 0.05]
            }
            #else
// 
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
        VStack {
            switch viewModel.viewState {
            case .initializing:
                ProgressView()
            case .preGrame:
                PreGameView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale))
            case .playing:
                GamePlayingView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale))
            case .gameOver(let data):
                GameOverView(viewModel: viewModel, data: data)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .frame(width: 800, height: 600)
        .animation(.smooth, value: viewModel.viewState)
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
