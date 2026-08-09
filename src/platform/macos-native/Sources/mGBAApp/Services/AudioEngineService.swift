import AVFAudio
import Foundation

final class AudioEngineService {
    var onError: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let audioQueue = DispatchQueue(
        label: "io.mgba.native.audio",
        qos: .userInteractive
    )

    private var sourceFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var scheduledBufferCount = 0
    private var isRunning = false
    private var isPaused = false

    init() {
        engine.attach(player)
        engine.isAutoShutdownEnabled = false
    }

    deinit {
        player.stop()
        engine.stop()
    }

    func start(sampleRate: Double) {
        audioQueue.async { [weak self] in
            guard let self, sampleRate > 0 else { return }
            self.stopOnQueue()

            guard let sourceFormat = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 2
            ) else {
                self.reportError("mGBA could not create its audio format.")
                return
            }

            let hardwareFormat = self.engine.outputNode.inputFormat(forBus: 0)
            guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
                self.reportError("No usable Mac audio output device is available.")
                return
            }

            guard let outputFormat = AVAudioFormat(
                standardFormatWithSampleRate: hardwareFormat.sampleRate,
                channels: min(hardwareFormat.channelCount, 2)
            ), let converter = AVAudioConverter(from: sourceFormat, to: outputFormat) else {
                self.reportError("mGBA could not prepare audio for the active output device.")
                return
            }

            self.sourceFormat = sourceFormat
            self.outputFormat = outputFormat
            self.converter = converter
            self.engine.connect(self.player, to: self.engine.mainMixerNode, format: outputFormat)
            self.engine.prepare()

            do {
                try self.engine.start()
                self.isRunning = true
            } catch {
                self.reportError("Audio could not start: \(error.localizedDescription)")
                self.stopOnQueue()
            }
        }
    }

    func stop() {
        audioQueue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    func setPaused(_ paused: Bool) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.isPaused = paused
            guard self.isRunning else { return }
            if paused {
                self.player.pause()
            } else if !self.player.isPlaying, self.scheduledBufferCount > 0 {
                self.player.play()
            }
        }
    }

    func flush() {
        audioQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.player.stop()
            self.converter?.reset()
            self.scheduledBufferCount = 0
        }
    }

    func enqueue(interleavedPCM16 samples: [Int16], sampleRate: Double) {
        guard !samples.isEmpty else { return }
        audioQueue.async { [weak self] in
            guard let self,
                  self.isRunning,
                  !self.isPaused,
                  self.sourceFormat?.sampleRate == sampleRate,
                  self.scheduledBufferCount < 12,
                  let sourceFormat = self.sourceFormat,
                  let outputFormat = self.outputFormat,
                  let converter = self.converter else {
                return
            }

            let frameCount = samples.count / 2
            guard frameCount > 0,
                  let input = AVAudioPCMBuffer(
                      pcmFormat: sourceFormat,
                      frameCapacity: AVAudioFrameCount(frameCount)
                  ), let channels = input.floatChannelData else {
                return
            }

            input.frameLength = AVAudioFrameCount(frameCount)
            let scale = 1.0 / Float(Int16.max)
            for frame in 0..<frameCount {
                channels[0][frame] = Float(samples[frame * 2]) * scale
                channels[1][frame] = Float(samples[frame * 2 + 1]) * scale
            }

            let rateRatio = outputFormat.sampleRate / sourceFormat.sampleRate
            let outputCapacity = AVAudioFrameCount(ceil(Double(frameCount) * rateRatio) + 64)
            guard let output = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputCapacity
            ) else { return }

            var suppliedInput = false
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                if suppliedInput {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                suppliedInput = true
                inputStatus.pointee = .haveData
                return input
            }

            guard status != .error, output.frameLength > 0 else {
                if let conversionError {
                    self.reportError("Audio conversion failed: \(conversionError.localizedDescription)")
                }
                return
            }

            let defaults = UserDefaults.standard
            self.player.volume = defaults.bool(forKey: "audio.muted")
                ? 0
                : defaults.float(forKey: "audio.volume")

            self.scheduledBufferCount += 1
            self.player.scheduleBuffer(output, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                self?.audioQueue.async { [weak self] in
                    guard let self else { return }
                    self.scheduledBufferCount = max(0, self.scheduledBufferCount - 1)
                }
            }
            if !self.player.isPlaying {
                self.player.play()
            }
        }
    }

    private func stopOnQueue() {
        player.stop()
        engine.stop()
        engine.disconnectNodeOutput(player)
        converter = nil
        sourceFormat = nil
        outputFormat = nil
        scheduledBufferCount = 0
        isRunning = false
        isPaused = false
    }

    private func reportError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(message)
        }
    }
}
