import SwiftUI

/// `.btn` and its variants. Primary is an accent outline, never a fill.
struct ClassicalButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, plain }

    var kind: Kind
    var fullWidth = false
    var alignment: Alignment = .center
    var fontSize: CGFloat = 14
    var minHeight: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, style: self)
    }

    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        let style: ClassicalButtonStyle
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            HStack(spacing: 6) { configuration.label }
                .font(Typeface.head(style.fontSize))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.vertical, Space.s2)
                .padding(.horizontal, style.kind == .ghost ? Space.s1 : Space.s3 * 1.2)
                .frame(minHeight: style.minHeight)
                .frame(maxWidth: style.fullWidth ? .infinity : nil, alignment: style.alignment)
                .background(RoundedRectangle(cornerRadius: Radius.md).fill(pressedFill))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(border, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: Radius.md))
                .opacity(isEnabled ? 1 : 0.45)
        }

        private var foreground: Color {
            switch style.kind {
            case .primary, .ghost: return Palette.accent
            case .secondary, .plain: return Palette.text
            }
        }

        private var border: Color {
            switch style.kind {
            case .primary: return Palette.accent
            case .secondary: return Palette.divider
            case .ghost, .plain: return .clear
            }
        }

        private var pressedFill: Color {
            guard configuration.isPressed else { return .clear }
            switch style.kind {
            case .primary: return Palette.accent.opacity(0.22)
            case .secondary, .plain: return Palette.text.opacity(0.14)
            case .ghost: return Palette.accent.opacity(0.18)
            }
        }
    }
}

/// `.btn-icon`: a 36pt square.
struct IconButtonStyle: ButtonStyle {
    var kind: ClassicalButtonStyle.Kind = .ghost
    var size: CGFloat = 36
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, style: self)
    }

    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        let style: IconButtonStyle
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(style.tint ?? (style.kind == .secondary ? Palette.text : Palette.accent))
                .frame(width: style.size, height: style.size)
                .background(RoundedRectangle(cornerRadius: Radius.md).fill(configuration.isPressed ? Palette.accent.opacity(0.18) : .clear))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(style.kind == .secondary ? Palette.divider : .clear, lineWidth: 1))
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.45)
        }
    }
}

/// Rows and chips that are tappable but carry their own look.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(configuration.isPressed ? Palette.text.opacity(0.04) : .clear)
    }
}

extension ButtonStyle where Self == ClassicalButtonStyle {
    static var primary: ClassicalButtonStyle {
        ClassicalButtonStyle(kind: .primary)
    }

    static var secondary: ClassicalButtonStyle {
        ClassicalButtonStyle(kind: .secondary)
    }

    static var ghost: ClassicalButtonStyle {
        ClassicalButtonStyle(kind: .ghost)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle {
        PressableStyle()
    }
}
