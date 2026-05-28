import SwiftUI

struct ChatDetailView: View {
    @ObservedObject var vm: AppViewModel
    let chatId: Int64

    private var title: String {
        vm.chats.first(where: { $0.id == chatId })?.title ?? "Чат"
    }

    private var selectedChat: TgChat? {
        vm.chats.first(where: { $0.id == chatId })
    }

    private var subtitle: String {
        vm.isBusy ? "обновление..." : "в сети недавно"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        vm.quoteMessage(message)
                                    } label: {
                                        Label("Цитата", systemImage: "arrowshape.turn.up.left")
                                    }
                                    .tint(AppColors.accent)
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .background(AppColors.chatBackground)
                .onChange(of: vm.messages.count) { _ in
                    if let last = vm.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if let last = vm.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                TextField("Сообщение", text: $vm.composeText, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await vm.sendMessage() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(AppColors.accent)
                        .clipShape(Circle())
                }
                .disabled(vm.isBusy || vm.composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
        }
        .background(AppColors.chatBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    AvatarView(
                        title: title,
                        identifier: chatId,
                        imagePath: selectedChat?.avatarPath,
                        size: 30
                    )
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await vm.refreshMessages() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(vm.isBusy)
            }
        }
        .refreshable {
            await vm.refreshMessages()
        }
    }
}
