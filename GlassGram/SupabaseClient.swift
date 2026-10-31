import Foundation
import Security

// MARK: - Keychain (session storage)

/// Minimal generic-password Keychain storage (one value per
/// account) — same pattern as the KeychainHelper in the MochiAI
/// project. The Supabase session (access + refresh token) lives
/// here, never in UserDefaults.
enum GGKeychain {
    private static let service = "dev.joe.glassgram"

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func set(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess {
            return
        }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func get(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}

// MARK: - Server payloads (parsed from JSON dictionaries)

/// A row of public.profiles.
struct GGProfile: Codable, Identifiable, Hashable {
    var id: String
    var username: String
    var displayName: String
    var isAdmin: Bool
    var activated: Bool
}

/// A row of public.messages.
struct GGServerMessage: Identifiable {
    var id: String
    var senderID: String
    var recipientID: String
    var body: String
    var createdAt: Date
}

/// A row of public.invite_codes.
struct GGInviteCodeRow: Identifiable {
    var code: String
    var createdBy: String?
    var usedBy: String?
    var createdAt: Date

    var id: String { code }
    var isUsed: Bool { usedBy != nil }
}

/// The stored auth session (Keychain, JSON).
private struct GGSession: Codable {
    var accessToken: String
    var refreshToken: String
    var userID: String
    var expiresAt: Date
}

// MARK: - Errors (with user-facing German text)

enum GGBackendError: Error, Equatable {
    /// No route to the backend at all (DNS, offline, timeout …).
    case offline
    /// The stored session could not be refreshed — signed out.
    case sessionExpired
    /// profiles.username unique violation.
    case usernameTaken
    /// Any other HTTP failure, with the status code.
    case http(Int)
    /// Payload did not have the expected shape.
    case badPayload

    var german: String {
        switch self {
        case .offline:
            return "Keine Verbindung zum Server. Prüfe deine Internetverbindung und versuch es erneut."
        case .sessionExpired:
            return "Deine Sitzung ist abgelaufen. Bitte registriere dich erneut."
        case .usernameTaken:
            return "Dieser Benutzername ist schon vergeben. Wähle bitte einen anderen."
        case .http(let status):
            return "Der Server meldet einen Fehler (HTTP \(status)). Bitte versuch es später erneut."
        case .badPayload:
            return "Der Server hat unerwartet geantwortet. Bitte versuch es später erneut."
        }
    }
}

// MARK: - Client

/// Thin hand-rolled Supabase client (Auth + PostgREST + RPC) over
/// URLSession. All parsing goes through JSONSerialization with
/// typed local extraction — no Decodable chains over server JSON.
///
/// Concurrency: an actor, so token refresh and session mutation
/// are race-free while the store polls from several tasks.
actor SupabaseClient {
    static let shared = SupabaseClient()

    private let base = BackendConfig.endpoint
    private let anonKey = BackendConfig.anonKey
    private let sessionAccount = "gg.session.v1"

    private var session: GGSession?
    private var sessionLoaded = false

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    // MARK: Session lifecycle

    /// The stored session's user ID, if any (session loaded lazily
    /// from Keychain).
    func restoreSession() -> String? {
        loadSessionIfNeeded()
        guard let session else { return nil }
        return session.userID
    }

    var hasSession: Bool { restoreSession() != nil }

    /// Anonymous sign-up: creates a fresh anonymous auth user and
    /// stores the returned session.
    @discardableResult
    func signUpAnonymous() async throws -> String {
        let (data, status) = try await rawRequest(
            path: "/auth/v1/signup",
            method: "POST",
            body: [:],
            authorized: false
        )
        guard status == 200 || status == 201 else {
            throw mapHTTPError(status: status, data: data)
        }
        guard let session = parseAuthResponse(data) else {
            throw GGBackendError.badPayload
        }
        self.session = session
        saveSession()
        return session.userID
    }

    /// A currently valid access token — refreshes transparently
    /// when the stored one is expired (or about to expire).
    func validAccessToken() async throws -> String {
        loadSessionIfNeeded()
        guard let current = session else { throw GGBackendError.sessionExpired }
        if current.expiresAt.timeIntervalSinceNow > 60 {
            return current.accessToken
        }
        return try await refreshSession()
    }

    private func refreshSession() async throws -> String {
        guard let current = session else { throw GGBackendError.sessionExpired }
        var components = URLComponents(string: base + "/auth/v1/token")!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        let (data, status) = try await rawRequest(
            url: components.url!,
            method: "POST",
            body: ["refresh_token": current.refreshToken],
            authorized: false
        )
        guard status == 200 else {
            // Refresh token is dead — the session is unrecoverable.
            session = nil
            GGKeychain.delete(account: sessionAccount)
            throw GGBackendError.sessionExpired
        }
        guard let refreshed = parseAuthResponse(data) else {
            throw GGBackendError.badPayload
        }
        session = refreshed
        saveSession()
        return refreshed.accessToken
    }

    // MARK: Profiles

    func fetchOwnProfile() async throws -> GGProfile? {
        guard let uid = restoreSession() else { throw GGBackendError.sessionExpired }
        let rows = try await restArray(path: "/rest/v1/profiles",
                                       query: [("id", "eq.\(uid)"), ("select", "*")])
        return rows.first.map(parseProfile)
    }

    func fetchProfile(id: String) async throws -> GGProfile? {
        let rows = try await restArray(path: "/rest/v1/profiles",
                                       query: [("id", "eq.\(id)"), ("select", "*")])
        return rows.first.map(parseProfile)
    }

    func fetchProfiles(ids: [String]) async throws -> [GGProfile] {
        guard !ids.isEmpty else { return [] }
        let list = ids.joined(separator: ",")
        let rows = try await restArray(path: "/rest/v1/profiles",
                                       query: [("id", "in.(\(list))"), ("select", "*")])
        return rows.map(parseProfile)
    }

    /// Contact search: activated users whose username contains the
    /// term (case-insensitive). The term is sanitized by the caller
    /// down to [a-z0-9._-], so it cannot break the filter syntax.
    func searchProfiles(term: String) async throws -> [GGProfile] {
        let rows = try await restArray(
            path: "/rest/v1/profiles",
            query: [
                ("username", "ilike.*\(term)*"),
                ("activated", "eq.true"),
                ("select", "id,username,display_name,is_admin,activated"),
                ("order", "username.asc"),
                ("limit", "25"),
            ]
        )
        return rows.map(parseProfile)
    }

    func createProfile(username: String, displayName: String) async throws {
        guard let uid = restoreSession() else { throw GGBackendError.sessionExpired }
        _ = try await authorizedRequest(
            path: "/rest/v1/profiles",
            method: "POST",
            query: [],
            body: ["id": uid, "username": username, "display_name": displayName],
            extraHeaders: ["Prefer": "return=minimal"]
        )
    }

    /// Only display_name is ever patched — the server restricts
    /// profile UPDATEs to display_name/username (column security),
    /// and is_admin/activated can never be set from the client.
    func updateDisplayName(_ name: String) async throws -> GGProfile? {
        guard let uid = restoreSession() else { throw GGBackendError.sessionExpired }
        let (data, status) = try await authorizedRequest(
            path: "/rest/v1/profiles",
            method: "PATCH",
            query: [("id", "eq.\(uid)")],
            body: ["display_name": name],
            extraHeaders: ["Prefer": "return=representation"]
        )
        guard status == 200 else { throw mapHTTPError(status: status, data: data) }
        let rows = parseJSONArray(data)
        return rows?.first.map(parseProfile)
    }

    // MARK: Invite redemption + admin codes

    /// Server-side redemption (existence + unused checked by the
    /// RPC; it also flips profiles.activated for the caller).
    func redeemInvite(code: String) async throws -> Bool {
        let (data, status) = try await authorizedRequest(
            path: "/rest/v1/rpc/redeem_invite",
            method: "POST",
            query: [],
            body: ["p_code": code],
            extraHeaders: [:]
        )
        guard status == 200 else { throw mapHTTPError(status: status, data: data) }
        let value = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments])
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        throw GGBackendError.badPayload
    }

