//
//  BallEntity.swift
//  Toss Tracker
//
//  Created by Arthur Schiller on 15.09.24.
//

import UIKit
import RealityKit

class BallEntity: Entity, HasModel, HasPhysics {
    let particleEntity: Entity
    let popAudioResouce: AudioResource
    
    deinit {
        print("Deinit BallEntity")
    }
    
    init(
        particleEntity: Entity,
        popAudioResouce: AudioResource
    ) {
        self.particleEntity = particleEntity
        self.popAudioResouce = popAudioResouce
        super.init()
        commonInit()
    }
    
    @MainActor @preconcurrency required init() {
        fatalError("init() has not been implemented")
    }
    
    private func commonInit() {
        let colors: [UIColor] = [
            .systemRed,
            .systemBlue,
            .systemCyan,
            .systemOrange,
            .systemGreen,
            .systemYellow,
            .systemPink
        ]
        
        let color = colors.randomElement()!
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: color)
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
        
        addChild(particleEntity)
        particleEntity.visit { entity in
            entity.modifyComponent(forType: ParticleEmitterComponent.self) { comp in
                comp.mainEmitter.color = .constant(.single(color))
            }
        }
        
        let audioController = prepareAudio(popAudioResouce)
        audioController.gain = -50
        audioController.play()
    }
}
