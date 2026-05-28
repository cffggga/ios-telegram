import SwiftUI

struct ChatProfileView: View {
    let profile: ChatProfile

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AvatarView(
                    title: profile.title,
                    identifier: profile.chatId,
                    imagePath: profile.avatarPath,
                    size: 90
                )
                .padding(.top, 20)

                Text(profile.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                if let status = profile.statusText, !status.isEmpty {
                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    row("Тип", value: kindText(profile.kind))
                    row("Chat ID", value: "\(profile.chatId)")
                    if let username = profile.username, !username.isEmpty {
                        row("Username", value: "@\(username)")
                    }
                    if let members = profile.membersCount {
                        row("Участники", value: "\(members)")
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                if let desc = profile.description, !desc.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Описание")
                            .font(.headline)
                        Text(desc)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding()
        }
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .background(AppColors.chatBackground)
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
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

