import Foundation

/// One thing the build needs on this Mac, with how to get it.
struct Requirement: Identifiable {
    enum State { case unknown, ok, missing, warning }
    let id: String
    let title: String
    var state: State = .unknown
    var detail: String = ""
    /// Command that installs it, run in Terminal (it may ask for the password).
    let fix: String?
    /// The build cannot start without it.
    let required: Bool
}

enum Prerequisites {
    static let pythonCandidates = ["/opt/homebrew/bin/python3.14", "/opt/homebrew/bin/python3.13", "/opt/homebrew/bin/python3.12",
                                   "/opt/homebrew/bin/python3", "/usr/local/bin/python3.13", "/usr/local/bin/python3.12",
                                   "/usr/local/bin/python3", "/usr/bin/python3"]

    static func initial() -> [Requirement] {
        [
            Requirement(id: "arm64", title: "Mac con Apple silicon", fix: nil, required: true),
            Requirement(id: "macos", title: "macOS 26.6 o posterior", fix: nil, required: false),
            Requirement(id: "xcode", title: "Xcode 27.1", fix: "open 'macappstore://apps.apple.com/app/xcode/id497799835'", required: true),
            Requirement(id: "metal", title: "Metal Toolchain de Xcode", fix: "xcodebuild -downloadComponent MetalToolchain", required: true),
            Requirement(id: "brew", title: "Homebrew", fix: "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"", required: true),
            Requirement(id: "tools", title: "xcodegen, zstd y glslang", fix: "brew install xcodegen zstd glslang", required: true),
            Requirement(id: "dotnet", title: ".NET SDK", fix: "brew install --cask dotnet-sdk", required: true),
            Requirement(id: "python", title: "Python 3.12 o posterior", fix: "brew install python@3.13", required: true),
        ]
    }

    /// The newest Python 3.12+ found, or nil.
    static func python() -> (path: String, version: String)? {
        for p in pythonCandidates where FileManager.default.isExecutableFile(atPath: p) {
            let r = Shell.run(p, ["-c", "import sys; print('%d.%d' % sys.version_info[:2])"])
            let v = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = v.split(separator: ".").compactMap { Int($0) }
            if r.code == 0, parts.count == 2, parts[0] == 3, parts[1] >= 12 { return (p, v) }
        }
        return nil
    }

    static func check(_ reqs: inout [Requirement]) {
        for i in reqs.indices {
            var r = reqs[i]
            switch r.id {
            case "arm64":
                let m = Shell.run("/usr/bin/uname", ["-m"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
                r.state = m == "arm64" ? .ok : .missing
                r.detail = m == "arm64" ? "arm64" : "Este Mac es \(m): el juego se arranca en el Mac durante la compilación para capturar sus shaders, y eso necesita Apple silicon."
            case "macos":
                let v = ProcessInfo.processInfo.operatingSystemVersion
                let ok = v.majorVersion > 26 || (v.majorVersion == 26 && v.minorVersion >= 6)
                r.state = ok ? .ok : .warning
                r.detail = "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" + (ok ? "" : ": NXnative está probado con 26.6 o posterior.")
            case "xcode":
                let x = Shell.run("/usr/bin/xcodebuild", ["-version"])
                let first = x.out.split(separator: "\n").first.map(String.init) ?? ""
                if x.code != 0 || !first.hasPrefix("Xcode") {
                    r.state = .missing; r.detail = "No se encuentra Xcode (instálalo y ejecuta: sudo xcode-select -s /Applications/Xcode.app)."
                } else {
                    r.state = (first == "Xcode 27.1" || first.hasPrefix("Xcode 27.1.")) ? .ok : .warning
                    r.detail = first + (r.state == .ok ? "" : ": los shaders están probados con Xcode 27.1. Con otra versión activa \"Permitir otro compilador Metal\" bajo tu responsabilidad.")
                }
            case "metal":
                let m = Shell.run("/usr/bin/xcrun", ["metal", "--version"])
                r.state = m.code == 0 ? .ok : .missing
                r.detail = m.code == 0 ? (m.out.split(separator: "\n").first.map(String.init) ?? "instalado") : "Falta el componente Metal Toolchain."
            case "brew":
                let b = Shell.which("brew")
                r.state = b != nil ? .ok : .missing
                r.detail = b ?? "No instalado."
            case "tools":
                let missing = ["xcodegen", "zstd", "glslangValidator"].filter { Shell.which($0) == nil }
                r.state = missing.isEmpty ? .ok : .missing
                r.detail = missing.isEmpty ? "Instalados." : "Faltan: " + missing.joined(separator: ", ")
            case "dotnet":
                if let d = Shell.which("dotnet") {
                    let v = Shell.run(d, ["--version"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
                    let major = Int(v.split(separator: ".").first ?? "") ?? 0
                    r.state = major >= 10 ? .ok : .missing
                    r.detail = major >= 10 ? ".NET \(v)" : ".NET \(v): hace falta el SDK 10 o posterior."
                } else {
                    r.state = .missing; r.detail = "No instalado."
                }
            case "python":
                if let p = python() { r.state = .ok; r.detail = "Python \(p.version) (\(p.path))" }
                else { r.state = .missing; r.detail = "No hay Python 3.12+ (el de macOS es más antiguo)." }
            default: break
            }
            reqs[i] = r
        }
    }
}
