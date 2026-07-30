import Observation

@Observable
final class MainWindowStore {
    var currentRoute: MainWindowRoute
    var backStack: [MainWindowRoute]
    var forwardStack: [MainWindowRoute]
    var sidebarSearchText: String

    init(
        initialRoute: MainWindowRoute = .assistant,
        backStack: [MainWindowRoute] = [],
        forwardStack: [MainWindowRoute] = [],
        sidebarSearchText: String = ""
    ) {
        self.currentRoute = initialRoute
        self.backStack = backStack
        self.forwardStack = forwardStack
        self.sidebarSearchText = sidebarSearchText
    }

    var hasPreviousSection: Bool {
        !backStack.isEmpty
    }

    var hasNextSection: Bool {
        !forwardStack.isEmpty
    }

    func reset(to route: MainWindowRoute) {
        currentRoute = route
        backStack.removeAll()
        forwardStack.removeAll()
    }

    @discardableResult
    func navigate(to route: MainWindowRoute) -> Bool {
        guard route != currentRoute else { return false }
        backStack.append(currentRoute)
        currentRoute = route
        forwardStack.removeAll()
        return true
    }

    @discardableResult
    func goToPreviousSection() -> Bool {
        guard let previous = backStack.popLast() else { return false }
        forwardStack.append(currentRoute)
        currentRoute = previous
        return true
    }

    @discardableResult
    func goToNextSection() -> Bool {
        guard let next = forwardStack.popLast() else { return false }
        backStack.append(currentRoute)
        currentRoute = next
        return true
    }

    func setRoute(_ route: MainWindowRoute) {
        currentRoute = route
    }
}
