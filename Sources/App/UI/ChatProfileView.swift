import SwiftUI

struct ChatProfileView: View {
    let profile: ChatProfile
    @State private var showAvatar = false

    private var hasAvatar: Bool {
        guard let avatarPath = profile.avatarPath else { return false }
        return !avatarPath.isEmpty
    }

    var body: some View {
        List {
            Section {
                profileHeader
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16))
            }

            Section("Информация") {
                if let username = profile.username, !username.isEmpty {
                    profileRow(icon: "at", title: "Username", value: "@\(username)")
                }

                profileRow(icon: "person.text.rectangle", title: "Тип", value: kindText(profile.kind))

                if let members = profile.membersCount {
                    profileRow(icon: "person.2.fill", title: "Участники", value: membersText(members))
                }

                profileRow(icon: "number", title: "Chat ID", value: "\(profile.chatId)", monospaced: true)
            }

            if let description = profile.description?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                Section("Описание") {
                    Text(description)
                        .textSelection(.enabled)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .background(AppColors.chatBackground.ignoresSafeArea())
        .fullScreenCover(isPresented: $showAvatar) {
            if let avatarPath = profile.avatarPath {
                FullscreenImageViewer(imagePath: avatarPath, title: profile.title)
            }
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 12) {
            Button {
                if hasAvatar {
                    showAvatar = true
                }
            } label: {
                AvatarView(
                    title: profile.title,
                    identifier: profile.chatId,
                    imagePath: profile.avatarPath,
                    size: 112
                )
                .overlay(alignment: .bottomTrailing) {
                    if hasAvatar {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(AppColors.accent)
                            .clipShape(Circle())
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!hasAvatar)

            Text(profile.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(profile.statusText?.isEmpty == false ? profile.statusText ?? "" : kindText(profile.kind))
                .font(.subheadline)
                .foregroundStyle(statusColor(profile.statusText))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func profileRow(icon: String, title: String, value: String, monospaced: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(AppColors.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(monospaced ? .subheadline.monospacedDigit() : .subheadline)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusColor(_ status: String?) -> Color {
        guard let status else { return .secondary }
        return status.localizedCaseInsensitiveContains("онлайн") || status.localizedCaseInsensitiveContains("online")
            ? .green
            : .secondary
    }

    private func membersText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "участник" : "участников")"
    }

    private func kindText(_ kind: ChatKind) -> String {
        switch kind {
        case .private: return "Пользователь"
        case .basicGroup: return "Группа"
        case .supergroup: return "Супергруппа"
        case .channel: return "Канал"
        case .unknown: return "Неизвестно"
        }
    }
}
