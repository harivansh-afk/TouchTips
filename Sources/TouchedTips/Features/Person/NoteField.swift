import SwiftUI
import TouchedTipsCore

/// A line or two about the person, under Where. One glass row that grows with the text and saves
/// as you type; empty, it is a prompt and nothing more. Optional by design: most people get none.
struct NoteField: View {
    let row: PersonRow

    @Environment(AppModel.self) private var app
    @State private var text: String
    @FocusState private var focused: Bool
    @State private var pending: Task<Void, Never>?

    init(row: PersonRow) {
        self.row = row
        _text = State(initialValue: row.person.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Note").padding(.leading, 6)
            TextField("Anything worth remembering", text: $text, axis: .vertical)
                .lineLimit(1 ... 8)
                .font(.system(size: 17))
                .focused($focused)
                .submitLabel(.done)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .glassEffect(.clear, in: .rect(cornerRadius: 22))
                .contentShape(.rect(cornerRadius: 22))
                .onTapGesture { focused = true }
        }
        .animation(.smooth(duration: 0.25), value: text)
        .onChange(of: text) { _, _ in schedule() }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { save(now: true) }
        }
        // Another screen saved a note meanwhile. Only replace what is shown when nobody is typing.
        .onChange(of: row.person.note) { _, note in
            if !focused, note ?? "" != text { text = note ?? "" }
        }
    }

    private func schedule() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            save(now: false)
        }
    }

    private func save(now: Bool) {
        if now { pending?.cancel() }
        guard (row.person.note ?? "") != text.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        do {
            try Ingest.setNote(contactID: row.id, note: text, to: app.database)
        } catch {
            Log.ui.error("note not saved: \(error.localizedDescription)")
        }
    }
}
