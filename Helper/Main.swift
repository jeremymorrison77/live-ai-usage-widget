import Foundation
import Darwin

@main struct UsageHelper {
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        let args = CommandLine.arguments
        func option(_ flag: String) -> String? { guard let index = args.firstIndex(of: flag), index+1 < args.count else { return nil }; return args[index+1] }
        guard let path = option("--state-dir"), path.hasPrefix("/"), let generation = option("--generation"),
              let index = args.firstIndex(of: "--providers") else { exit(64) }
        let providers = Array(args.dropFirst(index+1))
        guard Set(providers).isSubset(of: ["claude", "codex"]) else { exit(64) }
        do {
            let data = try Collector.run(root: URL(fileURLWithPath: path), generation: generation, providers: providers)
            FileHandle.standardOutput.write(data)
        } catch { exit((error as? ReaderFailure)?.reason == "busy" ? 75 : 1) }
    }
}
