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
    static let dmNav = Color(red: 0.090, green: 0.149, blue: 0.122)
    static let dmNavSelected = Color(red: 0.53, green: 0.84, blue: 0.67)
    static let dmHeroText = Color(red: 0.973, green: 0.976, blue: 0.953)
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
            .foregroundStyle(Color.dmInk)
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
    case "home", "house": return Color(red: 0.369, green: 0.498, blue: 0.639)
    case "groceries": return Color(red: 0.486, green: 0.561, blue: 0.247)
    case "food": return .dmIncome
    case "fun": return .dmSpend
    case "gym": return Color(red: 0.482, green: 0.353, blue: 0.651)
    case "self": return Color(red: 0.180, green: 0.561, blue: 0.541)
    case "investment", "investments": return .dmInvest
    default: return Color(red: 0.541, green: 0.541, blue: 0.494)
    }
}
