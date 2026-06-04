import Foundation

enum AppSettings {
    static var notificationSoundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "notificationSoundEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notificationSoundEnabled") }
    }
}
