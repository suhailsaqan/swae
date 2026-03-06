//
//  GlobeRenderer.swift
//  swae
//
//  Metal renderer for the globe zoom-out animation.
//  Tile pyramid: draws map tiles as spherical quads on the globe.
//
//  V12: Globe is hidden while tiles cover the screen. Tiles drawn with
//  depth-always-pass to eliminate seams. No tile eviction during animation.
//

import Metal
import MetalKit
import simd

// MARK: - Uniform Buffer (must match GlobeShaders.metal exactly)

struct GlobeUniforms {
    var mvp: matrix_float4x4
    var model: matrix_float4x4
    var normalMatrix: matrix_float3x3
    var cameraPos: SIMD3<Float>
    var padding1: Float
    var anchorWorldPos: SIMD3<Float>
    var patchBlend: Float
    var displacementScale: Float
    var starAlpha: Float
    var phoneAlpha: Float
    var phoneScale: Float
    var personAlpha: Float
    var time: Float
    var desaturationStrength: Float
    var darkenFactor: Float
    var nightLightsIntensity: Float
    var ambientLightIntensity: Float
}

// MARK: - Renderer

final class GlobeRenderer: NSObject, MTKViewDelegate {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    var config: GlobeZoomConfig

    // Pipelines
    private var globePipeline: MTLRenderPipelineState!
    private var tilePipeline: MTLRenderPipelineState!
    private var personPipeline: MTLRenderPipelineState!
    private var phonePipeline: MTLRenderPipelineState!
    private var depthStencilState: MTLDepthStencilState!
    private var noDepthWriteState: MTLDepthStencilState!
    private var depthAlwaysState: MTLDepthStencilState!
    private var linearSampler: MTLSamplerState!

    // Triple-buffered uniforms
    private let maxInflightFrames = 3
    private var uniformBuffers: [MTLBuffer] = []
    private var frameIndex = 0
    private let frameSemaphore: DispatchSemaphore

    // Meshes
    private var globeMesh: GlobeMesh!
    private var quadMesh: GlobeMesh!

    // Tile manager (set by ViewController)
    var tileManager: GlobeTileManager?

    // Textures
    private var globeTexture: MTLTexture?
    private var nightTexture: MTLTexture?
    var personTexture: MTLTexture?
    var phoneTexture: MTLTexture?

    // Billboard param buffers
    private var personParamBuffer: MTLBuffer!
    private var phoneParamBuffer: MTLBuffer!

    // Animation state
    var currentState = GlobeAnimationController.AnimationState(
        altitude: 4.0,
        fovRadians: 45.0 * .pi / 180.0,
        cameraTargetBlend: 1.0,
        floatZoom: 3.0,
        tileLayerAlpha: 0.0,
        tileDesaturation: 0.85,
        tileDarkenFactor: 0.75,
        phoneAlpha: 0,
        personAlpha: 0,
        starAlpha: 0,
        globeRotationY: 0,
        rawProgress: 1.0,
        easedProgress: 1.0
    )
    private var elapsedTime: Float = 0
    private var lastFrameTime: CFTimeInterval = 0

    // MARK: - Init

    init?(metalView: MTKView, config: GlobeZoomConfig) {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        self.config = config
        self.frameSemaphore = DispatchSemaphore(value: maxInflightFrames)
        super.init()

        metalView.device = device
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.depthStencilPixelFormat = .depth32Float
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        metalView.delegate = self
        buildResources(metalView: metalView)
    }

    // MARK: - Public Accessors

    var metalDevice: MTLDevice { device }

    // MARK: - Resource Setup

