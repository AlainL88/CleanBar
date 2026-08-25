import Foundation

public final class StateStore {
    private let userDefaults: UserDefaults
    private let storageKey = "CleanBarItemConfigs"
    private let onboardingKey = "CleanBarHasCompletedOnboarding"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var hasCompletedOnboarding: Bool {
        get { userDefaults.bool(forKey: onboardingKey) }
        set { userDefaults.set(newValue, forKey: onboardingKey) }
    }

    public func category(for id: String) -> ItemCategory {
        guard let data = userDefaults.data(forKey: storageKey),
              let configs = try? JSONDecoder().decode([String: ItemConfig].self, from: data),
              let config = configs[id] else {
            return .hiddenOnHover
        }
        return config.category
    }

    public func setCategory(_ category: ItemCategory, for id: String) {
        var configs = loadAll()
        var config = configs[id] ?? ItemConfig(id: id, category: category)
        config.category = category
        configs[id] = config
        saveAll(configs)
    }

    private func loadAll() -> [String: ItemConfig] {
        guard let data = userDefaults.data(forKey: storageKey),
              let configs = try? JSONDecoder().decode([String: ItemConfig].self, from: data) else {
            return [:]
        }
        return configs
    }

    private func saveAll(_ configs: [String: ItemConfig]) {
        if let data = try? JSONEncoder().encode(configs) {
            userDefaults.set(data, forKey: storageKey)
        }
    }
}
