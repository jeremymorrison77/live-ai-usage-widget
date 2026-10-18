import Foundation
import CryptoKit
import Security

/// Finds, downloads and installs new versions from this project's GitHub releases.
/// Only the release's app ZIP and its checksum are fetched; nothing about the user is sent.
enum Updater {
    static let latestURL = URL(string: "https://api.github.com/repos/jeremymorrison77/live-ai-usage-widget/releases/latest")!

    struct Release: Equatable {
        let version: String
        let app: URL
        let checksum: URL
    }

    /// True when `candidate` is a later version than `current` (for example 1.1.10 after 1.1.9).
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ value: String) -> [Int] {
            value.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Reads GitHub's latest-release reply: the version and the Apple Silicon app ZIP with its checksum.
    static func release(from data: Data) -> Release? {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              value["draft"] as? Bool != true, value["prerelease"] as? Bool != true,
              let tag = value["tag_name"] as? String, let assets = value["assets"] as? [[String: Any]] else { return nil }
        func asset(_ suffix: String) -> URL? {
            assets.first { ($0["name"] as? String)?.hasSuffix(suffix) == true }
                .flatMap { $0["browser_download_url"] as? String }.flatMap(URL.init(string:))
        }
        guard let app = asset("-macOS-arm64.zip"), let checksum = asset("-macOS-arm64.zip.sha256"),
              app.host == "github.com", checksum.host == "github.com" else { return nil }
        return Release(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), app: app, checksum: checksum)
    }

    static func latest() async throws -> Release? {
        var request = URLRequest(url: latestURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return release(from: data)
    }

    enum Failure: Error { case download, checksum, unpack, signature, location }

    /// Downloads the release, checks its checksum and Apple notarization under the same developer as this app,
    /// then swaps it in once this app quits and reopens it. Returns only if nothing was changed.
    static func install(_ release: Release, replacing current: URL = Mover.originalURL()) async throws {
        let (app, folder) = try await prepare(release, like: current)
        guard FileManager.default.isWritableFile(atPath: current.deletingLastPathComponent().path) else { throw Failure.location }
        try swap(current, with: app, cleaning: folder)
    }

    /// Downloads, checks and unpacks the release. Returns the verified app and its temporary folder.
    static func prepare(_ release: Release, like current: URL) async throws -> (URL, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("live-ai-usage-widget-update-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (zip, zipResponse) = try await URLSession.shared.download(from: release.app)
        let (sum, sumResponse) = try await URLSession.shared.data(from: release.checksum)
        guard (zipResponse as? HTTPURLResponse)?.statusCode == 200, (sumResponse as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.download }
        let expected = String(decoding: sum, as: UTF8.self).split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased()
        let actual = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        guard expected == actual else { throw Failure.checksum }

        let unpack = Process()
        unpack.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unpack.arguments = ["-x", "-k", zip.path, folder.path]
        try unpack.run(); unpack.waitUntilExit()
        guard unpack.terminationStatus == 0,
              let app = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" })
        else { throw Failure.unpack }
        guard trusted(app, like: current) else { throw Failure.signature }
        return (app, folder)
    }

    static func swap(_ current: URL, with app: URL, cleaning folder: URL) throws {
        // A small helper waits for this app to quit, moves the old copy to the Trash, puts the new one in place and opens it.
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        old="$1"; new="$2"; trash="$HOME/.Trash/$(basename "$old" .app) $(date +%Y%m%d%H%M%S).app"
        mv "$old" "$trash" && mv "$new" "$old" || { [ -e "$old" ] || mv "$trash" "$old"; }
        open "$old"
        rm -rf "$3"
        """
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/bash")
        helper.arguments = ["-c", script, "update", current.path, app.path, folder.path]
        helper.standardOutput = FileHandle.nullDevice; helper.standardError = FileHandle.nullDevice
        try helper.run()
    }

    /// The new copy must pass Apple's notarization check and be signed by the same developer team as this app.
    static func trusted(_ app: URL, like current: URL) -> Bool {
        guard let team = teamID(current) ?? teamID(Bundle.main.bundleURL), teamID(app) == team else { return false }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("notarized and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"" as CFString, [], &requirement) == errSecSuccess
        else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate), requirement) == errSecSuccess
    }

    static func teamID(_ app: URL) -> String? {
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

/// Opened straight from Downloads, macOS runs the app from a hidden read-only copy ("translocation"), which breaks
/// sign-in, Open at login and updates. This offers to move it into Applications and reopen it from there.
enum Mover {
    /// Where the app really is, even when macOS is running it from a hidden copy.
    static func originalURL(_ bundle: URL = Bundle.main.bundleURL) -> URL {
        guard bundle.path.contains("/AppTranslocation/"),
              let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let symbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return bundle }
        typealias Original = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        return (unsafeBitCast(symbol, to: Original.self)(bundle as CFURL, nil)?.takeRetainedValue() as URL?) ?? bundle
    }

    /// True when running from a hidden copy, or from Downloads or the Desktop.
    static func shouldOffer(_ bundle: URL = Bundle.main.bundleURL) -> Bool {
        if bundle.path.contains("/AppTranslocation/") { return true }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folder = bundle.deletingLastPathComponent().path
        return [home + "/Downloads", home + "/Desktop"].contains(folder)
    }

    /// Moves the app into Applications (an older copy there goes to the Trash), then reopens it once this one quits.
    static func moveToApplications() throws -> URL {
        let original = originalURL()
        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(original.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.trashItem(at: destination, resultingItemURL: nil) }
        try FileManager.default.moveItem(at: original, to: destination)
        // Already checked by Apple's Gatekeeper when it first opened; clearing the download flag stops the hidden copy.
        let clear = Process()
        clear.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        clear.arguments = ["-dr", "com.apple.quarantine", destination.path]
        try? clear.run(); clear.waitUntilExit()
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/bin/bash")
        reopen.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open \"$1\"", "move", destination.path]
        try reopen.run()
        return destination
    }
}
