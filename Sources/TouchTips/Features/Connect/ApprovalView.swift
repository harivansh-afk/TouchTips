// "Allow Claude?" The only way a client gets to read anything. The user taps the number its sign-in page shows,
// which ties this Allow to the screen in front of them: someone else's sign-in shows its number to them, not here.

import SwiftUI

struct ApprovalView: View {
    let cloud: CloudSync
    let request: ApprovalRequest

    @State private var answering = false
    @State private var wrongNumber = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Icon(request.recognised ? request.kind.icon : .plugs, size: 40)
                .foregroundStyle(.primary)
                .frame(width: 76, height: 76)
                .glassEffect(.clear, in: .circle)
                .padding(.bottom, 22)
            Text("Allow \(request.name)?")
                .font(.display(34))
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)
            Text("It will be able to read your people, places and meetings. It can't change anything.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !request.recognised {
                Text("TouchTips can't confirm which app this is. Only go on if you started connecting it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            Spacer(minLength: 28)
            if wrongNumber {
                Text("That wasn't the number on the sign-in page, so it wasn't allowed. Start again from the app you're connecting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 16)
                Button {
                    cloud.pendingApproval = nil
                } label: {
                    Text("Close")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            } else {
                Text("To allow, tap the number it's showing")
                    .font(.subheadline.weight(.semibold))
                    .padding(.bottom, 14)
                HStack(spacing: 12) {
                    ForEach(request.choices, id: \.self) { number in
                        Button {
                            answer(allow: true, number: number)
                        } label: {
                            Text("\(number)")
                                .font(.display(40))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, minHeight: 72)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.press)
                        .glassEffect(.clear, in: .rect(cornerRadius: 22))
                        .accessibilityIdentifier("approval.number.\(number)")
                    }
                }
                .padding(.bottom, 12)
                Button {
                    answer(allow: false, number: nil)
                } label: {
                    Text("Don't Allow")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .accessibilityIdentifier("approval.deny")
            }
        }
        .disabled(answering)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Color.ground.ignoresSafeArea() }
        .interactiveDismissDisabled(answering)
    }

    private func answer(allow: Bool, number: Int?) {
        answering = true
        allow ? HapticManager.medium() : HapticManager.light()
        Task {
            if await cloud.decide(request.id, allow: allow, number: number) == .wrongNumber {
                wrongNumber = true
            }
            // Still here means it didn't go through, or it was the wrong number: the sheet says which.
            answering = false
        }
    }
}

extension View {
    /// The Allow sheet, from whichever screen is on top. `active` is false where another sheet already covers this view.
    func approvalSheet(_ cloud: CloudSync, active: Bool = true) -> some View {
        sheet(item: Binding(
            get: { active ? cloud.pendingApproval : nil },
            set: { if $0 == nil { cloud.pendingApproval = nil } }
        )) { request in
            ApprovalView(cloud: cloud, request: request)
                .presentationDetents([.large])
                .presentationBackground(Color.ground)
        }
    }
}
