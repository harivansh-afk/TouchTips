import SwiftUI
import TouchTipsCore

/// Native icon-only swipe actions, following Mixbridge's TrackRow implementation.
private struct PersonSwipeActions: ViewModifier {
    let row: PersonRow
    @Environment(AppModel.self) private var app
    @State private var showNote = false
    @State private var showForget = false
    @State private var problem: String?

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    HapticManager.selection()
                    showNote = true
                } label: {
                    Label("", systemImage: "note.text")
                }
                .accessibilityLabel("Note")
                .tint(.yellow)
                .accessibilityIdentifier("person.swipe.note")
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if row.meet != nil || row.person.note != nil {
                    Button {
                        HapticManager.selection()
                        showForget = true
                    } label: {
                        Label("", systemImage: "trash")
                    }
                    .accessibilityLabel("Forget")
                    .tint(.red)
                    .accessibilityIdentifier("person.swipe.forget")
                }
            }
            .sheet(isPresented: $showNote) {
                NavigationStack {
                    ScrollView {
                        NoteField(row: row, autofocus: true)
                            .padding(16)
                    }
                    .navigationTitle(row.person.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                HapticManager.light()
                                showNote = false
                            } label: {
                                Icon(.check)
                            }
                            .accessibilityLabel("Done")
                            .accessibilityIdentifier("person.note.done")
                        }
                    }
                }
                .presentationDetents([.height(220), .medium])
                .presentationDragIndicator(.visible)
            }
            .alert("Forget \(row.person.name)?", isPresented: $showForget) {
                Button("Cancel", role: .cancel) {}
                Button("Forget", role: .destructive) {
                    do {
                        try Ingest.forgetPerson(contactID: row.id, to: app.database)
                    } catch {
                        problem = "Couldn’t remove these details. Try again."
                        HapticManager.error()
                    }
                }
            } message: {
                Text("Removes the meeting details and note from TouchTips. The contact stays in your phone.")
            }
            .alert("Couldn’t forget", isPresented: Binding(
                get: { problem != nil }, set: {
                    if !$0 {
                        problem = nil
                    }
                }
            )) {
                Button("OK") { problem = nil }
            } message: {
                Text(problem ?? "")
            }
    }
}

extension View {
    func personSwipeActions(row: PersonRow) -> some View {
        modifier(PersonSwipeActions(row: row))
    }
}
