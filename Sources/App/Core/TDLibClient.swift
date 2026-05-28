import Foundation

final class TDLibClient: TelegramClientProtocol, @unchecked Sendable {
    private let bridge: TDLibBridge
    private let syncQueue = DispatchQueue(label: "tdlib.client.sync")

    private var authState: AuthState = .waitPhone
    private var lastAuthorizationStateType = ""
    private var eventHandler: ((TelegramEvent) -> Void)?
    private var receiveLoopTask: Task<Void, Never>?
    private var pendingResponses: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var authorizationWaiters: [AuthStateWaiter] = []

    init() throws {
        self.bridge = try TDLibBridge()
    }

    func configure(apiId: Int, apiHash: String) async throws {
        guard apiId > 0, apiId <= Int(Int32.max), apiHash.count == 32 else {
            throw TDLibClientError.invalidApiCredentials
        }

        startReceiveLoopIfNeeded()
        setLogVerbosityLevel(1)

        try await waitForAuthorizationState("authorizationStateWaitTdlibParameters", timeout: 60)

        let databaseDirectory = try TDLibPaths.databaseDirectory()
        let filesDirectory = try TDLibPaths.filesDirectory()

        // TDLib 1.8.6+ requires flat fields at root — nested "parameters" makes api_id=0.
        _ = try await sendRequest([
            "@type": "setTdlibParameters",
            "use_test_dc": false,
            "database_directory": databaseDirectory,
            "files_directory": filesDirectory,
            "database_encryption_key": "",
            "use_file_database": true,
            "use_chat_info_database": true,
            "use_message_database": true,
            "use_secret_chats": false,
            "api_id": apiId,
            "api_hash": apiHash,
            "system_language_code": "ru",
            "device_model": "iPhone",
            "system_version": "iOS",
            "application_version": "1.0",
            "enable_storage_optimizer": true,
            "ignore_file_names": false
        ])

        try await waitForAuthorizationState(
            matching: [
                "authorizationStateWaitEncryptionKey",
                "authorizationStateWaitPhoneNumber",
                "authorizationStateWaitCode",
                "authorizationStateWaitPassword",
                "authorizationStateReady"
            ],
            timeout: 60
        )

        if currentAuthorizationStateType() == "authorizationStateWaitEncryptionKey" {
            _ = try await sendRequest([
                "@type": "checkDatabaseEncryptionKey",
                "encryption_key": ""
            ])
            try await waitForAuthorizationState(
                matching: [
                    "authorizationStateWaitPhoneNumber",
                    "authorizationStateWaitCode",
                    "authorizationStateWaitPassword",
                    "authorizationStateReady"
                ],
                timeout: 60
            )
        }
    }

    private func setLogVerbosityLevel(_ level: Int) {
        let payload = """
        {"@type":"setLogVerbosityLevel","new_verbosity_level":\(level)}
        """
        bridge.send(payload)
    }

    func currentAuthState() -> AuthState {
        authState
    }

    func setEventHandler(_ handler: @escaping (TelegramEvent) -> Void) {
        eventHandler = handler
    }

    func submitPhone(_ phone: String) async throws {
        _ = try await sendRequest([
            "@type": "setAuthenticationPhoneNumber",
            "phone_number": phone
        ])
    }

    func submitCode(_ code: String) async throws {
        _ = try await sendRequest([
            "@type": "checkAuthenticationCode",
            "code": code
        ])
    }

    func submitPassword(_ password: String) async throws {
        _ = try await sendRequest([
            "@type": "checkAuthenticationPassword",
            "password": password
        ])
    }

    func fetchChats(limit: Int = 50) async throws -> [TgChat] {
        let response = try await sendRequest([
            "@type": "getChats",
            "chat_list": ["@type": "chatListMain"],
            "limit": limit
        ])
        guard let ids = response["chat_ids"] as? [Any] else { return [] }

        var chats: [TgChat] = []
        for anyId in ids {
            guard let id = int64Value(anyId) else { continue }
            let chatResp = try await sendRequest([
                "@type": "getChat",
                "chat_id": id
            ])
            if let title = chatResp["title"] as? String {
                let subtitle = chatResp["last_message"] as? [String: Any]
                let preview = subtitle.flatMap { parseMessage($0, fallbackChatId: id)?.text }
                let avatarPath = try await resolveChatAvatarPath(chatResp)
                let statusInfo = try await resolveChatStatusInfo(chatResp)
                let sendInfo = try await resolveChatSendPermissions(chatResp)
                chats.append(
                    TgChat(
                        id: id,
                        title: title,
                        lastMessagePreview: preview,
                        avatarPath: avatarPath,
                        statusText: statusInfo.text,
                        isOnline: statusInfo.isOnline,
                        canSendMessages: sendInfo.canSend,
                        sendRestrictionText: sendInfo.reason
                    )
                )
            }
        }
        return chats
    }

