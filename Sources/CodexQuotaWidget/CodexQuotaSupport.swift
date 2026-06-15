import Foundation

public enum CodexQuotaAppConfig {
    public static let appGroupIdentifier = "group.com.ck.codexquota"
    public static let snapshotFileName = "quota-snapshot.json"
    public static let fallbackDirectoryName = "CodexQuotaDesktop"
    public static let widgetExtensionBundleIdentifier = "com.ck.CodexQuotaDesktop.widget"
}

public enum CodexQuotaPaths {
    public static var defaultStateDatabaseURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex")
            .appendingPathComponent("sqlite")
            .appendingPathComponent("state_5.sqlite")
    }

    public static var defaultLogsDatabaseURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex")
            .appendingPathComponent("sqlite")
            .appendingPathComponent("logs_2.sqlite")
    }
}

public enum QuotaRefreshFormatter {
    public static func displayText(
        for ring: QuotaRingSnapshot,
        style: QuotaRefreshStyle,
        now: Date,
        locale: Locale = Locale(identifier: "zh_Hans_CN"),
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone

        switch style {
        case .fiveHour:
            formatter.dateFormat = "HH:mm"
        case .week:
            if ring.resetAt.timeIntervalSince(now) < 86_400 {
                formatter.dateFormat = "HH:mm"
            } else {
                formatter.dateFormat = "M月d日"
            }
        }

        return formatter.string(from: ring.resetAt)
    }
}

public struct SharedSnapshotStore {
    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func save(_ snapshot: CodexQuotaSnapshot) throws {
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
    }

    public func load() throws -> CodexQuotaSnapshot {
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(CodexQuotaSnapshot.self, from: data)
    }

    public static func newestOKSnapshot(from stores: [SharedSnapshotStore]) -> CodexQuotaSnapshot? {
        stores
            .compactMap { try? $0.load() }
            .filter { $0.state == .ok }
            .max { lhs, rhs in
                lhs.freshnessDate < rhs.freshnessDate
            }
    }

    #if canImport(AppKit)
    public static func appGroupStore(
        groupIdentifier: String,
        fileName: String = "quota-snapshot.json"
    ) -> SharedSnapshotStore? {
        guard let baseURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            return nil
        }

        return SharedSnapshotStore(fileURL: baseURL.appendingPathComponent(fileName))
    }
    #endif

    public static func localFallbackStore(
        fileName: String = "quota-snapshot.json"
    ) -> SharedSnapshotStore {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")

        return SharedSnapshotStore(
            fileURL: applicationSupportURL
                .appendingPathComponent(CodexQuotaAppConfig.fallbackDirectoryName)
                .appendingPathComponent(fileName)
        )
    }

    public static func appContainerFallbackStore(
        bundleIdentifier: String,
        fileName: String = "quota-snapshot.json"
    ) -> SharedSnapshotStore {
        let baseURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library")
            .appendingPathComponent("Containers")
            .appendingPathComponent(bundleIdentifier)
            .appendingPathComponent("Data")
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")

        return SharedSnapshotStore(
            fileURL: baseURL
                .appendingPathComponent(CodexQuotaAppConfig.fallbackDirectoryName)
                .appendingPathComponent(fileName)
        )
    }
}

public extension CodexQuotaSnapshot {
    var freshnessDate: Date {
        sourceEventAt ?? snapshotAt
    }

    func isOlderThan(_ other: CodexQuotaSnapshot) -> Bool {
        freshnessDate < other.freshnessDate
    }

    func shouldBeReplaced(by candidate: CodexQuotaSnapshot) -> Bool {
        guard state == .ok else {
            return true
        }
        guard candidate.state == .ok else {
            return false
        }

        if let sourceEventAt {
            guard let candidateEventAt = candidate.sourceEventAt else {
                return false
            }
            return candidateEventAt >= sourceEventAt
        }

        if candidate.sourceEventAt != nil {
            return true
        }

        return candidate.snapshotAt >= snapshotAt
    }
}
