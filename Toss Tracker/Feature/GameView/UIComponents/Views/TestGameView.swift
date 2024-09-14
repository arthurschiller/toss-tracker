//
//  TestGameView.swift
//  Toss Tracker
//
//  Created by Arthur Schiller on 14.09.24.
//

#if !os(visionOS)
import SwiftUI
import Combine
import RealityKit

@Observable
class DummyViewModel {
    private(set) var currentPixelBuffer: CVPixelBuffer?
    private(set) var predictions: [ObjectDetectionManager.PredictionResult]?
    
    private var pixelBufferProvider: DummyPixelBufferProvider?
    private var pixelBufferSubscription: AnyCancellable?
    private var objectDetectionManager: ObjectDetectionManager?
    private var objectDetectionPredictionSubscription: AnyCancellable?
    
    init() {
        self.currentPixelBuffer = currentPixelBuffer
        self.objectDetectionManager = .init()
        
        objectDetectionPredictionSubscription = objectDetectionManager?.predictionsSubject
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { predictions in
//                print("New predictions: \(predictions.count)")
                self.predictions = predictions
//                print(predictions)
            })
    }
    
    func loadDummyVideo() {
        guard let url = Bundle.main.url(forResource: "jugglingTestVideo", withExtension: "mov") else {
            fatalError("Video URL not found")
        }
        let pixelBufferProvider = DummyPixelBufferProvider()
        pixelBufferSubscription?.cancel()
        pixelBufferSubscription = pixelBufferProvider.pixelBufferPublisher.sink { [weak self] buffer in
//            print("New dummy video bufferr: \(buffer)")
            self?.currentPixelBuffer = buffer
            self?.objectDetectionManager?.predictUsingVision(pixelBuffer: buffer, isARKitBuffer: false)
        }
        pixelBufferProvider.loadVideo(url: url)
        self.pixelBufferProvider = pixelBufferProvider
    }
}

struct TestGameView: View {
    @State var viewModel: DummyViewModel = .init()
    
    var body: some View {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        iOSView
        #else
        macOSView
        #endif
    }
    
    @ViewBuilder
    var iOSView: some View {
        ARViewContainer()
            .ignoresSafeArea()
    }
    
    @ViewBuilder
    var macOSView: some View {
        VStack {
            MetalCameraView(
                pixelBuffer: .init(get: {
                    viewModel.currentPixelBuffer
                }, set: { _ in })
            )
            .frame(width: 640, height: 360)
            .overlay(content: {
                if let firstPrediction = viewModel.predictions?.first, firstPrediction.isBallInAir {
                    Color(uiColor: .systemGreen).opacity(0.8)
                        .blendMode(.overlay)
                }
            })
            .overlay(alignment: .bottom) {
                VStack {
                    if let predictions = viewModel.predictions, !predictions.isEmpty {
                        ForEach(predictions, id: \.id) { prediction in
                            Text("\(prediction.label) – \(prediction.confidence)")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.primary)
                .padding()
                .background(
                    .thinMaterial
                )
            }
        }
        .padding()
        .task {
            viewModel.loadDummyVideo()
        }
    }
}

//#Preview(windowStyle: .automatic) {
//    ContentView()
//        .environment(AppModel())
//}

#endif
