import Foundation
import MGBABridge

final class EmulatorSession: ObservableObject {
    let frameMailbox = VideoFrameMailbox()
    @Published private(set) var videoSize = CGSize(width: 240, height: 160)
    @Published private(set) var gameTitle = ""
    @Published private(set) var romURL: URL?
    @Published private(set) var isPaused = false
    @Published private(set) var isFastForwarding = false
    @Published private(set) var availableStateSlots = Set<Int>()
    @Published private(set) var controllerNames: [String] = []
    @Published private(set) var statusMessage: String?
    @Published var errorMessage: String?

    var hasROM: Bool { romURL != nil }

    private let emulationQueue = DispatchQueue(
        label: "io.mgba.native.emulation",
        qos: .userInteractive
    )
    private let audioEngine = AudioEngineService()
    private var core: OpaquePointer?
    private var storage: GameStorage?
    private var frameTimer: DispatchSourceTimer?
    private var frameSequence: UInt64 = 0
    private var videoSizeOnQueue = CGSize(width: 240, height: 160)
    private var keyboardMask: UInt32 = 0
    private var controllerMask: UInt32 = 0
    private var pausedOnQueue = false
    private var fastForwardingOnQueue = false
    private var loadGeneration: UInt64 = 0
    private var audioScratch = [Int16](repeating: 0, count: 4096)
    private lazy var controllerService = ControllerInputService(
        onKeyMask: { [weak self] mask in self?.setControllerMask(mask) },
        onControllersChanged: { [weak self] names in self?.controllerNames = names }
    )

    init() {
        audioEngine.onError = { [weak self] message in
            self?.errorMessage = message
        }
        controllerService.start()
    }

    deinit {
        controllerService.stop()
        emulationQueue.sync {
            destroyCoreOnQueue()
        }
    }

    @MainActor
    func chooseAndOpenROM() {
        guard let url = ROMOpenPanel.chooseROM() else { return }
        openROM(url)
    }

    func openROM(_ url: URL) {
        loadGeneration &+= 1
        let generation = loadGeneration
        errorMessage = nil
        statusMessage = nil
        availableStateSlots.removeAll()
        isFastForwarding = false

        emulationQueue.async { [weak self] in
            guard let self else { return }
            self.destroyCoreOnQueue()

            let gameStorage: GameStorage
            do {
                gameStorage = try AppStoragePaths.prepare(for: url)
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.loadGeneration == generation else { return }
                    self.errorMessage = "mGBA could not prepare writable game data: \(error.localizedDescription)"
                    self.romURL = nil
                    self.gameTitle = ""
                    self.frameMailbox.clear()
                }
                return
            }

            var error = [CChar](repeating: 0, count: 512)
            let newCore = url.path.withCString { romPath in
                gameStorage.saveURL.path.withCString { savePath in
                    MGBANativeCoreCreate(romPath, savePath, &error, error.count)
                }
            }

            guard let newCore else {
                let message = String(cString: error)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.loadGeneration == generation else { return }
                    self.errorMessage = message.isEmpty ? "The ROM could not be opened." : message
                    self.romURL = nil
                    self.gameTitle = ""
                    self.frameMailbox.clear()
                }
                return
            }

            self.core = newCore
            self.storage = gameStorage
            self.pausedOnQueue = false
            self.fastForwardingOnQueue = false
            self.keyboardMask = 0
            self.controllerMask = 0
            self.frameSequence = 0
            let width = Int(MGBANativeCoreWidth(newCore))
            let height = Int(MGBANativeCoreHeight(newCore))
            if width > 0, height > 0 {
                self.videoSizeOnQueue = CGSize(width: width, height: height)
            }
            self.audioEngine.start(
                sampleRate: Double(MGBANativeCoreAudioSampleRate(newCore))
            )
            self.startTimerOnQueue(frameRate: MGBANativeCoreFrameRate(newCore))

