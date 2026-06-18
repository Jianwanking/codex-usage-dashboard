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
    private var sourceSidecarWatcher: FileWatcher?
    private var nextUsageAPIRefreshDate: Date?

    private static let widgetBackgroundOpacityKey = "widgetBackgroundOpacity"
    private static let widgetBackgroundStyleKey = "widgetBackgroundStyle"
    private static let widgetBackgroundColorKey = "widgetBackgroundColor"
    private static let defaultWidgetBackgroundOpacity = 0.18
    private static let localQuotaStaleInterval: TimeInterval = 10 * 60
    private static let usageAPIBaseRefreshInterval: TimeInterval = 20 * 60
    private static let usageAPIRefreshJitter: TimeInterval = 5 * 60
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
        Task { @MainActor in
            await refreshNow()
        }
    }

    private func refreshNow() async {
        let now = Date()

        do {
            let candidateSnapshot = applyWidgetAppearance(
                to: try await buildCandidateSnapshot(now: now)
            )
            lastErrorMessage = nil
            lastRefreshDate = now

            guard snapshot.shouldBeReplaced(by: candidateSnapshot) else {
                WidgetCenter.shared.reloadAllTimelines()
                return
            }

            snapshot = candidateSnapshot
            try persist(snapshot: candidateSnapshot)
            configureRolloutWatcher(for: candidateSnapshot.sourceRolloutPath)
        } catch {
            if snapshot.state == .ok {
                lastErrorMessage = error.localizedDescription
                lastRefreshDate = now
                WidgetCenter.shared.reloadAllTimelines()
                return
            }

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

    private func buildCandidateSnapshot(now: Date) async throws -> CodexQuotaSnapshot {
        var candidates: [CodexQuotaSnapshot] = []

        if let localSnapshot = try? CodexQuotaSnapshotBuilder.buildFromLocalCodexState(now: now) {
            if localSnapshot.state == .ok {
                candidates.append(localSnapshot)
            }
        }

        let localSnapshot = candidates.max { lhs, rhs in
            lhs.freshnessDate < rhs.freshnessDate
        }

        if shouldRefreshUsageAPI(now: now, localSnapshot: localSnapshot) {
            scheduleNextUsageAPIRefresh(after: now)
            if #available(macOS 10.15, *),
               let apiSnapshot = try? await CodexQuotaSnapshotBuilder.buildFromCodexUsageAPI(now: now) {
                candidates.append(apiSnapshot)
            }
        }

        if let bestSnapshot = candidates.max(by: { lhs, rhs in lhs.freshnessDate < rhs.freshnessDate }) {
            return bestSnapshot
        }

        return .fullQuotaFallback(at: now)
    }

    private func shouldRefreshUsageAPI(now: Date, localSnapshot: CodexQuotaSnapshot?) -> Bool {
        guard canRefreshUsageAPI(now: now) else {
            return false
        }

        let knownFreshnessDates = [
            localSnapshot?.freshnessDate,
            snapshot.state == .ok ? snapshot.freshnessDate : nil
        ].compactMap { $0 }

        guard let freshestKnownDate = knownFreshnessDates.max() else {
            return true
        }

        return now.timeIntervalSince(freshestKnownDate) >= Self.localQuotaStaleInterval
    }

    private func canRefreshUsageAPI(now: Date) -> Bool {
        guard let nextUsageAPIRefreshDate else {
            return true
        }

        return now >= nextUsageAPIRefreshDate
    }

    private func scheduleNextUsageAPIRefresh(after date: Date) {
        let jitter = Double.random(in: -Self.usageAPIRefreshJitter...Self.usageAPIRefreshJitter)
        nextUsageAPIRefreshDate = date.addingTimeInterval(Self.usageAPIBaseRefreshInterval + jitter)
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
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshNow()
            }
        }
    }

    private func configureStateWatcher() {
        let stateDatabaseURL = CodexQuotaPaths.defaultStateDatabaseURL
        stateWatcher = FileWatcher(url: stateDatabaseURL) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refreshNow()
            }
        }
    }

    private func configureRolloutWatcher(for path: String?) {
        rolloutWatcher = nil
        sourceSidecarWatcher = nil

        guard let path else {
            return
        }

        rolloutWatcher = FileWatcher(url: URL(fileURLWithPath: path)) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refreshNow()
            }
        }

        if path == CodexQuotaPaths.defaultLogsDatabaseURL.path {
            let walURL = URL(fileURLWithPath: path + "-wal")
            sourceSidecarWatcher = FileWatcher(url: walURL) { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.refreshNow()
                }
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
