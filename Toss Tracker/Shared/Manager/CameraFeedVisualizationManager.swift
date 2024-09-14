//
//  CameraFeedVisualizationManager.swift
//  Toss Tracker
//
//  Created by Arthur Schiller on 14.09.24.
//

import RealityKit
import MetalKit

class CameraFeedVisualizationManager {
    let textureResource: TextureResource
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pixelFormat: MTLPixelFormat = .bgra8Unorm
    private var drawableQueue: TextureResource.DrawableQueue?
    
    private var imagePlaneVertexBuffer: MTLBuffer!
    
    private var renderPipelineState: MTLRenderPipelineState?
    private var capturedImageTextureY: CVMetalTexture?
    private var capturedImageTextureCbCr: CVMetalTexture?
    private var capturedImageTextureCache: CVMetalTextureCache?
    
    private let context = CIContext()
    
    // Vertex data for an image plane
    private let imagePlaneVertexData: [Float] = [
        -1.0, -1.0,  0.0, 1.0,
        1.0, -1.0,  1.0, 1.0,
        -1.0,  1.0,  0.0, 0.0,
        1.0,  1.0,  1.0, 0.0,
    ]
    
    init() async throws {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue()
        else {
            throw "Could not create MTLDevice or CommandQueue"
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.textureResource = try await Self.placeholderTextureResource(pixelFormat: pixelFormat)
        commonInit()
    }
    
    private static func placeholderTextureResource(pixelFormat: MTLPixelFormat) async throws -> TextureResource {
        let data = Data([0x00, 0x00, 0x00, 0xFF])
        return try await TextureResource(
            dimensions: .dimensions(width: 1, height: 1),
            format: .raw(pixelFormat: pixelFormat),
            contents: .init(
                mipmapLevels: [
                    .mip(data: data, bytesPerRow: 4)
                ]
            )
        )
    }
}

private extension CameraFeedVisualizationManager {
    func commonInit() {
        renderPipelineState = createRenderipelineState()
        
        // Create captured image texture cache
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        capturedImageTextureCache = textureCache
    }
    
    func createRenderipelineState() -> MTLRenderPipelineState? {
        guard let library = device.makeDefaultLibrary() else { return nil }
        
        let vertexFunction = library.makeFunction(name: "vertex_main")
        let fragmentFunction = library.makeFunction(name: "fragment_main")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = pixelFormat
        
        do {
            return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
            return nil
        }
    }
    
    func makeDrawableQueue(
        withPixelBuffer pixelBuffer: CVPixelBuffer
    ) throws -> TextureResource.DrawableQueue {
        let descriptor = TextureResource.DrawableQueue.Descriptor(
            pixelFormat: pixelFormat,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetWidth(pixelBuffer),
            usage: [
                .shaderRead,
                .shaderWrite,
                .renderTarget
            ],
            mipmapsMode: .none
        )
        let queue = try TextureResource.DrawableQueue(descriptor)
        queue.allowsNextDrawableTimeout = true
        
        print("Create new drawable queue!")
        
        return queue
    }
    
    func createTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        guard let capturedImageTextureCache else {
            return nil
        }
        
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, capturedImageTextureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture)
        
        if status != kCVReturnSuccess {
            texture = nil
        }
        
        return texture
    }
    
    func updateCapturedImageTextures(withPixelBuffer pixelBuffer: CVPixelBuffer) {
        // Create two textures (Y and CbCr) from the provided frame's captured image
        if (CVPixelBufferGetPlaneCount(pixelBuffer) < 2) {
            return
        }
        
        capturedImageTextureY = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat: .r8Unorm, planeIndex:0)
        capturedImageTextureCbCr = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat: .rg8Unorm, planeIndex:1)
    }
}

extension CameraFeedVisualizationManager {
    @MainActor
    func update(
        withCameraFramePixelBuffer pixelBuffer: CVPixelBuffer
    ) {
        do {
            if drawableQueue == nil {
                let drawableQueue = try makeDrawableQueue(withPixelBuffer: pixelBuffer)
                textureResource.replace(withDrawables: drawableQueue)
                self.drawableQueue = drawableQueue
            }
            
            guard
                let drawableQueue
            else {
                return
            }
            
            let drawable = try drawableQueue.nextDrawable()
            
            // Test Render
//            let color = CIImage(color: .init(red: 1, green: 0, blue: 0)).cropped(to: CGRect(origin: .zero, size: .init(width: 256, height: 256)))
//            context.render(color, to: drawable.texture, commandBuffer: nil, bounds: color.extent, colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!)
//            drawable.present()
            
            guard
                let commandBuffer = commandQueue.makeCommandBuffer(),
                let renderPipelineState
            else {
                return
            }
            
            // Create a custom render pass descriptor for rendering into the texture
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .load
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            renderPassDescriptor.renderTargetWidth = drawableQueue.width
            renderPassDescriptor.renderTargetHeight = drawableQueue.height
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
            
            updateCapturedImageTextures(withPixelBuffer: pixelBuffer)
            
            // Set up render command encoder
            guard
                let textureY = capturedImageTextureY,
                let textureCbCr = capturedImageTextureCbCr,
                let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
            else {
                return
            }
            
            // Set pipeline state (vertex + fragment shader)
            renderEncoder.setRenderPipelineState(renderPipelineState)
            
            // Set up vertex buffer for a full-screen quad
            let quadVertices: [Float] = [
                -1.0, -1.0,  0.0, 1.0,  // Bottom-left
                 1.0, -1.0,  0.0, 1.0,  // Bottom-right
                -1.0,  1.0,  0.0, 1.0,  // Top-left
                 1.0,  1.0,  0.0, 1.0   // Top-right
            ]
            
            let vertexBuffer = device.makeBuffer(bytes: quadVertices, length: MemoryLayout<Float>.size * quadVertices.count, options: [])
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureY), index: 1)
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureCbCr), index: 2)
            
            // Draw the quad (2 triangles)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            renderEncoder.endEncoding()
            renderEncoder.popDebugGroup()

            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            drawable.presentOnSceneUpdate()
        } catch {
            print("Error: \(error)")
        }
    }
}
