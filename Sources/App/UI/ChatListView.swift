import SwiftUI

struct ChatListView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        List {
            ForEach(vm.filteredChats) { chat in
                NavigationLink(value: chat.id) {
                    ChatRowView(chat: chat)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $vm.chatSearch, prompt: "Поиск")
        .navigationTitle("Чаты")
        .navigationDestination(for: Int64.self) { chatId in
            ChatDetailView(vm: vm, chatId: chatId)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await vm.refreshChats() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(vm.isBusy)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Выйти", role: .destructive) {
                    vm.signOut()
                }
            }
        }
        .overlay {
            if vm.chats.isEmpty && !vm.isBusy {
                emptyChatsView
            }
        }
        .refreshable {
            await vm.refreshChats()
        }
    }

    @ViewBuilder
    private var emptyChatsView: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                "Нет чатов",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Потяните вниз или нажмите обновить")
            )
        } else {
            VStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("Нет чатов")
                    .font(.headline)
                Text("Потяните вниз или нажмите обновить")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
    }
}

private struct ChatRowView: View {
    let chat: TgChat

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(title: chat.title, identifier: chat.id, imagePath: chat.avatarPath, size: 50)
                Circle()
                    .fill((chat.isOnline ?? false) ? Color.green : Color.gray.opacity(0.85))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color(.systemBackground), lineWidth: 2)
                    )
                    .offset(x: 1, y: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(chat.title)
                    .font(.headline)
                    .lineLimit(1)
                if let preview = chat.lastMessagePreview, !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let status = chat.statusText, !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle((chat.isOnline ?? false) ? .green : .secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
