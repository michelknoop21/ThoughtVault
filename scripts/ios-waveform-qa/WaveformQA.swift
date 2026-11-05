// Device-only acceptance host. Compile with the production recorder, envelope,
// WaveformView and IOSLiveWave; use a separate bundle ID and empty entitlements.
import SwiftUI

@main
struct WaveformQAApp: App {
    var body: some Scene { WindowGroup { WaveformQAPanel() } }
}

struct WaveformQAPanel: View {
    @State private var recorder = AudioRecorder()
    @State private var task: Task<Void, Never>?
    @State private var instruction = "Test van 35 seconden met echte microfoon. Audio blijft op dit toestel."
    @State private var seconds = 0
    @State private var result = ""
    @State private var running = false

    private let stages = ["Stilte", "Zacht spreken", "Normaal spreken", "Iets luider spreken", "Pauze", "Hervat normaal spreken", "Stilte na spraak"]

    var body: some View {
        VStack(spacing: 20) {
            Text("ThoughtVault Wave QA").font(.title2.bold())
            Text("Echte microfoon · geen cloud · aparte testapp").font(.caption)
            Text(instruction).font(.title3).multilineTextAlignment(.center)
            Text(running ? "\(seconds) sec" : result).font(.headline)
            IOSLiveWave(isActive: recorder.isRecording && !recorder.isPaused,
                        levels: { recorder.audioLevels }, bands: { recorder.frequencyBands })
                .frame(height: 130)
            WaveformView(levelsProvider: { recorder.audioLevels },
                         isActive: recorder.isRecording && !recorder.isPaused,
                         bandsProvider: { recorder.frequencyBands })
                .frame(height: 32)
            Button(running ? "Stop test" : "Start geluidstest") {
                if running {
                    task?.cancel()
                } else {
                    task = Task { await runTest() }
                }
            }.buttonStyle(.borderedProminent)
            Text("Zeg bij spreken: Dit is een geluidstest van ThoughtVault.")
                .font(.caption).multilineTextAlignment(.center)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.04, green: 0.035, blue: 0.09))
            .foregroundStyle(.white).preferredColorScheme(.dark)
    }

    @MainActor
    private func runTest() async {
        running = true
        result = ""
        var rows = [[String: Any]]()
        do {
            await recorder.requestPermission()
            try await recorder.startRecording()
            for (index, stage) in stages.enumerated() {
                try Task.checkCancellation()
                instruction = stage
                if index == 4 { recorder.pauseRecording() }
                if index == 5 { recorder.resumeRecording() }
                var levels = [Float]()
                var bandPeaks = Array(repeating: Float(0), count: 7)
                for tick in 0..<50 {
                    seconds = 5 - tick / 10
                    try await Task.sleep(for: .milliseconds(100))
                    levels.append(recorder.isPaused ? 0 : recorder.audioLevels.last ?? 0)
                    for (band, value) in recorder.frequencyBands.prefix(7).enumerated() {
                        bandPeaks[band] = max(bandPeaks[band], value)
                    }
                }
                let row: [String: Any] = ["stage": stage, "count": levels.count,
                    "minimum": levels.min() ?? 0, "maximum": levels.max() ?? 0,
                    "mean": levels.reduce(0, +) / Float(max(1, levels.count)), "bands": bandPeaks]
                rows.append(row)
                let line = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                FileHandle.standardOutput.write(Data("QA_WAVE ".utf8) + line + Data("\n".utf8))
            }
            let data = try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .prettyPrinted])
            let url = URL.documentsDirectory.appendingPathComponent("waveform-qa-metrics.json")
            try data.write(to: url, options: .atomic)
            result = "Test voltooid — metingen opgeslagen"
        } catch is CancellationError {
            result = "Test afgebroken"
        } catch {
            result = error.localizedDescription
        }
        _ = await recorder.stopRecording()
        running = false
        instruction = "Microfoon gestopt"
    }
}
