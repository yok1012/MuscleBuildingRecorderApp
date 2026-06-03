//
//  TaskInputSheet.swift
//  MuscleBuildingRecorder
//
//  勉強・仕事ドメインの入力シート（ExerciseInputSheet の study/work 版）。
//  - workout は ExerciseInputSheet を使い続ける（重量・レップが必要なため）
//  - study/work は タスク名 + 科目/プロジェクト + メモ のみ
//

import SwiftUI

struct TaskInputSheet: View {
    let domain: ActivityDomain  // .study or .work

    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case task, secondary, note
    }

    /// 二次フィールドのラベル（科目 or プロジェクト）
    private var secondaryLabel: String {
        switch domain {
        case .study: return "科目".localizedSeed
        case .work:  return "プロジェクト".localizedSeed
        case .workout: return ""
        }
    }

    /// SessionManager 側のバインディング先（study=currentSubject、work=currentProject）
    private var secondaryBinding: Binding<String> {
        switch domain {
        case .study:
            return Binding(
                get: { sessionManager.currentSubject },
                set: { sessionManager.currentSubject = $0 }
            )
        case .work:
            return Binding(
                get: { sessionManager.currentProject },
                set: { sessionManager.currentProject = $0 }
            )
        case .workout:
            return .constant("")
        }
    }

    private var sheetTitle: String {
        switch domain {
        case .study: return "勉強タスク入力".localizedSeed
        case .work:  return "仕事タスク入力".localizedSeed
        case .workout: return ""
        }
    }

    private var taskPlaceholder: String {
        switch domain {
        case .study: return "例: 数学 第3章".localizedSeed
        case .work:  return "例: 提案書レビュー".localizedSeed
        case .workout: return ""
        }
    }

    private var secondaryPlaceholder: String {
        switch domain {
        case .study: return "例: 数学 / 英語".localizedSeed
        case .work:  return "例: ProjectA".localizedSeed
        case .workout: return ""
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("タスク名")) {
                    TextField(taskPlaceholder, text: $sessionManager.currentTaskName)
                        .focused($focusedField, equals: .task)
                        .textInputAutocapitalization(.never)
                }

                Section(header: Text(secondaryLabel)) {
                    TextField(secondaryPlaceholder, text: secondaryBinding)
                        .focused($focusedField, equals: .secondary)
                        .textInputAutocapitalization(.never)
                }

                Section(header: Text("メモ")) {
                    TextEditor(text: $sessionManager.currentNote)
                        .frame(minHeight: 100)
                        .focused($focusedField, equals: .note)
                        .overlay(alignment: .topLeading) {
                            if sessionManager.currentNote.isEmpty {
                                Text("内容や進捗を記入...")
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Section {
                    HStack {
                        Image(systemName: domain.iconName)
                            .foregroundColor(domainAccentColor)
                        Text("\(domain.displayName)モード")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
    }

    private var domainAccentColor: Color {
        switch domain {
        case .workout: return .red
        case .study:   return .blue
        case .work:    return .green
        }
    }
}
