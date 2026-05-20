import SwiftUI

enum Theme {
    static let navy = Color(red: 26/255, green: 50/255, blue: 99/255)
    static let slate = Color(red: 84/255, green: 119/255, blue: 146/255)
    static let amber = Color(red: 250/255, green: 185/255, blue: 91/255)
    static let cream = Color(red: 232/255, green: 226/255, blue: 219/255)
    static let coffee = Color(red: 78/255, green: 52/255, blue: 36/255)

    static let darkBg = Color(red: 10/255, green: 20/255, blue: 40/255)

    enum R {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 9
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let hero: CGFloat = 28
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? amber : coffee
    }

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkBg : cream
    }

    static func panel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? navy.opacity(0.85) : Color.white.opacity(0.5)
    }

    static func barBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? navy : Color.white.opacity(0.7)
    }

    static func text(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? cream : navy
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        slate
    }

    static func hover(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : navy.opacity(0.08)
    }

    static func divider(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : navy.opacity(0.1)
    }
}

struct Squircle: InsettableShape {
    var radius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = max(0, radius - insetAmount)
        return RoundedRectangle(cornerRadius: r, style: .continuous)
            .path(in: rect.insetBy(dx: insetAmount, dy: insetAmount))
    }

    func inset(by amount: CGFloat) -> Squircle {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

extension View {
    func squircle(_ color: Color, radius: CGFloat = Theme.R.lg) -> some View {
        background(Squircle(radius: radius).fill(color))
    }

    func squircleStroke(_ color: Color, lineWidth: CGFloat = 1, radius: CGFloat = Theme.R.lg) -> some View {
        overlay(Squircle(radius: radius).strokeBorder(color, lineWidth: lineWidth))
    }

    func squircleClip(radius: CGFloat = Theme.R.lg) -> some View {
        clipShape(Squircle(radius: radius))
    }
}

struct SquircleButtonStyle: ButtonStyle {
    enum Variant { case tinted, prominent, destructive }
    var variant: Variant = .tinted
    var radius: CGFloat = Theme.R.md
    var scheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let bg: Color
        let fg: Color
        switch variant {
        case .tinted:
            bg = Theme.hover(scheme).opacity(pressed ? 1.6 : 1)
            fg = Theme.text(scheme)
        case .prominent:
            bg = Theme.accent(scheme).opacity(pressed ? 0.85 : 1)
            fg = scheme == .dark ? Theme.navy : Theme.cream
        case .destructive:
            bg = Color.red.opacity(pressed ? 0.85 : 0.9)
            fg = .white
        }
        return configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .squircle(bg, radius: radius)
            .contentShape(Squircle(radius: radius))
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

struct CapsulePillButtonStyle: ButtonStyle {
    enum Variant { case tinted, accent }
    var variant: Variant = .tinted
    var scheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let bg: Color
        let fg: Color
        switch variant {
        case .tinted:
            bg = Theme.hover(scheme).opacity(pressed ? 1.6 : 1)
            fg = Theme.text(scheme)
        case .accent:
            bg = Theme.accent(scheme).opacity(pressed ? 0.18 : 0.14)
            fg = Theme.accent(scheme)
        }
        return configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Capsule(style: .continuous).fill(bg))
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

struct ChromeButton<Label: View>: View {
    var size: CGFloat = 32
    var radius: CGFloat = Theme.R.md
    var scheme: ColorScheme
    var action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hover = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: size, height: size)
                .foregroundColor(Theme.text(scheme))
                .background(
                    Squircle(radius: radius)
                        .fill(hover ? Theme.hover(scheme) : Color.clear)
                )
                .contentShape(Squircle(radius: radius))
                .scaleEffect(pressed ? 0.92 : 1)
                .animation(.easeOut(duration: 0.1), value: pressed)
                .animation(.easeOut(duration: 0.12), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

struct SquircleSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, label: String, icon: String?)]
    let scheme: ColorScheme
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                segment(for: option)
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.hover(scheme).opacity(0.7))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Theme.divider(scheme), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func segment(for option: (value: T, label: String, icon: String?)) -> some View {
        let isSelected = selection == option.value
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selection = option.value
            }
        } label: {
            HStack(spacing: 6) {
                if let icon = option.icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(option.label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(isSelected ? Theme.accent(scheme) : Theme.secondaryText(scheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                ZStack {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(scheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.95))
                            .shadow(color: Color.black.opacity(scheme == .dark ? 0.25 : 0.08),
                                    radius: 3, y: 1)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
