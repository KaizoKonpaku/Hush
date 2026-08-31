import SwiftUI

struct NativeGlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if os(visionOS)
        content()
        #else
        GlassEffectContainer(spacing: spacing, content: content)
        #endif
    }
}

extension View {
    @ViewBuilder
    func nativeGlass<S: InsettableShape>(in shape: S) -> some View {
        #if os(visionOS)
        glassBackgroundEffect(in: shape)
        #else
        glassEffect(.regular, in: shape)
        #endif
    }

    @ViewBuilder
    func nativeGlassButton(prominent: Bool = false) -> some View {
        #if os(visionOS)
        if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        #else
        if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        #endif
    }
}
