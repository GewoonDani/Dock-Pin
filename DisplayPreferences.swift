import Foundation

struct DisplayPreferences {
    let defaults: UserDefaults

    private func setupKey(_ displays: [DisplayArea]) -> String {
        displays.map(\.key).sorted().joined(separator: "|")
    }

    func selection(for displays: [DisplayArea]) -> String {
        guard !displays.isEmpty else { return "" }
        let choices = defaults.dictionary(forKey: "displaySelections") as? [String: String] ?? [:]
        if let key = choices[setupKey(displays)] {
            return displays.contains(where: { $0.key == key }) ? key : ""
        }
        // Preserve the old global choice once, without applying it to every new setup.
        if choices.isEmpty, let legacy = defaults.string(forKey: "selectedDisplay"),
           displays.contains(where: { $0.key == legacy }) {
            remember(legacy, for: displays)
            return legacy
        }
        return ""
    }

    func remember(_ key: String, for displays: [DisplayArea]) {
        guard displays.contains(where: { $0.key == key }) else { return }
        var choices = defaults.dictionary(forKey: "displaySelections") as? [String: String] ?? [:]
        choices[setupKey(displays)] = key
        defaults.set(choices, forKey: "displaySelections")
    }
}
