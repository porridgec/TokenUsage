import SwiftUI

@main
struct TokenUsageiOSApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            iOSMainView(model: model)
        }
    }
}
