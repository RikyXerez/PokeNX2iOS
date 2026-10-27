import Foundation

/// What this tool builds: Pokémon: Let's Go, Pikachu! 1.0.2 with the NXnative improvements.
/// The mods and the game profile are written for this exact update (main build ID C208DB6A…), so other versions are refused.
enum Game {
    static let name = "Pokémon: Let's Go, Pikachu!"
    static let baseTitleID = "010003F003A34000"
    static let updateTitleID = "010003F003A34800"
    static let updateVersion = 131072          // 1.0.2
    static let updateDisplay = "1.0.2"
    static let package = "v131072"
    static let defaultBundleID = "com.pokenx2ios.pokemonletsgo"
    static let defaultIPAName = "PokemonLetsGoPikachu.ipa"

    /// The languages the game ships (as the NSP script lists them).
    static let languages: [(code: String, label: String)] = [
        ("es", "Español"), ("en-US", "English"), ("fr", "Français"), ("de", "Deutsch"),
        ("it", "Italiano"), ("ja", "日本語"), ("ko", "한국어"), ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"),
    ]
}

/// Files bundled in the app: the engine snapshot (nxnative, branch unificado2) and the Let's Go profile and mods.
enum Bundled {
    static var resources: URL { Bundle.main.resourceURL ?? URL(fileURLWithPath: ".") }
    static var engineArchive: URL { resources.appendingPathComponent("engine.tar.gz") }
    static var engineVersionFile: URL { resources.appendingPathComponent("engine.version") }
    static var letsgo: URL { resources.appendingPathComponent("letsgo") }

    static var engineVersion: String {
        (try? String(contentsOf: engineVersionFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "desconocida"
    }
}
