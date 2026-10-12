import AppKit
import Foundation
import OSLog
import UserNotifications

struct UpdateVersion: Comparable, CustomStringConvertible, Sendable {
    private let major: Int
    private let minor: Int
    private let patch: Int

    init?(_ value: String) {
        let normalizedValue = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let components = normalizedValue.split(separator: ".", omittingEmptySubsequences: false)

        guard components.count == 3,
              components.allSatisfy({ component in
                  !component.isEmpty && component.unicodeScalars.allSatisfy {
                      (48...57).contains($0.value)
                  }
              }),
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2])
        else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: UpdateVersion, rhs: UpdateVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }
}

struct AvailableUpdate: Sendable {
    let version: UpdateVersion
    let releaseURL: URL
}

private struct GitHubRelease: Decodable, Sendable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

@MainActor
final class UpdateChecker: NSObject {
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/danilrez/Hideout/releases/latest"
    )!

    private let notificationCenter = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "com.danilrez.hideout", category: "Updates")
    private var onUpdateAvailable: (@MainActor (AvailableUpdate) -> Void)?
    private var periodicCheckTask: Task<Void, Never>?
    private var hasStarted = false

    func start(onUpdateAvailable: @escaping @MainActor (AvailableUpdate) -> Void) {
        guard !hasStarted else { return }
        hasStarted = true
        self.onUpdateAvailable = onUpdateAvailable
        notificationCenter.delegate = self

        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        restoreCachedUpdateIfAvailable()
        checkForUpdateIfDue()
        schedulePeriodicChecks()
    }

    private func schedulePeriodicChecks() {
        periodicCheckTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(Self.checkInterval))
                } catch {
                    return
                }

                guard let self else { return }
                self.checkForUpdateIfDue()
            }
        }
    }

    private func checkForUpdateIfDue(now: Date = Date()) {
        let defaults = UserDefaults.standard
        if let lastCheck = defaults.object(forKey: UserDefaults.Key.lastUpdateCheckDate) as? Date,
           now.timeIntervalSince(lastCheck) < Self.checkInterval {
            return
        }

        defaults.set(now, forKey: UserDefaults.Key.lastUpdateCheckDate)
        Task { await fetchLatestRelease() }
    }

    private func restoreCachedUpdateIfAvailable() {
        guard let currentVersionString = Bundle.main.releaseVersionNumber,
              let currentVersion = UpdateVersion(currentVersionString),
              let cachedVersionString = UserDefaults.standard.string(
                  forKey: UserDefaults.Key.availableUpdateVersion
              ),
              let cachedVersion = UpdateVersion(cachedVersionString),
              let cachedURLString = UserDefaults.standard.string(
                  forKey: UserDefaults.Key.availableUpdateURL
              ),
              let releaseURL = Self.trustedReleaseURL(from: cachedURLString)
        else {
            return
        }

        guard cachedVersion > currentVersion else {
            clearCachedUpdate()
            return
        }

        onUpdateAvailable?(AvailableUpdate(version: cachedVersion, releaseURL: releaseURL))
    }

    private func fetchLatestRelease() async {
        guard let currentVersionString = Bundle.main.releaseVersionNumber,
              let currentVersion = UpdateVersion(currentVersionString)
        else {
            logger.error("The app version is not a valid three-part version number.")
            return
        }

        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Hideout", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200
            else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.error("GitHub release check returned HTTP status \(statusCode).")
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard let latestVersion = UpdateVersion(release.tagName),
                  let releaseURL = Self.trustedReleaseURL(from: release.htmlURL)
            else {
                logger.error("GitHub returned an invalid release tag or URL.")
                return
            }

            guard latestVersion > currentVersion else {
                clearCachedUpdate()
                return
            }

            let update = AvailableUpdate(version: latestVersion, releaseURL: releaseURL)
            cache(update)
            onUpdateAvailable?(update)
            await deliverNotification(for: update)
        } catch {
            logger.error("GitHub release check failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func cache(_ update: AvailableUpdate) {
        let defaults = UserDefaults.standard
        defaults.set(update.version.description, forKey: UserDefaults.Key.availableUpdateVersion)
        defaults.set(update.releaseURL.absoluteString, forKey: UserDefaults.Key.availableUpdateURL)
    }

    private func clearCachedUpdate() {
        UserDefaults.standard.removeObject(forKey: UserDefaults.Key.availableUpdateVersion)
        UserDefaults.standard.removeObject(forKey: UserDefaults.Key.availableUpdateURL)
    }

    private func deliverNotification(for update: AvailableUpdate) async {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: UserDefaults.Key.lastNotifiedUpdateVersion)
                != update.version.description
        else {
            return
        }

        let settings = await notificationCenter.notificationSettings()
        let isAuthorized: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        case .notDetermined:
            do {
                isAuthorized = try await notificationCenter.requestAuthorization(options: [.alert])
            } catch {
                logger.error("Notification permission request failed: \(error.localizedDescription, privacy: .private)")
                return
            }
        case .denied:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }

        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Hideout update available".localized
        content.body = String(
            format: "Version %@ is ready. Select to open the release page and download it.".localized,
            update.version.description
        )
        content.userInfo = ["releaseURL": update.releaseURL.absoluteString]

        let request = UNNotificationRequest(
            identifier: "hideout-update-\(update.version)",
            content: content,
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
            defaults.set(update.version.description, forKey: UserDefaults.Key.lastNotifiedUpdateVersion)
        } catch {
            logger.error("Update notification could not be scheduled: \(error.localizedDescription, privacy: .private)")
        }
    }

    nonisolated private static func trustedReleaseURL(from value: String) -> URL? {
        guard let components = URLComponents(string: value),
              components.scheme == "https",
              components.host == "github.com",
              components.path.hasPrefix("/danilrez/Hideout/releases/tag/")
        else {
            return nil
        }

        return components.url
    }
}

extension UpdateChecker: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let releaseURLString = response.notification.request.content.userInfo["releaseURL"] as? String
        let releaseURL = releaseURLString.flatMap(Self.trustedReleaseURL(from:))
        let shouldOpenRelease = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        completionHandler()

        guard shouldOpenRelease, let releaseURL else { return }
        Task { @MainActor in
            NSWorkspace.shared.open(releaseURL)
        }
    }
}
