import SwiftUI
import UIKit

extension Color {
    private static func adaptive(light: UInt, dark: UInt) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static let dmPaper = adaptive(light: 0xEEF0E6, dark: 0x111B18)
    static let dmPaperRaised = adaptive(light: 0xF8F9F3, dark: 0x1C2923)
    static let dmInk = adaptive(light: 0x17261F, dark: 0xF0F4EB)
    static let dmInkSoft = adaptive(light: 0x4B594E, dark: 0xC0CEC1)
    static let dmInkFaint = adaptive(light: 0x707D70, dark: 0xA0B1A3)
    static let dmHairline = adaptive(light: 0xD8DBCC, dark: 0x394B40)
    static let dmFlow = adaptive(light: 0x1F6F78, dark: 0x81CDD0)
    static let dmFlowSoft = adaptive(light: 0xE4EEEC, dark: 0x284047)
    static let dmIncome = adaptive(light: 0x3F8F5F, dark: 0x73C995)
    static let dmSpend = adaptive(light: 0xC1594A, dark: 0xF18B7B)
    static let dmInvest = adaptive(light: 0xC99A3D, dark: 0xE4B96A)
    static let dmNav = adaptive(light: 0xF8F9F3, dark: 0x17261F)
    static let dmNavSelected = adaptive(light: 0x1F6F78, dark: 0x81CDD0)
    static let dmHeroText = Color(red: 0.973, green: 0.976, blue: 0.953)
    static let dmHeroMuted = Color(red: 0.725, green: 0.776, blue: 0.737)
    static let dmCategoryHome = adaptive(light: 0x5E7FA3, dark: 0x9BBDE0)
    static let dmCategoryGroceries = adaptive(light: 0x7C8F3F, dark: 0xB4CE75)
    static let dmCategoryGym = adaptive(light: 0x7B5AA6, dark: 0xBBA0DF)
    static let dmCategorySelf = adaptive(light: 0x2E8F8A, dark: 0x72CFC6)
    static let dmCategoryOther = adaptive(light: 0x76766F, dark: 0xB7C2B5)
}

struct RaisedPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dmPaperRaised)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.dmHairline, lineWidth: 1))
    }
}

struct ScreenSurface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.dmPaper.ignoresSafeArea())
    }
}

struct PrimaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.dmHeroText)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Color.dmInk.opacity(configuration.isPressed ? 0.86 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SecondaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.dmInk)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Color.dmPaperRaised.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.dmHairline, lineWidth: 1))
    }
}

struct DestructivePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.dmSpend)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Color.dmPaperRaised.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.dmSpend.opacity(0.45), lineWidth: 1))
    }
}

struct DockedTabBar<Tab: Hashable>: View {
    let tabs: [Tab]
    let selected: Tab
    let title: (Tab) -> String
    let icon: (Tab) -> String
    let isCenterAction: (Tab) -> Bool
    let action: (Tab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    action(tab)
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if isCenterAction(tab) {
                                Circle()
                                    .fill(Color.dmInk)
                                    .frame(width: 42, height: 42)
                            }
                            Image(systemName: icon(tab))
                                .font(.system(size: isCenterAction(tab) ? 22 : 20, weight: .semibold))
                                .foregroundStyle(isCenterAction(tab) ? Color.dmHeroText : (selected == tab ? Color.dmNavSelected : Color.dmInkSoft))
                        }
                        .frame(height: 42)
                        Text(title(tab))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(selected == tab && !isCenterAction(tab) ? Color.dmNavSelected : Color.dmInkSoft)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(tab))
                .accessibilityAddTraits(selected == tab && !isCenterAction(tab) ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Color.dmNav)
        .overlay(alignment: .top) { Rectangle().fill(Color.dmHairline).frame(height: 1) }
    }
}

struct HairlineBlock<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BrandHeader: View {
    let title: String
    var subtitle = "Know your flow"
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(subtitle).font(.caption.weight(.semibold)).foregroundStyle(Color.dmInkFaint)
            Text(title)
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundStyle(Color.dmInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }
}

struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.dmInkFaint)
    }
}

struct CategoryDot: View {
    let name: String
    var size: CGFloat = 10
    var body: some View {
        Circle()
            .fill(categoryColor(name))
            .frame(width: size, height: size)
    }
}

struct IconBubble: View {
    let category: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(categoryColor(category).opacity(0.14))
            CategoryDot(name: category, size: 11)
        }
        .frame(width: 34, height: 34)
    }
}

struct CategoryChip: View {
    let name: String
    let removable: Bool
    var onDelete: (() -> Void)?
    var body: some View {
        HStack(spacing: 7) {
            CategoryDot(name: name, size: 9)
            Text(name)
                .font(.caption.weight(.semibold))
            if removable {
                Button {
                    onDelete?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete " + name)
            }
        }
        .foregroundStyle(categoryColor(name))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.dmPaperRaised)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(categoryColor(name), lineWidth: 1))
    }
}

struct PaperField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboard)
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(Color.dmInk)
            .tint(Color.dmFlow)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.dmPaperRaised)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.dmHairline, lineWidth: 1))
    }
}

struct PaperSegment<Selection: Hashable>: View {
    let title: String
    let value: Selection
    @Binding var selection: Selection
    var body: some View {
        Button {
            selection = value
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selection == value ? Color.dmPaperRaised : Color.dmInkSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selection == value ? Color.dmInk : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct PaperOption: View {
    let title: String
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(active ? Color.dmPaperRaised : Color.dmInkSoft)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(active ? Color.dmInk : Color.dmPaperRaised)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.dmHairline, lineWidth: active ? 0 : 1))
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeading: View {
    let title: String
    var trailing: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline).foregroundStyle(Color.dmInk)
            Spacer()
            if let trailing {
                Text(trailing).font(.caption.weight(.semibold)).foregroundStyle(Color.dmFlow)
            }
        }
        .padding(.top, 8)
    }
}

func categoryColor(_ name: String) -> Color {
    switch name.lowercased() {
    case "home", "house": return .dmCategoryHome
    case "groceries": return .dmCategoryGroceries
    case "food": return .dmIncome
    case "fun": return .dmSpend
    case "gym": return .dmCategoryGym
    case "self": return .dmCategorySelf
    case "investment", "investments": return .dmInvest
    default: return .dmCategoryOther
    }
}