    /// Admin only (RLS enforces is_admin): newest first.
    func fetchInviteCodes() async throws -> [GGInviteCodeRow] {
        let rows = try await restArray(
            path: "/rest/v1/invite_codes",
            query: [("select", "*"), ("order", "created_at.desc")]
        )
        return rows.map(parseInviteCode)
    }

    /// Admin only: generates a fresh GG code (shared InviteCode
    /// module) and inserts it as a server row.
    func createInviteCode() async throws -> GGInviteCodeRow {
        guard let uid = restoreSession() else { throw GGBackendError.sessionExpired }
        let code = InviteCode.generate()
        let (data, status) = try await authorizedRequest(
            path: "/rest/v1/invite_codes",
            method: "POST",
            query: [],
            body: ["code": code, "created_by": uid],
            extraHeaders: ["Prefer": "return=representation"]
        )
        guard status == 200 || status == 201 else { throw mapHTTPError(status: status, data: data) }
        guard let row = parseJSONArray(data)?.first else { throw GGBackendError.badPayload }
        return parseInviteCode(row)
    }

    // MARK: Messages

    /// Full 1:1 history with one partner, oldest first.
    /// The nested and/or filter cannot be expressed via
    /// URLQueryItem without mangling, so the whole query string
    /// is passed verbatim (ids are UUIDs — nothing to escape).
    func fetchConversation(myID: String, partnerID: String) async throws -> [GGServerMessage] {
        let rawQuery = "or=(and(sender_id.eq.\(myID),recipient_id.eq.\(partnerID)),and(sender_id.eq.\(partnerID),recipient_id.eq.\(myID)))&select=*&order=created_at.asc&limit=500"
        let rows = try await restArray(
            path: "/rest/v1/messages",
            query: [],
            rawQueryOverride: rawQuery
        )
        return rows.map(parseMessage)
    }

