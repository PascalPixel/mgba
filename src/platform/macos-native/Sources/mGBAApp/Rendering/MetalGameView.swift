import AppKit
import MetalKit
import SwiftUI

struct MetalGameView: NSViewRepresentable {
    let frameMailbox: VideoFrameMailbox
    let filtering: Bool
    let shaderPreset: ShaderPreset
    let shaderURL: URL?
    let onKey: (UInt32, Bool) -> Void
    let onFastForward: (Bool) -> Void
    let onPointerActivity: (Bool) -> Void
    let onShaderError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onShaderError: onShaderError)
    }

    func makeNSView(context: Context) -> GameMTKView {
        let view = GameMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        view.keyHandler = onKey
        view.fastForwardHandler = onFastForward
        view.pointerActivityHandler = onPointerActivity
        context.coordinator.attach(to: view, frameMailbox: frameMailbox)
        return view
    }

    func updateNSView(_ view: GameMTKView, context: Context) {
        view.keyHandler = onKey
        view.fastForwardHandler = onFastForward
        view.pointerActivityHandler = onPointerActivity
        context.coordinator.renderer?.configure(
            filtering: filtering,
            shaderPreset: shaderPreset,
            shaderURL: shaderURL
        )
    }

    final class Coordinator {
        var renderer: MetalRenderer?
        private let onShaderError: (String) -> Void

        init(onShaderError: @escaping (String) -> Void) {
            self.onShaderError = onShaderError
        }

        func attach(to view: MTKView, frameMailbox: VideoFrameMailbox) {
            renderer = MetalRenderer(
                view: view,
                frameMailbox: frameMailbox,
                onShaderError: onShaderError
            )
        }
    }
}

final class GameMTKView: MTKView {
    var keyHandler: ((UInt32, Bool) -> Void)?
    var fastForwardHandler: ((Bool) -> Void)?
    var pointerActivityHandler: ((Bool) -> Void)?
    private var windowObservers = [NSObjectProtocol]()
    private var deferredResume: DispatchWorkItem?
    private var pointerTrackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeWindowTransitions()
        window?.makeFirstResponder(self)
    }

    deinit {
        stopObservingWindowTransitions()
    }

    override func updateTrackingAreas() {
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .activeInKeyWindow,
                .inVisibleRect,
                .mouseEnteredAndExited,
                .mouseMoved,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        pointerActivityHandler?(true)
        super.mouseEntered(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        pointerActivityHandler?(true)
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        pointerActivityHandler?(false)
        super.mouseExited(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        pointerActivityHandler?(true)
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            if !event.isARepeat { fastForwardHandler?(true) }
            return
        }
        guard !event.isARepeat, let bit = keyBit(for: event) else {
            super.keyDown(with: event)
            return
        }
        keyHandler?(bit, true)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            fastForwardHandler?(false)
            return
        }
        guard let bit = keyBit(for: event) else {
            super.keyUp(with: event)
            return
        }
        keyHandler?(bit, false)
    }

    override func resignFirstResponder() -> Bool {
        fastForwardHandler?(false)
        return super.resignFirstResponder()
    }

    private func observeWindowTransitions() {
        stopObservingWindowTransitions()
        guard let window else { return }
        let center = NotificationCenter.default
        windowObservers = [
            center.addObserver(
                forName: NSWindow.willEnterFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in self?.pauseForWindowTransition() },
            center.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in self?.resumeAfterWindowTransition() },
            center.addObserver(
                forName: NSWindow.willExitFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in self?.pauseForWindowTransition() },
            center.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in self?.resumeAfterWindowTransition() },
        ]
    }

    private func stopObservingWindowTransitions() {
        deferredResume?.cancel()
        deferredResume = nil
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
    }

    private func pauseForWindowTransition() {
        deferredResume?.cancel()
        deferredResume = nil
        isPaused = true
    }

    private func resumeAfterWindowTransition() {
        deferredResume?.cancel()
        let resume = DispatchWorkItem { [weak self] in
            self?.isPaused = false
            self?.deferredResume = nil
        }
        deferredResume = resume
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: resume)
    }

    private func keyBit(for event: NSEvent) -> UInt32? {
        switch event.keyCode {
        case 123: return 5 // Left
        case 124: return 4 // Right
        case 125: return 7 // Down
        case 126: return 6 // Up
        case 36, 76: return 3 // Start
        case 51: return 2 // Select
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "x": return 0 // A
            case "z": return 1 // B
            case "s": return 8 // R
            case "a": return 9 // L
            default: return nil
            }
        }
    }
}

final class MetalRenderer: NSObject, MTKViewDelegate {
    private weak var view: MTKView?
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let defaultLibrary: MTLLibrary
    private let onShaderError: (String) -> Void
    private let frameMailbox: VideoFrameMailbox
    private let pipelineCompilationQueue = DispatchQueue(
        label: "io.mgba.native.metal-pipeline",
        qos: .userInitiated
    )

