// "Allow Claude?" The only way a client gets to read anything: the phone says yes here, or on the notification.

import SwiftUI

struct ApprovalView: View {
    let cloud: CloudSync
    let request: ApprovalRequest

    @State private var answering = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Icon(request.isRecognised ? request.kind.icon : .plugs, size: 44)
                .foregroundStyle(.primary)
                .frame(width: 84, height: 84)
                .glassEffect(.clear, in: .circle)
                .padding(.bottom, 24)
            Text("Allow \(request.name)?")
                .font(.display(34))
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)
            Text("It will be able to read your people, places and meetings. It can't change anything.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !request.isRecognised {
                Text("This isn't the app you were connecting, or it's signing in from somewhere TouchTips doesn't know. Only allow it if you started this.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
            Spacer(minLength: 32)
            VStack(spacing: 10) {
                // The bright button is the safe answer when TouchTips doesn't know who's asking.
                choice("Allow", allow: true, prominent: request.isRecognised)
                    .accessibilityIdentifier("approval.allow")
                choice("Don't Allow", allow: false, prominent: !request.isRecognised)
                    .accessibilityIdentifier("approval.deny")
            }
            .disabled(answering)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Color.ground.ignoresSafeArea() }
        .interactiveDismissDisabled(answering)
    }

    @ViewBuilder
    private func choice(_ title: String, allow: Bool, prominent: Bool) -> some View {
        if prominent {
            Button { answer(allow) } label: {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.black).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.white)
            .controlSize(.large)
        } else {
            Button { answer(allow) } label: {
                Text(title).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }

    private func answer(_ allow: Bool) {
        answering = true
        allow ? HapticManager.medium() : HapticManager.light()
        Task {
            await cloud.decide(request.id, allow: allow)
            // Still here means it didn't go through; let them try again.
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
                .presentationDetents(request.isRecognised ? [.medium, .large] : [.large])
                .presentationBackground(Color.ground)
        }
    }
}
