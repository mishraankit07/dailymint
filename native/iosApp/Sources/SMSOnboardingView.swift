import SwiftUI

struct SMSOnboardingView: View {
    let onContinue: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var latestReceipt: ShortcutImportReceipt?
    @State private var shortcutsUnavailable = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BrandHeader(title: "Set up DailyMint")
                Text("Connect incoming messages with Apple's Shortcuts app. DailyMint checks them on your iPhone and adds recognized transactions.")
                    .font(.subheadline)
                    .foregroundStyle(Color.dmInkSoft)

                step(1, "Choose a message trigger", "In Shortcuts, open Automation, tap +, then choose Message. Pick the senders or text that cover your bank alerts. For broad coverage, choose Any Sender and a single space in Message Contains if Shortcuts requires a filter. Messages without a space will not match that filter.")
                step(2, "Run automatically", "Choose Run Immediately, then Create New Shortcut. If a Receive block appears at the top, set its input type to Messages.")
                step(3, "Send the message to DailyMint", "Search for DailyMint and add Capture Incoming SMS. Set Message to Shortcut Input's Message or Content. Set Sender to Shortcut Input's Sender if available. Leave the variable connected; do not type a sample message into the field.")
                step(4, "Save and check", "Tap Done in Shortcuts. After the next matching message arrives, return here to check whether DailyMint received it.")

                RaisedPanel {
                    SectionHeading(title: "Connection status")
                    if let receipt = latestReceipt {
                        Label(receipt.status.capitalized, systemImage: receipt.status == "transaction added" ? "checkmark.circle.fill" : "info.circle")
                            .foregroundStyle(receipt.status == "transaction added" ? Color.dmIncome : Color.dmFlow)
                            .accessibilityIdentifier("smsSetupStatus")
                        Text(receipt.status == "empty input"
                             ? "The automation ran, but its Message field did not contain the SMS body. Reopen the action and select the message variable."
                             : "Last received \(receipt.timestamp). A message reached the DailyMint action.")
                            .font(.caption)
                            .foregroundStyle(Color.dmInkSoft)
                    } else {
                        Text("Waiting for the first message from Shortcuts")
                            .foregroundStyle(Color.dmInkSoft)
                            .accessibilityIdentifier("smsSetupStatus")
                    }
                    Button("Check again", action: refreshReceipt)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("checkSMSSetup")
                }

                Text("Shortcuts controls which messages trigger the automation. DailyMint does not read your Messages inbox, and message processing stays on this device. You can revisit this guide in Settings.")
                    .font(.caption)
                    .foregroundStyle(Color.dmInkFaint)
            }
            .padding(20)
        }
        .background(Color.dmPaper)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                Button(action: launchShortcuts) {
                    Label("Open Shortcuts", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.dmNav)
                .accessibilityIdentifier("openShortcuts")
                Button("Continue to DailyMint", action: onContinue)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("continueWithoutSMS")
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(Color.dmPaperRaised)
        }
        .onAppear(perform: refreshReceipt)
        .onChange(of: scenePhase) { phase in
            if phase == .active { refreshReceipt() }
        }
        .alert("Shortcuts unavailable", isPresented: $shortcutsUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Install Apple's Shortcuts app, then return to this guide.")
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        RaisedPanel {
            HStack(alignment: .top, spacing: 12) {
                Text(String(number))
                    .font(.headline)
                    .foregroundStyle(Color.dmFlow)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline).foregroundStyle(Color.dmInk)
                    Text(detail).font(.subheadline).foregroundStyle(Color.dmInkSoft)
                }
            }
        }
    }

    private func refreshReceipt() {
        latestReceipt = ShortcutImportLog.recent(limit: 1).first
    }

    private func launchShortcuts() {
        guard let url = URL(string: "shortcuts://") else { return }
        openURL(url) { accepted in
            if !accepted { shortcutsUnavailable = true }
        }
    }
}
