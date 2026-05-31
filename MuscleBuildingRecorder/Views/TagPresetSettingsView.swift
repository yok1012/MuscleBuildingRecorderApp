import SwiftUI

/// ドメイン別のタグプリセットを編集する設定画面。
/// 休憩中のクイック入力でワンタップ選択するタグを追加・削除・並び替えできる。
struct TagPresetSettingsView: View {
    @ObservedObject private var store = TagPresetStore.shared
    @State private var selectedDomain: ActivityDomain = .workout
    @State private var newTag: String = ""
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("ドメイン", selection: $selectedDomain) {
                        ForEach(ActivityDomain.allCases, id: \.self) { domain in
                            Text(domain.displayName).tag(domain)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("登録済みタグ")) {
                    let tags = store.tags(for: selectedDomain.rawValue)
                    if tags.isEmpty {
                        Text("タグはまだありません")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                        }
                        .onDelete { offsets in
                            store.removeTag(at: offsets, for: selectedDomain.rawValue)
                        }
                        .onMove { source, dest in
                            store.moveTag(from: source, to: dest, for: selectedDomain.rawValue)
                        }
                    }
                }

                Section(header: Text("追加")) {
                    HStack {
                        TextField("新しいタグ", text: $newTag)
                            .focused($addFieldFocused)
                            .submitLabel(.done)
                            .onSubmit(addTag)
                        Button("追加", action: addTag)
                            .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        store.resetToDefaults(for: selectedDomain.rawValue)
                    } label: {
                        Text("このドメインを既定値に戻す")
                    }
                }
            }
            .navigationTitle("タグの管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { EditButton() }
        }
    }

    private func addTag() {
        store.addTag(newTag, for: selectedDomain.rawValue)
        newTag = ""
        addFieldFocused = false
    }
}
