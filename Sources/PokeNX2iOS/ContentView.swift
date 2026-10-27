import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @EnvironmentObject var b: Builder

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Section1Files()
                Section2Options()
                Section3Requirements()
                Section4Build()
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PokeNX2iOS").font(.largeTitle.bold())
                Spacer()
                Link(destination: Game.kofiURL) { Label("Apoyar en Ko-fi", systemImage: "cup.and.saucer.fill") }
                    .buttonStyle(.bordered)
                    .help(Game.kofiURL.absoluteString)
            }
            Text("Genera la IPA de \(Game.name) para iPhone y iPad con todas las mejoras de NXnative: pantalla completa adaptada a cualquier pantalla (también al iPhone Duo), combates salvajes, controles táctiles, soporte multilenguaje y las correcciones del motor.")
                .foregroundStyle(.secondary)
            Text("La herramienta no incluye ningún archivo del juego. Necesitas tus propios archivos: el juego base en NSP, el update \(Game.updateDisplay) en NSP y tu prod.keys, sacados de tu consola.")
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)))
        }
    }
}

// MARK: - 1. Files

struct Section1Files: View {
    @EnvironmentObject var b: Builder
    var body: some View {
        Card(title: "1. Importa tus archivos", done: b.filesReady) {
            FileRow(title: "Juego base (NSP)", hint: "\(Game.baseTitleID) · v0", url: $b.baseNSP, check: b.baseCheck, types: [UTType(filenameExtension: "nsp") ?? .data])
            FileRow(title: "Update \(Game.updateDisplay) (NSP)", hint: "\(Game.updateTitleID) · v\(Game.updateVersion)", url: $b.updateNSP, check: b.updateCheck, types: [UTType(filenameExtension: "nsp") ?? .data])
            FileRow(title: "prod.keys", hint: "claves de tu consola", url: $b.prodKeys, check: b.keysCheck, types: [.data, .plainText])
        }
    }
}

struct FileRow: View {
    let title: String
    let hint: String
    @Binding var url: URL?
    let check: FileCheck?
    let types: [UTType]
    @State private var targeted = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.headline)
                    Text(hint).font(.caption).foregroundStyle(.secondary)
                }
                Text(url?.path ?? "Arrastra el archivo aquí o pulsa Elegir…")
                    .font(.callout.monospaced())
                    .foregroundStyle(url == nil ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                if let check { CheckLabel(check: check) }
            }
            Spacer()
            Button("Elegir…") { pick() }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: url == nil ? [4] : [])))
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { u, _ in
                if let u { DispatchQueue.main.async { url = u } }
            }
            return true
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = title
        if panel.runModal() == .OK { url = panel.url }
    }
}

struct CheckLabel: View {
    let check: FileCheck
    var body: some View {
        Label(check.message, systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
    }
    private var icon: String {
        switch check.level { case .ok: "checkmark.circle.fill"; case .warning: "exclamationmark.triangle.fill"; case .error: "xmark.octagon.fill" }
    }
    private var color: Color {
        switch check.level { case .ok: .green; case .warning: .orange; case .error: .red }
    }
}

// MARK: - 2. Options

struct Section2Options: View {
    @EnvironmentObject var b: Builder
    var body: some View {
        Card(title: "2. Opciones", done: b.workRoot != nil) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Carpeta de trabajo y destino de la IPA").font(.headline)
                    Text(b.workRoot?.path ?? "Elige una carpeta en un disco con espacio")
                        .font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(b.workRoot == nil ? .secondary : .primary)
                    spaceLine
                }
                Spacer()
                Button("Elegir…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
                    if panel.runModal() == .OK { b.workRoot = panel.url }
                }
            }
            Divider()
            Picker("Idioma del juego", selection: $b.language) {
                ForEach(Game.languages, id: \.code) { Text($0.label).tag($0.code) }
            }
            .frame(maxWidth: 360)
            HStack {
                TextField("Bundle ID", text: $b.bundleID).frame(maxWidth: 360)
                TextField("Nombre en la pantalla de inicio (opcional)", text: $b.appName).frame(maxWidth: 300)
            }
            Text("Mods (se pueden activar o desactivar después en Ajustes de iOS → Pokémon)").font(.headline).padding(.top, 4)
            Toggle("Pantalla completa: 3D ensanchado al formato de la pantalla e interfaz ajustada (adaptado del mod 21:9)", isOn: $b.modFullScreen)
            Toggle("Combates salvajes (mod Wild Battles). Ojo: antes de desbloquear \"Jugar con Pikachu\" un combate salvaje se cuelga; desactívalo en Ajustes hasta entonces", isOn: $b.modWildBattles)
            Text("Avanzado").font(.headline).padding(.top, 4)
            Toggle("Mostrar los FPS arriba a la izquierda", isOn: $b.showFPS)
            Toggle("Conservar los archivos extraídos (la siguiente IPA tarda minutos en vez de una hora; ocupa unos 5 GB)", isOn: $b.keepExtracted)
            Toggle("Permitir otro compilador Metal que no sea el de Xcode 27.1 (puede dar gráficos incorrectos)", isOn: $b.allowOtherMetal)
        }
    }

    @ViewBuilder private var spaceLine: some View {
        if let free = b.spaceFree, b.baseNSP != nil {
            let need = b.spaceNeeded
            let f = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            let n = ByteCountFormatter.string(fromByteCount: need, countStyle: .file)
            CheckLabel(check: FileCheck(level: free >= need ? .ok : .warning, message: "Libre: \(f) · hacen falta unos \(n)"))
        }
    }
}

