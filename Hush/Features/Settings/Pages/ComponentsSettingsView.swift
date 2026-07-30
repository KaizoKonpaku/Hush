import SwiftUI

extension MainWindowView {
    var componentsSettings: some View {
        ContentUnavailableView {
            Label("Components", systemImage: "square.stack.3d.up.slash.fill")
        } description: {
            Text("Under development. Component controls will appear here once the feature set is ready.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
