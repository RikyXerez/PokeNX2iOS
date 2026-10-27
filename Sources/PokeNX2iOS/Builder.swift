import Foundation
import AppKit

struct LogLine: Identifiable {
    enum Kind { case info, red, error, tool }
    let id = UUID()
    let text: String
    let kind: Kind
}

/// The whole build: prepare the work folder, install the engine, run nxnative's NSP script with the Let's Go profile and mods, follow its JSON events.
@MainActor
final class Builder: ObservableObject {
    // ---- the user's files (never copied: the input folder only links to them) ----
    @Published var baseNSP: URL? { didSet { baseCheck = baseNSP.map { Inputs.checkNSP($0, expectTitleID: Game.baseTitleID, expectVersion: 0, what: "el juego base") }; suggestWorkRoot() } }
    @Published var updateNSP: URL? { didSet { updateCheck = updateNSP.map { Inputs.checkNSP($0, expectTitleID: Game.updateTitleID, expectVersion: Game.updateVersion, what: "el update") } } }
    @Published var prodKeys: URL? { didSet { keysCheck = prodKeys.map(Inputs.checkKeys) } }
    @Published private(set) var baseCheck: FileCheck?
    @Published private(set) var updateCheck: FileCheck?
    @Published private(set) var keysCheck: FileCheck?

    // ---- options ----
    @Published var workRoot: URL?
    @Published var language = "es"
    @Published var bundleID = Game.defaultBundleID
    @Published var appName = ""
    @Published var modFullScreen = true
    @Published var modWildBattles = true
    @Published var showFPS = true
    @Published var keepExtracted = true
    @Published var allowOtherMetal = false

    // ---- requirements ----
    @Published var requirements = Prerequisites.initial()
    @Published private(set) var checkingRequirements = false

    // ---- the run ----
    enum Phase: Equatable { case idle, running, done(URL), failed(String), cancelled }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var stageTitle = ""
    @Published private(set) var stepTitle = ""
    @Published private(set) var fraction: Double?
    @Published private(set) var eta: String = ""
    @Published private(set) var log: [LogLine] = []
    private var process: StreamingProcess?
    private var logFile: FileHandle?
    private var sawUpdate = false

    var workDir: URL? { workRoot?.appendingPathComponent("PokeNX2iOS_work", isDirectory: true) }
    var engineDir: URL? { workDir?.appendingPathComponent("engine", isDirectory: true) }
    var inputDir: URL? { workDir?.appendingPathComponent("input", isDirectory: true) }
    var outputIPA: URL? { workRoot?.appendingPathComponent(Game.defaultIPAName) }

    var filesReady: Bool {
        [baseCheck, updateCheck, keysCheck].allSatisfy { $0 != nil && $0!.level != .error }
    }
    var requirementsReady: Bool {
        requirements.allSatisfy { !$0.required || $0.state == .ok || ($0.id == "xcode" && $0.state == .warning && allowOtherMetal) }
    }
    var canBuild: Bool { filesReady && requirementsReady && workRoot != nil && phase != .running && !bundleID.isEmpty }

    /// Disk needed: about twice the NSPs plus 10 GB (the NSP script's own estimate), the IPA included.
    var spaceNeeded: Int64 { 2 * (Inputs.fileSize(baseNSP) + Inputs.fileSize(updateNSP)) + 10 * 1_000_000_000 }
    var spaceFree: Int64? { workRoot.flatMap(Inputs.freeSpace) }

    private func suggestWorkRoot() {
        if workRoot == nil, let b = baseNSP { workRoot = b.deletingLastPathComponent() }
    }

    func checkRequirements() {
        checkingRequirements = true
        let current = requirements
        Task.detached {
            var reqs = current
            Prerequisites.check(&reqs)
            await MainActor.run { [reqs] in
                self.requirements = reqs
                self.checkingRequirements = false
            }
        }
    }

    // ---- the build ----

