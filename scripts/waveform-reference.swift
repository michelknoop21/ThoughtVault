// Compile with the unchanged WaveformView.swift and AudioEnvelopeProcessor.swift.
// Emits geometry from the actual Apple renderer for the Windows parity test.
import Foundation

@main
struct WaveformReference {
    static func main() throws {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var cases = [[String: Any]]()
        let inputs: [(Float, [Float])] = [
            (0, [0, 0, 0, 0, 0, 0, 1]), (0.1, []), (0.3, []),
            (0.9, []), (0.6, [0.8, 0, 0, 0, 0, 0]),
            (0.6, [0, 0, 0, 0, 0, 0, 0.8])
        ]
        for height in [32.0, 240.0] {
            for fps in [30, 60, 120] {
                for (input, bands) in inputs {
                    let clock = WavePhaseClock()
                    for frame in 0...fps {
                        clock.advance(to: start.addingTimeInterval(Double(frame) / Double(fps)), level: input)
                    }
                    let expectedPhase = 2 * Double.pi * 0.65 * (1 + 0.8 * Double(input))
                    precondition(abs(clock.travel - expectedPhase) < 1e-9)
                    let lines = height < 64 ? WaveConfig.widgetLines : WaveConfig.desktopLines
                    let level = WaveConfig.visualEnergy(input)
                    let paths = lines.enumerated().map { j, line in
                        let bandIndex = min(bands.count - 1, j * bands.count / max(1, lines.count - 1))
                        let bandEnd = min(bands.count, max(bandIndex + 1, (j + 1) * bands.count / max(1, lines.count - 1)))
                        let peak = bands.max() ?? 0
                        let gain = line.main || bands.isEmpty ? 1.0 : peak > 0 ? Double((bands[bandIndex..<bandEnd].max() ?? 0) / peak) : 0
                        return [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0].map { x in
                            height / 2 - height * WaveConfig.heightFrac * WaveConfig.displacement(
                                x: x, amplitude: level, gain: gain, travel: clock.travel, index: j,
                                frequency: line.main ? 3.4 : 2.8 + Double(max(0, bandIndex)) * 0.22,
                                line: line, frozen: false)
                        }
                    }
                    cases.append(["height": height, "fps": fps, "level": input, "bands": bands, "paths": paths])
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: cases, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
