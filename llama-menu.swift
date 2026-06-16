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

    // Smart defaults (Apple Silicon optimized)
    var contextSize: Int = 16384
    var kvCacheType: String = "q8_0"
    var batchSize: Int = 2048
    var useMlock: Bool = true
    var useHighPrio: Bool = true

    // Advanced options (off by default, enable as needed)
    var useFlashAttn: Bool = true      // -fa auto
    var useNUMA: Bool = false          // --numa (x86 only, no-op on Apple Silicon)
    var useContinuousBatching: Bool = false // -cb
    var parallelSlots: Int = 1         // -np
    var noMmap: Bool = false           // --no-mmap (workaround for hangs)
    var temperature: Double = 0.7      // --temp
    var topP: Double = 0.9             // --top-p
    var minP: Double = 0.05            // --min-p
    var repeatPenalty: Double = 1.1    // --repeat-penalty

    let modelRegistry: [(alias: String, name: String, file: String)] = [
        ("qwen9",   "Qwen3.5-9B-Instruct",     "Qwen_Qwen3.5-9B-Q4_K_M.gguf"),
        ("gemma12", "Gemma 4 12B Instruct",     "gemma-4-12B-it-Q4_K_M.gguf"),
        ("gemma26", "Gemma 4 26B-A4B",          "google_gemma-4-26B-A4B-it-Q4_K_M.gguf"),
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

    // Track menu items to update checkmarks
    var advancedMenuLabel: NSMenuItem?
    var advancedVisible = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "🤖"
            button.font = NSFont.systemFont(ofSize: 14)
            button.toolTip = "llama.cpp server"
        }

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
            return (alias: model.alias, name: model.name, file: model.file, downloaded: FileManager.default.fileExists(atPath: path))
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

        // Quick settings (always visible)
        // Context size submenu
        let ctxMenu = NSMenu(title: "Context Size")
        for opt in contextOptions {
            let checkmark = (contextSize == opt.value) ? " ✓" : ""
            let item = NSMenuItem(title: "\(opt.label)\(checkmark)", action: #selector(setContextSize(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = opt.value
            ctxMenu.addItem(item)
        }
        let ctxItem = NSMenuItem(title: "Context: \(formatContext(contextSize))", action: nil, keyEquivalent: "")
        ctxItem.submenu = ctxMenu
        menu.addItem(ctxItem)

        // KV cache submenu
        let kvMenu = NSMenu(title: "KV Cache")
        for opt in kvCacheOptions {
            let checkmark = (kvCacheType == opt.value) ? " ✓" : ""
            let item = NSMenuItem(title: "\(opt.label)\(checkmark)", action: #selector(setKVCache(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = opt.value
            kvMenu.addItem(item)
        }
        let kvItem = NSMenuItem(title: "KV Cache: \(kvCacheType)", action: nil, keyEquivalent: "")
        kvItem.submenu = kvMenu
        menu.addItem(kvItem)

        // Quick toggles
        let mlockItem = NSMenuItem(title: "Memory Lock (\(useMlock ? "ON" : "OFF"))", action: #selector(toggleMlock), keyEquivalent: "")
        mlockItem.target = self
        menu.addItem(mlockItem)

        let prioItem = NSMenuItem(title: "High Priority (\(useHighPrio ? "ON" : "OFF"))", action: #selector(togglePrio), keyEquivalent: "")
        prioItem.target = self
        menu.addItem(prioItem)

        menu.addItem(NSMenuItem.separator())

        // Advanced (collapsible submenu)
        let advancedTitle = advancedVisible ? "▾ Advanced Settings" : "▸ Advanced Settings"
        let advToggle = NSMenuItem(title: advancedTitle, action: #selector(toggleAdvanced), keyEquivalent: "")
        advToggle.target = self
        menu.addItem(advToggle)

        if advancedVisible {
            let advMenu = NSMenu(title: "Advanced")

            // Batch size
            let batchSizeItem = NSMenuItem(title: "Batch Size: \(batchSize)", action: #selector(setBatchSizeFromDialog), keyEquivalent: "")
            batchSizeItem.target = self
            advMenu.addItem(batchSizeItem)

            // Flash Attention
            let faItem = NSMenuItem(title: "Flash Attention (\(useFlashAttn ? "ON" : "OFF"))", action: #selector(toggleFlashAttn), keyEquivalent: "")
            faItem.target = self
            advMenu.addItem(faItem)

            // Continuous batching
            let cbItem = NSMenuItem(title: "Continuous Batching (\(useContinuousBatching ? "ON" : "OFF"))", action: #selector(toggleContinuousBatching), keyEquivalent: "")
            cbItem.target = self
            advMenu.addItem(cbItem)

            // Parallel slots
            let npItem = NSMenuItem(title: "Parallel Slots: \(parallelSlots)", action: #selector(setParallelSlotsFromDialog), keyEquivalent: "")
            npItem.target = self
            advMenu.addItem(npItem)

            advMenu.addItem(NSMenuItem.separator())

            // Sampling
            let tempItem = NSMenuItem(title: "Temperature: \(temperature)", action: #selector(setTemperatureFromDialog), keyEquivalent: "")
            tempItem.target = self
            advMenu.addItem(tempItem)

            let topPItem = NSMenuItem(title: "Top-P: \(topP)", action: #selector(setTopPFromDialog), keyEquivalent: "")
            topPItem.target = self
            advMenu.addItem(topPItem)

            let minPItem = NSMenuItem(title: "Min-P: \(minP)", action: #selector(setMinPFromDialog), keyEquivalent: "")
            minPItem.target = self
            advMenu.addItem(minPItem)

            let rpItem = NSMenuItem(title: "Repeat Penalty: \(repeatPenalty)", action: #selector(setRepeatPenaltyFromDialog), keyEquivalent: "")
            rpItem.target = self
            advMenu.addItem(rpItem)

            advMenu.addItem(NSMenuItem.separator())

            // Special flags
            let noMmapItem = NSMenuItem(title: "no-mmap (hang workaround) (\(noMmap ? "ON" : "OFF"))", action: #selector(toggleNoMmap), keyEquivalent: "")
            noMmapItem.target = self
            advMenu.addItem(noMmapItem)

            let numaItem = NSMenuItem(title: "NUMA (x86 only) (\(useNUMA ? "ON" : "OFF"))", action: #selector(toggleNUMA), keyEquivalent: "")
            numaItem.target = self
            advMenu.addItem(numaItem)

            // Custom flags
            advMenu.addItem(NSMenuItem.separator())
            let customItem = NSMenuItem(title: "Custom Flags...", action: #selector(showCustomCommand), keyEquivalent: "e")
            customItem.target = self
            advMenu.addItem(customItem)

            if useCustomFlags {
                let clearItem = NSMenuItem(title: "Clear Custom Flags", action: #selector(clearCustomFlags), keyEquivalent: "")
                clearItem.target = self
                advMenu.addItem(clearItem)
            }

            // Reset to defaults
            let resetItem = NSMenuItem(title: "Reset to Defaults", action: #selector(resetDefaults), keyEquivalent: "")
            resetItem.target = self
            advMenu.addItem(resetItem)

            // Inject the advanced submenu items directly into the main menu
            for item in advMenu.items {
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Unload model
        let unloadItem = NSMenuItem(title: "Unload Model", action: #selector(unloadModel), keyEquivalent: "u")
        unloadItem.target = self; unloadItem.isEnabled = isRunning
        menu.addItem(unloadItem)

        menu.addItem(NSMenuItem.separator())

        // Server control
        let startItem = NSMenuItem(title: "Start Server", action: #selector(startServer), keyEquivalent: "s")
        startItem.target = self; menu.addItem(startItem)

        let stopItem = NSMenuItem(title: "Stop Server", action: #selector(stopServer), keyEquivalent: "x")
        stopItem.target = self; menu.addItem(stopItem)

        let restartItem = NSMenuItem(title: "Restart Server", action: #selector(restartServer), keyEquivalent: "r")
        restartItem.target = self; menu.addItem(restartItem)

        menu.addItem(NSMenuItem.separator())

        let logsItem = NSMenuItem(title: "View Logs", action: #selector(viewLogs), keyEquivalent: "l")
        logsItem.target = self; menu.addItem(logsItem)

        let webUIItem = NSMenuItem(title: "Open Web Chat", action: #selector(openWebUI), keyEquivalent: "w")
        webUIItem.target = self; webUIItem.isEnabled = isRunning
        menu.addItem(webUIItem)

        let folderItem = NSMenuItem(title: "Open Models Folder", action: #selector(openModelsFolder), keyEquivalent: "o")
        folderItem.target = self; menu.addItem(folderItem)

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshMenu), keyEquivalent: "")
        refreshItem.target = self; menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self; menu.addItem(quitItem)

        self.statusItem.menu = menu
    }

    // ─── QUICK SETTINGS ────────────────────────────────────────────────────────

    @objc func refreshMenu() { updateMenu() }

    @objc func switchModel(_ sender: NSMenuItem) {
        guard let alias = sender.representedObject as? String else { return }
        currentModel = alias; useCustomFlags = false
        if isRunning { restartServer() } else { updateMenu() }
    }

    @objc func setContextSize(_ sender: NSMenuItem) {
        guard let val = sender.representedObject as? Int else { return }
        contextSize = val; if isRunning { restartServer() } else { updateMenu() }
    }

    @objc func setKVCache(_ sender: NSMenuItem) {
        guard let val = sender.representedObject as? String else { return }
        kvCacheType = val; if isRunning { restartServer() } else { updateMenu() }
    }

    @objc func toggleMlock() { useMlock.toggle(); if isRunning { restartServer() } else { updateMenu() } }
    @objc func togglePrio() { useHighPrio.toggle(); if isRunning { restartServer() } else { updateMenu() } }

    // ─── ADVANCED TOGGLES ──────────────────────────────────────────────────────

    @objc func toggleAdvanced() { advancedVisible.toggle(); updateMenu() }
    @objc func toggleFlashAttn() { useFlashAttn.toggle(); if isRunning { restartServer() } else { updateMenu() } }
    @objc func toggleContinuousBatching() { useContinuousBatching.toggle(); if isRunning { restartServer() } else { updateMenu() } }
    @objc func toggleNoMmap() { noMmap.toggle(); if isRunning { restartServer() } else { updateMenu() } }
    @objc func toggleNUMA() { useNUMA.toggle(); if isRunning { restartServer() } else { updateMenu() } }

    @objc func resetDefaults() {
        contextSize = 16384; kvCacheType = "q8_0"; batchSize = 2048
        useMlock = true; useHighPrio = true
        useFlashAttn = true; useNUMA = false; useContinuousBatching = false
        parallelSlots = 1; noMmap = false
        temperature = 0.7; topP = 0.9; minP = 0.05; repeatPenalty = 1.1
        customFlags = []; useCustomFlags = false
        if isRunning { restartServer() } else { updateMenu() }
    }

    // ─── DIALOGS FOR NUMERIC VALUES ────────────────────────────────────────────

    @objc func setBatchSizeFromDialog() { showNumberDialog("Batch Size", current: "\(batchSize)", defaultVal: "2048") { self.batchSize = Int($0) ?? 2048; if self.isRunning { self.restartServer() } else { self.updateMenu() } } }
    @objc func setParallelSlotsFromDialog() { showNumberDialog("Parallel Slots", current: "\(parallelSlots)", defaultVal: "1") { self.parallelSlots = Int($0) ?? 1; if self.isRunning { self.restartServer() } else { self.updateMenu() } } }
    @objc func setTemperatureFromDialog() { showFloatDialog("Temperature", current: String(format: "%.2f", temperature), defaultVal: "0.7") { self.temperature = Double($0) ?? 0.7; if self.isRunning { self.restartServer() } else { self.updateMenu() } } }
    @objc func setTopPFromDialog() { showFloatDialog("Top-P", current: String(format: "%.2f", topP), defaultVal: "0.9") { self.topP = Double($0) ?? 0.9; if self.isRunning { self.restartServer() } else { self.updateMenu() } } }
    @objc func setMinPFromDialog() { showFloatDialog("Min-P", current: String(format: "%.2f", minP), defaultVal: "0.05") { self.minP = Double($0) ?? 0.05; if self.isRunning { self.restartServer() } else { self.updateMenu() } } }
    @objc func setRepeatPenaltyFromDialog() { showFloatDialog("Repeat Penalty", current: String(format: "%.2f", repeatPenalty), defaultVal: "1.1") { self.repeatPenalty = Double($0) ?? 1.1; if self.isRunning { self.restartServer() } else { self.updateMenu() } } }

    func showNumberDialog(_ title: String, current: String, defaultVal: String, onSave: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Enter a whole number:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = current
        input.placeholderString = defaultVal
        alert.accessoryView = input
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { onSave(input.stringValue) }
    }

    func showFloatDialog(_ title: String, current: String, defaultVal: String, onSave: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Enter a decimal number:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = current
        input.placeholderString = defaultVal
        alert.accessoryView = input
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { onSave(input.stringValue) }
    }

    // ─── CUSTOM COMMAND ────────────────────────────────────────────────────────

    @objc func showCustomCommand() {
        let alert = NSAlert()
        alert.messageText = "Custom llama-server Command"
        alert.informativeText = "Enter custom flags for llama-server.\n\n⚠️ You MUST include -m /path/to/model.gguf\n\nPaste your flags below (one line, space-separated):"
        alert.alertStyle = .informational
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 500, height: 60))
        input.stringValue = "-m /Users/ausarmundra/.models/Qwen_Qwen3.5-9B-Q4_K_M.gguf -ngl 99 --ctx-size 16384 --batch-size 2048 --ubatch-size 2048 --threads 8 --cache-type-k q8_0 --cache-type-v q8_0 -fa auto --tools all --jinja --ui-mcp-proxy --mlock --prio 2 --host 127.0.0.1 --port 11434 --sleep-idle-seconds 180"
        input.placeholderString = "-m /path/to/model.gguf -ngl 99 --ctx-size 16384 ..."
        alert.accessoryView = input
        alert.addButton(withTitle: "Start Server"); alert.addButton(withTitle: "Save Flags"); alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        let flagsText = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if flagsText.isEmpty { return }
        let flags = parseFlags(flagsText)
        let hasModel = flags.contains("-m") || flags.contains("--model")
        if !hasModel { var f = ["-m", modelPathForAlias(currentModel)]; f.append(contentsOf: flags); customFlags = f } else { customFlags = flags }
        useCustomFlags = true
        if response == .alertFirstButtonReturn { restartServer() }
        updateMenu()
    }

    @objc func clearCustomFlags() { customFlags = []; useCustomFlags = false; updateMenu() }

    // ─── SERVER CONTROL ────────────────────────────────────────────────────────

    @objc func startServer() {
        guard !isRunning else { return }
        var flags: [String]
        if useCustomFlags && !customFlags.isEmpty {
            flags = customFlags
        } else {
            let model = availableModels().first { $0.alias == currentModel && $0.downloaded } ?? availableModels().first { $0.downloaded }
            guard let model = model else { showAlert("No models downloaded", "Download a model first: models download qwen9"); return }
            let modelPath = "\(modelsDir)/\(model.file)"
            currentModel = model.alias
            flags = ["-m", modelPath, "-ngl", "99", "--ctx-size", "\(contextSize)", "--batch-size", "\(batchSize)", "--ubatch-size", "\(batchSize)", "--threads", "8", "--cache-type-k", kvCacheType, "--cache-type-v", kvCacheType, "--tools", "all", "--jinja", "--ui-mcp-proxy", "--host", "127.0.0.1", "--port", port, "--sleep-idle-seconds", "180"]
            if useFlashAttn { flags += ["-fa", "auto"] }
            if useMlock { flags += ["--mlock"] }
            if useHighPrio { flags += ["--prio", "2"] }
            if useNUMA { flags += ["--numa", "distribute"] }
            if useContinuousBatching { flags += ["-cb"] }
            if parallelSlots > 1 { flags += ["-np", "\(parallelSlots)"] }
            if noMmap { flags += ["--no-mmap"] }
            if temperature != 0.7 { flags += ["--temp", String(format: "%.2f", temperature)] }
            if topP != 0.9 { flags += ["--top-p", String(format: "%.2f", topP)] }
            if minP != 0.05 { flags += ["--min-p", String(format: "%.2f", minP)] }
            if repeatPenalty != 1.1 { flags += ["--repeat-penalty", String(format: "%.2f", repeatPenalty)] }
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: serverBinary)
        task.arguments = flags
        do {
            try task.run(); serverTask = task; isRunning = true; updateMenu()
            task.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.isRunning = false; self?.serverTask = nil; self?.updateMenu() } }
        } catch { showAlert("Failed to start server", error.localizedDescription) }
    }

    @objc func stopServer() {
        let _ = shell("launchctl unload ~/Library/LaunchAgents/com.llama.server.plist 2>/dev/null")
        serverTask?.terminate(); serverTask = nil
        let _ = shell("pkill -f llama-server 2>/dev/null"); sleep(1)
        isRunning = false; updateMenu()
    }

    @objc func restartServer() { stopServer(); DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.startServer() } }

    @objc func unloadModel() {
        if let task = serverTask { let _ = shell("kill -USR1 \(task.processIdentifier) 2>/dev/null"); sleep(1); let h = shell("curl -s --max-time 2 http://127.0.0.1:\(port)/health 2>/dev/null"); if h.contains("ok") { isRunning = true; updateMenu(); return } }
    }

    @objc func viewLogs() { NSWorkspace.shared.open(URL(fileURLWithPath: "\(NSHomeDirectory())/.llama-server-error.log")) }
    @objc func openWebUI() { NSWorkspace.shared.open(URL(string: "http://127.0.0.1:\(port)")!) }
    @objc func openModelsFolder() { NSWorkspace.shared.open(URL(fileURLWithPath: modelsDir)) }
    @objc func quitApp() { stopServer(); NSApp.terminate(nil) }

    // ─── HELPERS ───────────────────────────────────────────────────────────────

    func formatContext(_ val: Int) -> String { val >= 1024 ? "\(val / 1024)K" : "\(val)" }

    func modelPathForAlias(_ alias: String) -> String {
        if let model = modelRegistry.first(where: { $0.alias == alias }) { return "\(modelsDir)/\(model.file)" }
        return "\(modelsDir)/\(modelRegistry[0].file)"
    }

    func parseFlags(_ text: String) -> [String] {
        var flags: [String] = []; var current = ""; var inQuotes = false; var escaped = false
        for char in text {
            if escaped { current.append(char); escaped = false; continue }
            if char == "\\" { escaped = true; continue }
            if char == "\"" { inQuotes.toggle(); continue }
            if char == " " && !inQuotes { if !current.isEmpty { flags.append(current); current = "" }; continue }
            current.append(char)
        }
        if !current.isEmpty { flags.append(current) }
        return flags
    }

    func checkServerStatus() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        task.arguments = ["-s", "--max-time", "2", "http://127.0.0.1:\(port)/health"]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = pipe
        do { try task.run(); task.waitUntilExit(); let was = isRunning; isRunning = (task.terminationStatus == 0); if was != isRunning { DispatchQueue.main.async { [weak self] in self?.updateMenu() } } }
        catch { if isRunning { isRunning = false; DispatchQueue.main.async { [weak self] in self?.updateMenu() } } }
    }

    func showAlert(_ title: String, _ message: String) {
        DispatchQueue.main.async { let a = NSAlert(); a.messageText = title; a.informativeText = message; a.alertStyle = .warning; a.runModal() }
    }

    @discardableResult
    func shell(_ command: String) -> String {
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/bin/bash"); task.arguments = ["-c", command]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = pipe
        do { try task.run(); task.waitUntilExit(); return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "" }
        catch { return "" }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
