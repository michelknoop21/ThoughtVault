import AVFoundation
import Foundation

/// Repairs WAV files whose header was never finalised (crash or force-quit mid-recording).
enum RecordingRecovery {
    /// Fixes the RIFF and `data` chunk sizes in place. Returns true if bytes were changed.
    static func repairHeaderIfNeeded(at url: URL) throws -> Bool {
        guard url.pathExtension.lowercased() == "wav" else { return false }
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let fileLength = Int(try handle.seekToEnd())
        try handle.seek(toOffset: 0)
        guard let head = try handle.read(upToCount: 12), head.count == 12,
              head.prefix(4) == Data("RIFF".utf8), head.suffix(4) == Data("WAVE".utf8)
        else { return false }

        func readU32(at offset: Int) throws -> UInt32? {
            try handle.seek(toOffset: UInt64(offset))
            guard let d = try handle.read(upToCount: 4), d.count == 4 else { return nil }
            return d.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        }
        func writeU32(_ value: UInt32, at offset: Int) throws {
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: withUnsafeBytes(of: value.littleEndian) { Data($0) })
        }

        // Walk chunks from offset 12.
        var offset = 12
        var blockAlign = 1
        var dataSizeOffset: Int?
        var declaredDataSize: UInt32 = 0
        while offset + 8 <= fileLength {
            try handle.seek(toOffset: UInt64(offset))
            guard let idData = try handle.read(upToCount: 4), idData.count == 4,
                  let size = try readU32(at: offset + 4) else { break }
            let id = String(decoding: idData, as: UTF8.self)
            if id == "fmt " {
                try handle.seek(toOffset: UInt64(offset + 8 + 12))
                if let d = try handle.read(upToCount: 2), d.count == 2 {
                    blockAlign = max(1, Int(UInt16(littleEndian: d.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) })))
                }
            } else if id == "data" {
                dataSizeOffset = offset + 4
                declaredDataSize = size
                break
            }
            offset += 8 + Int(size) + Int(size & 1)
        }
        guard let sizeOffset = dataSizeOffset else { return false }

        let payloadStart = sizeOffset + 4
        // ponytail: assumes `data` is the last chunk, as AVAudioRecorder/AVAudioFile write it.
        let onDisk = max(0, fileLength - payloadStart)
        let dataSize = UInt32(truncatingIfNeeded: onDisk - onDisk % blockAlign)
        let riffSize = UInt32(truncatingIfNeeded: fileLength - 8)
        let declaredRiff = try readU32(at: 4)
        // A correct RIFF size with a sane data size may just have trailing chunks after `data`: leave it.
        let dataLooksBroken = declaredDataSize == 0 || payloadStart + Int(declaredDataSize) > fileLength
        guard declaredRiff != riffSize || dataLooksBroken else { return false }
        try writeU32(riffSize, at: 4)
        try writeU32(dataSize, at: sizeOffset)
        return true
    }

    /// Repairs each file and returns those that now open with a non-zero length.
    static func recoverOrphans(_ urls: [URL]) -> [URL] {
        urls.filter { url in
            do { _ = try repairHeaderIfNeeded(at: url) } catch { return false }
            guard let file = try? AVAudioFile(forReading: url) else { return false }
            return file.length > 0
        }
    }
}
