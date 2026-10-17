import Foundation

/// Homebrew is only used for command-line tools. Apps never need it.
///
/// When someone picks command-line tools and Homebrew isn't there, we install it
/// with Homebrew's official, notarized installer package, which needs Apple
/// Silicon and macOS 15 or later. Homebrew's install script refuses Intel Macs,
/// so on Intel only an existing Homebrew can be used.
nonisolated enum HomebrewSupport {

    /// Team ID on Homebrew's "Developer ID Installer" certificate.
    static let installerTeamID = "927JGANW46"

    static var isInstalled: Bool { MacEnvironment.homebrewExecutable != nil }

    /// Why command-line tools can't be installed on this Mac, or nil if they can.
    static var unavailableReason: String? {
        if isInstalled || MacEnvironment.canInstallHomebrew { return nil }
        if MacEnvironment.chip == .intel {
            return "Needs Homebrew, which no longer installs on Intel Macs"
        }
        return "Needs Homebrew, which needs macOS 15 or later"
    }

    /// Downloads the latest official Homebrew installer and checks that it's
    /// signed by Homebrew and notarized by Apple. Returns the package to run as root.
    static func stageInstaller(in workRoot: URL) async throws -> StagedPkg {
        let api = URL(string: "https://api.github.com/repos/Homebrew/brew/releases/latest")!
        var request = URLRequest(url: api, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let release = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = release["assets"] as? [[String: Any]],
              let link = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".pkg") == true })?["browser_download_url"] as? String,
              let url = URL(string: link)
        else { throw InstallFailure.downloadFailed("couldn't find Homebrew's installer") }

        let dir = workRoot.appending(path: "homebrew", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let (temp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw InstallFailure.downloadFailed("HTTP \(http.statusCode)")
        }
        let pkg = dir.appending(path: "Homebrew.pkg")
        try? FileManager.default.removeItem(at: pkg)
        try FileManager.default.moveItem(at: temp, to: pkg)

        let (trusted, signer) = await DirectInstaller.gatekeeperAccepts(pkg, type: "install")
        guard trusted, signer?.contains("(\(installerTeamID))") == true else {
            AppLog.error(.homebrew, "Homebrew installer failed verification (signer: \(signer ?? "none"))")
            throw InstallFailure.untrusted("Homebrew's installer")
        }
        AppLog.info(.homebrew, "Staged Homebrew installer from \(link)")
        return StagedPkg(token: "homebrew", file: pkg, choicesXML: nil)
    }

    /// Formula names Homebrew has installed (empty if Homebrew isn't installed).
    static func installedFormulae() async -> Set<String> {
        guard let brew = MacEnvironment.homebrewExecutable else { return [] }
        let result = await DirectInstaller.run(brew, ["list", "--formula", "-1"])
        return Set(String(decoding: result.stdout, as: UTF8.self)
            .split(separator: "\n").map(String.init))
    }

    /// Formulae the person asked for (not ones pulled in as dependencies).
    static func formulaeInstalledOnRequest() async -> Set<String> {
        guard let brew = MacEnvironment.homebrewExecutable else { return [] }
        let result = await DirectInstaller.run(brew, ["leaves", "--installed-on-request"])
        return Set(String(decoding: result.stdout, as: UTF8.self)
            .split(separator: "\n").map(String.init))
    }

    /// Cask tokens Homebrew has installed, for people who used Homebrew before.
    static func installedCasks() async -> Set<String> {
        guard let brew = MacEnvironment.homebrewExecutable else { return [] }
        let result = await DirectInstaller.run(brew, ["list", "--cask", "-1"])
        return Set(String(decoding: result.stdout, as: UTF8.self)
            .split(separator: "\n").map(String.init))
    }

    /// Shell command that installs one formula (or cask), for `ShellRunner.run`,
    /// which streams output to the install log. Analytics are off for our runs.
    static func installCommand(_ name: String, cask: Bool = false) -> String? {
        guard let brew = MacEnvironment.homebrewExecutable,
              isValidFormulaName(name) else { return nil }
        return "HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 \(DirectInstaller.quote(brew)) install \(cask ? "--cask" : "--formula") \(DirectInstaller.quote(name))"
    }

    /// Homebrew formula names: lowercase letters, digits and + _ . @ -
    /// (e.g. "python@3.13"). Keeps anything shell-special out of the command.
    static func isValidFormulaName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first,
              CharacterSet.lowercaseLetters.union(.decimalDigits).contains(first) else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789+_.@-")
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
