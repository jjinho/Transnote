import Foundation

enum AppVersion {
    static func current(bundle: Bundle = .main) -> String {
        bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^[vV]", with: "", options: .regularExpression)
    }

    static func compare(_ lhs: String, to rhs: String) -> ComparisonResult {
        let left = parsed(normalize(lhs))
        let right = parsed(normalize(rhs))

        // 1. Compare MAJOR / MINOR / PATCH numerically (independent of Int width)
        for index in 0..<max(left.core.count, right.core.count) {
            let leftNumber = index < left.core.count ? left.core[index] : "0"
            let rightNumber = index < right.core.count ? right.core[index] : "0"
            let result = compareNumericIdentifier(leftNumber, rightNumber)
            if result != .orderedSame {
                return result
            }
        }

        // 2. If the numeric parts are equal, compare prereleases per the SemVer spec
        // Build metadata is already excluded in parsed(), so it does not affect the comparison
        switch (left.prerelease, right.prerelease) {
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            // A version without a prerelease is newer than one with a prerelease
            return .orderedDescending
        case (_, nil):
            return .orderedAscending
        case let (leftIdentifiers?, rightIdentifiers?):
            return comparePrerelease(leftIdentifiers, rightIdentifiers)
        }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, to: current) == .orderedDescending
    }

    private struct ParsedVersion {
        let core: [String]
        let prerelease: [String]?
    }

    /// Parses `MAJOR.MINOR.PATCH[-prerelease][+build]`.
    /// - Build metadata (after `+`) is excluded from comparison
    /// - The prerelease (after the first `-`) is kept as a list of dot-separated identifiers
    private static func parsed(_ version: String) -> ParsedVersion {
        guard !version.isEmpty else {
            return ParsedVersion(core: [], prerelease: nil)
        }

        let withoutBuild = version.split(separator: "+", maxSplits: 1).first.map(String.init) ?? version
        let parts = withoutBuild.split(separator: "-", maxSplits: 1).map(String.init)
        let coreString = parts[0]
        let prerelease = parts.count > 1 ? parts[1].split(separator: ".").map(String.init) : nil

        let core = coreString
            .split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)

        return ParsedVersion(core: core, prerelease: prerelease)
    }

    /// Compares prerelease identifier lists per the SemVer spec.
    /// - If one list is a prefix of the other, the shorter list is smaller
    private static func comparePrerelease(_ leftIdentifiers: [String], _ rightIdentifiers: [String]) -> ComparisonResult {
        let count = max(leftIdentifiers.count, rightIdentifiers.count)
        for index in 0..<count {
            if index >= leftIdentifiers.count {
                return .orderedAscending
            }
            if index >= rightIdentifiers.count {
                return .orderedDescending
            }

            let result = compareIdentifier(leftIdentifiers[index], rightIdentifiers[index])
            if result != .orderedSame {
                return result
            }
        }
        return .orderedSame
    }

    /// Compares a single prerelease identifier.
    /// - Numeric-only identifiers are compared numerically (ASCII digits only; signed values are non-numeric)
    /// - Numeric identifiers are smaller than non-numeric identifiers
    /// - If both are non-numeric, compare in ASCII lexical order
    private static func compareIdentifier(_ left: String, _ right: String) -> ComparisonResult {
        switch (isNumericIdentifier(left), isNumericIdentifier(right)) {
        case (true, true):
            return compareNumericIdentifier(left, right)
        case (true, false):
            return .orderedAscending
        case (false, true):
            return .orderedDescending
        case (false, false):
            return left.compare(right, options: .literal)
        }
    }

    /// SemVer numeric identifier: non-empty and ASCII digits only. Signs and non-ASCII digits are non-numeric.
    private static func isNumericIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    /// Overflow-safe numeric comparison: digit count after stripping leading zeros, then lexical order.
    /// Non-numeric core components are treated as `0` (compatible with the existing fallback).
    private static func compareNumericIdentifier(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = normalizedNumeric(lhs)
        let right = normalizedNumeric(rhs)
        if left.count != right.count {
            return left.count < right.count ? .orderedAscending : .orderedDescending
        }
        return left.compare(right, options: .literal)
    }

    private static func normalizedNumeric(_ value: String) -> String {
        guard isNumericIdentifier(value) else { return "0" }
        let stripped = value.drop(while: { $0 == "0" })
        return stripped.isEmpty ? "0" : String(stripped)
    }
}

enum AppDiagnostics {
    static var summary: String {
        let appVersion = AppVersion.current()
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osText = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let models = AppConfig.shared.models.map { model in "- \(model.id): \(model.whisperKitModelName)" }
        var lines = [
            String(format: NSLocalizedString("アプリバージョン: %@", comment: "Diagnostics app version"), appVersion),
            "macOS: \(osText)",
            String(
                format: NSLocalizedString("CPUコア数: %@", comment: "Diagnostics CPU core count"),
                String(ProcessInfo.processInfo.processorCount)
            ),
            String(
                format: NSLocalizedString("メモリ: %@ GB", comment: "Diagnostics physical memory"),
                String(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
            ),
            NSLocalizedString("モデル:", comment: "Diagnostics models header"),
        ]
        return (lines + models).joined(separator: " | ")
    }
}
