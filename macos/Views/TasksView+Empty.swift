// TasksView+Empty.swift
// ThoughtVault
//
// macOS empty state of Taken: what appears here, the two ways to start (the
// Opnemen tab and the existing audio import) and the three processing steps.

#if os(macOS)
import SwiftUI

extension TasksView {

    var emptyState: some View {
        GeometryReader { geo in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Geen actieve taken")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(HomeColor.text)
                        .accessibilityAddTraits(.isHeader)
                    Text("Wanneer je een opname start of een audiobestand importeert, verschijnt de voortgang hier.")
                        .font(.system(size: 16))
                        .foregroundStyle(HomeColor.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 600, alignment: .leading)
                        .padding(.top, 10)
                    HStack(spacing: 12) {
                        Button("Start een opname") { onStartRecording?() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(onStartRecording == nil)
                        Button("Audiobestand importeren") { showImporter = true }
                            .buttonStyle(StudioQuietButtonStyle(height: 40))
                    }
                    .padding(.top, 26)
                    HStack(alignment: .top, spacing: 12) {
                        stepCard(1, title: "Transcriberen", text: "De opname wordt tekst, op je eigen apparaat of in de cloud.")
                        stepCard(2, title: "Concept schrijven", text: "Het gekozen profiel bepaalt de opbouw van de notule.")
                        stepCard(3, title: "Controleren", text: "De notule wordt naast de transcriptie gelegd. Je ziet de teller oplopen.")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 34)
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio, .audiovisualContent, .movie, .mpeg4Movie], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task {
                    await recordingVM.importAudioFile(url)
                    // An import error is shown on the Opnemen screen.
                    if case .error = recordingVM.recordingState { onStartRecording?() }
                }
            }
        }
    }

    private func stepCard(_ number: Int, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(HomeColor.lavender)
                .frame(width: 26, height: 26)
                .background(Circle().fill(HomeColor.violet.opacity(0.2)))
                .padding(.bottom, 10)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HomeColor.text)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(HomeColor.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(HomeColor.card.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(HomeColor.cardBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
#endif
