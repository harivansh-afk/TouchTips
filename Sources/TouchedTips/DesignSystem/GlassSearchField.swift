import SwiftUI

/// The search field roots draw themselves, in the bar's clear glass. Focus is the caller's.
struct GlassSearchField: View {
    let prompt: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Icon(.magnifyingGlass, size: 18)
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .focused(focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    HapticManager.light()
                    text = ""
                } label: {
                    Icon(.x, size: 16)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .glassEffect(.clear, in: .capsule)
    }
}
