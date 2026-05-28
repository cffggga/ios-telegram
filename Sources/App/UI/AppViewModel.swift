import Foundation
import Combine
import Security

@MainActor
final class AppViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case setup
        case login
        case main
    }

    @Published var phase: Phase = .loading
    @Published var apiIdText = ""
    @Published var apiHash = ""
    @Published var phone = ""
    @Published var code = ""
    @Published var password = ""

    @Published var chats: [TgChat] = []
    @Published var selectedChatId: Int64?
    @Published var messages: [TgMessage] = []
    @Published var composeText = ""
    @Published var editingMessageId: Int64?
    @Published var chatSearch = ""
    @Published var status = ""
    @Published var authState: AuthState = .waitPhone
    @Published var isBusy = false
    @Published var bootstrapError: String?

    private var repository: TelegramRepository?
    private var isTdlibConfigured = false
    private let credentials = ApiCredentialsStore()

    var filteredChats: [TgChat] {
        let query = chatSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return chats }
        return chats.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.lastMessagePreview?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var selectedChat: TgChat? {
        guard let selectedChatId else { return nil }
        return chats.first(where: { $0.id == selectedChatId })
    }

    func start() async {
        phase = .loading
        bootstrapError = nil

        do {
            let repo = try TelegramRepository.bootstrap()
            repository = repo
            wireRepository(repo)

            if let saved = credentials.load() {
                apiIdText = String(saved.apiId)
                apiHash = saved.apiHash
                await connect(saveCredentials: false)
            } else {
                phase = .setup
                status = "Введите API ID и API Hash с my.telegram.org"
            }
        } catch {
            bootstrapError = error.localizedDescription
            phase = .setup
            status = "TDLib недоступен: \(error.localizedDescription)"
        }
    }

    func saveAndConnect() async {
        guard let credentials = normalizedApiCredentials() else {
            status = "Укажите корректные api_id и api_hash (без пробелов и лишних символов)"
            return
        }
        apiIdText = String(credentials.apiId)
        apiHash = credentials.apiHash
        self.credentials.save(apiId: credentials.apiId, apiHash: credentials.apiHash)

        if isTdlibConfigured, let repository {
            authState = repository.authState()
            await applyPhase(for: authState)
            return
        }

        await recreateRepository()
        await connect(saveCredentials: false)
    }

    func connect(saveCredentials: Bool) async {
        guard let repository else {
            status = "Клиент не инициализирован"
            phase = .setup
            return
        }

        guard let credentials = normalizedApiCredentials() else {
            status = "Укажите api_id и api_hash"
            phase = .setup
            return
        }
        let apiId = credentials.apiId
        let apiHash = credentials.apiHash
        apiIdText = String(apiId)
        self.apiHash = apiHash

        if saveCredentials {
            self.credentials.save(apiId: apiId, apiHash: apiHash)
        }

        isBusy = true
        defer { isBusy = false }

        do {
            if !isTdlibConfigured {
                try await repository.setup(apiId: apiId, apiHash: apiHash)
                isTdlibConfigured = true
            }
            authState = repository.authState()
            await applyPhase(for: authState)
        } catch {
            let message = error.localizedDescription
            let upper = message.uppercased()
            if upper.contains("API_ID_INVALID") || upper.contains("APP_ID_INVALID") {
                status = "Telegram отклоняет api_id/api_hash. Проверь на my.telegram.org -> API development tools, что это App api_id и App api_hash из одной пары."
            } else {
                status = message
            }
            phase = .setup
        }
    }

    func submitAuth() async {
        guard let repository else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            switch authState {
            case .waitPhone:
                let normalized = phone.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else {
                    status = "Введите номер телефона"
                    return
                }
                try await repository.submitPhone(normalized)
            case .waitCode:
                let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else {
                    status = "Введите код из Telegram"
                    return
                }
                try await repository.submitCode(normalized)
            case .waitPassword:
                guard !password.isEmpty else {
                    status = "Введите пароль 2FA"
                    return
                }
                try await repository.submitPassword(password)
            case .ready:
                break
            }

            authState = repository.authState()
            await applyPhase(for: authState)
        } catch {
            status = error.localizedDescription
        }
    }

    func signOut() {
        credentials.clear()
        apiIdText = ""
        apiHash = ""
        phone = ""
        code = ""
        password = ""
        chats = []
        messages = []
        selectedChatId = nil
        authState = .waitPhone
        repository = nil
        isTdlibConfigured = false
        bootstrapError = nil
        phase = .setup
        status = "Войдите снова — укажите API данные"
        Task { await start() }
    }

    func refreshChats() async {
        guard let repository, authState == .ready else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            chats = try await repository.loadChats()
            status = ""
        } catch {
            status = error.localizedDescription
        }
    }

    func selectChat(_ chatId: Int64) async {
        selectedChatId = chatId
        await refreshMessages()
    }

    func refreshMessages() async {
        guard let repository, let chatId = selectedChatId else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            messages = try await repository.syncMessages(chatId: chatId)
        } catch {
            status = error.localizedDescription
        }
    }

    func sendMessage() async {
        guard let repository, let chatId = selectedChatId else { return }
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isBusy = true
        defer { isBusy = false }
        do {
            if let editingMessageId {
                messages = try await repository.edit(chatId: chatId, messageId: editingMessageId, text: text)
                self.editingMessageId = nil
            } else {
                messages = try await repository.send(chatId: chatId, text: text)
            }
            composeText = ""
            await refreshChats()
        } catch {
            status = error.localizedDescription
        }
    }

    func startEditing(_ message: TgMessage) {
        guard message.outgoing else { return }
        editingMessageId = message.id
        composeText = message.text
    }

    func cancelEditing() {
        editingMessageId = nil
    }

    func deleteMyMessage(_ message: TgMessage, revoke: Bool) async {
        guard let repository, let chatId = selectedChatId, message.outgoing else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            messages = try await repository.delete(chatId: chatId, messageIds: [message.id], revoke: revoke)
            await refreshChats()
        } catch {
            status = error.localizedDescription
        }
    }

    func quoteMessage(_ message: TgMessage) {
        let snippet = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !snippet.isEmpty else { return }
        let author = message.outgoing ? "Вы" : "Собеседник"
        composeText = "> \(author): \(snippet)\n" + composeText
    }

    func authStepTitle() -> String {
        switch authState {
        case .waitPhone: return "Номер телефона"
        case .waitCode: return "Код подтверждения"
        case .waitPassword: return "Пароль 2FA"
        case .ready: return "Готово"
        }
    }

    func authStepSubtitle() -> String {
        switch authState {
        case .waitPhone:
            return "Введите номер в международном формате, например +79991234567"
        case .waitCode:
            return "Код придёт в Telegram или по SMS"
        case .waitPassword:
            return "У аккаунта включена двухэтапная аутентификация"
        case .ready:
            return ""
        }
    }

    private func wireRepository(_ repository: TelegramRepository) {
        repository.onAuthStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.authState = state
                await self?.applyPhase(for: state)
            }
        }

        repository.onMessagesChanged = { [weak self] chatId in
            guard let self else { return }
            Task { @MainActor in
                if self.selectedChatId == chatId {
                    await self.refreshMessages()
                }
                await self.refreshChats()
            }
        }

        repository.onChatsChanged = { [weak self] in
            Task { @MainActor in
                await self?.refreshChats()
            }
        }
    }

    private func applyPhase(for state: AuthState) async {
        switch state {
        case .ready:
            phase = .main
            status = ""
            await refreshChats()
            if selectedChatId == nil {
                selectedChatId = chats.first?.id
            }
            if let selectedChatId {
                await selectChat(selectedChatId)
            }
        case .waitPhone, .waitCode, .waitPassword:
            phase = .login
            status = ""
        }
    }

    private func normalizedApiCredentials() -> (apiId: Int, apiHash: String)? {
        let idDigits = apiIdText.unicodeScalars
            .filter { CharacterSet.decimalDigits.contains($0) }
            .map(String.init)
            .joined()

        guard let apiId = Int(idDigits), apiId > 0 else {
            return nil
        }

        let trimmedHash = apiHash.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowedHex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        let normalizedHash = trimmedHash.unicodeScalars
            .filter { allowedHex.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()

        guard normalizedHash.count == 32 else {
            return nil
        }

        return (apiId, normalizedHash)
    }

    private func recreateRepository() async {
        do {
            let repo = try TelegramRepository.bootstrap()
            repository = repo
            wireRepository(repo)
            isTdlibConfigured = false
            bootstrapError = nil
        } catch {
            bootstrapError = error.localizedDescription
            status = "Не удалось пересоздать TDLib клиент: \(error.localizedDescription)"
        }
    }
}

