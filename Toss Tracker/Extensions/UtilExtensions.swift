//
//  UtilExtensions.swift
//  Toss Tracker
//
//  Created by Arthur Schiller on 14.09.24.
//

import Foundation
import RealityKit
import Combine
 
enum AsyncError: Error {
    case finishedWithoutValue
}
 extension Publisher {
    func async() async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            var finishedWithoutValue = true
            cancellable = first()
                .sink { result in
                    switch result {
                    case .finished:
                        if finishedWithoutValue {
                            continuation.resume(throwing: AsyncError.finishedWithoutValue)
                        }
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                    cancellable?.cancel()
                } receiveValue: { value in
                    finishedWithoutValue = false
                    continuation.resume(with: .success(value))
                }
        }
    }
}

extension String: @retroactive LocalizedError {
    public var errorDescription: String? { return self }
}

extension float4x4 {
    // The identity transform
    static let identity = matrix_identity_float4x4
    
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3.x = translation.x
        columns.3.y = translation.y
        columns.3.z = translation.z
    }
    
    init(scale: SIMD3<Float>) {
        self = matrix_identity_float4x4
        self.scale = scale
    }
    
    /**
     Treats matrix as a (right-hand column-major convention) transform matrix
     and factors out the translation component of the transform.
     */
    var translation: SIMD3<Float> {
        get {
            let translation = columns.3
            return SIMD3<Float>(translation.x, translation.y, translation.z)
        }
        set(newValue) {
            columns.3 = SIMD4<Float>(newValue.x, newValue.y, newValue.z, columns.3.w)
        }
    }
    
    /**
     Factors out the orientation component of the transform.
     */
    var orientation: simd_quatf {
        get {
            var localMatrix = self
            localMatrix.scale = .one
            return simd_quaternion(localMatrix)
        }
        set {
            let translationMatrix = simd_float4x4(translation: translation)
            let rotationMatrix = matrix_float4x4(newValue)
            let scaleMatrix = simd_float4x4(scale: scale)
            self = simd_mul(simd_mul(translationMatrix, rotationMatrix), scaleMatrix)
        }
    }
    
    var scale: SIMD3<Float> {
        get {
            let sx = columns.0
            let sy = columns.1
            let sz = columns.2
            return simd_make_float3(length(sx), length(sy), length(sz))
        }
        set {
            columns.0 = columns.0 * (newValue.x / length(columns.0))
            columns.1 = columns.1 * (newValue.y / length(columns.1))
            columns.2 = columns.2 * (newValue.z / length(columns.2))
        }
    }
    
    ///Linearly interpolates between x and y, taking the value x when t=0 and y when t=1
    func mix(with y: float4x4, t: Float) -> float4x4 {
        var newTransform = simd_float4x4(diagonal: [1,1,1,1])
        
        let x = self
        
        newTransform.orientation = simd_slerp(x.orientation, y.orientation, t)
        newTransform.translation = simd_mix(x.translation, y.translation, .init(repeating: t))
        newTransform.scale = simd_mix(x.scale, y.scale, .init(repeating: t))
        
        return newTransform
    }
}

extension Entity {
    var opacity: Float {
        get {
            return components[OpacityComponent.self]?.opacity ?? 1
        }
        set {
            if !components.has(OpacityComponent.self) {
                components[OpacityComponent.self] = OpacityComponent(opacity: newValue)
            } else {
                components[OpacityComponent.self]?.opacity = newValue
            }
        }
    }
    
    func setOpacityComponentIfNeeded() {
        if !components.has(OpacityComponent.self) {
            components[OpacityComponent.self] = OpacityComponent(opacity: 1)
        }
    }

    @MainActor
    func fadeOpacity(
        to opacity: Float,
        duration: TimeInterval = 0.2,
        delay: TimeInterval = 0,
        timing: AnimationTimingFunction = .linear,
        scene suppliedScene: RealityKit.Scene? = nil
    ) async {
        if !components.has(OpacityComponent.self) {
            components[OpacityComponent.self] = OpacityComponent(opacity: 1)
        }
        
        let animation = FromToByAnimation(
            name: "Entity/setOpacity",
            to: opacity,
            duration: duration,
            timing: timing,
            isAdditive: false,
            bindTarget: .opacity,
            delay: delay
        )
        
        let scene = suppliedScene ?? self.scene
        
        do {
            let animationResource: AnimationResource = try .generate(with: animation)
            let animationPlaybackController = playAnimation(animationResource)
            let _ = try await scene?.publisher(for: AnimationEvents.PlaybackCompleted.self)
                .filter {
                    $0.playbackController == animationPlaybackController
                }
                .async()
        } catch {
            assertionFailure("Could not generate animation: \(error.localizedDescription)")
        }
    }
    
    var worldPosition: SIMD3<Float> {
        get {
            return position(relativeTo: nil)
        }
        set {
            setPosition(newValue, relativeTo: nil)
        }
    }
    
    var worldOrientation: simd_quatf {
        get {
            return orientation(relativeTo: nil)
        }
        set {
            setOrientation(newValue, relativeTo: nil)
        }
    }
    
    var worldScale: SIMD3<Float> {
        get {
            return scale(relativeTo: nil)
        }
        set {
            setScale(newValue, relativeTo: nil)
        }
    }
    
    var worldTransform: float4x4 {
        get {
            return transformMatrix(relativeTo: nil)
        }
        set {
            setTransformMatrix(newValue, relativeTo: nil)
        }
    }
    
    func visit(using block: (Entity) -> Void) {
        block(self)
        for child in children {
            child.visit(using: block)
        }
    }
    
    /// Recursive search of children looking for any descendants with a specific component and calling a closure with them.
    func forEachDescendant<T: Component>(withComponent componentClass: T.Type, _ closure: (Entity, T) -> Void) {
        for child in children {
            if #available(visionOS 1.0, iOS 18.0, *) {
                if let component = child.components[componentClass] {
                    closure(child, component)
                }
            } else {
                if let component = child.components[componentClass] {
                    closure(child, component)
                }
            }
            child.forEachDescendant(withComponent: componentClass, closure)
        }
    }
    
    func component<T: Component>(forType: T.Type) -> T? {
        return components[T.self]
    }
    
    func modifyComponent<T: Component>(forType: T.Type, _ closure: (inout T) -> Void) {
        guard var component = component(forType: T.self) else { return }
        closure(&component)
        components[T.self] = component
    }
}

extension AudioPlaybackController {
    static func volumeInDecibels(volume: Double) -> Double {
        return 20.0 * log10(volume)
    }
}
