import Combine
import Foundation
import WidgetKit

@MainActor
final class QuotaDashboardViewModel: ObservableObject {
    @Published private(set) var snapshot = CodexQuotaSnapshot.unavailable(at: Date())
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var widgetBackgroundOpacity: Double
    @Published private(set) var widgetBackgroundStyle: WidgetBackgroundStyle
    @Published private(set) var widgetBackgroundColor: WidgetBackgroundColor

    private var refreshTimer: Timer?
    private var stateWatcher: FileWatcher?
    private var rolloutWatcher: FileWatcher?

    private static let widgetBackgroundOpacityKey = "widgetBackgroundOpacity"
    private static let widgetBackgroundStyleKey = "widgetBackgroundStyle"
    private static let widgetBackgroundColorKey = "widgetBackgroundColor"
    private static let defaultWidgetBackgroundOpacity = 0.18
    private static let defaultWidgetBackgroundStyle: WidgetBackgroundStyle = .defaultColor
    private static let defaultWidgetBackgroundColor = WidgetBackgroundColor(
        red: 0.74,
        green: 0.76,
        blue: 0.82
    )

    init() {
        let defaults = UserDefaults.standard
        let storedOpacity = defaults.object(forKey: Self.widgetBackgroundOpacityKey) as? Double
        let storedStyle = defaults.string(forKey: Self.widgetBackgroundStyleKey)
        let storedColorData = defaults.data(forKey: Self.widgetBackgroundColorKey)

        self.widgetBackgroundOpacity = Self.clampWidgetBackgroundOpacity(
            storedOpacity ?? Self.defaultWidgetBackgroundOpacity
        )
        self.widgetBackgroundStyle = WidgetBackgroundStyle(rawValue: storedStyle ?? "")
            ?? Self.defaultWidgetBackgroundStyle
        self.widgetBackgroundColor = Self.decodeWidgetBackgroundColor(from: storedColorData)
            ?? Self.defaultWidgetBackgroundColor
        refresh()
        configureStateWatcher()
        startRefreshTimer()
    }

    func refresh() {
        let now = Date()

        do {
            let latestSnapshot = applyWidgetAppearance(
                to: try CodexQuotaSnapshotBuilder.buildFromLocalCodexState(now: now)
            )
            snapshot = latestSnapshot
            lastErrorMessage = nil
            lastRefreshDate = now
            try persist(snapshot: latestSnapshot)
            configureRolloutWatcher(for: latestSnapshot.sourceRolloutPath)
        } catch {
            let unavailableSnapshot = applyWidgetAppearance(
                to: CodexQuotaSnapshot.unavailable(at: now)
            )
            snapshot = unavailableSnapshot
            lastErrorMessage = error.localizedDescription
            lastRefreshDate = now
            try? persist(snapshot: unavailableSnapshot)
            configureRolloutWatcher(for: nil)
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    func setWidgetBackgroundOpacity(_ opacity: Double) {
        let clampedOpacity = Self.clampWidgetBackgroundOpacity(opacity)
        guard clampedOpacity != widgetBackgroundOpacity else {
            return
        }

        widgetBackgroundOpacity = clampedOpacity
        UserDefaults.standard.set(clampedOpacity, forKey: Self.widgetBackgroundOpacityKey)
        applyAppearanceAndReload()
    }

    func setWidgetBackgroundStyle(_ style: WidgetBackgroundStyle) {
        guard style != widgetBackgroundStyle else {
            return
        }

        widgetBackgroundStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: Self.widgetBackgroundStyleKey)
        applyAppearanceAndReload()
    }

    func setWidgetBackgroundColor(_ color: WidgetBackgroundColor) {
        guard color != widgetBackgroundColor else {
            return
        }

        widgetBackgroundColor = color
        widgetBackgroundStyle = .custom

        let defaults = UserDefaults.standard
        defaults.set(WidgetBackgroundStyle.custom.rawValue, forKey: Self.widgetBackgroundStyleKey)
        defaults.set(try? JSONEncoder().encode(color), forKey: Self.widgetBackgroundColorKey)
        applyAppearanceAndReload()
    }

    var sharedStorePath: String? {
        snapshotStores.first?.fileURL.path
    }

    private func persist(snapshot: CodexQuotaSnapshot) throws {
        var lastError: Error?

        for store in snapshotStores {
            do {
                try store.save(snapshot)
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func configureStateWatcher() {
        let stateDatabaseURL = CodexQuotaPaths.defaultStateDatabaseURL
        stateWatcher = FileWatcher(url: stateDatabaseURL) { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func configureRolloutWatcher(for path: String?) {
        rolloutWatcher = nil

        guard let path else {
            return
        }

        rolloutWatcher = FileWatcher(url: URL(fileURLWithPath: path)) { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private var snapshotStores: [SharedSnapshotStore] {
        var stores: [SharedSnapshotStore] = []

        if let appGroupStore = SharedSnapshotStore.appGroupStore(
            groupIdentifier: CodexQuotaAppConfig.appGroupIdentifier,
            fileName: CodexQuotaAppConfig.snapshotFileName
        ) {
            stores.append(appGroupStore)
        }

        stores.append(
            SharedSnapshotStore.appContainerFallbackStore(
                bundleIdentifier: CodexQuotaAppConfig.widgetExtensionBundleIdentifier,
                fileName: CodexQuotaAppConfig.snapshotFileName
            )
        )

        stores.append(
            SharedSnapshotStore.localFallbackStore(
                fileName: CodexQuotaAppConfig.snapshotFileName
            )
        )

        var seenPaths = Set<String>()
        return stores.filter { store in
            seenPaths.insert(store.fileURL.path).inserted
        }
    }

    private func applyAppearanceAndReload() {
        let updatedSnapshot = applyWidgetAppearance(to: snapshot)
        snapshot = updatedSnapshot
        try? persist(snapshot: updatedSnapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func applyWidgetAppearance(to snapshot: CodexQuotaSnapshot) -> CodexQuotaSnapshot {
        snapshot.withWidgetAppearance(
            opacity: widgetBackgroundOpacity,
            style: widgetBackgroundStyle,
            color: widgetBackgroundStyle == .custom ? widgetBackgroundColor : nil
        )
    }

    private static func clampWidgetBackgroundOpacity(_ opacity: Double) -> Double {
        min(0.70, max(0.08, opacity))
    }

    private static func decodeWidgetBackgroundColor(from data: Data?) -> WidgetBackgroundColor? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode(WidgetBackgroundColor.self, from: data)
    }
}
