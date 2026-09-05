import SwiftUI
import TouchTipsCore

/// A line or two about the person, under Where. One glass row that grows with the text and saves
/// as you type; empty, it is a prompt and nothing more. Optional by design: most people get none.
struct NoteField: View {
    let row: PersonRow
    var autofocus = false

    @Environment(AppModel.self) private var app
    @State private var text: String
    @FocusState private var focused: Bool
    @State private var pending: Task<Void, Never>?
    @State private var problem: String?

    init(row: PersonRow, autofocus: Bool = false) {
        self.row = row
        self.autofocus = autofocus
        _text = State(initialValue: row.person.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Note").padding(.leading, 6)
            TextField("Anything worth remembering", text: $text, axis: .vertical)
                .lineLimit(1 ... 8)
                .font(.system(size: 17))
                .focused($focused)
                .accessibilityIdentifier("person.note")
                .submitLabel(.done)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .glassEffect(.clear, in: .rect(cornerRadius: 22))
                .contentShape(.rect(cornerRadius: 22))
                .onTapGesture { focused = true }
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .animation(.smooth(duration: 0.25), value: text)
        .task {
            guard autofocus else { return }
            focused = true
        }
        .onDisappear { save(now: true) }
        // A vertical field turns Return into a newline. Here Return means done: keep the note on one
        // breath, put the keyboard away, save.
        .onChange(of: text) { _, new in
            if new.contains("\n") {
                text = new.replacingOccurrences(of: "\n", with: " ")
                focused = false
            } else {
                schedule()
            }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused {
                save(now: true)
            }
        }
        // Another screen saved a note meanwhile. Only replace what is shown when nobody is typing.
        .onChange(of: row.person.note) { _, note in
            if !focused, note ?? "" != text {
                text = note ?? ""
            }
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
        if now {
            pending?.cancel()
        }
        guard (row.person.note ?? "") != text.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        do {
            try Ingest.setNote(contactID: row.id, note: text, to: app.database)
            problem = nil
        } catch {
            problem = "Couldn’t save your note. Try again."
            Log.ui.error("note not saved: \(error.localizedDescription)")
        }
    }
}
