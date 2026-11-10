import XCTest
import WhisperKit
@testable import ThoughtVault

final class WhisperOfflineTokenizerTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-offline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
    }

    private func model(vocab: Int?, dim: Int = 1280, parts: Bool = true) throws -> URL {
        let dir = tmp.appendingPathComponent("model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let vocab {
            try JSONSerialization.data(withJSONObject: ["vocab_size": vocab, "d_model": dim])
                .write(to: dir.appendingPathComponent("config.json"))
        }
        if parts {
            for n in ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"] {
                try FileManager.default.createDirectory(at: dir.appendingPathComponent(n), withIntermediateDirectories: true)
            }
        }
        return dir
    }

    func testVariantMapping() throws {
        XCTAssertEqual(WhisperModelStore.tokenizerVariant(modelFolder: try model(vocab: 51866)), .largev3)
        XCTAssertEqual(WhisperModelStore.tokenizerVariant(modelFolder: try model(vocab: 51865, dim: 768)), .small)
        XCTAssertEqual(WhisperModelStore.tokenizerVariant(modelFolder: try model(vocab: 51864, dim: 384)), .tinyEn)
        XCTAssertNil(WhisperModelStore.tokenizerVariant(modelFolder: try model(vocab: 12345)))
        XCTAssertNil(WhisperModelStore.tokenizerVariant(modelFolder: try model(vocab: nil)))
    }

    func testIsInstalledNeedsTokenizer() throws {
        let root = tmp.appendingPathComponent("hub")
        let m = try model(vocab: 51866)
        XCTAssertFalse(WhisperModelStore.isInstalled(modelFolder: m, tokenizerRoot: root))

        let tf = WhisperModelStore.tokenizerFolder(for: .largev3, root: root)
        try FileManager.default.createDirectory(at: tf, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: tf.appendingPathComponent("tokenizer.json"))
        XCTAssertTrue(WhisperModelStore.isInstalled(modelFolder: m, tokenizerRoot: root))

        let m2 = try model(vocab: 51866)
        try Data("{}".utf8).write(to: m2.appendingPathComponent("tokenizer.json"))
        XCTAssertTrue(WhisperModelStore.isInstalled(modelFolder: m2, tokenizerRoot: tmp.appendingPathComponent("none")))

        let partial = try model(vocab: 51866, parts: false)
        try Data("{}".utf8).write(to: partial.appendingPathComponent("tokenizer.json"))
        XCTAssertFalse(WhisperModelStore.isInstalled(modelFolder: partial, tokenizerRoot: root))
    }

    func testLocalTokenizerLoadsWithoutNetwork() async throws {
        let realModel = "openai_whisper-large-v3-v20240930_626MB"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: WhisperModelStore.folder(for: realModel).path), "model not installed")
        let src = WhisperModelStore.tokenizerFolder(for: .largev3)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: src.appendingPathComponent("tokenizer.json").path), "tokenizer not present")
        let dst = WhisperModelStore.tokenizerFolder(for: .largev3, root: tmp)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        for f in ["tokenizer.json", "tokenizer_config.json"] {
            try FileManager.default.copyItem(at: src.appendingPathComponent(f), to: dst.appendingPathComponent(f))
        }
        let tokenizer = try await ModelUtilities.loadTokenizer(for: .largev3, tokenizerFolder: tmp)
        XCTAssertFalse(tokenizer.encode(text: " hallo").isEmpty)
    }
}