    func fetchMessages(chatId: Int64, limit: Int = 100) async throws -> [TgMessage] {
        let response = try await sendRequest([
            "@type": "getChatHistory",
            "chat_id": chatId,
            "limit": limit,
            "from_message_id": 0,
            "offset": 0,
            "only_local": false
        ])
        guard let items = response["messages"] as? [[String: Any]] else { return [] }
        return items.compactMap { parseMessage($0, fallbackChatId: chatId) }
            .sorted(by: { $0.createdAt < $1.createdAt })
    }

    func sendMessage(chatId: Int64, text: String, replyToMessageId: Int64?) async throws {
        var body: [String: Any] = [
            "@type": "sendMessage",
            "chat_id": chatId,
            "input_message_content": [
                "@type": "inputMessageText",
                "text": [
                    "@type": "formattedText",
                    "text": text
                ]
            ]
        ]

        if let replyToMessageId {
            body["reply_to"] = [
                "@type": "inputMessageReplyToMessage",
                "message_id": replyToMessageId
            ]
        }

        _ = try await sendRequest(body)
    }

    func editMessage(chatId: Int64, messageId: Int64, text: String) async throws {
        _ = try await sendRequest([
            "@type": "editMessageText",
            "chat_id": chatId,
            "message_id": messageId,
            "input_message_content": [
                "@type": "inputMessageText",
                "text": [
                    "@type": "formattedText",
                    "text": text
                ]
            ]
        ])
    }

    func deleteMessages(chatId: Int64, messageIds: [Int64], revoke: Bool) async throws {
        guard !messageIds.isEmpty else { return }
        _ = try await sendRequest([
            "@type": "deleteMessages",
            "chat_id": chatId,
            "message_ids": messageIds,
            "revoke": revoke
        ])
    }

    func downloadFile(fileId: Int64) async throws -> String? {
        let response = try await sendRequest([
            "@type": "downloadFile",
            "file_id": fileId,
            "priority": 32,
            "offset": 0,
            "limit": 0,
            "synchronous": true
        ])
        if let local = response["local"] as? [String: Any],
           (local["is_downloading_completed"] as? Bool) == true,
           let path = local["path"] as? String,
           !path.isEmpty {
            return path
        }
        return nil
    }

