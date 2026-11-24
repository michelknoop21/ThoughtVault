// ParakeetCatalog.swift
// ThoughtVault
//
// The multilingual Parakeet speech models the app can download, and which one
// fits a device. Pure data and rules; downloading lives in ParakeetModelStore.

import Foundation

struct ParakeetModel: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    /// Approximate download size in MB.
    let megabytes: Int
    /// Lowest major macOS and iOS version the model runs on.
    let minimumMac: Int
    let minimumPhone: Int
    /// Memory (GB) from which the model is recommended on a Mac and on an iPhone or iPad.
    let memoryGBMac: Int
    let memoryGBPhone: Int
    let languages: String

    var sizeText: String { Self.sizeText(megabytes) }

    static func sizeText(_ megabytes: Int) -> String {
        megabytes >= 1000 ? String(format: "%.1f GB", Double(megabytes) / 1000) : "\(megabytes) MB"
    }
}

enum ParakeetCatalog {
    static let defaultsKey = "parakeetModel"
    static let fallbackID = "v3"

    static let all: [ParakeetModel] = [
        ParakeetModel(id: "ultra", label: "Parakeet Ultra", megabytes: 632, minimumMac: 14, minimumPhone: 17,
                      memoryGBMac: 16, memoryGBPhone: 8, languages: "Nederlands en 24 andere talen"),
        ParakeetModel(id: "v3", label: "Parakeet TDT v3", megabytes: 496, minimumMac: 14, minimumPhone: 17,
                      memoryGBMac: 8, memoryGBPhone: 8, languages: "Nederlands en 24 andere talen"),
        ParakeetModel(id: "redux", label: "Parakeet Redux", megabytes: 220, minimumMac: 15, minimumPhone: 18,
                      memoryGBMac: 0, memoryGBPhone: 0, languages: "Nederlands en 24 andere talen"),
    ]

    /// The model with this id, else the fallback.
    static func model(_ id: String) -> ParakeetModel { all.first { $0.id == id } ?? all.first { $0.id == fallbackID }! }

    /// The selected model id; per device, not synced. Nothing or an unknown
    /// value stored means the model recommended for this device.
    static func selectedID(defaults: UserDefaults = .standard,
                           recommended: @autoclosure () -> ParakeetModel = ParakeetModelStore.recommended) -> String {
        selectedID(stored: defaults.string(forKey: defaultsKey), recommended: recommended())
    }

    static func selectedID(stored: String?, recommended: ParakeetModel) -> String {
        all.first { $0.id == stored }?.id ?? recommended.id
    }

    /// Why a model cannot run here, in the order the user can do something about it.
    enum Blocker: Equatable {
        case system(Int), memory(Int), storage(Int)
    }

    static func blocker(_ model: ParakeetModel, memoryGB: Int, system: Int, phone: Bool, freeMegabytes: Int) -> Blocker? {
        let minimum = phone ? model.minimumPhone : model.minimumMac
        if system < minimum { return .system(minimum) }
        let memory = phone ? model.memoryGBPhone : model.memoryGBMac
        if memoryGB < memory { return .memory(memory) }
        if freeMegabytes < model.megabytes * 2 { return .storage(model.megabytes * 2) }
        return nil
    }

    /// Runs here: the OS is new enough and there is room for the download.
    static func fits(_ model: ParakeetModel, system: Int, phone: Bool, freeMegabytes: Int) -> Bool {
        system >= (phone ? model.minimumPhone : model.minimumMac) && freeMegabytes >= model.megabytes * 2
    }

    /// Catalog order is preference order: the first model with enough memory that fits wins.
    // ponytail: memory thresholds are an estimate, not measured per device; adjust once load time and memory use are measured.
    static func recommended(memoryGB: Int, system: Int, phone: Bool, freeMegabytes: Int) -> ParakeetModel {
        all.first { memoryGB >= (phone ? $0.memoryGBPhone : $0.memoryGBMac) && fits($0, system: system, phone: phone, freeMegabytes: freeMegabytes) }
            ?? model(fallbackID)
    }
}
