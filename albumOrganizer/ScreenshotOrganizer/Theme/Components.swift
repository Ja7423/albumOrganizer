import SwiftUI

/// `.hr` / `var(--color-divider)` hairline.
struct Hairline: View {
    var color: Color = Palette.divider
    var body: some View {
        Rectangle().fill(color).frame(height: 1)
    }
}

/// The small tracked label above titles and sections (12pt, 0.06em, neutral-700).
struct Kicker: View {
    var text: String
    var color: Color = Palette.neutral700
    var tracking: CGFloat = 0.06

    init(_ text: String, color: Color = Palette.neutral700, tracking: CGFloat = 0.06) {
        self.text = text
        self.color = color
        self.tracking = tracking
    }

    var body: some View {
        Text(text)
            .font(Typeface.body(12))
            .tracking(12 * tracking)
            .foregroundStyle(color)
    }
}

/// The 34pt screen title with its kicker, ruled underneath.
struct ScreenHeader<Trailing: View>: View {
    var kicker: String?
    var title: String
    var topPadding: CGFloat = 42
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    if let kicker { Kicker(kicker) }
                    Text(title)
                        .font(Typeface.head(34))
                        .tracking(-0.34)
                        .lineLimit(1)
                        .foregroundStyle(Palette.text)
                }
                Spacer(minLength: 0)
                trailing.fixedSize()
            }
            .padding(.top, topPadding)
            .padding(.bottom, 12)
            Hairline()
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(kicker: String? = nil, title: String, topPadding: CGFloat = 42) {
        self.init(kicker: kicker, title: title, topPadding: topPadding) { EmptyView() }
    }
}

/// `.tag` and its variants.
struct TagChip: View {
    enum Style { case accent, neutral, outline }
    enum Size {
        case small, regular, large
        var font: CGFloat { switch self { case .small: 12; case .regular: 13; case .large: 14 } }
        var vertical: CGFloat { switch self { case .small: 5; case .regular: 6; case .large: 7 } }
        var horizontal: CGFloat { switch self { case .small: 9; case .regular: 10; case .large: 12 } }
        var icon: CGFloat { switch self { case .small: 11; case .regular, .large: 12 } }
    }

    var text: String = ""
    var style: Style
    var size: Size = .regular
    var leadingIcon: String? = nil
    var trailingIcon: String? = nil
    var horizontalPadding: CGFloat? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let leadingIcon { Image(systemName: leadingIcon).font(.system(size: size.icon, weight: .medium)) }
            if !text.isEmpty { Text(text).lineLimit(1) }
            if let trailingIcon { Image(systemName: trailingIcon).font(.system(size: size.icon, weight: .medium)) }
        }
        .font(Typeface.body(size.font))
        .tracking(size.font * 0.02)
        .foregroundStyle(foreground)
        .padding(.vertical, size.vertical)
        .padding(.horizontal, horizontalPadding ?? size.horizontal)
        .background(RoundedRectangle(cornerRadius: Radius.md * 0.75).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: Radius.md * 0.75).strokeBorder(style == .outline ? Palette.accent : .clear, lineWidth: 1))
        .fixedSize()
    }

    private var foreground: Color {
        switch style {
        case .accent: return Palette.accent800
        case .neutral: return Palette.neutral800
        case .outline: return Palette.accent
        }
    }

    private var fill: Color {
        switch style {
        case .accent: return Palette.accent100
        case .neutral: return Palette.neutral100
        case .outline: return .clear
        }
    }
}

/// A key/value row under a hairline (資訊 metadata).
struct MetaRow: View {
    var key: String
    var value: String
    var fontSize: CGFloat = 13
    var vertical: CGFloat = 8

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(key).foregroundStyle(Palette.neutral700)
                Spacer(minLength: 0)
                Text(value).multilineTextAlignment(.trailing)
            }
            .font(Typeface.body(fontSize))
            .padding(.vertical, vertical)
            Hairline()
        }
    }
}

/// Kicker over things the app added on its own.
struct AutoLabel: View {
    var text = "自動偵測"
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 12))
            Text(text)
        }
        .font(Typeface.body(12))
        .tracking(0.72)
        .foregroundStyle(Palette.accent700)
    }
}

/// Wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