    /// Newest 200 messages I am part of (either direction) — the
    /// chat list is derived from these.
    func fetchRecentMessages(myID: String) async throws -> [GGServerMessage] {
        let rows = try await restArray(
            path: "/rest/v1/messages",
            query: [
                ("or", "(sender_id.eq.\(myID),recipient_id.eq.\(myID))"),
                ("select", "*"),
                ("order", "created_at.desc"),
                ("limit", "200"),
            ]
        )
        return rows.map(parseMessage)
    }

    @discardableResult
    func sendMessage(myID: String, partnerID: String, body: String) async throws -> GGServerMessage {
        let (data, status) = try await authorizedRequest(
            path: "/rest/v1/messages",
            method: "POST",
            query: [],
            body: ["sender_id": myID, "recipient_id": partnerID, "body": body],
            extraHeaders: ["Prefer": "return=representation"]
        )
        guard status == 200 || status == 201 else { throw mapHTTPError(status: status, data: data) }
        guard let row = parseJSONArray(data)?.first else { throw GGBackendError.badPayload }
        return parseMessage(row)
    }

    // MARK: - Plumbing

    /// Authorized GET that must return a JSON array of row objects.
    private func restArray(path: String,
                           query: [(String, String)],
                           rawQueryOverride: String? = nil) async throws -> [[String: Any]] {
        let (data, status) = try await authorizedRequest(
            path: path, method: "GET", query: query, body: nil,
            extraHeaders: [:], rawQueryOverride: rawQueryOverride
        )
        guard status == 200 else { throw mapHTTPError(status: status, data: data) }
        guard let rows = parseJSONArray(data) else { throw GGBackendError.badPayload }
        return rows
    }

    /// Performs an authorized REST call; on 401 it refreshes the
    /// token once and retries exactly once.
    private func authorizedRequest(path: String,
                                   method: String,
                                   query: [(String, String)],
                                   body: [String: Any]?,
                                   extraHeaders: [String: String],
                                   rawQueryOverride: String? = nil) async throws -> (Data, Int) {
        var token = try await validAccessToken()
        var result = try await rawRequest(path: path, method: method, query: query,
                                          body: body, accessToken: token,
                                          extraHeaders: extraHeaders,
                                          rawQueryOverride: rawQueryOverride)
        if result.1 == 401 {
            token = try await refreshSession()
            result = try await rawRequest(path: path, method: method, query: query,
                                          body: body, accessToken: token,
                                          extraHeaders: extraHeaders,
                                          rawQueryOverride: rawQueryOverride)
        }
        return result
    }

    private func rawRequest(path: String,
                            method: String,
                            query: [(String, String)],
                            body: [String: Any]?,
                            accessToken: String?,
                            extraHeaders: [String: String],
                            rawQueryOverride: String? = nil) async throws -> (Data, Int) {
        var components = URLComponents(string: base + path)!
        if let rawQueryOverride {
            components.percentEncodedQuery = rawQueryOverride
        } else if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        return try await rawRequest(url: components.url!, method: method,
                                    bodyObject: body, accessToken: accessToken,
                                    extraHeaders: extraHeaders)
    }

    /// Signup/refresh variant: no access token yet.
    private func rawRequest(path: String,
                            method: String,
                            body: [String: Any],
                            authorized: Bool) async throws -> (Data, Int) {
        let url = URL(string: base + path)!
        return try await rawRequest(url: url, method: method, bodyObject: body,
                                    accessToken: nil, extraHeaders: [:])
    }