    private var texture: MTLTexture?
    private var pipeline: MTLRenderPipelineState?
    private var builtInPipelines = [String: MTLRenderPipelineState]()
    private var filtering = false
    private var shaderPreset = ShaderPreset.native
    private var shaderURL: URL?
    private var configuredShaderPath: String?
    private var configuredPreset = ShaderPreset.native
    private var configuredFiltering = false
    private var customCompilationGeneration: UInt64 = 0

    init?(
        view: MTKView,
        frameMailbox: VideoFrameMailbox,
        onShaderError: @escaping (String) -> Void
    ) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.defaultMetalSource, options: nil) else {
            return nil
        }
        self.view = view
        self.device = device
        self.commandQueue = commandQueue
        self.defaultLibrary = library
        self.frameMailbox = frameMailbox
        self.onShaderError = onShaderError
        super.init()
        view.device = device
        view.delegate = self
        prepareBuiltInPipelines()
        pipeline = builtInPipeline(for: .native, filtering: false)
    }

    func configure(
        filtering: Bool,
        shaderPreset: ShaderPreset,
        shaderURL: URL?
    ) {
        self.filtering = filtering
        self.shaderPreset = shaderPreset
        self.shaderURL = shaderURL

        let shaderPath = shaderURL?.path
        if configuredFiltering != filtering
            || configuredPreset != shaderPreset
            || configuredShaderPath != shaderPath {
            configuredFiltering = filtering
            configuredPreset = shaderPreset
            configuredShaderPath = shaderPath
            selectPipeline()
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let frame = frameMailbox.snapshot(),
              let pipeline,
              let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }

        ensureTexture(width: frame.width, height: frame.height)
        guard let texture else {
            encoder.endEncoding()
            return
        }

        frame.pixels.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, frame.width, frame.height),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: frame.stride * MemoryLayout<UInt32>.stride
            )
        }

        let scale = presentationScale(
            drawableSize: view.drawableSize,
            frameWidth: frame.width,
            frameHeight: frame.height
        )
        let width = Double(frame.width) * scale
        let height = Double(frame.height) * scale
        encoder.setViewport(MTLViewport(
            originX: (Double(view.drawableSize.width) - width) / 2,
            originY: (Double(view.drawableSize.height) - height) / 2,
            width: width,
            height: height,
            znear: 0,
            zfar: 1
        ))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func ensureTexture(width: Int, height: Int) {
        if texture?.width == width, texture?.height == height { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        texture = device.makeTexture(descriptor: descriptor)
    }

    private func presentationScale(
        drawableSize: CGSize,
        frameWidth: Int,
        frameHeight: Int
    ) -> Double {
        let available = min(
            Double(drawableSize.width) / Double(frameWidth),
            Double(drawableSize.height) / Double(frameHeight)
        )
        return max(available, 0.01)
    }

    private func prepareBuiltInPipelines() {
        for preset in ShaderPreset.allCases {
            if let pipeline = makePipeline(fragmentName: preset.fragmentFunctionName) {
                builtInPipelines[preset.id] = pipeline
            }
        }
        if let pipeline = makePipeline(fragmentName: "mgba_linear") {
            builtInPipelines["\(ShaderPreset.native.id).linear"] = pipeline
        }
    }

    private func selectPipeline() {
        customCompilationGeneration &+= 1
        let generation = customCompilationGeneration
        guard let shaderURL else {
            pipeline = builtInPipeline(for: shaderPreset, filtering: filtering)
            return
        }

        let device = device
        let defaultLibrary = defaultLibrary
        pipelineCompilationQueue.async { [weak self] in
            do {
                let source = try String(contentsOf: shaderURL, encoding: .utf8)
                let library = try device.makeLibrary(source: source, options: nil)
                guard let fragment = library.makeFunction(name: "mgba_fragment"),
                      let vertex = defaultLibrary.makeFunction(name: "mgba_vertex") else {
                    throw RendererError.missingFragmentFunction
                }
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = vertex
                descriptor.fragmentFunction = fragment
                descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
                let compiledPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.customCompilationGeneration == generation else { return }
                    self.pipeline = compiledPipeline
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.customCompilationGeneration == generation else { return }
                    self.pipeline = self.builtInPipeline(for: .native, filtering: self.filtering)
                    self.onShaderError(error.localizedDescription)
                }
            }
        }
    }

    private func builtInPipeline(
        for preset: ShaderPreset,
        filtering: Bool
    ) -> MTLRenderPipelineState? {
        let key = preset == .native && filtering ? "\(preset.id).linear" : preset.id
        return builtInPipelines[key]
    }

    private func makePipeline(fragmentName: String) -> MTLRenderPipelineState? {
        guard let vertex = defaultLibrary.makeFunction(name: "mgba_vertex"),
              let fragment = defaultLibrary.makeFunction(name: fragmentName) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private enum RendererError: LocalizedError {
        case missingFragmentFunction
        case missingBuiltInFunction

        var errorDescription: String? {
            switch self {
            case .missingFragmentFunction:
                return "The shader must export a Metal fragment function named mgba_fragment."
            case .missingBuiltInFunction:
                return "The built-in Metal shader could not be created."
            }
        }
    }

    private static let defaultMetalSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct MGBARasterData {
        float4 position [[position]];
        float2 textureCoordinate;
    };

    vertex MGBARasterData mgba_vertex(uint vertexID [[vertex_id]]) {
        const float2 positions[4] = {
            float2(-1.0, -1.0), float2(1.0, -1.0),
            float2(-1.0,  1.0), float2(1.0,  1.0)
        };
        const float2 coordinates[4] = {
            float2(0.0, 1.0), float2(1.0, 1.0),
            float2(0.0, 0.0), float2(1.0, 0.0)
        };
        MGBARasterData output;
        output.position = float4(positions[vertexID], 0.0, 1.0);
        output.textureCoordinate = coordinates[vertexID];
        return output;
    }

    fragment float4 mgba_nearest(
        MGBARasterData input [[stage_in]],
        texture2d<float> frame [[texture(0)]]) {
        constexpr sampler frameSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
        float4 color = frame.sample(frameSampler, input.textureCoordinate);
        return float4(color.rgb, 1.0);
    }

    fragment float4 mgba_linear(
        MGBARasterData input [[stage_in]],
        texture2d<float> frame [[texture(0)]]) {
        constexpr sampler frameSampler(coord::normalized, address::clamp_to_edge, filter::linear);
        float4 color = frame.sample(frameSampler, input.textureCoordinate);
        return float4(color.rgb, 1.0);
    }

    float3 mgba_gba_color(float3 color) {
        float3 linear = pow(max(color, float3(0.0)), float3(2.2));
        float3 corrected = float3(
            dot(linear, float3(0.82, 0.12, 0.06)),
            dot(linear, float3(0.10, 0.80, 0.10)),
            dot(linear, float3(0.06, 0.16, 0.78))
        );
        corrected = mix(corrected, float3(dot(corrected, float3(0.299, 0.587, 0.114))), 0.08);
        return pow(clamp(corrected * 0.92 + 0.015, 0.0, 1.0), float3(1.0 / 2.2));
    }

    fragment float4 mgba_color_corrected(
        MGBARasterData input [[stage_in]],
        texture2d<float> frame [[texture(0)]]) {
        constexpr sampler frameSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
        float3 color = frame.sample(frameSampler, input.textureCoordinate).rgb;
        return float4(mgba_gba_color(color), 1.0);
    }

    float mgba_pixel_grid(float2 coordinate, float2 sourceSize, float strength) {
        float2 withinPixel = fract(coordinate * sourceSize);
        float2 edgeDistance = min(withinPixel, 1.0 - withinPixel);
        float nearestEdge = min(edgeDistance.x, edgeDistance.y);
        return mix(strength, 1.0, smoothstep(0.035, 0.16, nearestEdge));
    }

    fragment float4 mgba_lcd_grid(
        MGBARasterData input [[stage_in]],
        texture2d<float> frame [[texture(0)]]) {
        constexpr sampler frameSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
        float3 color = frame.sample(frameSampler, input.textureCoordinate).rgb;
        float2 size = float2(frame.get_width(), frame.get_height());
        color *= mgba_pixel_grid(input.textureCoordinate, size, 0.72);
        return float4(color, 1.0);
    }

    fragment float4 mgba_soft_lcd(
        MGBARasterData input [[stage_in]],
        texture2d<float> frame [[texture(0)]]) {
        constexpr sampler frameSampler(coord::normalized, address::clamp_to_edge, filter::linear);
        float3 color = mgba_gba_color(frame.sample(frameSampler, input.textureCoordinate).rgb);
        float sourceY = input.textureCoordinate.y * float(frame.get_height());
        float scanline = 0.94 + 0.06 * cos(sourceY * 6.2831853);
        return float4(color * scanline, 1.0);
    }

    fragment float4 mgba_classic_green(
        MGBARasterData input [[stage_in]],
        texture2d<float> frame [[texture(0)]]) {
        constexpr sampler frameSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
        float3 color = frame.sample(frameSampler, input.textureCoordinate).rgb;
        float luminance = dot(color, float3(0.299, 0.587, 0.114));
        float level = floor(clamp(luminance, 0.0, 1.0) * 3.0 + 0.5) / 3.0;
        float3 darkest = float3(0.055, 0.12, 0.085);
        float3 lightest = float3(0.72, 0.82, 0.53);
        return float4(mix(darkest, lightest, level), 1.0);
    }
    """
}
