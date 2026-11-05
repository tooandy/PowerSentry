import Foundation

func tr(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: "Localizable")
}

func trf(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: tr(key), locale: Locale.current, arguments: arguments)
}

enum PowerSentryLocalization {
    static let supportedLanguages = ["en", "zh-Hans", "zh-Hant", "es", "ko", "ja", "de", "fr", "nl"]

    static func validateResources() -> Bool {
        let requiredKeys = [
            "menu.open_dashboard",
            "section.battery_power",
            "incident.title.power",
            "alert.termination.title"
        ]

        for language in supportedLanguages {
            guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
                  let bundle = Bundle(path: path) else {
                fputs("Missing localization bundle: \(language)\n", stderr)
                return false
            }

            for key in requiredKeys {
                let value = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
                guard !value.isEmpty, value != key else {
                    fputs("Missing localization key \(key) in \(language)\n", stderr)
                    return false
                }
            }
        }

        print("PASS: \(supportedLanguages.count) localized language resources are bundled and readable")
        return true
    }
}