    private func rawRequest(url: URL,
                            method: String,
                            body: [String: Any]?,
                            accessToken: String?,
                            extraHeaders: [String: String]) async throws -> (Data, Int) {
        try await rawRequest(url: url, method: method,
                             bodyObject: body as Any?, accessToken: accessToken,
                             extraHeaders: extraHeaders)
    }

    private func rawRequest(url: URL,
                            method: String,
                            bodyObject: Any?,
                            accessToken: String?,
                            extraHeaders: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let bodyObject {
            request.httpBody = try JSONSerialization.data(withJSONObject: bodyObject)
        }
        do {
            let (data, response) = try await urlSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            return (data, status)
        } catch let error as URLError {
            throw mapURLError(error)
        }
    }

    // MARK: Error mapping

    private func mapURLError(_ error: URLError) -> GGBackendError {
        switch error.code {
        case .notConnectedToInternet, .timedOut, .cannotFindHost,
             .cannotConnectToHost, .networkConnectionLost,
             .dnsLookupFailed, .internationalRoamingOff, .callIsActive,
             .dataNotAllowed:
            return .offline
        default:
            return .offline
        }
    }

    private func mapHTTPError(status: Int, data: Data) -> GGBackendError {
        if status == 409 { return .usernameTaken }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let code = (object["code"] as? String) ?? ""
            let message = (object["message"] as? String) ?? ""
            if code == "23505" || message.localizedCaseInsensitiveContains("duplicate key") {
                return .usernameTaken
            }
        }
        return .http(status)
    }

    // MARK: Parsing (JSONSerialization + typed locals)

    private func parseJSONArray(_ data: Data) -> [[String: Any]]? {
        guard let value = try? JSONSerialization.jsonObject(with: data),
              let rows = value as? [[String: Any]] else { return nil }
        return rows
    }

    private func parseAuthResponse(_ data: Data) -> GGSession? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = object["access_token"] as? String,
              let refreshToken = object["refresh_token"] as? String,
              let user = object["user"] as? [String: Any],
              let userID = user["id"] as? String else { return nil }
        let expiresIn = (object["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        return GGSession(accessToken: accessToken,
                         refreshToken: refreshToken,
                         userID: userID,
                         expiresAt: Date().addingTimeInterval(expiresIn))
    }

    private func parseProfile(_ row: [String: Any]) -> GGProfile {
        GGProfile(
            id: (row["id"] as? String) ?? "",
            username: (row["username"] as? String) ?? "",
            displayName: (row["display_name"] as? String) ?? "",
            isAdmin: (row["is_admin"] as? Bool) ?? false,
            activated: (row["activated"] as? Bool) ?? false
        )
    }

    private func parseMessage(_ row: [String: Any]) -> GGServerMessage {
        GGServerMessage(
            id: (row["id"] as? String) ?? UUID().uuidString,
            senderID: (row["sender_id"] as? String) ?? "",
            recipientID: (row["recipient_id"] as? String) ?? "",
            body: (row["body"] as? String) ?? "",
            createdAt: parseServerDate((row["created_at"] as? String) ?? "") ?? Date()
        )
    }

    private func parseInviteCode(_ row: [String: Any]) -> GGInviteCodeRow {
        GGInviteCodeRow(
            code: (row["code"] as? String) ?? "",
            createdBy: row["created_by"] as? String,
            usedBy: row["used_by"] as? String,
            createdAt: parseServerDate((row["created_at"] as? String) ?? "") ?? Date()
        )
    }

    /// Supabase timestamps arrive as ISO-8601 with up to 6
    /// fractional digits and a +00:00 offset — try the formatters
    /// in order of likelihood.
    private func parseServerDate(_ string: String) -> Date? {
        if string.isEmpty { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        if let date = formatter.date(from: string) { return date }
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.date(from: string)
    }

    // MARK: Session persistence

    private func loadSessionIfNeeded() {
        guard !sessionLoaded else { return }
        sessionLoaded = true
        guard let json = GGKeychain.get(account: sessionAccount),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(GGSession.self, from: data) else { return }
        session = decoded
    }

    private func saveSession() {
        guard let session,
              let data = try? JSONEncoder().encode(session),
              let json = String(data: data, encoding: .utf8) else { return }
        GGKeychain.set(json, account: sessionAccount)
    }
}
