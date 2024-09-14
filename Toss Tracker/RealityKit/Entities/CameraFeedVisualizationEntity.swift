//
//  CameraFeedVisualizationEntity.swift
//  Toss Tracker
//
//  Created by Arthur Schiller on 14.09.24.
//

import RealityKit
import MetalKit

struct CameraFeedVisualizationComponent: Component {
    let manager: CameraFeedVisualizationManager
    var didUpdatePlaneMesh = false
    
    var textureResource: TextureResource {
        manager.textureResource
    }
    
    init() async throws {
        self.manager = try await .init()
    }
    
    @MainActor
    mutating func update(
        withCameraFramePixelBuffer pixelBuffer: CVPixelBuffer,
        entity: HasModel
    ) {
        if !didUpdatePlaneMesh {
            let aspectRatio = Float(CVPixelBufferGetHeight(pixelBuffer)) / Float(CVPixelBufferGetWidth(pixelBuffer))
            let size: Float = 0.2
            let planeMesh = MeshResource.generatePlane(
                width: size,
                height: size * aspectRatio,
                cornerRadius: size * 0.05
            )
            entity.model?.mesh = planeMesh
            didUpdatePlaneMesh = true
        }
        manager.update(withCameraFramePixelBuffer: pixelBuffer)
    }
}

class CameraFeedVisualizationEntity: Entity, HasModel {
    required init() {
        super.init()
        commonInit()
    }
    
    private func commonInit() {
        Task { @MainActor in
            do {
                let cameraFeedVisualizationComponent = try await CameraFeedVisualizationComponent()
                
                var material = UnlitMaterial(applyPostProcessToneMap: false)
                material.color = .init(texture: .init(cameraFeedVisualizationComponent.textureResource))
                
                model = .init(
                    mesh: .generatePlane(width: 0.2, height: 0.2),
                    materials: [
                        material
                    ]
                )

                components.set(cameraFeedVisualizationComponent)
            } catch {
                print(error)
            }
        }
    }
    
    func update(
        withCameraFramePixelBuffer pixelBuffer: CVPixelBuffer
    ) {
        Task { @MainActor in
            guard var component = components[CameraFeedVisualizationComponent.self] else {
                return
            }
            component.update(
                withCameraFramePixelBuffer: pixelBuffer,
                entity: self
            )
            components.set(component)
        }
    }
}

