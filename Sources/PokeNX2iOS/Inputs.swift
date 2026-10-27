import Foundation

/// A check on one imported file, shown under its drop zone.
struct FileCheck: Equatable {
    enum Level { case ok, warning, error }
    var level: Level
    var message: String
}

enum Inputs {
    /// Title ID and version from a file name such as "… [010003F003A34800][v131072].nsp".
    static func idsFromName(_ url: URL) -> (titleID: String?, version: Int?) {
        let name = url.lastPathComponent
        var tid: String?, ver: Int?
        if let r = name.range(of: #"\[([0-9A-Fa-f]{16})\]"#, options: .regularExpression) {
            tid = String(name[r].dropFirst().dropLast()).uppercased()
        }
        if let r = name.range(of: #"\[v([0-9]+)\]"#, options: .regularExpression) {
            ver = Int(name[r].dropFirst(2).dropLast())
        }
        return (tid, ver)
    }

    /// The names inside an NSP's PFS0 header (NCAs, the ticket, the content meta). Only the header is read.
    static func pfs0Entries(_ url: URL) -> [String]? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let head = try? h.read(upToCount: 16), head.count == 16,
              head.prefix(4) == Data("PFS0".utf8) else { return nil }
        func u32(_ d: Data, _ o: Int) -> Int { d[d.startIndex + o ..< d.startIndex + o + 4].enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) } }
        let count = u32(head, 4), strSize = u32(head, 8)
        guard count > 0, count < 4096, strSize < 1 << 20 else { return nil }
        guard let rest = try? h.read(upToCount: count * 24 + strSize), rest.count == count * 24 + strSize else { return nil }
        let strings = rest.suffix(strSize)
        var names: [String] = []
        for i in 0..<count {
            let off = u32(rest, i * 24 + 16)
            guard off < strSize else { return nil }
            let start = strings.startIndex + off
            let end = strings[start...].firstIndex(of: 0) ?? strings.endIndex
            names.append(String(decoding: strings[start..<end], as: UTF8.self))
        }
        return names
    }

    static func checkNSP(_ url: URL, expectTitleID: String, expectVersion: Int?, what: String) -> FileCheck {
        guard url.pathExtension.lowercased() == "nsp" else {
            return FileCheck(level: .error, message: "Tiene que ser un archivo .nsp.")
        }
        guard let names = pfs0Entries(url) else {
            return FileCheck(level: .error, message: "No parece un NSP válido (no tiene cabecera PFS0).")
        }
        guard names.contains(where: { $0.lowercased().hasSuffix(".cnmt.nca") }) else {
            return FileCheck(level: .error, message: "El NSP no contiene metadatos de contenido (.cnmt.nca); puede estar incompleto.")
        }
        let (tid, ver) = idsFromName(url)
        if let tid, tid != expectTitleID {
            return FileCheck(level: .error, message: "El nombre indica el título \(tid), pero \(what) de Let's Go Pikachu es \(expectTitleID).")
        }
        if let expectVersion, let ver, ver != expectVersion {
            return FileCheck(level: .error, message: "El nombre indica la versión v\(ver); las mejoras están hechas para la v\(expectVersion) (\(Game.updateDisplay)).")
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let sizeText = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        if tid == nil {
            return FileCheck(level: .warning, message: "NSP correcto (\(sizeText)). El nombre no indica el título; se comprobará al extraerlo.")
        }
        return FileCheck(level: .ok, message: "NSP correcto (\(sizeText)), título \(tid!)" + (ver.map { " v\($0)" } ?? "") + ".")
    }

    /// prod.keys must hold the header key and the application key-area keys; the values are never read into the UI.
    static func checkKeys(_ url: URL) -> FileCheck {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return FileCheck(level: .error, message: "No se puede leer el archivo.")
        }
        let names = Set(text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let parts = line.split(separator: "=", maxSplits: 1)
            return parts.count == 2 ? parts[0].trimmingCharacters(in: .whitespaces).lowercased() : nil
        })
        guard names.contains("header_key") else {
            return FileCheck(level: .error, message: "Falta header_key: no parece un prod.keys.")
        }
        let kaek = names.filter { $0.hasPrefix("key_area_key_application_") }.count
        let titlekek = names.filter { $0.hasPrefix("titlekek_") }.count
        guard kaek > 0, titlekek > 0 else {
            return FileCheck(level: .error, message: "Faltan las claves key_area_key_application_xx o titlekek_xx.")
        }
        return FileCheck(level: .ok, message: "prod.keys correcto (\(names.count) claves). No se copia: se lee en su sitio.")
    }

    /// Free space on the volume of a folder, in bytes.
    static func freeSpace(_ url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }

    static func fileSize(_ url: URL?) -> Int64 {
        guard let url else { return 0 }
        return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
