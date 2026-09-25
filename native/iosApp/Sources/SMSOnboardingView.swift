import SwiftUI

struct SMSOnboardingView: View {
    let onContinue: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var page = 0
    @State private var shortcutsUnavailable = false

    private let steps = [
        SetupStep(title: "Open Automation", detail: "In Shortcuts, choose Automation and tap +."),
        SetupStep(title: "Choose Message", detail: "Create a Personal Automation, then choose Message."),
        SetupStep(title: "Choose a bank trigger", detail: "Enter your bank name and select Run Immediately."),
        SetupStep(title: "Find DailyMint", detail: "Search for DailyMint and choose Import Bank SMS."),
        SetupStep(title: "Connect the message", detail: "Pass Shortcut Input's Message and Sender to DailyMint."),
        SetupStep(title: "Save and repeat", detail: "Tap Done, then repeat for each bank that sends you alerts.")
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
                        setupVisual(index)
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

    @ViewBuilder
    private func setupVisual(_ index: Int) -> some View {
        switch index {
        case 0: AutomationVisual()
        case 1: MessageTriggerVisual()
        case 2: TriggerConfigurationVisual()
        case 3: DailyMintSearchVisual()
        case 4: ConnectMessageVisual()
        default: FinishedAutomationVisual()
        }
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
}

private struct AutomationVisual: View {
    var body: some View {
        ShortcutCanvas(title: "Automation") {
            HStack {
                Text("Personal").font(.title3.weight(.bold)).foregroundStyle(Color.dmInk)
                Spacer()
                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Color.dmInk)
                    .frame(width: 48, height: 48)
                    .background(Color.dmPaperRaised)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.dmFlow, lineWidth: 2))
            }
            MockFlowRow(title: "Bank message", subtitle: "Import Bank SMS")
            MockFlowRow(title: "Another bank", subtitle: "Import Bank SMS")
            Spacer(minLength: 0)
            HStack {
                MockTab(icon: "books.vertical.fill", label: "Library", selected: false)
                MockTab(icon: "checkmark.circle.fill", label: "Automation", selected: true)
                MockTab(icon: "square.grid.2x2.fill", label: "Gallery", selected: false)
            }
        }
    }
}

private struct MessageTriggerVisual: View {
    var body: some View {
        ShortcutCanvas(title: "Personal Automation") {
            MockChoiceRow(icon: "clock.fill", color: .dmInvest, title: "Time of Day")
            MockChoiceRow(icon: "alarm.fill", color: .dmInvest, title: "Alarm")
            MockChoiceRow(icon: "envelope.fill", color: .dmFlow, title: "Email")
            MockChoiceRow(icon: "message.fill", color: .dmIncome, title: "Message", highlighted: true)
            Spacer(minLength: 0)
        }
    }
}

private struct TriggerConfigurationVisual: View {
    var body: some View {
        ShortcutCanvas(title: "When") {
            MockSettingRow(label: "Sender", value: "Any Sender")
            MockSettingRow(label: "Message Contains", value: "Your bank")
            VStack(spacing: 0) {
                MockSelectionRow(title: "Run After Confirmation", selected: false)
                Divider().background(Color.dmHairline)
                MockSelectionRow(title: "Run Immediately", selected: true)
            }
            .padding(.horizontal, 16)
            .background(Color.dmPaperRaised)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("Use the name or code that appears in your bank's alerts.")
                .font(.caption)
                .foregroundStyle(Color.dmInkFaint)
            Spacer(minLength: 0)
        }
    }
}

private struct DailyMintSearchVisual: View {
    var body: some View {
        ShortcutCanvas(title: "Add an action") {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.dmInkSoft)
                Text("DailyMint").foregroundStyle(Color.dmInk)
                Spacer()
            }
            .padding(14)
            .background(Color.dmHairline.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(spacing: 12) {
                DailyMintGlyph()
                Text("DailyMint").font(.headline).foregroundStyle(Color.dmInk)
            }
            HStack(spacing: 12) {
                DailyMintGlyph(size: 32)
                Text("Import Bank SMS").font(.headline).foregroundStyle(Color.dmInk)
                Spacer()
                Image(systemName: "info.circle").foregroundStyle(Color.dmInkFaint)
            }
            .padding(16)
            .background(Color.dmPaperRaised)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.dmFlow, lineWidth: 2))
            Spacer(minLength: 0)
        }
    }
}

