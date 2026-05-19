import Foundation

struct IgnoredApp: Identifiable, Equatable {
    let bundleID: String
    let name: String

    var id: String {
        bundleID
    }
}

@MainActor
final class IgnoredAppSettings: ObservableObject {
    @Published private(set) var apps: [IgnoredApp] = []

    private static let key = "ignoredApps"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.apps = Self.loadApps(from: userDefaults)
    }

    func contains(bundleID: String?) -> Bool {
        guard let bundleID else {
            return false
        }

        guard bundleID != SourceAppInfo.currentAppBundleID,
              bundleID != SourceAppInfo.clipease.bundleID else {
            return false
        }

        return apps.contains { $0.bundleID == bundleID }
    }

    @discardableResult
    func add(bundleID: String?, name: String) -> Bool {
        guard let bundleID,
              !bundleID.isEmpty,
              bundleID != SourceAppInfo.currentAppBundleID,
              bundleID != SourceAppInfo.clipease.bundleID,
              !contains(bundleID: bundleID) else {
            return false
        }

        apps.append(IgnoredApp(bundleID: bundleID, name: name))
        sortAndSave()
        return true
    }

    func remove(bundleID: String) {
        apps.removeAll { $0.bundleID == bundleID }
        save()
    }

    func removeAll() {
        apps.removeAll()
        save()
    }

    private func sortAndSave() {
        apps.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        save()
    }

    private func save() {
        let values = apps.map { app in
            [
                "bundleID": app.bundleID,
                "name": app.name
            ]
        }
        userDefaults.set(values, forKey: Self.key)
    }

    private static func loadApps(from userDefaults: UserDefaults) -> [IgnoredApp] {
        guard let values = userDefaults.array(forKey: key) as? [[String: String]] else {
            return []
        }

        return values.compactMap { value in
            guard let bundleID = value["bundleID"],
                  !bundleID.isEmpty else {
                return nil
            }

            return IgnoredApp(
                bundleID: bundleID,
                name: value["name"] ?? bundleID
            )
        }
    }
}
