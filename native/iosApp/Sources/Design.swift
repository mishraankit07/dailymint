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
    static let dmInkSoft = adaptive(light: 0x3F4D42, dark: 0xC0CEC1)
    static let dmInkFaint = adaptive(light: 0x59665A, dark: 0xA0B1A3)
    static let dmHairline = adaptive(light: 0xD8DBCC, dark: 0x394B40)
    static let dmFlow = adaptive(light: 0x1F6F78, dark: 0x81CDD0)
    static let dmFlowSoft = adaptive(light: 0xE4EEEC, dark: 0x284047)
    static let dmIncome = adaptive(light: 0x3F8F5F, dark: 0x73C995)
    static let dmSpend = adaptive(light: 0xC1594A, dark: 0xF18B7B)
    static let dmInvest = adaptive(light: 0xC99A3D, dark: 0xE4B96A)
    static let dmNav = adaptive(light: 0xF8F9F3, dark: 0x17261F)
    static let dmNavSelected = adaptive(light: 0x1F6F78, dark: 0x81CDD0)
    static let dmActionFill = adaptive(light: 0x17261F, dark: 0x81CDD0)
    static let dmActionText = adaptive(light: 0xF8F9F3, dark: 0x111B18)
    static let dmHeroText = adaptive(light: 0x17261F, dark: 0xF8F9F3)
    static let dmHeroMuted = adaptive(light: 0x3F4D42, dark: 0xB9C6BC)
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

struct StableMenu<MenuContent: View, Label: View>: View {
    @State private var isPresented = false
    private let menuContent: MenuContent
    private let label: Label

    init(@ViewBuilder _ content: () -> MenuContent, @ViewBuilder label: () -> Label) {
        menuContent = content()
        self.label = label()
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog(
            "Choose an option",
            isPresented: $isPresented,
            titleVisibility: .hidden
        ) {
            menuContent
        }
    }
}

struct ScreenSurface<Content: View>: View {
    @ViewBuilder var content: Content
    private let bottomContentClearance: CGFloat = 84

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, bottomContentClearance)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissKeyboard()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(
            Color.dmPaper
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissKeyboard()
                }
        )
    }
}

func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

struct PrimaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.dmActionText)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            .background(Color.dmActionFill.opacity(configuration.isPressed ? 0.86 : 1))
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
    @Environment(\.colorScheme) private var colorScheme
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
                    VStack(spacing: 2) {
                        ZStack {
                            Circle()
                                .fill(selected == tab && !isCenterAction(tab) ? Color.dmFlowSoft : Color.clear)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle().stroke(
                                        selected == tab && !isCenterAction(tab)
                                            ? Color.dmNavSelected.opacity(0.45)
                                            : (isCenterAction(tab) ? Color.dmHairline : Color.clear),
                                        lineWidth: 1
                                    )
                                )
                            Image(systemName: icon(tab))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(selected == tab && !isCenterAction(tab) ? Color.dmNavSelected : Color.dmInkSoft)
                        }
                        .frame(height: 36)
                        Text(title(tab))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(selected == tab && !isCenterAction(tab) ? Color.dmNavSelected : Color.dmInkSoft)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
                .accessibilityLabel(title(tab))
                .accessibilityIdentifier("tab-" + title(tab))
                .accessibilityAddTraits(selected == tab && !isCenterAction(tab) ? .isSelected : [])
            }
        }
        .frame(height: 50)
        .padding(.horizontal, 8)
        .padding(.top, 5)
        .padding(.bottom, 4)
        .background { Rectangle().fill(Color.dmNav).ignoresSafeArea(edges: .bottom) }
        .overlay(alignment: .top) { Rectangle().fill(Color.dmHairline).frame(height: 1) }
        .id(colorScheme)
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
    var subtitle = "Money made clear"
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