private struct ApiCredentialsStore {
    private let apiIdKey = "telegram.api_id"
    private let apiHashKey = "telegram.api_hash"
    private let service = "online.maseai.telegramuserclient.credentials"
    private let account = "telegram.api_credentials"
    private let bundledApiId = 39444423
    private let bundledApiHash = "07679c329a2ea28d6b6f1858d5129d01"

    struct Saved {
        let apiId: Int
        let apiHash: String
    }

    func load() -> Saved? {
        if let fromKeychain = loadFromKeychain() {
            return fromKeychain
        }

        // One-time migration from old storage.
        let defaults = UserDefaults.standard
        let apiId = defaults.integer(forKey: apiIdKey)
        if apiId > 0, let apiHash = defaults.string(forKey: apiHashKey), !apiHash.isEmpty {
            let saved = Saved(apiId: apiId, apiHash: apiHash)
            saveToKeychain(saved)
            defaults.removeObject(forKey: apiIdKey)
            defaults.removeObject(forKey: apiHashKey)
            return saved
        }

        let bundled = bundledCredentials()
        saveToKeychain(bundled)
        return bundled
    }

    func save(apiId: Int, apiHash: String) {
        saveToKeychain(Saved(apiId: apiId, apiHash: apiHash))
    }

    func clear() {
        deleteFromKeychain()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: apiIdKey)
        defaults.removeObject(forKey: apiHashKey)
    }

    private func loadFromKeychain() -> Saved? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let apiId = object["api_id"] as? Int,
            let apiHash = object["api_hash"] as? String,
            apiId > 0,
            !apiHash.isEmpty
        else {
            return nil
        }
        return Saved(apiId: apiId, apiHash: apiHash)
    }

    private func bundledCredentials() -> Saved {
        Saved(apiId: bundledApiId, apiHash: bundledApiHash)
    }

    private func saveToKeychain(_ saved: Saved) {
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: ["api_id": saved.apiId, "api_hash": saved.apiHash]
            )
        else {
            return
        }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let update: [String: Any] = [kSecValueData as String: data]
            SecItemUpdate(query as CFDictionary, update as CFDictionary)
        }
    }

    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