    func fetchChatProfile(chatId: Int64) async throws -> ChatProfile {
        let chat = try await sendRequest([
            "@type": "getChat",
            "chat_id": chatId
        ])

        let title = (chat["title"] as? String) ?? "Чат"
        let avatarPath = try await resolveChatAvatarPath(chat, preferBig: true)
        let statusInfo = try await resolveChatStatusInfo(chat)

        guard
            let type = chat["type"] as? [String: Any],
            let typeName = type["@type"] as? String
        else {
            return ChatProfile(
                chatId: chatId,
                title: title,
                kind: .unknown,
                avatarPath: avatarPath,
                username: nil,
                description: nil,
                membersCount: nil,
                statusText: statusInfo.text
            )
        }

        switch typeName {
        case "chatTypePrivate":
            if let userId = int64Value(type["user_id"]) {
                let user = try await sendRequest([
                    "@type": "getUser",
                    "user_id": userId
                ])
                let username = (user["usernames"] as? [String: Any]).flatMap { $0["active_usernames"] as? [String] }?.first
                    ?? (user["username"] as? String)
                return ChatProfile(
                    chatId: chatId,
                    title: title,
                    kind: .private,
                    avatarPath: avatarPath,
                    username: username,
                    description: nil,
                    membersCount: nil,
                    statusText: statusInfo.text
                )
            }
            fallthrough
        case "chatTypeBasicGroup":
            if let groupId = int64Value(type["basic_group_id"]) {
                let group = try await sendRequest([
                    "@type": "getBasicGroup",
                    "basic_group_id": groupId
                ])
                let members = (group["member_count"] as? Int)
                return ChatProfile(
                    chatId: chatId,
                    title: title,
                    kind: .basicGroup,
                    avatarPath: avatarPath,
                    username: nil,
                    description: nil,
                    membersCount: members,
                    statusText: nil
                )
            }
            fallthrough
        case "chatTypeSupergroup":
            if let sgId = int64Value(type["supergroup_id"]) {
                let sg = try await sendRequest([
                    "@type": "getSupergroup",
                    "supergroup_id": sgId
                ])
                let isChannel = (sg["is_channel"] as? Bool) ?? false
                let username = sg["username"] as? String
                let members = sg["member_count"] as? Int
                let desc = sg["description"] as? String
                return ChatProfile(
                    chatId: chatId,
                    title: title,
                    kind: isChannel ? .channel : .supergroup,
                    avatarPath: avatarPath,
                    username: username,
                    description: desc,
                    membersCount: members,
                    statusText: nil
                )
            }
            fallthrough
        default:
            return ChatProfile(
                chatId: chatId,
                title: title,
                kind: .unknown,
                avatarPath: avatarPath,
                username: nil,
                description: nil,
                membersCount: nil,
                statusText: statusInfo.text
            )
        }
    }

    private func startReceiveLoopIfNeeded() {
        guard receiveLoopTask == nil else { return }
        receiveLoopTask = Task.detached { [weak self] in
            await self?.runReceiveLoop()
        }
    }

    private func waitForAuthorizationState(_ type: String, timeout: TimeInterval) async throws {
        try await waitForAuthorizationState(matching: [type], timeout: timeout)
    }

    private func currentAuthorizationStateType() -> String {
        syncQueue.sync { lastAuthorizationStateType }
    }

