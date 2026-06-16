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
    var batchSize: Int = 2048
    var useMlock: Bool = true
    var useHighPrio: Bool = true
    var useFlashAttn: Bool = true
    var useNUMA: Bool = false
    var useContinuousBatching: Bool = false
    var parallelSlots: Int = 1
    var noMmap: Bool = false
    var temperature: Double = 0.7
    var topP: Double = 0.9
    var minP: Double = 0.05
    var repeatPenalty: Double = 1.1

    // Known model aliases (friendly names for specific filenames)
    let knownModels: [String: String] = [
        "Qwen_Qwen3.5-9B-Q4_K_M.gguf": "Qwen3.5-9B-Instruct",
        "gemma-4-12B-it-Q4_K_M.gguf": "Gemma 4 12B Instruct",
        "google_gemma-4-26B-A4B-it-Q4_K_M.gguf": "Gemma 4 26B-A4B",
        "Qwen_Qwen3.5-0.8B-Q4_K_M.gguf": "Qwen3.5-0.8B (draft)",
    ]

    let contextOptions: [(label: String, value: Int)] = [
        ("4K", 4096), ("8K", 8192), ("16K", 16384),
        ("32K", 32768), ("64K", 65536), ("128K", 131072),
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

    // Dynamically scan ~/.models/ for .gguf files
    func scanModels() -> [(file: String, name: String)] {
        var result: [(file: String, name: String)] = []
        if let enumerator = FileManager.default.enumerator(atPath: modelsDir) {
            for case let filename as String in enumerator {
                if filename.hasSuffix(".gguf") && !filename.hasPrefix(".cache") {
                    let displayName = knownModels[filename] ?? filename
                        .replacingOccurrences(of: ".gguf", with: "")
                        .replacingOccurrences(of: "_", with: " ")
                    result.append((file: filename, name: displayName))
                }
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "🤖"
            button.font = NSFont.systemFont(ofSize: 14)
            button.toolTip = "llama.cpp server"
        }
        let _ = shell("launchctl unload ~/Library/LaunchAgents/com.llama.server.plist 2>/dev/null")
        isRunning = false
        updateMenu()
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkServerStatus()
        }
    }

    func updateMenu() {
        let menu = NSMenu()
        let models = scanModels()

        // Status
        let statusTitle = isRunning ? "● Running (\(currentModel))" : "○ Stopped"
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(NSMenuItem.separator())

        // Model list (dynamic)
        for model in models {
            let checkmark = (isRunning && currentModel == model.file) ? " ✓" : ""
            let item = NSMenuItem(title: "\(model.name)\(checkmark)", action: #selector(switchModel(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = model.file
            menu.addItem(item)
        }
        if models.isEmpty {
            let item = NSMenuItem(title: "No models in ~/.models/", action: nil, keyEquivalent: "")
            item.isEnabled = false; menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Context size submenu
        let ctxMenu = NSMenu(title: "Context Size")
        for opt in contextOptions {
            let checkmark = (contextSize == opt.value) ? " ✓" : ""
            let item = NSMenuItem(title: "\(opt.label)\(checkmark)", action: #selector(setContextSize(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = opt.value; ctxMenu.addItem(item)
        }
        let ctxItem = NSMenuItem(title: "Context: \(formatCtx(contextSize))", action: nil, keyEquivalent: "")
        ctxItem.submenu = ctxMenu; menu.addItem(ctxItem)

        // KV cache submenu
        let kvMenu = NSMenu(title: "KV Cache")
        for opt in kvCacheOptions {
            let checkmark = (kvCacheType == opt.value) ? " ✓" : ""
            let item = NSMenuItem(title: "\(opt.label)\(checkmark)", action: #selector(setKVCache(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = opt.value; kvMenu.addItem(item)
        }
        let kvItem = NSMenuItem(title: "KV Cache: \(kvCacheType)", action: nil, keyEquivalent: "")
        kvItem.submenu = kvMenu; menu.addItem(kvItem)

        // Quick toggles
        let mlockItem = NSMenuItem(title: "Memory Lock (\(useMlock ? "ON" : "OFF"))", action: #selector(toggleMlock), keyEquivalent: "")
        mlockItem.target = self; menu.addItem(mlockItem)
        let prioItem = NSMenuItem(title: "High Priority (\(useHighPrio ? "ON" : "OFF"))", action: #selector(togglePrio), keyEquivalent: "")
        prioItem.target = self; menu.addItem(prioItem)

        menu.addItem(NSMenuItem.separator())

        // Advanced Settings submenu
        let advMenu = NSMenu(title: "Advanced Settings")
        let batchSizeItem = NSMenuItem(title: "Batch Size: \(batchSize)", action: #selector(setBatchSizeFromDialog), keyEquivalent: "")
        batchSizeItem.target = self; advMenu.addItem(batchSizeItem)
        let faItem = NSMenuItem(title: "Flash Attention (\(useFlashAttn ? "ON" : "OFF"))", action: #selector(toggleFlashAttn), keyEquivalent: "")
        faItem.target = self; advMenu.addItem(faItem)
        let cbItem = NSMenuItem(title: "Continuous Batching (\(useContinuousBatching ? "ON" : "OFF"))", action: #selector(toggleContinuousBatching), keyEquivalent: "")
        cbItem.target = self; advMenu.addItem(cbItem)
        let npItem = NSMenuItem(title: "Parallel Slots: \(parallelSlots)", action: #selector(setParallelSlotsFromDialog), keyEquivalent: "")
        npItem.target = self; advMenu.addItem(npItem)
        advMenu.addItem(NSMenuItem.separator())
        let tempItem = NSMenuItem(title: "Temperature: \(temperature)", action: #selector(setTemperatureFromDialog), keyEquivalent: "")
        tempItem.target = self; advMenu.addItem(tempItem)
        let topPItem = NSMenuItem(title: "Top-P: \(topP)", action: #selector(setTopPFromDialog), keyEquivalent: "")
        topPItem.target = self; advMenu.addItem(topPItem)
        let minPItem = NSMenuItem(title: "Min-P: \(minP)", action: #selector(setMinPFromDialog), keyEquivalent: "")
        minPItem.target = self; advMenu.addItem(minPItem)
        let rpItem = NSMenuItem(title: "Repeat Penalty: \(repeatPenalty)", action: #selector(setRepeatPenaltyFromDialog), keyEquivalent: "")
        rpItem.target = self; advMenu.addItem(rpItem)
        advMenu.addItem(NSMenuItem.separator())
        let noMmapItem = NSMenuItem(title: "no-mmap (\(noMmap ? "ON" : "OFF"))", action: #selector(toggleNoMmap), keyEquivalent: "")
        noMmapItem.target = self; advMenu.addItem(noMmapItem)
        let numaItem = NSMenuItem(title: "NUMA x86 only (\(useNUMA ? "ON" : "OFF"))", action: #selector(toggleNUMA), keyEquivalent: "")
        numaItem.target = self; advMenu.addItem(numaItem)
        advMenu.addItem(NSMenuItem.separator())
        let customItem = NSMenuItem(title: "Custom Flags...", action: #selector(showCustomCommand), keyEquivalent: "e")
        customItem.target = self; advMenu.addItem(customItem)
        if useCustomFlags {
            let clearItem = NSMenuItem(title: "Clear Custom Flags", action: #selector(clearCustomFlags), keyEquivalent: "")
            clearItem.target = self; advMenu.addItem(clearItem)
        }
        let resetItem = NSMenuItem(title: "Reset to Defaults", action: #selector(resetDefaults), keyEquivalent: "")
        resetItem.target = self; advMenu.addItem(resetItem)

        let advItem = NSMenuItem(title: "Advanced Settings", action: nil, keyEquivalent: "")
        advItem.submenu = advMenu; menu.addItem(advItem)

        menu.addItem(NSMenuItem.separator())

        // Unload model
        let unloadItem = NSMenuItem(title: "Unload Model", action: #selector(unloadModel), keyEquivalent: "u")
        unloadItem.target = self; unloadItem.isEnabled = isRunning; menu.addItem(unloadItem)

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
        webUIItem.target = self; webUIItem.isEnabled = isRunning; menu.addItem(webUIItem)
        let folderItem = NSMenuItem(title: "Open Models Folder", action: #selector(openModelsFolder), keyEquivalent: "o")
        folderItem.target = self; menu.addItem(folderItem)
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshMenu), keyEquivalent: "")
        refreshItem.target = self; menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self; menu.addItem(quitItem)

        self.statusItem.menu = menu
    }

    func formatCtx(_ val: Int) -> String { val >= 1024 ? "\(val / 1024)K" : "\(val)" }

    @objc func refreshMenu() { updateMenu() }

    @objc func switchModel(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? String else { return }
        currentModel = file; useCustomFlags = false
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
    @objc func toggleFlashAttn() { useFlashAttn.toggle(); if isRunning { restartServer() } else { updateMenu() } }
    @objc func toggleContinuousBatching() { useContinuousBatching.toggle(); if isRunning { restartServer() } else { updateMenu() } }
    @objc func toggleNoMmap() { noMmap.toggle(); if isRunning { restartServer() } else { updateMenu() } }
    @objc func toggleNUMA() { useNUMA.toggle(); if isRunning { restartServer() } else { updateMenu() } }

    @objc func resetDefaults() {
        contextSize = 16384; kvCacheType = "q8_0"; batchSize = 2048
        useMlock = true; useHighPrio = true; useFlashAttn = true
        useNUMA = false; useContinuousBatching = false; parallelSlots = 1; noMmap = false
        temperature = 0.7; topP = 0.9; minP = 0.05; repeatPenalty = 1.1
        customFlags = []; useCustomFlags = false
        if isRunning { restartServer() } else { updateMenu() }
    }

    @objc func setBatchSizeFromDialog() { showIntDialog("Batch Size", current: batchSize, defaultVal: 2048) { self.batchSize = $0; if self.isRunning { self.restartServer() } else { self.updateMenu() } } }
    @objc func setParallelSlotsFromDialog() { showIntDialog("Parallel Slots", current: parallelSlots, defaultVal: 1) { self.parallelSlots = $0; if self.isRunning { self.restartServer() } else { self.updateMenu() } } }
    @objc func setTemperatureFromDialog() { showFloatDialog("Temperature", current: temperature, defaultVal: 0.7) { self.temperature = $0; if self.isRunning { self.restartServer() } else { self.updateMenu() } } }
    @objc func setTopPFromDialog() { showFloatDialog("Top-P", current: topP, defaultVal: 0.9) { self.topP = $0; if self.isRunning { self.restartServer() } else { self.updateMenu() } } }
    @objc func setMinPFromDialog() { showFloatDialog("Min-P", current: minP, defaultVal: 0.05) { self.minP = $0; if self.isRunning { self.restartServer() } else { self.updateMenu() } } }
    @objc func setRepeatPenaltyFromDialog() { showFloatDialog("Repeat Penalty", current: repeatPenalty, defaultVal: 1.1) { self.repeatPenalty = $0; if self.isRunning { self.restartServer() } else { self.updateMenu() } } }

    func showIntDialog(_ title: String, current: Int, defaultVal: Int, onSave: @escaping (Int) -> Void) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = "Enter a whole number:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24)); input.stringValue = "\(current)"; input.placeholderString = "\(defaultVal)"
        alert.accessoryView = input; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { onSave(Int(input.stringValue) ?? defaultVal) }
    }

    func showFloatDialog(_ title: String, current: Double, defaultVal: Double, onSave: @escaping (Double) -> Void) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = "Enter a decimal number:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24)); input.stringValue = String(format: "%.2f", current); input.placeholderString = String(format: "%.2f", defaultVal)
        alert.accessoryView = input; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { onSave(Double(input.stringValue) ?? defaultVal) }
    }

    @objc func showCustomCommand() {
        let alert = NSAlert()
        alert.messageText = "Custom llama-server Command"
        alert.informativeText = "Enter custom flags.\n⚠️ Include -m /path/to/model.gguf"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 500, height: 60))
        input.stringValue = "-m \(modelsDir)/\(currentModel) -ngl 99 --ctx-size 16384 -fa auto --tools all --jinja --host 127.0.0.1 --port 11434"
        alert.accessoryView = input
        alert.addButton(withTitle: "Start Server"); alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        let flagsText = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if flagsText.isEmpty { return }
        let flags = parseFlags(flagsText)
        let hasModel = flags.contains("-m") || flags.contains("--model")
        customFlags = hasModel ? flags : ["-m", "\(modelsDir)/\(currentModel)"] + flags
        useCustomFlags = true
        if response == .alertFirstButtonReturn { restartServer() }
        updateMenu()
    }

    @objc func clearCustomFlags() { customFlags = []; useCustomFlags = false; updateMenu() }

    @objc func startServer() {
        guard !isRunning else { return }
        let modelPath = "\(modelsDir)/\(currentModel)"
        guard FileManager.default.fileExists(atPath: modelPath) else {
            showAlert("Model not found", "File: \(modelPath)\n\nDownload a model first:\nmodels download qwen9"); return
        }
        var flags: [String]
        if useCustomFlags && !customFlags.isEmpty {
            flags = customFlags
        } else {
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
        let task = Process(); task.executableURL = URL(fileURLWithPath: serverBinary); task.arguments = flags
        do { try task.run(); serverTask = task; isRunning = true; updateMenu()
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
        if let task = serverTask { let _ = shell("kill -USR1 \(task.processIdentifier) 2>/dev/null"); sleep(1) }
    }

    @objc func viewLogs() { NSWorkspace.shared.open(URL(fileURLWithPath: "\(NSHomeDirectory())/.llama-server-error.log")) }
    @objc func openWebUI() { NSWorkspace.shared.open(URL(string: "http://127.0.0.1:\(port)")!) }
    @objc func openModelsFolder() { NSWorkspace.shared.open(URL(fileURLWithPath: modelsDir)) }
    @objc func quitApp() { stopServer(); NSApp.terminate(nil) }

    func checkServerStatus() {
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/curl"); task.arguments = ["-s", "--max-time", "2", "http://127.0.0.1:\(port)/health"]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = pipe
        do { try task.run(); task.waitUntilExit(); let was = isRunning; isRunning = (task.terminationStatus == 0); if was != isRunning { DispatchQueue.main.async { [weak self] in self?.updateMenu() } } }
        catch { if isRunning { isRunning = false; DispatchQueue.main.async { [weak self] in self?.updateMenu() } } }
    }

    func showAlert(_ title: String, _ message: String) {
        DispatchQueue.main.async { let a = NSAlert(); a.messageText = title; a.informativeText = message; a.alertStyle = .warning; a.runModal() }
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
