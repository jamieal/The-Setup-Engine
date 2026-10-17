import Foundation

/// Facts about the Mac we're running on: chip, macOS version, and the codename
/// Homebrew's catalog uses to pick the right download for this Mac.
nonisolated enum MacEnvironment {

    enum Chip: String {
        case appleSilicon = "Apple Silicon"
        case intel = "Intel"
    }

    /// The physical chip — true even when this process runs under Rosetta.
    static let chip: Chip = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let found = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0
        return found && value == 1 ? .appleSilicon : .intel
    }()

    static var macOSMajor: Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    static var macOSVersionString: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }

    /// Codenames as they appear in Homebrew's `variations` keys, oldest first.
    private static let codenames: [(major: Int, name: String)] = [
        (11, "big_sur"),
        (12, "monterey"),
        (13, "ventura"),
        (14, "sonoma"),
        (15, "sequoia"),
        (26, "tahoe"),
        (27, "golden_gate"),
    ]

    /// Codename for this macOS. Newer-than-known releases use the newest known
    /// name, which is what Homebrew's own resolution falls back to.
    static var osCodename: String {
        let major = macOSMajor
        if let exact = codenames.first(where: { $0.major == major }) { return exact.name }
        if major > codenames.last!.major { return codenames.last!.name }
        return codenames.last(where: { $0.major < major })?.name ?? codenames.first!.name
    }

    /// The `variations` key Homebrew uses for this Mac (e.g. `arm64_sequoia`, `sequoia`).
    static var variationKey: String {
        chip == .appleSilicon ? "arm64_\(osCodename)" : osCodename
    }

    /// Homebrew's official installer package needs Apple Silicon and macOS 15+.
    /// Homebrew's install script refuses Intel Macs outright, so on Intel only an
    /// existing Homebrew can be used.
    static var canInstallHomebrew: Bool {
        chip == .appleSilicon && macOSMajor >= 15
    }

    /// Where Homebrew lives on this Mac, if it's installed.
    static var homebrewExecutable: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
