// AudioSpectrumAnalyzer.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Lightweight parallel FFT tap that runs only while recording. AVAudioRecorder
// exposes a single averagePower value (no spectral data), so the waveform can't
// react to pitch. This engine tap computes per-band magnitudes + a spectral
// centroid so low voices render as broad slow waves and high tones as tight fast
// ones. Runs alongside the recorder; it does not capture the file itself.

import AVFoundation
import Accelerate
import Foundation
import OSLog

private let log = Logger(subsystem: "com.buildmind.ThoughtVault", category: "AudioSpectrumAnalyzer")

final class AudioSpectrumAnalyzer: @unchecked Sendable {

    static let bandCount = 5

    /// Latest per-band magnitudes (0…1, low→high frequency). Read from the render loop.
    private(set) var bands: [Float] = Array(repeating: 0, count: bandCount)
    /// Latest spectral centroid, normalized 0…1 over the analyzed range (0 = low, 1 = high).
    private(set) var centroid: Float = 0.5

    private let lock = NSLock()
    /// Guarded by `lock`. False when the tap isn't running, so `snapshot()` can
    /// return empty bands and let the waveform fall back to level-only (avoids
    /// damping the wave in modes where the mic analyzer never starts).
    private var isRunning = false

    private var engine: AVAudioEngine?

    // FFT setup (1024-point).
    private let log2n: vDSP_Length = 10
    private let fftLength = 1024
    private let fftSetup: FFTSetup?
    private var window: [Float]

    init() {
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        self.window = [Float](repeating: 0, count: fftLength)
        vDSP_hann_window(&window, vDSP_Length(fftLength), Int32(vDSP_HANN_NORM))
    }

    deinit {
        if let fftSetup { vDSP_destroy_fftsetup(fftSetup) }
    }

    // MARK: - Lifecycle

    func start() {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            log.warning("[Spectrum] no input format, skipping")
            return
        }

        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftLength), format: format) { [weak self] buffer, _ in
            self?.process(buffer: buffer, sampleRate: Float(format.sampleRate))
        }

        do {
            engine.prepare()
            try engine.start()
            self.engine = engine
            lock.withLock { isRunning = true }
            log.info("[Spectrum] started")
        } catch {
            log.warning("[Spectrum] engine start failed: \(error.localizedDescription)")
            input.removeTap(onBus: 0)
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        lock.withLock {
            isRunning = false
            bands = Array(repeating: 0, count: Self.bandCount)
            centroid = 0.5
        }
    }

    // MARK: - Snapshot (thread-safe read for the render loop)

    /// Empty bands when the tap isn't running, so the waveform falls back to
    /// level-only instead of being damped by all-zero band gains.
    func snapshot() -> (bands: [Float], centroid: Float) {
        lock.withLock { isRunning ? (bands, centroid) : ([], centroid) }
    }

    // MARK: - FFT

    private func process(buffer: AVAudioPCMBuffer, sampleRate: Float) {
        guard let fftSetup, let channel = buffer.floatChannelData?[0] else { return }
        let available = Int(buffer.frameLength)
        guard available >= fftLength else { return }

        // Windowed copy of the first fftLength samples.
        var windowed = [Float](repeating: 0, count: fftLength)
        vDSP_vmul(channel, 1, window, 1, &windowed, 1, vDSP_Length(fftLength))

        let half = fftLength / 2
        var realp = [Float](repeating: 0, count: half)
        var imagp = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)

        realp.withUnsafeMutableBufferPointer { realBuf in
            imagp.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                windowed.withUnsafeBufferPointer { ptr in
                    ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { typeConv in
                        vDSP_ctoz(typeConv, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        // sqrt → amplitude, then log-spaced band grouping.
        var amplitude = [Float](repeating: 0, count: half)
        var count = Int32(half)
        vvsqrtf(&amplitude, magnitudes, &count)

        let nyquist = sampleRate / 2
        let binHz = nyquist / Float(half)

        // Log-spaced band edges across the speech-relevant range (80 Hz…6 kHz).
        let lowHz: Float = 80, highHz: Float = 6000
        var edges: [Float] = []
        for i in 0...Self.bandCount {
            let t = Float(i) / Float(Self.bandCount)
            edges.append(lowHz * powf(highHz / lowHz, t))
        }

        var newBands = [Float](repeating: 0, count: Self.bandCount)
        var centroidNum: Float = 0
        var centroidDen: Float = 0
        for b in 0..<Self.bandCount {
            let startBin = max(1, Int(edges[b] / binHz))
            let endBin = min(half - 1, Int(edges[b + 1] / binHz))
            guard endBin >= startBin else { continue }
            var sum: Float = 0
            for bin in startBin...endBin {
                let a = amplitude[bin]
                sum += a
                let hz = Float(bin) * binHz
                centroidNum += a * hz
                centroidDen += a
            }
            let mean = sum / Float(endBin - startBin + 1)
            // Compress: FFT amplitudes are tiny; log-scale to a visible 0…1 range.
            newBands[b] = min(1, log10f(1 + mean * 40) )
        }

        // Centroid → normalized 0…1 over the log range.
        var normCentroid: Float = 0.5
        if centroidDen > 0 {
            let cHz = max(lowHz, min(highHz, centroidNum / centroidDen))
            normCentroid = logf(cHz / lowHz) / logf(highHz / lowHz)
        }

        lock.withLock {
            // Light smoothing to avoid jitter.
            for i in 0..<Self.bandCount {
                bands[i] += (newBands[i] - bands[i]) * 0.5
            }
            centroid += (normCentroid - centroid) * 0.3
        }
    }
}
