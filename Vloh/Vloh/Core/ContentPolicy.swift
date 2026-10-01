import Foundation

enum ContentPolicy {
    static func allows(_ text: String) -> Bool {
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return !["kill yourself", "child pornography", "child porn", "rape you"].contains(where: normalized.contains)
    }
}
