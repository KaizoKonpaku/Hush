import SwiftUI

private struct NoticePresenter: ViewModifier {
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(\.appearsActive) private var appearsActive

    func body(content: Content) -> some View {
        content.alert(item: Binding(get: {
            appearsActive ? workspace.notice : nil
        }, set: { workspace.notice = $0 })) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
    }
}

extension View {
    func hushNotices() -> some View { modifier(NoticePresenter()) }
}
