import SwiftUI

struct SMSOnboardingView: View {
    let onContinue: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var page = 0
    @State private var shortcutsUnavailable = false

    private let steps = [
        SetupStep(title: "Open Automation", detail: "In Shortcuts, open Automation and tap +.", imageName: "SMSSetup01Automation"),
        SetupStep(title: "Choose Message", detail: "Create a Personal Automation, then choose Message.", imageName: "SMSSetup02Message"),
        SetupStep(title: "Set the trigger", detail: "Leave Sender as Any Sender, then tap Message Contains.", imageName: "SMSSetup03Trigger"),
        SetupStep(title: "Run automatically", detail: "Enter your bank name, choose Run Immediately, then tap Next.", imageName: "SMSSetup04Immediate"),
        SetupStep(title: "Create the shortcut", detail: "Tap Create New Shortcut to add the DailyMint action.", imageName: "SMSSetup05Create"),
        SetupStep(title: "Find DailyMint", detail: "Search for DailyMint and choose Import Bank SMS.", imageName: "SMSSetup06Search"),
        SetupStep(title: "Connect the message", detail: "Use the blue Shortcut Input variable for Message. Do not type sample SMS text.", imageName: "SMSSetup07MessageInput"),
        SetupStep(title: "Connect the sender", detail: "Choose Sender from Shortcut Input when the Sender field is shown.", imageName: "SMSSetup08SenderInput"),
        SetupStep(title: "Save and repeat", detail: "Tap the blue checkmark, then repeat these steps for each bank.", imageName: "SMSSetup09Complete")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $page) {
                ForEach(steps.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(steps[index].title)
                                .font(.system(size: 30, weight: .semibold, design: .serif))
                                .foregroundStyle(Color.dmInk)
                            Text(steps[index].detail)
                                .font(.subheadline)
                                .foregroundStyle(Color.dmInkSoft)
                        }
                        ShortcutScreenshot(name: steps[index].imageName)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                    .tag(index)
                    .accessibilityIdentifier("smsOnboardingPage-\(index + 1)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            controls
        }
        .background(Color.dmPaper.ignoresSafeArea())
        .alert("Shortcuts unavailable", isPresented: $shortcutsUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Install Apple's Shortcuts app, then return to this guide.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if page > 0 {
                Button { withAnimation { page -= 1 } } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dmInk)
                .accessibilityLabel("Previous step")
                .accessibilityIdentifier("onboardingBack")
            } else {
                Color.clear.frame(width: 42, height: 42)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Set up bank messages")
                    .font(.headline)
                    .foregroundStyle(Color.dmInk)
                Text("Step \(page + 1) of \(steps.count)")
                    .font(.caption)
                    .foregroundStyle(Color.dmInkFaint)
            }
            Spacer()
            HStack(spacing: 5) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Color.dmFlow : Color.dmHairline)
                        .frame(width: index == page ? 18 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                Text("Only matching messages are sent by Shortcuts and processed on this iPhone.")
            }
            .font(.caption2)
            .foregroundStyle(Color.dmInkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            if page == steps.count - 1 {
                Button("Finish setup", action: onContinue)
                    .buttonStyle(PrimaryPillButtonStyle())
                    .accessibilityIdentifier("continueWithoutSMS")
            } else {
                Button {
                    withAnimation { page += 1 }
                } label: {
                    Label("Next step", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryPillButtonStyle())
                .accessibilityIdentifier("onboardingNext")
            }
            Button(action: launchShortcuts) {
                Label("Open Shortcuts", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryPillButtonStyle())
            .accessibilityIdentifier("openShortcuts")
            if page < steps.count - 1 {
                Button("Finish later", action: onContinue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.dmInkSoft)
                    .frame(minHeight: 32)
                    .accessibilityIdentifier("continueWithoutSMS")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.dmPaperRaised)
        .overlay(alignment: .top) { Rectangle().fill(Color.dmHairline).frame(height: 1) }
    }

    private func launchShortcuts() {
        guard let url = URL(string: "shortcuts://") else { return }
        openURL(url) { accepted in
            if !accepted { shortcutsUnavailable = true }
        }
    }
}

private struct SetupStep {
    let title: String
    let detail: String
    let imageName: String
}

private struct ShortcutScreenshot: View {
    let name: String

    var body: some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.dmHairline, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
