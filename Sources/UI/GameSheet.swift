import SwiftUI
import PhotosUI

struct GameSheet: View {
    @EnvironmentObject var game: GameStore
    @EnvironmentObject var engine: ChatEngine
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var busy = false
    @State private var message = ""
    @State private var editing = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("从相册选一张图", systemImage: "photo")
                    }
                    if busy {
                        HStack {
                            ProgressView()
                            Text("正在读图…").font(.caption)
                        }
                    }
                    if !message.isEmpty {
                        Text(message).font(.caption).foregroundStyle(.orange)
                    }
                } header: {
                    Text("用图片生成规则")
                } footer: {
                    Text("棋盘、卡牌、规则页、场景图都行。模型会把它整理成可执行的玩法。")
                }

                if let rules = game.rules {
                    Section {
                        LabeledContent("游戏", value: rules.title)
                        LabeledContent("类型", value: rules.kind)
                        if !rules.goal.isEmpty {
                            LabeledContent("目标", value: rules.goal)
                        }
                        LabeledContent("回合", value: "\(rules.rounds)")
                        if game.playing {
                            LabeledContent("进度", value: "第 \(game.round + 1)/\(rules.rounds) 回合")
                        }
                    } header: {
                        Text("当前规则")
                    }

                    Section {
                        if game.playing {
                            Button("结束游戏", role: .destructive) {
                                game.stop()
                                dismiss()
                            }
                        } else {
                            Button("开始游戏") {
                                game.start()
                                dismiss()
                            }
                        }
                    }
                }

                Section {
                    TextEditor(text: $editing)
                        .frame(minHeight: 120)
                        .font(.callout)
                } header: {
                    Text("手写规则（可跳过识别）")
                } footer: {
                    Text("直接从「玩法：…」写起也行，第一行会当游戏名。")
                }

                Section {
                    Button("用这段文字开局") {
                        let text = editing.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        var rules = GameRules()
                        rules.title = text.split(separator: "\n").first.map(String.init) ?? "自定义玩法"
                        rules.rounds = 5
                        rules.steps = text.split(separator: "\n").dropFirst().map(String.init)
                        game.save(rules)
                        editing = ""
                    }
                }
            }
            .navigationTitle("游戏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onChange(of: pickerItem) { item in
                guard let item else { return }
                Task { await load(item) }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func load(_ item: PhotosPickerItem) async {
        busy = true
        message = ""
        defer { busy = false }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            message = "这张图读不出来"
            return
        }
        do {
            let rules = try await engine.importGame(from: data, mime: "image/jpeg")
            message = "已生成：\(rules.summary)"
        } catch {
            message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
