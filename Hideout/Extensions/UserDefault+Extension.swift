import Foundation

extension UserDefaults {
    enum Key {
        static let globalKey = "globalKey"
        static let numberOfSecondForAutoHide = "numberOfSecondForAutoHide"
        static let isAutoStart = "isAutoStart"
        static let isAutoHide = "isAutoHide"
        static let isShowPreference = "isShowPreferences"
        static let useFullStatusBarOnExpandEnabled = "useFullStatusBarOnExpandEnabled"
        static let hoverToExpand = "hoverToExpand"
        static let lastUpdateCheckDate = "lastUpdateCheckDate"
        static let lastNotifiedUpdateVersion = "lastNotifiedUpdateVersion"
        static let availableUpdateVersion = "availableUpdateVersion"
        static let availableUpdateURL = "availableUpdateURL"
    }
}
