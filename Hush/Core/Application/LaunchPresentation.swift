import Foundation

struct LaunchPresentationBehavior: Equatable {
    let showsMainWindow: Bool
    let showsOverlay: Bool
}

enum LaunchPresentation: String, Equatable {
    case window
    case overlay
    case windowAndOverlay

    var initialBehavior: LaunchPresentationBehavior {
        switch self {
        case .window:
            return LaunchPresentationBehavior(showsMainWindow: true, showsOverlay: false)
        case .overlay:
            return LaunchPresentationBehavior(showsMainWindow: false, showsOverlay: true)
        case .windowAndOverlay:
            return LaunchPresentationBehavior(showsMainWindow: true, showsOverlay: true)
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> LaunchPresentation {
        LaunchPresentation(
            rawValue: defaults.string(forKey: "general.launchPresentation") ?? LaunchPresentation.window.rawValue
        ) ?? .window
    }
}
