import Foundation

/// Remembers a menu choice across launches. Stored by case name rather than
/// the Thai title, so rewording a title does not lose the saved choice.
nonisolated enum Preference {
    static func decode<T: CaseIterable>(_ stored: String?, default value: T) -> T {
        guard let stored else { return value }
        return T.allCases.first { "\($0)" == stored } ?? value
    }

    static func encode<T>(_ value: T) -> String { "\(value)" }

    static func load<T: CaseIterable>(_ key: String, default value: T) -> T {
        decode(UserDefaults.standard.string(forKey: key), default: value)
    }

    static func save<T>(_ value: T, _ key: String) {
        UserDefaults.standard.set(encode(value), forKey: key)
    }
}
