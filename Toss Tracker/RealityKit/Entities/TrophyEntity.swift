//
//  TrophyEntity.swift
//  Toss Tracker
//
//  Created by Arthur Schiller on 15.09.24.
//

import UIKit
import RealityKit
import SwiftUI

class TrophyEntity: Entity, HasModel, HasPhysics {
    let sourceEntity: Entity
    let confettiOneEntity: Entity
    let confettiTwoEntity: Entity
    let trophyContainerEntity = Entity()
    let audioResource: AudioResource
    
    deinit {
        print("Deinit BallEntity")
    }
    
    init(
        sourceEntity: Entity,
        confettiOneEntity: Entity,
        confettiTwoEntity: Entity,
        audioResource: AudioResource
    ) {
        self.sourceEntity = sourceEntity
        self.confettiOneEntity = confettiOneEntity
        self.confettiTwoEntity = confettiTwoEntity
        self.audioResource = audioResource
        super.init()
        commonInit()
    }
    
    @MainActor @preconcurrency required init() {
        fatalError("init() has not been implemented")
    }
    
    private func commonInit() {
        trophyContainerEntity.opacity = 0
        trophyContainerEntity.transform = .init(
            scale: .init(repeating: 0.5),
            translation: [0, 0, 0]
        )
        
        sourceEntity.position.z = -0.5
        sourceEntity.scale = .init(repeating: 0.25)
        
        trophyContainerEntity.addChild(sourceEntity)
        addChild(trophyContainerEntity)
        
        addChild(confettiOneEntity)
        addChild(confettiTwoEntity)
        
        let colors: [UIColor] = [
            .systemRed,
            .systemBlue,
            .systemCyan,
            .systemOrange,
            .systemGreen,
            .systemYellow,
            .systemPink,
            .systemPurple,
            .systemMint
        ]
        
        let color1 = colors.randomElement()!
        let color2 = colors.randomElement()!
        let color3 = colors.randomElement()!

        confettiOneEntity.visit { entity in
            entity.modifyComponent(forType: ParticleEmitterComponent.self) { comp in
                comp.mainEmitter.color = .constant(.single(color1))
                comp.spawnedEmitter?.color = .constant(.single(color2))
            }
        }
        
        confettiTwoEntity.visit { entity in
            entity.modifyComponent(forType: ParticleEmitterComponent.self) { comp in
                comp.mainEmitter.color = .constant(.single(color2))
                comp.spawnedEmitter?.color = .constant(.single(color3))
            }
        }
        
//        let audioController = trophyEntity.prepareAudio(audioResource)
//        audioController.play()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.playAudio(self.audioResource)
        }
    }
    
    func reveal() {
        makeAnimation(
            targetTransform: .identity,
            targetOpacity: 1
        )
    }
    
    func remove() {
        removeChild(confettiOneEntity)
        removeChild(confettiTwoEntity)
        
        makeAnimation(
            targetTransform: .init(
                scale: .init(repeating: 0.5),
                translation: [0, -0.2, 0]
            ),
            targetOpacity: 0
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: {
            self.removeFromParent()
        })
    }
    
    func makeAnimation(targetTransform: Transform, targetOpacity: Float) {
        let transformAnimation = FromToByAnimation<Transform>(
            from: trophyContainerEntity.transform,
            to: targetTransform,
            duration: 0.5,
            timing: .easeInOut,
            bindTarget: .transform,
            delay: 0.25
        )
        
        let opacityAnimation = FromToByAnimation<Float>(
            from: trophyContainerEntity.opacity,
            to: targetOpacity,
            duration: 0.5,
            timing: .easeInOut,
            isAdditive: false,
            bindTarget: .opacity,
            delay: 0.25
        )

        // Group the animations into one sequence
        let group = AnimationGroup(group: [transformAnimation, opacityAnimation], name: "group")
        let animationResource = try! AnimationResource.generate(with: group)
        
        trophyContainerEntity.playAnimation(animationResource)
    }
}
