// NotuleFallbackPicker.swift
// ThoughtVault
//
// Optional second provider for on-device notule generation. The fallback uses the
// model already configured for that provider; "Geen" turns it off.

import SwiftUI

struct NotuleFallbackPicker: View {
    @AppStorage(NotuleGenerator.fallbackProviderKey) private var fallback = ""

    private let choices: [NotulenProvider] = [
        .ollama, .lmStudio, .appleIntelligence, .openAI, .anthropic, .ollamaCloud, .openAICompatible, .openRouter,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            #if os(iOS)
            // Outside a Form an iOS menu picker shows only its value; name it.
            HStack {
                Text("Terugval bij fout")
                Spacer(minLength: 8)
                picker.labelsHidden()
            }
            #else
            picker
            #endif
            Text("Bij een terugval naar ChatGPT, Claude of een andere online aanbieder gaat het transcript naar die aanbieder.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var picker: some View {
        Picker("Terugval bij fout", selection: $fallback) {
            Text("Geen").tag("")
            ForEach(choices, id: \.rawValue) { Text($0.displayName).tag($0.rawValue) }
        }
    }
}