    private func buildResources(metalView: MTKView) {
        globeMesh = GlobeMeshBuilder.build(
            device: device, radius: config.globeRadius,
            latSegments: config.globeLatSegments, lonSegments: config.globeLonSegments)
        quadMesh = buildQuadMesh()

        guard let library = device.makeDefaultLibrary() else {
            fatalError("GlobeRenderer: Failed to create Metal library")
        }
        let vd = globeMesh.vertexDescriptor

        // Globe pipeline
        let globeDesc = MTLRenderPipelineDescriptor()
        globeDesc.vertexFunction = library.makeFunction(name: "globe_vertex")
        globeDesc.fragmentFunction = library.makeFunction(name: "globe_fragment")
        globeDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        globeDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        globeDesc.vertexDescriptor = vd

        // Tile pipeline — alpha blended
        let tileDesc = MTLRenderPipelineDescriptor()
        tileDesc.vertexFunction = library.makeFunction(name: "tile_vertex")
        tileDesc.fragmentFunction = library.makeFunction(name: "tile_fragment")
        tileDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        tileDesc.colorAttachments[0].isBlendingEnabled = true
        tileDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        tileDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        tileDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        tileDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        tileDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        tileDesc.vertexDescriptor = vd

        // Person pipeline (premultiplied alpha)
        let personDesc = MTLRenderPipelineDescriptor()
        personDesc.vertexFunction = library.makeFunction(name: "billboard_vertex")
        personDesc.fragmentFunction = library.makeFunction(name: "person_fragment")
        personDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        personDesc.colorAttachments[0].isBlendingEnabled = true
        personDesc.colorAttachments[0].sourceRGBBlendFactor = .one
        personDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        personDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        personDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        personDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        personDesc.vertexDescriptor = vd

        // Phone pipeline
        let phoneDesc = MTLRenderPipelineDescriptor()
        phoneDesc.vertexFunction = library.makeFunction(name: "billboard_vertex")
        phoneDesc.fragmentFunction = library.makeFunction(name: "phone_fragment")
        phoneDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        phoneDesc.colorAttachments[0].isBlendingEnabled = true
        phoneDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        phoneDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        phoneDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        phoneDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        phoneDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        phoneDesc.vertexDescriptor = vd

        do {
            globePipeline = try device.makeRenderPipelineState(descriptor: globeDesc)
            tilePipeline = try device.makeRenderPipelineState(descriptor: tileDesc)
            personPipeline = try device.makeRenderPipelineState(descriptor: personDesc)
            phonePipeline = try device.makeRenderPipelineState(descriptor: phoneDesc)
        } catch {
            fatalError("GlobeRenderer: Failed to create pipeline state: \(error)")
        }

        // Depth stencil states
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .lessEqual
        depthDesc.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: depthDesc)

        let noWriteDesc = MTLDepthStencilDescriptor()
        noWriteDesc.depthCompareFunction = .lessEqual
        noWriteDesc.isDepthWriteEnabled = false
        noDepthWriteState = device.makeDepthStencilState(descriptor: noWriteDesc)

        // Depth-always: tiles always pass depth test, no seams from z-offset issues
        let alwaysDesc = MTLDepthStencilDescriptor()
        alwaysDesc.depthCompareFunction = .always
        alwaysDesc.isDepthWriteEnabled = false
        depthAlwaysState = device.makeDepthStencilState(descriptor: alwaysDesc)

        // Sampler
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.mipFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        linearSampler = device.makeSamplerState(descriptor: samplerDesc)

        // Triple-buffered uniforms
        for i in 0..<maxInflightFrames {
            let buf = device.makeBuffer(length: MemoryLayout<GlobeUniforms>.stride, options: .storageModeShared)!
            buf.label = "Uniforms \(i)"
            uniformBuffers.append(buf)
        }