private struct ConnectMessageVisual: View {
    var body: some View {
        ShortcutCanvas(title: "Connect the message") {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(Color.dmFlow)
                Text("Receive messages as input").font(.headline).foregroundStyle(Color.dmInk)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dmPaperRaised)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    DailyMintGlyph(size: 30)
                    Text("Import").font(.headline)
                    ShortcutToken(text: "Message")
                }
                HStack(spacing: 8) {
                    Text("from").font(.headline)
                    ShortcutToken(text: "Sender")
                }
            }
            .foregroundStyle(Color.dmInk)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dmPaperRaised)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("Tap each blue field and choose the matching value from Shortcut Input.")
                .font(.caption)
                .foregroundStyle(Color.dmInkFaint)
            Spacer(minLength: 0)
        }
    }
}

private struct FinishedAutomationVisual: View {
    var body: some View {
        ShortcutCanvas(title: "You're ready") {
            MockFlowRow(title: "Your bank", subtitle: "Import Bank SMS")
            VStack(alignment: .leading, spacing: 14) {
                ChecklistRow(text: "Run Immediately is selected")
                ChecklistRow(text: "Message and Sender are connected")
                ChecklistRow(text: "Tap Done in Shortcuts")
                ChecklistRow(text: "The next matching transaction appears in Ledger")
            }
            .padding(18)
            .background(Color.dmPaperRaised)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Color.dmFlow)
                Text("Repeat these steps for each bank name you want DailyMint to capture.")
                    .font(.subheadline)
                    .foregroundStyle(Color.dmInkSoft)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ShortcutCanvas<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.dmInk)
                .frame(maxWidth: .infinity, alignment: .center)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.dmFlowSoft.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.dmHairline, lineWidth: 1))
    }
}

private struct MockFlowRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "message.fill").foregroundStyle(Color.dmIncome)
                Image(systemName: "arrow.right").foregroundStyle(Color.dmInkFaint)
                DailyMintGlyph(size: 30)
            }
            Text(title).font(.headline).foregroundStyle(Color.dmInk)
            Text(subtitle).font(.caption).foregroundStyle(Color.dmInkFaint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dmPaperRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MockChoiceRow: View {
    let icon: String
    let color: Color
    let title: String
    var highlighted = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 28)
            Text(title).font(.headline).foregroundStyle(Color.dmInk)
            Spacer()
            Image(systemName: highlighted ? "checkmark.circle.fill" : "chevron.right")
                .foregroundStyle(highlighted ? Color.dmFlow : Color.dmInkFaint)
        }
        .padding(16)
        .background(Color.dmPaperRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(highlighted ? Color.dmFlow : Color.clear, lineWidth: 2))
    }
}

private struct MockSettingRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(Color.dmInk)
            Spacer()
            Text(value).foregroundStyle(Color.dmFlow)
        }
        .padding(16)
        .background(Color.dmPaperRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MockSelectionRow: View {
    let title: String
    let selected: Bool
    var body: some View {
        HStack {
            Text(title).foregroundStyle(Color.dmInk)
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(Color.dmFlow) }
        }
        .padding(.vertical, 14)
    }
}

private struct ShortcutToken: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(Color.dmFlow)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.dmFlowSoft)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ChecklistRow: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.dmIncome)
            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(Color.dmInk)
        }
    }
}

private struct MockTab: View {
    let icon: String
    let label: String
    let selected: Bool
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3)
            Text(label).font(.caption2)
        }
        .foregroundStyle(selected ? Color.dmFlow : Color.dmInkSoft)
        .frame(maxWidth: .infinity)
    }
}

private struct DailyMintGlyph: View {
    var size: CGFloat = 36
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Color.dmIncome)
            Image(systemName: "leaf.fill")
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(Color.white)
        }
        .frame(width: size, height: size)
    }
}
