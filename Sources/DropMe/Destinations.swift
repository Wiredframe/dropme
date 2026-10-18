import Foundation

/// Ordner für „Kopieren nach“ und „Bewegen nach“.
/// Schnellziele erscheinen zusätzlich direkt im Menü und kopieren dorthin. Gepflegt werden sie
/// in den Einstellungen, gespeichert als `Schnellziele` = [{name, path}, …] in den Defaults.
struct Destination {
    let name: String
    let url: URL

    static var standard: [Destination] {
        let fm = FileManager.default
        return [
            (FileManager.SearchPathDirectory.desktopDirectory, "Schreibtisch"),
            (.documentDirectory, "Dokumente"),
            (.downloadsDirectory, "Downloads"),
        ].compactMap { dir, name in
            fm.urls(for: dir, in: .userDomainMask).first.map { Destination(name: name, url: $0) }
        }
    }

    /// Alle gespeicherten Schnellziele, auch solche, deren Ordner gerade fehlt.
    static var quickStored: [Destination] {
        get {
            let entries = UserDefaults.standard.array(forKey: "Schnellziele") ?? []
            return entries.compactMap { entry in
                let name: String, path: String
                if let dict = entry as? [String: String], let n = dict["name"], let p = dict["path"] {
                    (name, path) = (n, p)
                } else if let text = entry as? String {
                    // Älteres Format „Name=Pfad“; der Pfad beginnt mit / oder ~, das letzte solche „=“ trennt.
                    guard let split = text.range(of: "=/", options: .backwards) ?? text.range(of: "=~", options: .backwards)
                    else { return nil }
                    (name, path) = (String(text[..<split.lowerBound]), String(text[text.index(after: split.lowerBound)...]))
                } else {
                    return nil
                }
                guard !name.isEmpty, !path.isEmpty else { return nil }
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
                return Destination(name: name, url: url)
            }
        }
        set {
            UserDefaults.standard.set(newValue.map { ["name": $0.name, "path": $0.url.path] }, forKey: "Schnellziele")
        }
    }

    /// Schnellziele, deren Ordner existiert.
    static var quick: [Destination] {
        quickStored.filter { dest in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: dest.url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    /// Freier Zielname im Ordner: „Datei.pdf“, sonst „Datei 2.pdf“, „Datei 3.pdf“ …
    static func freeURL(for name: String, in dir: URL) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}
