//
//  ARViewContainer.swift
//  Toss Tracker
//
//  Created by Arthur Schiller on 14.09.24.
//


#if !os(visionOS)
import SwiftUI
import RealityKit
import ARKit
import Combine

struct ARViewContainer: UIViewRepresentable {
    class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView? {
            didSet {
                subscription?.cancel()
                subscription = arView?.scene.subscribe(to: SceneEvents.Update.self, { [weak self] _ in
                    guard
                        let self,
                        let cameraFrameEntity = self.cameraFrameEntity,
                        let pixelBuffer = self.arView?.session.currentFrame?.capturedImage
                    else {
                        return
                    }
                    
                    cameraFrameEntity.update(withCameraFramePixelBuffer: pixelBuffer)
                })
            }
        }
        weak var cameraFrameEntity: CameraFeedVisualizationEntity?
        
        private var subscription: Cancellable?
    }
    
    func makeCoordinator() -> Coordinator {
        .init()
    }
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.cameraMode = .ar
        arView.session.delegate = context.coordinator
        arView.renderOptions.insert(.disableDepthOfField)
        arView.renderOptions.insert(.disableMotionBlur)
//        arView.renderOptions.insert(.disableCameraGrain)
//        arView.renderOptions.insert(.disableHDR)
        
        CameraFeedVisualizationComponent.registerComponent()
        
        let cameraFeedVisualizationEntity = CameraFeedVisualizationEntity()
        cameraFeedVisualizationEntity.position.z = -0.4
        let anchorEntity = AnchorEntity(.camera)
        anchorEntity.addChild(cameraFeedVisualizationEntity)
        arView.scene.addAnchor(anchorEntity)
        
        context.coordinator.arView = arView
        context.coordinator.cameraFrameEntity = cameraFeedVisualizationEntity
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Update ARView if needed
    }
    
    static func dismantleUIView(_ uiView: ARView, coordinator: ()) {}
}
#endif
