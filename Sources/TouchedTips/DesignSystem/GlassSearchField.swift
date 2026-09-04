import SwiftUI

/// The search field roots draw themselves, in the bar's clear glass. Focus is the caller's.
struct GlassSearchField: View {
    let prompt: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        TextField(prompt, text: $text)
            .focused(focused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .glassEffect(.clear, in: .capsule)
    }
}
