import SwiftUI

/// ライブラリ一覧の1行。タイトル・作曲者・ページ数・タグと、演奏開始ボタンを持つ。
struct ScoreRowView: View {
    let score: Score
    let onPerform: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(score.title)
                    .font(.headline)
                    .lineLimit(1)

                if !score.composer.isEmpty {
                    Text(score.composer)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Label("\(score.pageCount)ページ", systemImage: "doc.plaintext")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !score.tags.isEmpty {
                        Text(score.tags.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            // NavigationLink の行タップと衝突しないよう .borderless にしている。
            Button(action: onPerform) {
                Image(systemName: "play.circle.fill")
                    .font(.title)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("演奏を開始")
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}
