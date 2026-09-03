import SwiftData
import SwiftUI

/// 最上位の画面。ライブラリとセットリストを切り替える。
///
/// iPad では `NavigationSplitView` の方が自然だが、v1 では
/// 縦横・Split View・Slide Over のどの幅でも破綻しないこと（FR-16）を優先し、
/// 単純なタブ構成にしている。
struct ContentView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var scores: [Score]

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("楽譜", systemImage: "music.note.list") }

            SetlistListView()
                .tabItem { Label("セットリスト", systemImage: "list.number") }

            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
        .task {
            environment.cleanupOrphanFiles(scores: scores)
        }
    }
}
