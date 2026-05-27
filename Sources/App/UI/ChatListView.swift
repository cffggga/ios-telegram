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
                .onAppear {
                    Task { await vm.selectChat(chatId) }
                }
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
                ContentUnavailableView(
                    "Нет чатов",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Потяните вниз или нажмите обновить")
                )
            }
        }
        .refreshable {
            await vm.refreshChats()
        }
    }
}

private struct ChatRowView: View {
    let chat: TgChat

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AppColors.accent.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay {
                    Text(chat.title.prefix(1).uppercased())
                        .font(.headline)
                        .foregroundStyle(AppColors.accent)
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
            }
        }
        .padding(.vertical, 4)
    }
}