    func start() {
        guard canBuild, let workDir, let engineDir, let inputDir, let outputIPA,
              let baseNSP, let updateNSP, let prodKeys else { return }
        log = []; fraction = nil; eta = ""; stageTitle = "Preparando"; stepTitle = ""; sawUpdate = false
        phase = .running
        let opts = (language: language, bundleID: bundleID, appName: appName, showFPS: showFPS, keep: keepExtracted,
                    otherMetal: allowOtherMetal, mods: [("pantalla_completa", modFullScreen), ("pwildbattles2", modWildBattles)])
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(at: workDir.appendingPathComponent("logs"), withIntermediateDirectories: true)
                await self.openLogFile(workDir)
                await self.say("PokeNX2iOS · motor NXnative \(Bundled.engineVersion)")
                guard let py = Prerequisites.python() else { throw BuildFailure("No hay Python 3.12+.") }
                try await self.prepareEngine(engineDir)
                let venvPython = try await self.prepareVenv(workDir, basePython: py.path)
                try await self.prepareInput(inputDir, base: baseNSP, update: updateNSP, mods: opts.mods)
                var args = ["-u", engineDir.appendingPathComponent("scripts/build_ipa_from_nsp.py").path, inputDir.path,
                            "-k", prodKeys.path, "-p", Game.package, "-l", opts.language,
                            "--bundle-id", opts.bundleID, "-o", outputIPA.path,
                            "--profile-out", inputDir.appendingPathComponent("\(Game.baseTitleID)_build/profile").path,
                            "--progress", "json", opts.showFPS ? "--show-fps" : "--no-show-fps",
                            opts.keep ? "--keep-extracted" : "--no-keep-extracted"]
                if !opts.appName.isEmpty { args += ["--app-name", opts.appName] }
                if opts.otherMetal { args.append("--allow-other-metal") }
                await self.say("Ejecutando el script de NXnative (la primera vez tarda 30–60 minutos)…")
                let code = try await self.runScript(venvPython, args, cwd: engineDir)
                await self.finish(code: code, ipa: outputIPA)
            } catch {
                await self.fail((error as? BuildFailure)?.message ?? error.localizedDescription)
            }
        }
    }

    func cancel() {
        process?.interrupt()
    }

    func revealIPA() {
        if case .done(let url) = phase { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func revealLogs() {
        if let d = workDir?.appendingPathComponent("logs") { NSWorkspace.shared.open(d) }
    }

    // ---- steps (run off the main actor) ----

    /// The engine is nxnative at the branch with our changes (unificado2), shipped in the app as a source snapshot.
    /// It is unpacked into the work folder once per engine version; the game's build cache lives in input/, so a new engine keeps it.
    nonisolated private func prepareEngine(_ dir: URL) async throws {
        let fm = FileManager.default
        let stamp = dir.appendingPathComponent(".pokenx2ios-engine")
        let want = Bundled.engineVersion
        if (try? String(contentsOf: stamp, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) == want {
            await say("Motor NXnative \(want): ya instalado.")
            return
        }
        guard fm.fileExists(atPath: Bundled.engineArchive.path) else { throw BuildFailure("La app no incluye el motor (engine.tar.gz). Genérala con scripts/make_app.sh.") }
        await stage("Instalando el motor NXnative", step: want)
        let partial = dir.deletingLastPathComponent().appendingPathComponent("engine.partial")
        try? fm.removeItem(at: partial)
        try fm.createDirectory(at: partial, withIntermediateDirectories: true)
        let r = Shell.run("/usr/bin/tar", ["-xzf", Bundled.engineArchive.path, "-C", partial.path])
        guard r.code == 0 else { throw BuildFailure("No se pudo descomprimir el motor: \(r.out)") }
        if fm.fileExists(atPath: dir.path) {
            let old = dir.deletingLastPathComponent().appendingPathComponent("engine.old")
            try? fm.removeItem(at: old)
            try fm.moveItem(at: dir, to: old)
            try? fm.removeItem(at: old)
        }
        try fm.moveItem(at: partial, to: dir)
        try want.write(to: stamp, atomically: true, encoding: .utf8)
        await say("Motor NXnative \(want) instalado en \(dir.path)")
    }

    /// A venv of its own, so pip never touches Homebrew's Python (PEP 668).
    nonisolated private func prepareVenv(_ work: URL, basePython: String) async throws -> String {
        let venv = work.appendingPathComponent("venv")
        let py = venv.appendingPathComponent("bin/python3").path
        let stamp = venv.appendingPathComponent(".pokenx2ios-ok")
        if FileManager.default.fileExists(atPath: stamp.path), FileManager.default.isExecutableFile(atPath: py) { return py }
        await stage("Preparando Python", step: "lz4, capstone, fonttools")
        var r = Shell.run(basePython, ["-m", "venv", "--clear", venv.path])
        guard r.code == 0 else { throw BuildFailure("No se pudo crear el entorno de Python: \(r.out)") }
        r = Shell.run(py, ["-m", "pip", "install", "--disable-pip-version-check", "lz4", "capstone", "fonttools", "backports.zstd; python_version < '3.14'"])
        await tool(r.out)
        guard r.code == 0 else { throw BuildFailure("pip no pudo instalar lz4 / capstone / fonttools (¿sin conexión?).") }
        try "ok".write(to: stamp, atomically: true, encoding: .utf8)
        return py
    }

    /// input/: links to the two NSPs, our mods in mod/ (only the ones switched on) and the Let's Go profile, where the NSP script looks for them.
    nonisolated private func prepareInput(_ dir: URL, base: URL, update: URL, mods: [(String, Bool)]) async throws {
        let fm = FileManager.default
        await stage("Preparando los archivos", step: "")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // links from a previous run (other file names) go; the build folder stays
        for item in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? [] {
            if item.pathExtension.lowercased() == "nsp", (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                try fm.removeItem(at: item)
            }
        }
        for src in [base, update] {
            try fm.createSymbolicLink(at: dir.appendingPathComponent(src.lastPathComponent), withDestinationURL: src)
        }
        let modDir = dir.appendingPathComponent("mod")
        try? fm.removeItem(at: modDir)
        try fm.createDirectory(at: modDir, withIntermediateDirectories: true)
        for (name, on) in mods where on {
            try fm.copyItem(at: Bundled.letsgo.appendingPathComponent("mod/\(name)"), to: modDir.appendingPathComponent(name))
            await say("Mod incluido: \((try? String(contentsOf: Bundled.letsgo.appendingPathComponent("mod/\(name)/name.txt"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? name)")
        }
        // the profile: our game.tsv; the tables next to it are made again by the script from the user's own game files
        let prof = dir.appendingPathComponent("\(Game.baseTitleID)_build/profile/\(Game.baseTitleID)")
        try fm.createDirectory(at: prof, withIntermediateDirectories: true)
        let dst = prof.appendingPathComponent("game.tsv")
        try? fm.removeItem(at: dst)
        try fm.copyItem(at: Bundled.letsgo.appendingPathComponent("profile/\(Game.baseTitleID)/game.tsv"), to: dst)
    }

    nonisolated private func runScript(_ exe: String, _ args: [String], cwd: URL) async throws -> Int32 {
        try await withCheckedThrowingContinuation { cont in
            let p = StreamingProcess(exe: exe, args: args, cwd: cwd)
            Task { @MainActor in self.process = p }
            do {
                try p.start(onLine: { [weak self] line, isErr in
                    Task { @MainActor in self?.handle(line, isErr: isErr) }
                }, onExit: { code in cont.resume(returning: code) })
            } catch { cont.resume(throwing: error) }
        }
    }

    // ---- the NSP script's JSON events (docs/frontends.md) ----

    private func handle(_ line: String, isErr: Bool) {
        guard !isErr, line.hasPrefix("{"), let data = line.data(using: .utf8),
              let ev = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let kind = ev["ev"] as? String else {
            if !line.isEmpty { append(LogLine(text: line, kind: .tool)) }
            return
        }
        switch kind {
        case "stage":
            let k = ev["k"] as? Int ?? 0, n = ev["n"] as? Int ?? 0
            stageTitle = "[\(k)/\(n)] " + (ev["name"] as? String ?? "")
            stepTitle = ev["step"] as? String ?? ""
            fraction = nil; eta = ""
            append(LogLine(text: stageTitle + (stepTitle.isEmpty ? "" : " · \(stepTitle)") + " …", kind: .info))
        case "step":
            stepTitle = ev["step"] as? String ?? ""
        case "progress":
            stepTitle = ev["step"] as? String ?? stepTitle
            fraction = ev["frac"] as? Double
            if let e = ev["eta"] as? Double { eta = "quedan " + Builder.hms(e) } else { eta = "" }
        case "stage_end":
            let ok = ev["ok"] as? Bool ?? true
            let summary = ev["summary"] as? String ?? ""
            let elapsed = (ev["elapsed"] as? Double).map { " (\(Builder.hms($0)))" } ?? ""
            append(LogLine(text: (ok ? "✓ " : "✗ ") + (ev["name"] as? String ?? "") + elapsed + (summary.isEmpty ? "" : ": \(summary)"), kind: ok ? .info : .error))
        case "say":
            let msg = ev["msg"] as? String ?? ""
            if msg.contains("update \(Game.package)") { sawUpdate = true }
            append(LogLine(text: msg, kind: msg.hasPrefix("[RED] ") ? .red : .info))
        default: break
        }
    }

    private func finish(code: Int32, ipa: URL) {
        process = nil
        switch code {
        case 0 where FileManager.default.fileExists(atPath: ipa.path):
            if !sawUpdate { append(LogLine(text: "Aviso: el script no confirmó el update \(Game.package) (\(Game.updateDisplay)).", kind: .red)) }
            stageTitle = "IPA lista"; stepTitle = ipa.lastPathComponent; fraction = 1; eta = ""
            say("Hecho: \(ipa.path)")
            phase = .done(ipa)
        case 130:
            say("Cancelado.")
            phase = .cancelled
        case 0:
            fail("El script terminó pero no se encuentra la IPA en \(ipa.path).")
        default:
            let reason = log.last(where: { $0.kind == .red })?.text ?? "el script terminó con el código \(code)"
            fail(reason)
        }
        try? logFile?.close(); logFile = nil
    }

    private func fail(_ message: String) {
        process = nil
        append(LogLine(text: "Error: " + message, kind: .error))
        phase = .failed(message)
        try? logFile?.close(); logFile = nil
    }

    private func openLogFile(_ work: URL) {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let url = work.appendingPathComponent("logs/pokenx2ios-\(f.string(from: Date())).log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        logFile = try? FileHandle(forWritingTo: url)
    }

    private func append(_ l: LogLine) {
        log.append(l)
        if log.count > 4000 { log.removeFirst(log.count - 4000) }
        logFile?.write(Data((l.text + "\n").utf8))
    }

    private func say(_ s: String) { append(LogLine(text: s, kind: .info)) }
    private func tool(_ s: String) { s.split(separator: "\n").suffix(20).forEach { append(LogLine(text: String($0), kind: .tool)) } }
    private func stage(_ title: String, step: String) { stageTitle = title; stepTitle = step; fraction = nil; eta = ""; say(title + (step.isEmpty ? "" : " · \(step)") + " …") }

    nonisolated static func hms(_ s: Double) -> String {
        let t = Int(s), h = t / 3600, m = t / 60 % 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

struct BuildFailure: Error { let message: String; init(_ m: String) { message = m } }
