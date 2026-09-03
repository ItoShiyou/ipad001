import SwiftData
import SwiftUI

@main
struct ScoreStandApp: App {
    private let container: ModelContainer
    @State private var environment: AppEnvironment

    init() {
        do {
            let container = try ModelContainer(
                for: Score.self, PageSource.self, PageSetting.self,
                AnnotationLayer.self, Setlist.self, SetlistItem.self
            )
            self.container = container
            _environment = State(initialValue: AppEnvironment(modelContext: container.mainContext))
        } catch {
            // ここで落ちるのはスキーマ不整合か、ディスクが読めない場合しかない。
            // 握り潰すとユーザーの楽譜を静かに失わせることになるため、
            // 原因が分かる形で落とす。
            fatalError("楽譜データベースを開けませんでした: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(environment)
                .environment(environment.session)
                .environment(environment.purchase)
                .task {
                    await environment.purchase.loadProduct()
                }
        }
        .modelContainer(container)
    }
}
