import SwiftUI

private struct DismissSearchFocusKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var dismissSearchFocus: () -> Void {
        get { self[DismissSearchFocusKey.self] }
        set { self[DismissSearchFocusKey.self] = newValue }
    }
}