struct ChipFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let availableWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0
        var contentHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0 && rowWidth + horizontalSpacing + size.width > availableWidth {
                contentWidth = max(contentWidth, rowWidth)
                contentHeight += rowHeight + verticalSpacing
                rowWidth = 0
                rowHeight = 0
            }
            if rowWidth > 0 { rowWidth += horizontalSpacing }
            rowWidth += size.width
            rowHeight = max(rowHeight, size.height)
        }

        contentWidth = max(contentWidth, rowWidth)
        contentHeight += rowHeight
        return CGSize(width: proposal.width ?? contentWidth, height: contentHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
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
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct SelectableCategoryChip: View {
    let name: String
    let selected: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                CategoryDot(name: name, size: 9)
                Text(name)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.leading)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                }
            }
            .foregroundStyle(selected ? Color.dmPaperRaised : categoryColor(name))
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(selected ? categoryColor(name) : Color.dmPaperRaised)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(categoryColor(name), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

struct PaperAmountField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        FormattedAmountTextField(placeholder: placeholder, text: $text)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.dmPaperRaised)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.dmHairline, lineWidth: 1))
    }
}

struct FormattedAmountTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .decimalPad
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.borderStyle = .none
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        field.placeholder = placeholder
        field.textColor = UIColor(Color.dmInk)
        field.tintColor = UIColor(Color.dmFlow)
        if field.text != text {
            field.text = text
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: FormattedAmountTextField

        init(parent: FormattedAmountTextField) {
            self.parent = parent
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let current = textField.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return false }

            let candidate = current.replacingCharacters(in: swiftRange, with: string)
            let candidateCaretOffset = range.location + string.utf16.count
            let candidatePrefix = (candidate as NSString).substring(to: min(candidateCaretOffset, candidate.utf16.count))
            let logicalCaretOffset = candidatePrefix.filter { $0 != "," }.count
            let formatted = AmountInputFormatter.formatted(candidate)

            textField.text = formatted
            parent.text = formatted

            let visualCaretOffset = Self.visualCaretOffset(
                in: formatted,
                afterLogicalCharacters: logicalCaretOffset
            )
            if let position = textField.position(from: textField.beginningOfDocument, offset: visualCaretOffset) {
                textField.selectedTextRange = textField.textRange(from: position, to: position)
            }
            return false
        }

        private static func visualCaretOffset(in value: String, afterLogicalCharacters target: Int) -> Int {
            guard target > 0 else { return 0 }
            var logicalOffset = 0
            for (offset, character) in value.enumerated() {
                if character != "," {
                    logicalOffset += 1
                }
                if logicalOffset == target {
                    return offset + 1
                }
            }
            return value.count
        }
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

struct CategorySelectionSheet: View {
    let title: String
    let options: [String]
    @Binding var selection: String
    @Binding var isPresented: Bool
    var optionIdentifierPrefix: String?
    var addActionTitle: String?
    var addActionIdentifier: String?
    var onSelection: ((String) -> Void)?
    var onAdd: (() -> Void)?
    var optionLabel: (String) -> String = { $0 == "All" ? "All categories" : $0 }

    private var uniqueOptions: [String] {
        options.reduce(into: []) { result, option in
            if !result.contains(option) { result.append(option) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(uniqueOptions, id: \.self) { option in
                    Button {
                        selection = option
                        onSelection?(option)
                        DispatchQueue.main.async {
                            isPresented = false
                        }
                    } label: {
                        HStack {
                            CategoryDot(name: option, size: 10)
                            Text(optionLabel(option))
                                .foregroundStyle(Color.dmInk)
                            Spacer()
                            if option == selection {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.dmFlow)
                            }
                        }
                    }
                    .accessibilityIdentifier(optionIdentifier(option))
                }

                if let addActionTitle, let onAdd {
                    Button {
                        onAdd()
                        DispatchQueue.main.async {
                            isPresented = false
                        }
                    } label: {
                        Label(addActionTitle, systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.dmFlow)
                    }
                    .accessibilityIdentifier(addActionIdentifier ?? "")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.dmPaper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func optionIdentifier(_ option: String) -> String {
        guard let optionIdentifierPrefix else { return "" }
        return "\(optionIdentifierPrefix)-\(option)"
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