// MARK: - 3. Requirements

struct Section3Requirements: View {
    @EnvironmentObject var b: Builder
    var body: some View {
        Card(title: "3. Requisitos del Mac", done: b.requirementsReady) {
            ForEach(b.requirements) { r in
                HStack(alignment: .top) {
                    Image(systemName: icon(r.state)).foregroundStyle(color(r.state))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).font(.body.weight(.medium))
                        if !r.detail.isEmpty { Text(r.detail).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if r.state == .missing || r.state == .warning, let fix = r.fix {
                        Button("Instalar") { Shell.runInTerminal(fix) }
                            .help(fix)
                    }
                }
            }
            HStack {
                Button(b.checkingRequirements ? "Comprobando…" : "Volver a comprobar") { b.checkRequirements() }
                    .disabled(b.checkingRequirements)
                Text("\"Instalar\" abre Terminal con el comando; cuando termine, vuelve a comprobar.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func icon(_ s: Requirement.State) -> String {
        switch s { case .ok: "checkmark.circle.fill"; case .missing: "xmark.circle.fill"; case .warning: "exclamationmark.triangle.fill"; case .unknown: "circle.dotted" }
    }
    private func color(_ s: Requirement.State) -> Color {
        switch s { case .ok: .green; case .missing: .red; case .warning: .orange; case .unknown: .secondary }
    }
}

// MARK: - 4. Build

struct Section4Build: View {
    @EnvironmentObject var b: Builder
    var body: some View {
        Card(title: "4. Generar la IPA", done: { if case .done = b.phase { return true }; return false }()) {
            HStack {
                if b.phase == .running {
                    Button("Cancelar", role: .cancel) { b.cancel() }
                } else {
                    Button("Generar IPA") { b.start() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!b.canBuild)
                }
                if case .done = b.phase {
                    Button("Mostrar en Finder") { b.revealIPA() }
                    Link("¿Te ha servido? Apoya en Ko-fi", destination: Game.kofiURL)
                }
                if b.workDir != nil, b.phase != .idle { Button("Abrir registros") { b.revealLogs() } }
                Spacer()
                Text("Motor NXnative \(Bundled.engineVersion.prefix(12))").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if !b.canBuild, b.phase != .running { Text(missingText).font(.caption).foregroundStyle(.secondary) }
            if b.phase != .idle {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(b.stageTitle).font(.headline)
                        if !b.stepTitle.isEmpty { Text("· " + b.stepTitle).foregroundStyle(.secondary) }
                        Spacer()
                        Text(b.eta).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if b.phase == .running {
                        if let f = b.fraction { ProgressView(value: f) } else { ProgressView().progressViewStyle(.linear) }
                    }
                    statusLine
                }
                LogView(lines: b.log)
            }
        }
    }

    private var missingText: String {
        var m: [String] = []
        if !b.filesReady { m.append("importa los tres archivos") }
        if b.workRoot == nil { m.append("elige la carpeta de trabajo") }
        if !b.requirementsReady { m.append("completa los requisitos") }
        if b.bundleID.isEmpty { m.append("escribe un bundle ID") }
        return m.isEmpty ? "" : "Para empezar: " + m.joined(separator: ", ") + "."
    }

    @ViewBuilder private var statusLine: some View {
        switch b.phase {
        case .done(let url):
            Label("IPA lista: \(url.lastPathComponent). Instálala con AltStore, Sideloadly o LiveContainer; si tu herramienta lo permite, fírmala con Increased Memory Limit.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
        case .failed(let m):
            Label(m, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        case .cancelled:
            Label("Cancelado. Lo que ya estaba hecho se reutiliza la próxima vez.", systemImage: "stop.circle").foregroundStyle(.orange)
        default: EmptyView()
        }
    }
}

struct LogView: View {
    let lines: [LogLine]
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(lines) { l in
                        Text(l.text)
                            .font(.caption.monospaced())
                            .foregroundStyle(color(l.kind))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(l.id)
                    }
                }
                .padding(8)
            }
            .frame(height: 260)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .onChange(of: lines.count) { _, _ in
                if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
    private func color(_ k: LogLine.Kind) -> Color {
        switch k { case .info: .primary; case .red: .orange; case .error: .red; case .tool: .secondary }
    }
}

// MARK: - Card

struct Card<Content: View>: View {
    let title: String
    let done: Bool
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.title2.bold())
                if done { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
