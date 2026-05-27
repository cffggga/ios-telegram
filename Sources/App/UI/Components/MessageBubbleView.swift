import SwiftUI

struct MessageBubbleView: View {
    let message: TgMessage

    var body: some View {
        HStack {
            if message.outgoing { Spacer(minLength: 48) }

            VStack(alignment: message.outgoing ? .trailing : .leading, spacing: 4) {
                Text(message.isDeleted ? "Сообщение удалено" : message.text)
                    .font(.body)
                    .foregroundStyle(message.isDeleted ? .secondary : .primary)
                    .multilineTextAlignment(message.outgoing ? .trailing : .leading)

                if !message.attachments.isEmpty {
                    ForEach(message.attachments) { attachment in
                        Text(attachmentCaption(attachment))
                            .font(.caption)
                            .foregroundStyle(AppColors.accent)
                    }
                }

                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(message.outgoing ? AppColors.outgoingBubble : AppColors.incomingBubble)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !message.outgoing { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private func attachmentCaption(_ attachment: TgAttachment) -> String {
        switch attachment.kind {
        case .photo: return "Фото"
        case .video: return attachment.fileName ?? "Видео"
        case .voice: return "Голосовое"
        case .videoNote: return "Кружок"
        case .document: return attachment.fileName ?? "Файл"
        }
    }
}
