import SwiftUI

struct MessageBubbleView: View {
    let message: TgMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.outgoing {
                Spacer(minLength: 48)
            } else {
                AvatarView(title: "С", identifier: message.chatId, imagePath: nil, size: 30)
            }

            VStack(alignment: message.outgoing ? .trailing : .leading, spacing: 4) {
                Text(message.text.isEmpty ? " " : message.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(message.outgoing ? .trailing : .leading)
                    .strikethrough(message.isDeleted, pattern: .solid, color: .secondary)
                    .padding(.bottom, 12)

                if !message.attachments.isEmpty {
                    ForEach(message.attachments) { attachment in
                        Text(attachmentCaption(attachment))
                            .font(.caption)
                            .foregroundStyle(AppColors.accent)
                    }
                }

                HStack(spacing: 4) {
                    if message.isDeleted {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(message.outgoing ? AppColors.outgoingBubble : AppColors.incomingBubble)
            .clipShape(BubbleShape(isOutgoing: message.outgoing))
            .overlay(alignment: .bottomTrailing) {
                if message.outgoing {
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .foregroundStyle(AppColors.accent)
                        .padding(.trailing, 8)
                        .padding(.bottom, 6)
                }
            }

            if !message.outgoing {
                Spacer(minLength: 48)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .contextMenu {
            if !message.text.isEmpty {
                Button("Скопировать") {
                    UIPasteboard.general.string = message.text
                }
            }
        }
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

private struct BubbleShape: Shape {
    let isOutgoing: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        var path = Path(roundedRect: rect, cornerRadius: radius)

        // Small tail to look closer to Telegram bubble style.
        let tailWidth: CGFloat = 7
        let tailHeight: CGFloat = 10
        let y = rect.maxY - 16
        if isOutgoing {
            path.move(to: CGPoint(x: rect.maxX - 2, y: y))
            path.addLine(to: CGPoint(x: rect.maxX + tailWidth, y: y + 3))
            path.addLine(to: CGPoint(x: rect.maxX - 2, y: y + tailHeight))
            path.closeSubpath()
        } else {
            path.move(to: CGPoint(x: rect.minX + 2, y: y))
            path.addLine(to: CGPoint(x: rect.minX - tailWidth, y: y + 3))
            path.addLine(to: CGPoint(x: rect.minX + 2, y: y + tailHeight))
            path.closeSubpath()
        }
        return path
    }
}
