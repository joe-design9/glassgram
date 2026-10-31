import Foundation

// MARK: - Data models (all Codable, persisted as JSON in UserDefaults)

struct GGContact: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// Subtitle shown in the contacts list, e.g. "zul. online gestern um 23:01".
    var status: String
    /// Index into Theme.avatarColors.
    var colorIndex: Int
    /// Broadcast channel (CyberLeek-style): never auto-replies.
    var isChannel: Bool = false
    /// Group chat partner (GTA-news-style): replies come from the group.
    var isGroup: Bool = false
}

struct GGMessage: Codable, Identifiable {
    var id: UUID = UUID()
    var chatID: String
    var isMine: Bool
    var text: String
    var date: Date
}

struct GGChat: Codable, Identifiable {
    var id: String
    /// nil only for the "Gespeichertes" (saved messages) chat.
    var contactID: String?
    var title: String
    var colorIndex: Int
    var isMuted: Bool = false
    var unread: Int = 0
    /// Optional custom folder name (drives the filter pill in the chat list).
    var folder: String? = nil

    var isSavedMessages: Bool { id == Store.savedChatID }
}

enum GGCallDirection: String, Codable {
    case incoming
    case outgoing
}

struct GGCall: Codable, Identifiable {
    var id: UUID = UUID()
    var contactID: String
    var date: Date
    var direction: GGCallDirection
    var missed: Bool
    /// Answered duration in seconds (0 when not answered / not applicable).
    var durationSec: Int = 0
}

struct GGSettings: Codable {
    var soundEnabled: Bool = true
    var vibrationEnabled: Bool = false
    /// Multiplier for chat text size (Darstellung → Schriftgröße).
    var fontScale: Double = 1.0
}

/// One invite code managed inside the admin build.
struct AdminCode: Codable, Identifiable {
    var id: UUID = UUID()
    var code: String
    var createdAt: Date
    /// "frei" (not handed out yet) or "verteilt" (handed out).
    var status: String = "frei"
}

// MARK: - Display helpers

enum TimeFormat {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yy"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEE"
        return f
    }()

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yy, HH:mm"
        return f
    }()

    /// Inside a message bubble: always HH:mm.
    static func bubble(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// Chat-list timestamp: HH:mm today, weekday this week, date when older.
    static func list(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return timeFormatter.string(from: date) }
        if cal.isDateInYesterday(date) { return "Gestern" }
        if let days = cal.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return weekdayFormatter.string(from: date)
        }
        return dayFormatter.string(from: date)
    }

    /// Call-list timestamp.
    static func call(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Heute, " + timeFormatter.string(from: date) }
        if cal.isDateInYesterday(date) { return "Gestern, " + timeFormatter.string(from: date) }
        return fullFormatter.string(from: date)
    }

    /// Settings/admin rows: plain date.
    static func dateOnly(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// Call duration as m:ss.
    static func duration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Initials for the letter avatars ("Stefan B" → "SB", "Mama" → "M").
func avatarInitials(_ name: String) -> String {
    let words = name.split(separator: " ").prefix(2)
    let letters = words.compactMap { $0.first }.map { String($0) }
    return letters.joined().uppercased()
}
