import Foundation

enum TgAttachmentKind: String, Equatable {
    case photo
    case video
    case voice
    case videoNote
    case document
}

struct TgAttachment: Identifiable, Equatable {
    let id: String
    let kind: TgAttachmentKind
    let fileId: Int64?
    let fileName: String?
    let mimeType: String?
    let size: Int64?
    let localPath: String?
}

struct TgChat: Identifiable, Equatable {
    let id: Int64
    let title: String
    var lastMessagePreview: String?
    var avatarPath: String?
    var statusText: String?

    init(id: Int64, title: String, lastMessagePreview: String? = nil, avatarPath: String? = nil, statusText: String? = nil) {
        self.id = id
        self.title = title
        self.lastMessagePreview = lastMessagePreview
        self.avatarPath = avatarPath
        self.statusText = statusText
    }
}

struct TgMessage: Identifiable, Equatable {
    let id: Int64
    let chatId: Int64
    let text: String
    let outgoing: Bool
    let createdAt: Date
    let isDeleted: Bool
    let attachments: [TgAttachment]
}

enum AuthState: Equatable {
    case waitPhone
    case waitCode
    case waitPassword
    case ready
}

enum TelegramEvent {
    case authChanged(AuthState)
    case newMessage(TgMessage)
    case messageReplaced(chatId: Int64, oldMessageId: Int64, newMessage: TgMessage)
    case messagesDeleted(chatId: Int64, messageIds: [Int64])
    case chatsChanged
}
