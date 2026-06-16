// llama-menu.swift
// Menu bar app for llama.cpp server management
// Build: swiftc -o llama-menu llama-menu.swift -framework Cocoa

import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var serverTask: Process?
    var currentModel: String = "qwen9"
    var isRunning: Bool = false
    var customFlags: [String] = []
    var useCustomFlags: Bool = false

    // Configurable options
    var contextSize: Int = 16384
    var kvCacheType: String = "q8_0"

    let modelRegistry: [(alias: String, name: String, file: String)] = [
        ("qwen9",   "Qwen3.5-9B-Instruct",     "Qwen_Qwen3.5-9B-Q4_K_M.gguf"),
        ("gemma12", "Gemma 4 12B Instruct",     "gemma-4-12B-it-Q4_K_M.gguf"),
        ("gemma26", "Gemma 4 26B-A4B",          "gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"),
        ("draft",   "Qwen3.5-0.8B (draft)",     "Qwen_Qwen3.5-0.8B-Q4_K_M.gguf"),
    ]

    let contextOptions: [(label: String, value: Int)] = [
        ("4K", 4096),
        ("8K", 8192),
        ("16K", 16384),
        ("32K", 32768),
        ("64K", 65536),
        ("128K", 131072),
    ]

    let kvCacheOptions: [(label: String, value: String)] = [
        ("F16 (best quality)", "f16"),
        ("Q8_0 (balanced)", "q8_0"),
        ("Q4_K_S (smallest)", "q4_k_s"),
        ("Q4_K_M", "q4_k_m"),
        ("Q5_K_M", "q5_k_m"),
    ]

    let modelsDir = "\(NSHomeDirectory())/.models"
    let serverBinary = "/opt/homebrew/bin/llama-server"
    let port = "11434"

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "🤖"
            button.font = NSFont.systemFont(ofSize: 14)
            button.toolTip = "llama.cpp server"
        }

        // Ensure no server auto-starts on launch
        let _ = shell("launchctl unload ~/Library/LaunchAgents/com.llama.server.plist 2>/dev/null")
        isRunning = false
        currentModel = "qwen9"

        updateMenu()

        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkServerStatus()
        }
    }

    func availableModels() -> [(alias: String, name: String, file: String, downloaded: Bool)] {
        return modelRegistry.map { model in
            let path = "\(modelsDir)/\(model.file)"
            let exists = FileManager.default.fileExists(atPath: path)
            return (alias: model.alias, name: model.name, file: model.file, downloaded: exists)
        }
    }

    func updateMenu() {
        let menu = NSMenu()

        // Status
        let modeLabel = useCustomFlags ? "custom" : currentModel
        let statusTitle = isRunning ? "● Running (\(modeLabel))" : "○ Stopped"
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(NSMenuItem.separator())

        // Model list
        let models = availableModels()
        var hasModels = false
        for model in models {
            if !model.downloaded { continue }
            hasModels = true
            let checkmark = (isRunning && currentModel == model.alias && !useCustomFlags) ? " ✓" : ""
            let item = NSMenuItem(title: "\(model.name)\(checkmark)", action: #selector(switchModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model.alias
            menu.addItem(item)
        }
        if !hasModels {
            let item = NSMenuItem(title: "No models downloaded", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Context size submenu
        let ctxMenu = NSMenu(title: "Context Size")
        for opt in contextOptions {
            let checkmark = (contextSize == opt.value) ? " ✓" : ""
            let item = NSMenuItem(title: "\(opt.label)\(checkmark)", action: #selector(setContextSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = opt.value
            ctxMenu.addItem(item)
        }
        let ctxItem = NSMenuItem(title: "Context Size: \(formatContext(contextSize))", action: nil, keyEquivalent: "")
        ctxItem.submenu = ctxMenu
        menu.addItem(ctxItem)

        // KV cache submenu
        let kvMenu = NSMenu(title: "KV Cache Type")
        for opt in kvCacheOptions {
            let checkmark = (kvCacheType == opt.value) ? " ✓" : ""
            let item = NSMenuItem(title: "\(opt.label)\(checkmark)", action: #selector(setKVCache(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = opt.value
            kvMenu.addItem(item)
        }
        let kvItem = NSMenuItem(title: "KV Cache: \(kvCacheType)", action: nil, keyEquivalent: "")
        kvItem.submenu = kvMenu
        menu.addItem(kvItem)

        menu.addItem(NSMenuItem.separator())

        // Custom command
        let customTitle = useCustomFlags ? "⚡ Custom: ON" : "Custom Command..."
        let customItem = NSMenuItem(title: customTitle, action: #selector(showCustomCommand), keyEquivalent: "e")
        customItem.target = self
        menu.addItem(customItem)

        if useCustomFlags {
            let clearItem = NSMenuItem(title: "Clear Custom Flags", action: #selector(clearCustomFlags), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Unload model
        let unloadItem = NSMenuItem(title: "Unload Model", action: #selector(unloadModel), keyEquivalent: "u")
        unloadItem.target = self
        unloadItem.isEnabled = isRunning
        menu.addItem(unloadItem)

        menu.addItem(NSMenuItem.separator())

        // Server control
        let startItem = NSMenuItem(title: "Start Server", action: #selector(startServer), keyEquivalent: "s")
        startItem.target = self
        menu.addItem(startItem)

        let stopItem = NSMenuItem(title: "Stop Server", action: #selector(stopServer), keyEquivalent: "x")
        stopItem.target = self
        menu.addItem(stopItem)

        let restartItem = NSMenuItem(title: "Restart Server", action: #selector(restartServer), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)

        menu.addItem(NSMenuItem.separator())

        let logsItem = NSMenuItem(title: "View Logs", action: #selector(viewLogs), keyEquivalent: "l")
        logsItem.target = self
        menu.addItem(logsItem)

        let webUIItem = NSMenuItem(title: "Open Web Chat", action: #selector(openWebUI), keyEquivalent: "w")
        webUIItem.target = self
        webUIItem.isEnabled = isRunning
        menu.addItem(webUIItem)

        let folderItem = NSMenuItem(title: "Open Models Folder", action: #selector(openModelsFolder), keyEquivalent: "o")
        folderItem.target = self
        menu.addItem(folderItem)

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshMenu), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem.menu = menu
    }

    func formatContext(_ val: Int) -> String {
        if val >= 1024 { return "\(val / 1024)K" }
        return "\(val)"
    }

    @objc func refreshMenu() { updateMenu() }

    @objc func switchModel(_ sender: NSMenuItem) {
        guard let alias = sender.representedObject as? String else { return }
        currentModel = alias
        useCustomFlags = false
        if isRunning { restartServer() } else { updateMenu() }
    }

    @objc func setContextSize(_ sender: NSMenuItem) {
        guard let val = sender.representedObject as? Int else { return }
        contextSize = val
        if isRunning { restartServer() } else { updateMenu() }
    }

    @objc func setKVCache(_ sender: NSMenuItem) {
        guard let val = sender.representedObject as? String else { return }
        kvCacheType = val
        if isRunning { restartServer() } else { updateMenu() }
    }

    @objc func showCustomCommand() {
        let alert = NSAlert()
        alert.messageText = "Custom llama-server Command"
        alert.informativeText = "Enter custom flags for llama-server.\n\n⚠️ You MUST include -m /path/to/model.gguf\n\nPaste your flags below (one line, space-separated):"
        alert.alertStyle = .informational

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 500, height: 60))
        input.stringValue = "-m /Users/ausarmundra/.models/Qwen_Qwen3.5-9B-Q4_K_M.gguf -ngl 99 --ctx-size 16384 --batch-size 512 --threads 8 --cache-type-k q8_0 --cache-type-v q8_0 -fa auto --tools all --jinja --ui-mcp-proxy --host 127.0.0.1 --port 11434 --sleep-idle-seconds 180"
        input.placeholderString = "-m /path/to/model.gguf -ngl 99 --ctx-size 16384 ..."
        alert.accessoryView = input

        alert.addButton(withTitle: "Start Server")
        alert.addButton(withTitle: "Save Flags")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        let flagsText = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if flagsText.isEmpty { return }

        let flags = parseFlags(flagsText)

        let hasModel = flags.contains("-m") || flags.contains("--model")
        if !hasModel {
            let modelPath = modelPathForAlias(currentModel)
            var fullFlags = ["-m", modelPath]
            fullFlags.append(contentsOf: flags)
            customFlags = fullFlags
        } else {
            customFlags = flags
        }

        useCustomFlags = true

        if response == .alertFirstButtonReturn {
            restartServer()
        }

        updateMenu()
    }

    func parseFlags(_ text: String) -> [String] {
        var flags: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false
        for char in text {
            if escaped { current.append(char); escaped = false; continue }
            if char == "\\" { escaped = true; continue }
            if char == "\"" { inQuotes.toggle(); continue }
            if char == " " && !inQuotes {
                if !current.isEmpty { flags.append(current); current = "" }
                continue
            }
            current.append(char)
        }
        if !current.isEmpty { flags.append(current) }
        return flags
    }

    func modelPathForAlias(_ alias: String) -> String {
        if let model = modelRegistry.first(where: { $0.alias == alias }) {
            return "\(modelsDir)/\(model.file)"
        }
        return "\(modelsDir)/\(modelRegistry[0].file)"
    }

    @objc func clearCustomFlags() {
        customFlags = []
        useCustomFlags = false
        updateMenu()
    }

    @objc func startServer() {
        guard !isRunning else { return }

        var flags: [String]

        if useCustomFlags && !customFlags.isEmpty {
            flags = customFlags
        } else {
            let model = availableModels().first { $0.alias == currentModel && $0.downloaded }
                ?? availableModels().first { $0.downloaded }

            guard let model = model else {
                showAlert("No models downloaded", "Download a model first: models download qwen9")
                return
            }

            let modelPath = "\(modelsDir)/\(model.file)"
            flags = [
                "-m", modelPath,
                "-ngl", "99",
                "--ctx-size", "\(contextSize)",
                "--batch-size", "2048",
                "--ubatch-size", "2048",
                "--threads", "8",
                "--cache-type-k", kvCacheType,
                "--cache-type-v", kvCacheType,
                "-fa", "auto",
                "--tools", "all",
                "--jinja",
                "--ui-mcp-proxy",
                "--mlock",
                "--prio", "2",
                "--host", "127.0.0.1",
                "--port", port,
                "--sleep-idle-seconds", "180"
            ]
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: serverBinary)
        task.arguments = flags

        do {
            try task.run()
            serverTask = task
            isRunning = true
            updateMenu()
            task.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    self?.isRunning = false
                    self?.serverTask = nil
                    self?.updateMenu()
                }
            }
        } catch {
            showAlert("Failed to start server", error.localizedDescription)
        }
    }

    @objc func stopServer() {
        let _ = shell("launchctl unload ~/Library/LaunchAgents/com.llama.server.plist 2>/dev/null")
        serverTask?.terminate()
        serverTask = nil
        let _ = shell("pkill -f llama-server 2>/dev/null")
        sleep(1)
        isRunning = false
        updateMenu()
    }

    @objc func restartServer() {
        stopServer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.startServer()
        }
    }

    @objc func unloadModel() {
        if let task = serverTask {
            let pid = task.processIdentifier
            let _ = shell("kill -USR1 \(pid) 2>/dev/null")
            sleep(1)
            let health = shell("curl -s --max-time 2 http://127.0.0.1:\(port)/health 2>/dev/null")
            if health.contains("ok") {
                isRunning = true
                updateMenu()
                return
            }
        }
    }

    @objc func viewLogs() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "\(NSHomeDirectory())/.llama-server-error.log"))
    }

    @objc func openWebUI() {
        NSWorkspace.shared.open(URL(string: "http://127.0.0.1:\(port)")!)
    }

    @objc func openModelsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: modelsDir))
    }

    @objc func quitApp() {
        stopServer()
        NSApp.terminate(nil)
    }

    func checkServerStatus() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        task.arguments = ["-s", "--max-time", "2", "http://127.0.0.1:\(port)/health"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let wasRunning = isRunning
            isRunning = (task.terminationStatus == 0)
            if wasRunning != isRunning {
                DispatchQueue.main.async { [weak self] in self?.updateMenu() }
            }
        } catch {
            if isRunning {
                isRunning = false
                DispatchQueue.main.async { [weak self] in self?.updateMenu() }
            }
        }
    }

    func showAlert(_ title: String, _ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @discardableResult
    func shell(_ command: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", command]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch { return "" }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