            let title = String(cString: MGBANativeCoreGameTitle(newCore))
            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadGeneration == generation else { return }
                self.romURL = url
                self.gameTitle = title.isEmpty ? url.deletingPathExtension().lastPathComponent : title
                self.isPaused = false
                self.isFastForwarding = false
                if width > 0, height > 0 {
                    self.videoSize = CGSize(width: width, height: height)
                }
                self.refreshAvailableStateSlots(storage: gameStorage)
            }
        }
    }

    func togglePause() {
        emulationQueue.async { [weak self] in
            guard let self, self.core != nil else { return }
            self.pausedOnQueue.toggle()
            let paused = self.pausedOnQueue
            if paused {
                self.fastForwardingOnQueue = false
            }
            self.audioEngine.setPaused(paused || self.fastForwardingOnQueue)
            DispatchQueue.main.async { [weak self] in
                self?.isPaused = paused
                if paused { self?.isFastForwarding = false }
            }
        }
    }

    func setPaused(_ paused: Bool) {
        emulationQueue.async { [weak self] in
            guard let self, self.core != nil else { return }
            self.pausedOnQueue = paused
            if paused {
                self.fastForwardingOnQueue = false
            }
            self.audioEngine.setPaused(paused || self.fastForwardingOnQueue)
            DispatchQueue.main.async { [weak self] in
                self?.isPaused = paused
                if paused { self?.isFastForwarding = false }
            }
        }
    }

    func reset() {
        guard let url = romURL else { return }
        openROM(url)
    }

    func setFastForwarding(_ active: Bool) {
        emulationQueue.async { [weak self] in
            guard let self, self.core != nil, !self.pausedOnQueue else { return }
            guard self.fastForwardingOnQueue != active else { return }
            self.fastForwardingOnQueue = active
            self.audioEngine.setPaused(active)
            if !active {
                self.audioEngine.flush()
            }
            DispatchQueue.main.async { [weak self] in
                self?.isFastForwarding = active
            }
        }
    }

    func setKey(bit: UInt32, pressed: Bool) {
        emulationQueue.async { [weak self] in
            guard let self, let core = self.core else { return }
            if pressed {
                self.keyboardMask |= 1 << bit
            } else {
                self.keyboardMask &= ~(1 << bit)
            }
            MGBANativeCoreSetKeys(core, self.keyboardMask | self.controllerMask)
        }
    }

    func saveState(slot: Int) {
        guard (1...9).contains(slot) else { return }
        emulationQueue.async { [weak self] in
            guard let self, let core = self.core, let storage = self.storage else { return }
            let stateURL = storage.stateURL(slot: slot)
            let success = stateURL.path.withCString { path in
                MGBANativeCoreSaveState(core, path)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if success {
                    self.availableStateSlots.insert(slot)
                    self.showStatus("Saved state \(slot)")
                } else {
                    self.errorMessage = "State \(slot) could not be saved."
                }
            }
        }
    }

    func loadState(slot: Int) {
        guard (1...9).contains(slot) else { return }
        emulationQueue.async { [weak self] in
            guard let self, let core = self.core, let storage = self.storage else { return }
            let stateURL = storage.stateURL(slot: slot)
            let success = stateURL.path.withCString { path in
                MGBANativeCoreLoadState(core, path)
            }
            if success {
                self.audioEngine.flush()
                self.runFrameOnQueue()
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if success {
                    self.showStatus("Loaded state \(slot)")
                } else {
                    self.errorMessage = "State \(slot) could not be loaded."
                }
            }
        }
    }

    private func setControllerMask(_ mask: UInt32) {
        emulationQueue.async { [weak self] in
            guard let self else { return }
            self.controllerMask = mask
            if let core = self.core {
                MGBANativeCoreSetKeys(core, self.keyboardMask | self.controllerMask)
            }
        }
    }

    @MainActor
    private func refreshAvailableStateSlots(storage: GameStorage) {
        availableStateSlots = Set((1...9).filter {
            FileManager.default.fileExists(atPath: storage.stateURL(slot: $0).path)
        })
    }

    @MainActor
    private func showStatus(_ message: String) {
        statusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard self?.statusMessage == message else { return }
            self?.statusMessage = nil
        }
    }

    private func startTimerOnQueue(frameRate: Double) {
        frameTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: emulationQueue)
        let nanoseconds = Int(1_000_000_000 / max(frameRate, 1))
        timer.schedule(
            deadline: .now(),
            repeating: .nanoseconds(nanoseconds),
            leeway: .microseconds(500)
        )
        timer.setEventHandler { [weak self] in
            self?.runFrameOnQueue()
        }
        frameTimer = timer
        timer.resume()
    }

    private func runFrameOnQueue() {
        guard !pausedOnQueue, let core else { return }
        let frameCount = fastForwardingOnQueue ? 4 : 1
        for _ in 0..<frameCount {
            MGBANativeCoreRunFrame(core)
        }

        let audioFrames = audioScratch.withUnsafeMutableBufferPointer { buffer in
            MGBANativeCoreReadAudio(core, buffer.baseAddress, buffer.count / 2)
        }
        if audioFrames > 0 {
            let sampleCount = min(audioScratch.count, Int(audioFrames) * 2)
            audioEngine.enqueue(
                interleavedPCM16: Array(audioScratch.prefix(sampleCount)),
                sampleRate: Double(MGBANativeCoreAudioSampleRate(core))
            )
        }

        let width = Int(MGBANativeCoreWidth(core))
        let height = Int(MGBANativeCoreHeight(core))
        let stride = Int(MGBANativeCoreStride(core))
        guard width > 0, height > 0, let pixels = MGBANativeCorePixels(core) else { return }

        frameSequence &+= 1
        let byteCount = stride * height * MemoryLayout<UInt32>.stride
        let snapshot = Data(bytes: pixels, count: byteCount)
        let nextFrame = VideoFrame(
            sequence: frameSequence,
            width: width,
            height: height,
            stride: stride,
            pixels: snapshot
        )

        frameMailbox.publish(nextFrame)

        let nextSize = CGSize(width: width, height: height)
        if nextSize != videoSizeOnQueue {
            videoSizeOnQueue = nextSize
            DispatchQueue.main.async { [weak self] in
                self?.videoSize = nextSize
            }
        }
    }

    private func destroyCoreOnQueue() {
        frameTimer?.cancel()
        frameTimer = nil
        audioEngine.stop()
        if let core {
            MGBANativeCoreDestroy(core)
            self.core = nil
        }
        storage = nil
        fastForwardingOnQueue = false
        frameMailbox.clear()
    }
}
