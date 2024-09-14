//
//  MetalCameraView.swift
//  Toss Tracker
//
//  Created by Arthur Schiller on 14.09.24.
//

import SwiftUI
import MetalKit
import ARKit
import MetalPerformanceShaders

struct MetalCameraView: UIViewRepresentable {
    @Binding var pixelBuffer: CVPixelBuffer?
    
    init(pixelBuffer: Binding<CVPixelBuffer?>) {
        self._pixelBuffer = pixelBuffer
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.framebufferOnly = false
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = false
        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        uiView.setNeedsDisplay()
    }

    class Coordinator: NSObject, MTKViewDelegate {
        private var parent: MetalCameraView
        private var textureCache: CVMetalTextureCache?
        private var processARKitTexture = false
        
        init(_ parent: MetalCameraView) {
            let device = MTLCreateSystemDefaultDevice()!
            
            self.parent = parent
            super.init()
            
            CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Handle size change if necessary
        }
        
        func draw(in view: MTKView) {
            guard
                let pixelBuffer = parent.pixelBuffer,
                let drawable = view.currentDrawable,
                let textureCache
            else {
                return
            }
            
            var cvTextureOut: CVMetalTexture?
            
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            
//            print("Width: \(width) Height: \(height)")
            
            let status = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                textureCache,
                pixelBuffer,
                nil,
                .bgra8Unorm,
                width,
                height,
                0,
                &cvTextureOut
            )
            
            if status != kCVReturnSuccess {
                print("Error creating texture from pixel buffer")
                return
            }
            
            guard
                let cvTexture = cvTextureOut,
                var sourceTexture = CVMetalTextureGetTexture(cvTexture)
            else {
                print("Failed to create Metal texture from CVPixelBuffer")
                return
            }
            
            // Get the drawable's texture (the destination for the blit operation)
            let destinationTexture = drawable.texture
            
            // Create a command queue and command buffer
            guard let commandQueue = view.device?.makeCommandQueue() else { return }
            guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
            
            // Resize the texture if needed
            let inputTexture = resizedTextureIfNeeded(sourceTexture: sourceTexture,
                                                      destinationTexture: destinationTexture,
                                                      device: view.device!,
                                                      commandBuffer: commandBuffer)
            
            // Use a blit command encoder to copy the resized texture to the drawable texture
            guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }
            
            // Blit the (possibly resized) texture to the drawable texture
            blitEncoder.copy(from: inputTexture,
                             sourceSlice: 0,
                             sourceLevel: 0,
                             sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                             sourceSize: MTLSize(width: inputTexture.width, height: inputTexture.height, depth: 1),
                             to: destinationTexture,
                             destinationSlice: 0,
                             destinationLevel: 0,
                             destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            
            // End encoding and commit the command buffer
            blitEncoder.endEncoding()
            commandBuffer.present(drawable) // Present the drawable texture on the screen
            commandBuffer.commit()
        }

        func resizedTextureIfNeeded(sourceTexture: MTLTexture, destinationTexture: MTLTexture, device: MTLDevice, commandBuffer: MTLCommandBuffer) -> MTLTexture {
            // Check if the source texture size matches the destination texture size
            if sourceTexture.width == destinationTexture.width && sourceTexture.height == destinationTexture.height {
                // No need to resize, return the original source texture
                return sourceTexture
            }

            // Create a new texture for the resized result
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: destinationTexture.pixelFormat,
                                                                      width: destinationTexture.width,
                                                                      height: destinationTexture.height,
                                                                      mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
            
            guard let resizedTexture = device.makeTexture(descriptor: descriptor) else {
                fatalError("Failed to create resized texture")
            }

            // Create a Metal Performance Shader for resizing
            let lanczos = MPSImageLanczosScale(device: device)

            // Prepare the scale transform
            let scaleTransform = MPSScaleTransform(
                scaleX: Double(destinationTexture.width) / Double(sourceTexture.width),
                scaleY: Double(destinationTexture.height) / Double(sourceTexture.height),
                translateX: 0.0,
                translateY: 0.0
            )
//            lanczos.scaleTransform = scaleTransform
            
            lanczos.encode(
                commandBuffer: commandBuffer,
                sourceTexture: sourceTexture,
                destinationTexture: resizedTexture
            )
            return resizedTexture
        }

    }
}
