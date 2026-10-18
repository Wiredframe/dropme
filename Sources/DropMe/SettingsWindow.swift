import AppKit
import SwiftUI

/// Settings: quick destinations with display name and target folder.
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let win = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            win.title = "DropMe Einstellungen"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct QuickTarget: Identifiable {
    let id = UUID()
    var name: String
    var path: String
}

private struct SettingsView: View {
    @State private var targets = Destination.quickStored.map { QuickTarget(name: $0.name, path: $0.url.path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schnellziele")
                .font(.headline)
            Text("Erscheinen direkt im Aktionsmenü und kopieren die Dateien in den Ordner.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach($targets) { $target in
                HStack {
                    TextField("Anzeigename", text: $target.name)
                        .frame(width: 170)
                    Button {
                        if let url = pickFolder() { target.path = url.path }
                    } label: {
                        Label(target.path.isEmpty ? "Ordner wählen …" : (target.path as NSString).lastPathComponent,
                              systemImage: "folder")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .help(target.path)
                    Button(role: .destructive) {
                        targets.removeAll { $0.id == target.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Button {
                if let url = pickFolder() {
                    targets.append(QuickTarget(name: url.lastPathComponent, path: url.path))
                }
            } label: {
                Label("Schnellziel hinzufügen", systemImage: "plus")
            }
        }
        .padding(20)
        .frame(width: 440)
        .onChange(of: targets.map { "\($0.name)=\($0.path)" }) { _, _ in save() }
    }

    private func save() {
        Destination.quickStored = targets
            .filter { !$0.name.isEmpty && !$0.path.isEmpty }
            .map { Destination(name: $0.name, url: URL(fileURLWithPath: $0.path, isDirectory: true)) }
    }

    private func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Auswählen"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