    private func waitForAuthorizationState(matching types: [String], timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let waiterID = UUID()
            syncQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: TDLibClientError.deallocated)
                    return
                }

                if types.contains(self.lastAuthorizationStateType) {
                    continuation.resume()
                    return
                }

                self.authorizationWaiters.append(
                    AuthStateWaiter(id: waiterID, matching: Set(types), continuation: continuation)
                )

                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                    guard let self else { return }
                    self.syncQueue.async {
                        guard let index = self.authorizationWaiters.firstIndex(where: { $0.id == waiterID }) else {
                            return
                        }
                        let waiter = self.authorizationWaiters.remove(at: index)
                        waiter.continuation.resume(throwing: TDLibClientError.authorizationTimeout)
                    }
                }
            }
        }
    }

    private func sendRequest(_ body: [String: Any]) async throws -> [String: Any] {
        var payload = body
        let extra = UUID().uuidString
        payload["@extra"] = extra
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw TDLibClientError.jsonEncodingFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            syncQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: TDLibClientError.deallocated)
                    return
                }
                self.pendingResponses[extra] = continuation
                self.bridge.send(json)
            }
        }
    }

    private func runReceiveLoop() async {
        while !Task.isCancelled {
            guard let raw = bridge.receive(timeout: 0.2),
                  let data = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let extra = obj["@extra"] as? String {
                syncQueue.async { [weak self] in
                    guard let self else { return }
                    let continuation = self.pendingResponses.removeValue(forKey: extra)
                    if let error = self.tdError(from: obj) {
                        continuation?.resume(throwing: error)
                    } else {
                        continuation?.resume(returning: obj)
                    }
                }
            }

            handleUpdate(obj)
        }
    }

    private func handleUpdate(_ obj: [String: Any]) {
        guard let type = obj["@type"] as? String else { return }

        if type == "updateAuthorizationState",
           let stateObj = obj["authorization_state"] as? [String: Any],
           let stateType = stateObj["@type"] as? String {
            syncQueue.async { [weak self] in
                guard let self else { return }
                self.lastAuthorizationStateType = stateType
                let mapped = self.mapAuthState(from: stateType)
                self.authState = mapped

                var remaining: [AuthStateWaiter] = []
                for waiter in self.authorizationWaiters {
                    if waiter.matching.contains(stateType) {
                        waiter.continuation.resume()
                    } else {
                        remaining.append(waiter)
                    }
                }
                self.authorizationWaiters = remaining
            }
            eventHandler?(.authChanged(mapAuthState(from: stateType)))
            return
        }

        if type == "updateNewMessage",
           let messageObj = obj["message"] as? [String: Any],
           let message = parseMessage(messageObj, fallbackChatId: 0) {
            eventHandler?(.newMessage(message))
            return
        }

        if type == "updateMessageSendSucceeded",
           let oldMessageId = int64Value(obj["old_message_id"]),
           let messageObj = obj["message"] as? [String: Any],
           let message = parseMessage(messageObj, fallbackChatId: 0) {
            eventHandler?(.messageReplaced(chatId: message.chatId, oldMessageId: oldMessageId, newMessage: message))
            return
        }

        if type == "updateDeleteMessages",
           let chatId = int64Value(obj["chat_id"]),
           let idsAny = obj["message_ids"] as? [Any] {
            let isPermanent = (obj["is_permanent"] as? Bool) ?? false
            let fromCache = (obj["from_cache"] as? Bool) ?? false
            let ids = idsAny.compactMap(int64Value)
            if isPermanent, !fromCache, !ids.isEmpty {
                eventHandler?(.messagesDeleted(chatId: chatId, messageIds: ids))
            }
            return
        }

        if type == "updateNewChat" || type == "updateChatLastMessage" {
            eventHandler?(.chatsChanged)
        }
    }

    private func parseMessage(_ obj: [String: Any], fallbackChatId: Int64) -> TgMessage? {
        guard let id = int64Value(obj["id"]) else { return nil }
        let chatId = int64Value(obj["chat_id"]) ?? fallbackChatId
        let dateUnix = (obj["date"] as? Double) ?? Date().timeIntervalSince1970
        let isOutgoing = (obj["is_outgoing"] as? Bool) ?? false
        let editDate = int64Value(obj["edit_date"]) ?? 0
        let isEdited = editDate > 0

        var replyToMessageId: Int64?
        if let replyTo = obj["reply_to"] as? [String: Any] {
            if let messageId = int64Value(replyTo["message_id"]) {
                replyToMessageId = messageId
            } else if
                let replyType = replyTo["@type"] as? String,
                replyType == "messageReplyToMessage",
                let messageId = int64Value(replyTo["message_id"]) {
                replyToMessageId = messageId
            }
        }

        var text = ""
        if let content = obj["content"] as? [String: Any],
           let contentType = content["@type"] as? String {
            if contentType == "messageText",
               let textObj = content["text"] as? [String: Any],
               let rawText = textObj["text"] as? String {
                text = rawText
            } else if let captionObj = content["caption"] as? [String: Any],
                      let caption = captionObj["text"] as? String {
                text = caption
            } else if isRenderableAttachmentContent(contentType) {
                text = ""
            } else {
                text = "[\(contentType)]"
            }
        }

        return TgMessage(
            id: id,
            chatId: chatId,
            text: text,
            outgoing: isOutgoing,
            createdAt: Date(timeIntervalSince1970: dateUnix),
            isEdited: isEdited,
            replyToMessageId: replyToMessageId,
            isDeleted: false,
            attachments: parseAttachments(obj["content"] as? [String: Any])
        )
    }

    private func parseAttachments(_ content: [String: Any]?) -> [TgAttachment] {
        guard let content, let contentType = content["@type"] as? String else { return [] }

        switch contentType {
        case "messagePhoto":
            guard let photo = content["photo"] as? [String: Any] else { return [] }
            let fileInfo = extractFileInfo(from: photo["sizes"])
            return [TgAttachment(
                id: UUID().uuidString,
                kind: .photo,
                fileId: fileInfo.id,
                fileName: nil,
                mimeType: "image/*",
                size: fileInfo.size,
                localPath: fileInfo.localPath
            )]
        case "messageVideo":
            guard let video = content["video"] as? [String: Any] else { return [] }
            let fileInfo = extractFileInfo(from: video["video"])
            return [TgAttachment(
                id: UUID().uuidString,
                kind: .video,
                fileId: fileInfo.id,
                fileName: video["file_name"] as? String,
                mimeType: video["mime_type"] as? String,
                size: fileInfo.size ?? int64Value(video["size"]),
                localPath: fileInfo.localPath
            )]
        case "messageVoiceNote":
            guard let voice = content["voice_note"] as? [String: Any] else { return [] }
            let fileInfo = extractFileInfo(from: voice["voice"])
            return [TgAttachment(
                id: UUID().uuidString,
                kind: .voice,
                fileId: fileInfo.id,
                fileName: nil,
                mimeType: voice["mime_type"] as? String,
                size: fileInfo.size ?? int64Value(voice["size"]),
                localPath: fileInfo.localPath
            )]
        case "messageVideoNote":
            guard let note = content["video_note"] as? [String: Any] else { return [] }
            let fileInfo = extractFileInfo(from: note["video"])
            return [TgAttachment(
                id: UUID().uuidString,
                kind: .videoNote,
                fileId: fileInfo.id,
                fileName: nil,
                mimeType: "video/*",
                size: fileInfo.size ?? int64Value(note["size"]),
                localPath: fileInfo.localPath
            )]
        case "messageDocument":
            guard let doc = content["document"] as? [String: Any] else { return [] }
            let fileInfo = extractFileInfo(from: doc["document"])
            return [TgAttachment(
                id: UUID().uuidString,
                kind: .document,
                fileId: fileInfo.id,
                fileName: doc["file_name"] as? String,
                mimeType: doc["mime_type"] as? String,
                size: fileInfo.size ?? int64Value(doc["size"]),
                localPath: fileInfo.localPath
            )]
        default:
            return []
        }
    }

    private func extractFileInfo(from source: Any?) -> (id: Int64?, localPath: String?, size: Int64?) {
        if let file = source as? [String: Any] {
            return fileInfo(file)
        }
        if let sizes = source as? [[String: Any]] {
            for item in sizes.reversed() {
                if let photo = item["photo"] as? [String: Any] {
                    return fileInfo(photo)
                }
            }
        }
        return (nil, nil, nil)
    }

    private func fileInfo(_ file: [String: Any]) -> (id: Int64?, localPath: String?, size: Int64?) {
        let local = file["local"] as? [String: Any]
        let path = (local?["path"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let size = int64Value(file["size"]) ?? int64Value(file["expected_size"])
        return (int64Value(file["id"]), path, size)
    }

    private func extractFileId(from source: Any?) -> Int64? {
        if let file = source as? [String: Any],
           let id = int64Value(file["id"]) {
            return id
        }
        if let sizes = source as? [[String: Any]] {
            for item in sizes.reversed() {
                if let photo = item["photo"] as? [String: Any],
                   let id = int64Value(photo["id"]) {
                    return id
                }
            }
        }
        return nil
    }

    private func isRenderableAttachmentContent(_ contentType: String) -> Bool {
        switch contentType {
        case "messagePhoto", "messageVideo", "messageVoiceNote", "messageVideoNote", "messageDocument":
            return true
        default:
            return false
        }
    }

    private func resolveChatAvatarPath(_ chat: [String: Any], preferBig: Bool = false) async throws -> String? {
        guard
            let photo = chat["photo"] as? [String: Any],
            let file = preferredAvatarFile(from: photo, preferBig: preferBig)
        else {
            return nil
        }

        if
            let local = file["local"] as? [String: Any],
            let path = local["path"] as? String,
            !path.isEmpty {
            return path
        }

        if let fileId = int64Value(file["id"]) {
            return try await downloadFile(fileId: fileId)
        }

        return nil
    }

    private func preferredAvatarFile(from photo: [String: Any], preferBig: Bool) -> [String: Any]? {
        if preferBig {
            return (photo["big"] as? [String: Any]) ?? (photo["small"] as? [String: Any])
        }
        return (photo["small"] as? [String: Any]) ?? (photo["big"] as? [String: Any])
    }

    private func resolveChatStatusInfo(_ chat: [String: Any]) async throws -> (text: String?, isOnline: Bool?) {
        guard
            let type = chat["type"] as? [String: Any],
            let typeName = type["@type"] as? String
        else {
            return (nil, nil)
        }

        if typeName == "chatTypePrivate", let userId = int64Value(type["user_id"]) {
            let userResp = try await sendRequest([
                "@type": "getUser",
                "user_id": userId
            ])
            if let status = userResp["status"] as? [String: Any] {
                return mapUserStatus(status)
            }
            return ("был(а) недавно", false)
        }

        if typeName == "chatTypeBasicGroup" || typeName == "chatTypeSupergroup" {
            return ("группа", false)
        }

        return (nil, nil)
    }

    private func resolveChatSendPermissions(_ chat: [String: Any]) async throws -> (canSend: Bool?, reason: String?) {
        // 1) If TDLib provided chat permissions directly (groups), trust it.
        if let permissions = chat["permissions"] as? [String: Any] {
            if let canSend = permissions["can_send_messages"] as? Bool {
                return (canSend, canSend ? nil : "Запрещено отправлять сообщения")
            }
        }

        // 2) Supergroups/channels: if it's a channel, usually нельзя писать (только постить, если админ).
        if
            let type = chat["type"] as? [String: Any],
            let typeName = type["@type"] as? String,
            typeName == "chatTypeSupergroup",
            let supergroupId = int64Value(type["supergroup_id"])
        {
            let sg = try await sendRequest([
                "@type": "getSupergroup",
                "supergroup_id": supergroupId
            ])

            let isChannel = (sg["is_channel"] as? Bool) ?? false
            if isChannel {
                // If admin with posting rights, allow.
                if
                    let status = sg["status"] as? [String: Any],
                    let statusType = status["@type"] as? String,
                    statusType.contains("Administrator"),
                    let canPost = status["can_post_messages"] as? Bool,
                    canPost == true
                {
                    return (true, nil)
                }
                return (false, "Это канал — отправка сообщений недоступна")
            }

            // Non-channel supergroup: allow by default unless restricted (we'll refine later).
            return (true, nil)
        }

        // 3) Private chats: allow.
        return (true, nil)
    }

    private func mapUserStatus(_ status: [String: Any]) -> (text: String, isOnline: Bool) {
        let statusType = status["@type"] as? String ?? ""
        switch statusType {
        case "userStatusOnline":
            return ("в сети", true)
        case "userStatusOffline":
            if let wasOnline = int64Value(status["was_online"]), wasOnline > 0 {
                return ("был(а) в сети \(relativeTimeText(fromUnix: wasOnline))", false)
            }
            return ("был(а) недавно", false)
        case "userStatusRecently":
            return ("был(а) недавно", false)
        case "userStatusLastWeek":
            return ("был(а) на этой неделе", false)
        case "userStatusLastMonth":
            return ("был(а) в этом месяце", false)
        default:
            return ("скрыт(а)", false)
        }
    }

    private func relativeTimeText(fromUnix value: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(value))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func mapAuthState(from tdType: String) -> AuthState {
        switch tdType {
        case "authorizationStateWaitPhoneNumber": return .waitPhone
        case "authorizationStateWaitCode": return .waitCode
        case "authorizationStateWaitPassword": return .waitPassword
        case "authorizationStateReady": return .ready
        default: return authState
        }
    }

    private func int64Value(_ any: Any?) -> Int64? {
        if let value = any as? Int64 { return value }
        if let value = any as? Int { return Int64(value) }
        if let value = any as? NSNumber { return value.int64Value }
        if let value = any as? String { return Int64(value) }
        return nil
    }

    private func tdError(from obj: [String: Any]) -> Error? {
        guard (obj["@type"] as? String) == "error" else { return nil }
        let code = (obj["code"] as? Int) ?? -1
        let message = (obj["message"] as? String) ?? "TDLib error"
        return NSError(domain: "TDLibClient", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private struct AuthStateWaiter {
    let id: UUID
    let matching: Set<String>
    let continuation: CheckedContinuation<Void, Error>
}

enum TDLibClientError: LocalizedError {
    case deallocated
    case jsonEncodingFailed
    case authorizationTimeout
    case invalidApiCredentials

    var errorDescription: String? {
        switch self {
        case .deallocated:
            return "TDLib client was closed"
        case .jsonEncodingFailed:
            return "Failed to encode TDLib request"
        case .authorizationTimeout:
            return "Timed out waiting for TDLib authorization state"
        case .invalidApiCredentials:
            return "Invalid API credentials format"
        }
    }
}
