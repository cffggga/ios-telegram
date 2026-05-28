import SwiftUI
import UIKit

struct ChatListView: View {
    @ObservedObject var vm: AppViewModel
    @State private var searchVisible = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            List {
                pullDetector

                ForEach(vm.filteredChats) { chat in
                    NavigationLink(value: chat.id) {
                        ChatCardView(chat: chat)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            UIPasteboard.general.string = "\(chat.id)"
                        } label: {
                            Label("Copy ID", systemImage: "number")
                        }
                        .tint(.secondary)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .coordinateSpace(name: "chat-list-scroll")
            .background(AppColors.screenBackground)
            .animation(.spring(response: 0.28, dampingFraction: 0.88), value: vm.filteredChats)
            .navigationTitle("Chats")
            .navigationDestination(for: Int64.self) { chatId in
                ChatDetailView(vm: vm, chatId: chatId)
            }
            .overlay {
                if vm.chats.isEmpty && !vm.isBusy {
                    emptyChatsView
                }
            }
            .refreshable {
                await vm.refreshChats()
            }

            searchField
        }
        .onPreferenceChange(ChatListPullOffsetKey.self) { value in
            updateSearchVisibility(offset: value)
        }
    }

    private var pullDetector: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: ChatListPullOffsetKey.self,
                    value: proxy.frame(in: .named("chat-list-scroll")).minY
                )
        }
        .frame(height: 1)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search", text: $vm.chatSearch)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !vm.chatSearch.isEmpty {
                Button {
                    vm.chatSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: 360)
        .glassContainer(cornerRadius: 18)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .opacity(searchVisible || !vm.chatSearch.isEmpty ? 1 : 0)
        .offset(y: searchVisible || !vm.chatSearch.isEmpty ? 0 : -22)
        .allowsHitTesting(searchVisible || !vm.chatSearch.isEmpty)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: searchVisible)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: vm.chatSearch.isEmpty)
    }

    private func updateSearchVisibility(offset: CGFloat) {
        if offset > 38 {
            searchVisible = true
        } else if offset < -8 && vm.chatSearch.isEmpty {
            searchVisible = false
            searchFocused = false
        }
    }

    @ViewBuilder
    private var emptyChatsView: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                "Нет чатов",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Потяните вниз для обновления")
            )
        } else {
            VStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("Нет чатов")
                    .font(.headline)
                Text("Потяните вниз для обновления")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
    }
}

private struct ChatCardView: View {
    let chat: TgChat

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(title: chat.title, identifier: chat.id, imagePath: chat.avatarPath, size: 52)
                Circle()
                    .fill((chat.isOnline ?? false) ? Color.green : Color.gray.opacity(0.75))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .offset(x: 1, y: 1)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(chat.title)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if chat.unreadCount > 0 {
                        Text(unreadText(chat.unreadCount))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppColors.accent)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: iconName(for: chat.kind))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(previewText)
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassContainer(cornerRadius: 18)
    }

    private var previewText: String {
        if let preview = chat.lastMessagePreview, !preview.isEmpty {
            return preview
        }
        switch chat.kind {
        case .private: return "Личное сообщение"
        case .basicGroup, .supergroup: return "Группа"
        case .channel: return "Канал"
        case .unknown: return "Чат"
        }
    }

    private func iconName(for kind: ChatKind) -> String {
        switch kind {
        case .private: return "person.fill"
        case .basicGroup, .supergroup: return "person.2.fill"
        case .channel: return "megaphone.fill"
        case .unknown: return "bubble.left.fill"
        }
    }

    private func unreadText(_ value: Int) -> String {
        value > 99 ? "99+" : "\(value)"
    }
}

private struct ChatListPullOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
