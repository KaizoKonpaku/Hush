import SwiftUI

enum HushStyle {
    static let accent = Color.teal
    static let amber = Color.orange

    static var minimumHitSize: CGFloat {
        #if os(macOS)
        28
        #else
        44
        #endif
    }

    static var canvas: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #elseif os(visionOS) || os(tvOS)
        Color.clear
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    static var surface: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #elseif os(visionOS) || os(tvOS)
        Color.white.opacity(0.09)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}

struct WorkspaceBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            HushStyle.canvas
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.55, 0.55], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ], colors: [
                HushStyle.canvas, HushStyle.canvas, HushStyle.accent.opacity(0.10),
                HushStyle.canvas, HushStyle.canvas, HushStyle.canvas,
                HushStyle.amber.opacity(0.07), HushStyle.canvas, HushStyle.accent.opacity(0.12)
            ])
            .opacity(colorScheme == .dark ? 0.7 : 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct HushMark: View {
    var size: CGFloat = 32
    var body: some View {
        HStack(spacing: size * 0.10) {
            Capsule().frame(width: size * 0.15, height: size * 0.45)
            Capsule().frame(width: size * 0.15, height: size * 0.85)
            Capsule().frame(width: size * 0.15, height: size * 0.65)
            Capsule().frame(width: size * 0.15, height: size * 0.35)
        }
        .foregroundStyle(HushStyle.accent.gradient)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(.caption2, design: .monospaced, weight: .medium))
            .tracking(2.2).foregroundStyle(.secondary)
    }
}

struct CapabilityBadge: View {
    let title: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: .capsule)
    }
}

struct ModelGlyph: View {
    let model: ModelRecord
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.31).fill(color.opacity(0.10))
            if model.engine == .apple {
                Image(systemName: "apple.intelligence").font(.system(size: size * 0.47, weight: .medium))
            } else if model.engine == .coreAI {
                Image(systemName: "cpu").font(.system(size: size * 0.45, weight: .light))
            } else {
                Text(String(model.name.prefix(1)).uppercased()).font(.system(size: size * 0.58, weight: .regular, design: .serif))
            }
        }
        .foregroundStyle(color).frame(width: size, height: size)
        .accessibilityHidden(true)
    }
    private var color: Color { model.engine == .mlx ? HushStyle.amber : HushStyle.accent }
}

extension View {
    func hushCard(padding: CGFloat = 22) -> some View {
        self.padding(padding)
            .background(HushStyle.surface.opacity(0.8), in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.055), lineWidth: 1) }
    }
}
