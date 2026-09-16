import SwiftUI

extension Color {
    static let dmPaper = Color(red: 0.933, green: 0.941, blue: 0.902)
    static let dmPaperRaised = Color(red: 0.973, green: 0.976, blue: 0.953)
    static let dmInk = Color(red: 0.090, green: 0.149, blue: 0.122)
    static let dmInkSoft = Color(red: 0.294, green: 0.349, blue: 0.306)
    static let dmInkFaint = Color(red: 0.545, green: 0.588, blue: 0.545)
    static let dmHairline = Color(red: 0.847, green: 0.859, blue: 0.800)
    static let dmFlow = Color(red: 0.122, green: 0.435, blue: 0.471)
    static let dmIncome = Color(red: 0.247, green: 0.561, blue: 0.373)
    static let dmSpend = Color(red: 0.757, green: 0.349, blue: 0.290)
    static let dmInvest = Color(red: 0.788, green: 0.604, blue: 0.239)
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
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.dmHairline, lineWidth: 1))
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
