// SpinningProgressView.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Lightweight spinning indicator that avoids ProgressView's heavyweight behavior
// in small inline contexts (status badges, task rows). Shared across views so the
// app has one spinner vocabulary with consistent reduced-motion handling.

import SwiftUI

struct SpinningProgressView: View {
    let color: Color
    var size: CGFloat = 11

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRotating: Bool = false

    var body: some View {
        // Reduce Motion: show the static glyph instead of a perpetual spin (WCAG 2.3.3).
        Image(systemName: "arrow.2.circlepath")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color)
            .rotationEffect(.degrees(isRotating ? 360 : 0))
            .animation(
                reduceMotion ? .default
                    : .linear(duration: 1.0).repeatForever(autoreverses: false),
                value: isRotating
            )
            .onAppear { if !reduceMotion { isRotating = true } }
    }
}
