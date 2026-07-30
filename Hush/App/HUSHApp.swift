import SwiftUI
import AppKit

@main
struct HUSHApp: App {
    private let appModel = AppModel.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private func showAboutPanel() {
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Hush",
            .applicationVersion: appVersionString(),
            .version: appBuildString(),
            .credits: aboutCredits()
        ]
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func aboutCredits() -> NSAttributedString {
        let text = "BY KON, FROM KAIZŌSHA"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return NSAttributedString(
            
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]
        )
    }

    private func appVersionString() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func appBuildString() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button {
                    showAboutPanel()
                } label: {
                    Label("About Hush", systemImage: "info.circle")
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button {
                    Task { @MainActor in
                        appModel.toggleMainWindow(appModel.mainWindowRoute)
                    }
                } label: {
                    Label("App Window", systemImage: "macwindow")
                }
            }
            CommandGroup(replacing: .appVisibility) {
                Button {
                    Task { @MainActor in
                        appModel.toggleOverlay()
                    }
                } label: {
                    Text(appModel.isOverlayEnabled ? "Hide Overlay" : "Show Overlay")
                }
                .keyboardShortcut("h", modifiers: [.command])

                Divider()

                Button("Hide Others") {
                    NSApp.hideOtherApplications(nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .option])

                Button("Show All") {
                    NSApp.unhideAllApplications(nil)
                }
            }
        }
    }
}

struct AppWindowRootView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage("settings.appearance") private var appearanceMode = "system"
    @AppStorage("themes.accent.red") private var themesAccentRed = 0.0
    @AppStorage("themes.accent.green") private var themesAccentGreen = 0.48
    @AppStorage("themes.accent.blue") private var themesAccentBlue = 1.0

    var body: some View {
        MainWindowView()
            .environmentObject(appModel.assistantWorkspace)
            .preferredColorScheme(InterfaceAppearanceMode.preferredColorScheme(for: appearanceMode))
            .tint(.interfaceAccent(red: themesAccentRed, green: themesAccentGreen, blue: themesAccentBlue))
    }
}
