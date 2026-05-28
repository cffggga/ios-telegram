import SwiftUI

struct ChatDetailView: View {
    @ObservedObject var vm: AppViewModel
    let chatId: Int64
    @FocusState private var isComposerFocused: Bool
    @State private var showProfile = false

    private var title: String {
        vm.chats.first(where: { $0.id == chatId })?.title ?? "Чат"
    }

    private var selectedChat: TgChat? {
        vm.chats.first(where: { $0.id == chatId })
    }

    private var subtitle: String {
        if vm.isBusy { return "обновление..." }
        return selectedChat?.statusText ?? "был(а) недавно"
    }

    private var canSend: Bool {
        selectedChat?.canSendMessages ?? true
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.messages) { message in
                            let replyPreview = message.replyToMessageId.flatMap { replyId in
                                vm.messages.first(where: { $0.id == replyId })?.text
                            }
                            MessageBubbleView(
                                message: message,
                                incomingAvatarPath: selectedChat?.avatarPath,
                                incomingTitle: title,
                                replyPreviewText: replyPreview,
                                onReply: {
                                    vm.startReply(message)
                                    isComposerFocused = true
                                },
                                onEdit: {
                                    vm.startEditing(message)
                                    isComposerFocused = true
                                },
                                onDelete: { revoke in
                                    Task { await vm.deleteMyMessage(message, revoke: revoke) }
                                }
                            )
                                .id(message.id)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        vm.quoteMessage(message)
                                        isComposerFocused = true
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
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .local)
                        .onChanged { value in
                            if value.translation.height > 18 {
                                isComposerFocused = false
                            }
                        }
                )
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

            if !canSend, let reason = selectedChat?.sendRestrictionText {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppColors.chatBackground)
            } else {
                HStack(spacing: 12) {
                    if let reply = vm.replyPreviewText(), vm.replyingToMessageId != nil {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Ответ")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    vm.cancelReply()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(reply)
                                .font(.caption)
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                        }
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    TextField("Сообщение", text: $vm.composeText, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($isComposerFocused)
                        .glassField()

                    if vm.editingMessageId != nil {
                        Button {
                            vm.cancelEditing()
                            isComposerFocused = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(10)
                                .background(Color.white.opacity(0.10))
                                .clipShape(Circle())
                        }
                        .disabled(vm.isBusy)
                    }

                    Button {
                        Task {
                            await vm.sendMessage()
                            isComposerFocused = false
                        }
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(vm.composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.white)
                            .padding(10)
                            .background(vm.composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.white.opacity(0.12) : AppColors.accent)
                            .clipShape(Circle())
                    }
                    .disabled(vm.isBusy || vm.composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppColors.chatBackground)
            }
        }
        .background(AppColors.chatBackground)
        .preferredColorScheme(.dark)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await vm.selectChat(chatId) }
        }
        .task(id: chatId) {
            // Always load immediately when entering/switching chat
            await vm.selectChat(chatId)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    showProfile = true
                } label: {
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
                .buttonStyle(.plain)
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
        .sheet(isPresented: $showProfile) {
            NavigationStack {
                Group {
                    if let profile = vm.chatProfile {
                        ChatProfileView(profile: profile)
                    } else if vm.isProfileLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text("Не удалось загрузить профиль")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .task {
                await vm.loadProfile(chatId: chatId)
            }
        }
    }
}
