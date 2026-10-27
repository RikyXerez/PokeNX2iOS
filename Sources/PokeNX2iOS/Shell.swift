import Foundation
import AppKit

enum Shell {
    /// GUI apps do not get the shell's PATH: the places Homebrew, .NET and Xcode tools live.
    static let toolPaths = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/share/dotnet",
                            NSHomeDirectory() + "/.dotnet", NSHomeDirectory() + "/.dotnet/tools",
                            "/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (toolPaths + (env["PATH"]?.split(separator: ":").map(String.init) ?? [])).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: ":")
        env["PYTHONUNBUFFERED"] = "1"
        env["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        return env
    }

    static func which(_ tool: String) -> String? {
        for dir in toolPaths {
            let p = dir + "/" + tool
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// Run a command to the end and return its exit code and output (stdout and stderr together).
    @discardableResult
    static func run(_ exe: String, _ args: [String], cwd: URL? = nil) -> (code: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = environment
        if let cwd { p.currentDirectoryURL = cwd }
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Open Terminal and run a command there (installs that may ask for the administrator password).
    static func runInTerminal(_ command: String) {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell"
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
    }

    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

/// A long-running command whose output arrives line by line.
final class StreamingProcess {
    private let process = Process()
    private var buffers: [ObjectIdentifier: Data] = [:]
    private let lock = NSLock()

    init(exe: String, args: [String], cwd: URL?, env: [String: String] = Shell.environment) {
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        process.environment = env
        if let cwd { process.currentDirectoryURL = cwd }
    }

    /// Starts the command; onLine is called (on a background queue) for every stdout line (isErr false) and stderr line (isErr true).
    func start(onLine: @escaping (String, Bool) -> Void, onExit: @escaping (Int32) -> Void) throws {
        let out = Pipe(), err = Pipe()
        process.standardOutput = out; process.standardError = err
        for (pipe, isErr) in [(out, false), (err, true)] {
            pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
                let chunk = h.availableData
                guard let self else { return }
                if chunk.isEmpty { h.readabilityHandler = nil; self.flush(h, isErr, onLine); return }
                self.feed(h, chunk, isErr, onLine)
            }
        }
        process.terminationHandler = { p in
            // let the readers drain what is left before reporting the exit
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { onExit(p.terminationStatus) }
        }
        try process.run()
    }

    private func feed(_ h: FileHandle, _ chunk: Data, _ isErr: Bool, _ onLine: (String, Bool) -> Void) {
        lock.lock()
        var buf = buffers[ObjectIdentifier(h)] ?? Data()
        buf.append(chunk)
        var lines: [String] = []
        while let nl = buf.firstIndex(of: 0x0A) {
            lines.append(String(decoding: buf[buf.startIndex..<nl], as: UTF8.self))
            buf.removeSubrange(buf.startIndex...nl)
        }
        buffers[ObjectIdentifier(h)] = buf
        lock.unlock()
        lines.forEach { onLine($0, isErr) }
    }

    private func flush(_ h: FileHandle, _ isErr: Bool, _ onLine: (String, Bool) -> Void) {
        lock.lock()
        let rest = buffers.removeValue(forKey: ObjectIdentifier(h)) ?? Data()
        lock.unlock()
        if !rest.isEmpty { onLine(String(decoding: rest, as: UTF8.self), isErr) }
    }

    /// Ctrl-C: the NSP script stops cleanly (exit code 130).
    func interrupt() { if process.isRunning { process.interrupt() } }
    var isRunning: Bool { process.isRunning }
}