        // Billboard param buffers
        personParamBuffer = device.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared)!
        personParamBuffer.label = "Person Params"
        phoneParamBuffer = device.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared)!
        phoneParamBuffer.label = "Phone Params"

        let personH = config.personModelHeight
        var personParams = SIMD4<Float>(personH * 0.8, personH, 0.00005, 0)
        memcpy(personParamBuffer.contents(), &personParams, MemoryLayout<SIMD4<Float>>.stride)
        var phoneParams = SIMD4<Float>(0.0003, 0.0005, 0.00008, 0)
        memcpy(phoneParamBuffer.contents(), &phoneParams, MemoryLayout<SIMD4<Float>>.stride)

        loadTextures()
    }

    // MARK: - Quad Mesh

    private func buildQuadMesh() -> GlobeMesh {
        let vertices: [GlobeVertex] = [
            GlobeVertex(position: SIMD3(-0.5, -0.5, 0), normal: SIMD3(0, 0, 1), uv: SIMD2(0, 1)),
            GlobeVertex(position: SIMD3( 0.5, -0.5, 0), normal: SIMD3(0, 0, 1), uv: SIMD2(1, 1)),
            GlobeVertex(position: SIMD3(-0.5,  0.5, 0), normal: SIMD3(0, 0, 1), uv: SIMD2(0, 0)),
            GlobeVertex(position: SIMD3( 0.5,  0.5, 0), normal: SIMD3(0, 0, 1), uv: SIMD2(1, 0)),
        ]
        let indices: [UInt32] = [0, 1, 2, 2, 1, 3]
        let vb = device.makeBuffer(bytes: vertices, length: MemoryLayout<GlobeVertex>.stride * 4, options: .storageModeShared)!
        vb.label = "Quad Vertices"
        let ib = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt32>.stride * 6, options: .storageModeShared)!
        ib.label = "Quad Indices"
        return GlobeMesh(vertexBuffer: vb, indexBuffer: ib, indexCount: 6, vertexDescriptor: globeMesh.vertexDescriptor)
    }

    // MARK: - Texture Loading

    private func loadTextures() {
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .SRGB: false
        ]
        let ktxAssets: [(name: String, assign: (MTLTexture) -> Void)] = [
            ("earth_dark", { [weak self] tex in self?.globeTexture = tex }),
            ("earth_lights", { [weak self] tex in self?.nightTexture = tex }),
        ]
        for asset in ktxAssets {
            guard let url = Bundle.main.url(forResource: asset.name, withExtension: "ktx") else {
                print("GlobeRenderer: Missing \(asset.name).ktx"); continue
            }
            loader.newTexture(URL: url, options: options) { texture, error in
                if let texture = texture {
                    DispatchQueue.main.async { asset.assign(texture) }
                } else {
                    print("GlobeRenderer: Failed to load \(asset.name).ktx — \(error?.localizedDescription ?? "unknown")")
                }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let personCG = self.generateTopDownPersonSprite()
            if let tex = self.uploadCGImage(personCG, label: "personTexture") {
                DispatchQueue.main.async { self.personTexture = tex }
            }
        }
    }

    // MARK: - Procedural Person Sprite

    private func generateTopDownPersonSprite() -> CGImage {
        let w = 128, h = 128
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1.0))
        let cx = CGFloat(w) / 2.0, cy = CGFloat(h) / 2.0
        let bodyW: CGFloat = 48, bodyH: CGFloat = 36
        ctx.fillEllipse(in: CGRect(x: cx - bodyW/2, y: cy - bodyH/2 + 8, width: bodyW, height: bodyH))
        let headR: CGFloat = 16
        ctx.fillEllipse(in: CGRect(x: cx - headR, y: cy - bodyH/2 - headR + 12, width: headR * 2, height: headR * 2))
        let armW: CGFloat = 12, armH: CGFloat = 28
        ctx.fillEllipse(in: CGRect(x: cx - bodyW/2 - armW/2 + 4, y: cy - armH/2 + 10, width: armW, height: armH))
        ctx.fillEllipse(in: CGRect(x: cx + bodyW/2 - armW/2 - 4, y: cy - armH/2 + 10, width: armW, height: armH))
        ctx.setFillColor(CGColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0))
        ctx.fill(CGRect(x: cx + bodyW/2 - 10, y: cy + 4, width: 5, height: 9))
        return ctx.makeImage()!
    }

    // MARK: - Texture Upload

    func uploadCGImage(_ cgImage: CGImage, label: String) -> MTLTexture? {
        let width = cgImage.width, height = cgImage.height
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        texture.label = label
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: data, bytesPerRow: width * 4)
        return texture
    }

    // MARK: - Update Uniforms

    private func updateUniforms(into buffer: MTLBuffer, viewportSize: CGSize) {
        let state = currentState
        let aspect = Float(viewportSize.width / viewportSize.height)

        let anchorLat = config.resolvedAnchorLat
        let anchorLon = config.resolvedAnchorLon
        let anchorPos = latLonToCartesian(lat: anchorLat, lon: anchorLon, radius: config.globeRadius)
        let surfaceNormal = normalize(anchorPos)

        let cameraUp = cameraUpVector(surfaceNormal: surfaceNormal, anchorLat: anchorLat)
        let eye = anchorPos + surfaceNormal * state.altitude
        let target = mix(anchorPos, SIMD3<Float>(0, 0, 0), t: state.cameraTargetBlend)

        let view = lookAtMatrix(eye: eye, target: target, up: cameraUp)
        let proj = perspectiveMatrix(fovRadians: state.fovRadians, aspect: aspect, near: 0.0001, far: 20.0)
        let model = rotationY(state.globeRotationY)
        let mvp = proj * view * model

        var uniforms = GlobeUniforms(
            mvp: mvp,
            model: model,
            normalMatrix: upperLeft3x3(model),
            cameraPos: eye,
            padding1: 0,
            anchorWorldPos: anchorPos,
            patchBlend: 0,
            displacementScale: 0,
            starAlpha: state.starAlpha,
            phoneAlpha: state.phoneAlpha,
            phoneScale: 1.0,
            personAlpha: state.personAlpha,
            time: elapsedTime,
            desaturationStrength: config.desaturationStrength,
            darkenFactor: config.darkenFactor,
            nightLightsIntensity: config.nightLightsIntensity,
            ambientLightIntensity: config.ambientLightIntensity
        )
        memcpy(buffer.contents(), &uniforms, MemoryLayout<GlobeUniforms>.stride)
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        frameSemaphore.wait()
        let uniformBuffer = uniformBuffers[frameIndex]
        frameIndex = (frameIndex + 1) % maxInflightFrames

        let now = CACurrentMediaTime()
        if lastFrameTime > 0 { elapsedTime += Float(now - lastFrameTime) }
        lastFrameTime = now

        updateUniforms(into: uniformBuffer, viewportSize: view.drawableSize)

        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            frameSemaphore.signal()
            return
        }

        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.frameSemaphore.signal()
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else {
            frameSemaphore.signal()
            return
        }

        encoder.setFragmentSamplerState(linearSampler, index: 0)

        let state = currentState
        let tilesFullyVisible = state.tileLayerAlpha >= 0.999

        // ── 1. Draw Globe (only when tiles are fading or gone) ──
        if !tilesFullyVisible {
            encoder.setDepthStencilState(depthStencilState)
            encoder.setRenderPipelineState(globePipeline)
            encoder.setVertexBuffer(globeMesh.vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
            if let globeTex = globeTexture { encoder.setFragmentTexture(globeTex, index: 0) }
            if let nightTex = nightTexture { encoder.setFragmentTexture(nightTex, index: 1) }
            encoder.drawIndexedPrimitives(
                type: .triangle, indexCount: globeMesh.indexCount,
                indexType: .uint32, indexBuffer: globeMesh.indexBuffer, indexBufferOffset: 0)
        }

        // ── 2. Draw Tile Layer ──
        if state.tileLayerAlpha > 0.001, let mgr = tileManager {
            // Use depth-always so tiles always draw on top, no seams from z-fighting
            encoder.setDepthStencilState(depthAlwaysState)
            encoder.setRenderPipelineState(tilePipeline)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)

            let dl = mgr.drawList(floatZoom: state.floatZoom)

            var tileDesat = state.tileDesaturation
            var tileDarken = state.tileDarkenFactor

            var baseAlpha = state.tileLayerAlpha
            for tile in dl.baseTiles {
                encoder.setVertexBuffer(tile.mesh.vertexBuffer, offset: 0, index: 0)
                encoder.setFragmentBytes(&baseAlpha, length: MemoryLayout<Float>.stride, index: 1)
                encoder.setFragmentBytes(&tileDesat, length: MemoryLayout<Float>.stride, index: 2)
                encoder.setFragmentBytes(&tileDarken, length: MemoryLayout<Float>.stride, index: 3)
                encoder.setFragmentTexture(tile.texture, index: 0)
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: tile.mesh.indexCount,
                    indexType: .uint32, indexBuffer: tile.mesh.indexBuffer, indexBufferOffset: 0)
            }
        }

        // ── 3. Draw Person Billboard ──
        if state.personAlpha > 0.001, let personTex = personTexture {
            encoder.setDepthStencilState(depthAlwaysState)
            encoder.setRenderPipelineState(personPipeline)
            encoder.setVertexBuffer(quadMesh.vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.setVertexBuffer(personParamBuffer, offset: 0, index: 2)
            encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
            encoder.setFragmentTexture(personTex, index: 0)
            encoder.drawIndexedPrimitives(
                type: .triangle, indexCount: quadMesh.indexCount,
                indexType: .uint32, indexBuffer: quadMesh.indexBuffer, indexBufferOffset: 0)
        }

        // ── 4. Draw Phone Billboard ──
        if state.phoneAlpha > 0.001, let phoneTex = phoneTexture {
            encoder.setDepthStencilState(depthAlwaysState)
            encoder.setRenderPipelineState(phonePipeline)
            encoder.setVertexBuffer(quadMesh.vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.setVertexBuffer(phoneParamBuffer, offset: 0, index: 2)
            encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
            encoder.setFragmentTexture(phoneTex, index: 0)
            encoder.drawIndexedPrimitives(
                type: .triangle, indexCount: quadMesh.indexCount,
                indexType: .uint32, indexBuffer: quadMesh.indexBuffer, indexBufferOffset: 0)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
