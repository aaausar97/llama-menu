// llama-menu.swift — clean v5 (with metrics)
// Build: swiftc -o llama-menu-bin llama-menu.swift -framework Cocoa

import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var serverTask: Process?
    var currentModel: String = ""
    var isRunning: Bool = false
    var modelLoaded: Bool = false
    var lastActivity: Date = Date()
    var customFlags: [String] = []
    var useCustomFlags: Bool = false

    // Defaults (mlock/prio OFF)
    var contextSize: Int = 16384
    var kvCacheType: String = "q8_0"
    var useMlock: Bool = false
    var useHighPrio: Bool = false
    var useFlashAttn: Bool = true
    var useSpeculative: Bool = false
    var draftModel: String = ""

    // Sampling presets
    var samplingPreset: String = "standard"
    var temperature: Double = 0.7
    var topP: Double = 0.9
    var topK: Int = 40
    var minP: Double = 0.05
    var repeatPenalty: Double = 1.1
    var dryMultiplier: Double = 0.8
    var dryBase: Double = 1.75
    var dryAllowedLength: Int = 2
    var xtcProbability: Double = 0.5
    var xtcThreshold: Double = 0.1

    // Metrics
    var tokensPerSecond: Double = 0
    var totalTokensGenerated: Int = 0

    let modelsDir = "\(NSHomeDirectory())/.models"
    let serverBinary = "/opt/homebrew/bin/llama-server"
    let port = "11434"

    // Models hidden from main list (shown only in speculative decoding)
    let hiddenModels: Set<String> = [
        "Qwen_Qwen3.5-0.8B-Q4_K_M.gguf",
    ]

    // ─── SCAN ────────────────────────────────────────────────────────────────────

    func scanModels() -> [(file: String, size: Int64)] {
        var result: [(String, Int64)] = []
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: modelsDir) {
            for f in files {
                if f.hasSuffix(".gguf") && !f.hasPrefix(".cache") && !hiddenModels.contains(f) {
                    let path = "\(modelsDir)/\(f)"
                    if let attr = try? fm.attributesOfItem(atPath: path),
                       let size = attr[.size] as? Int64 {
                        result.append((f, size))
                    }
                }
            }
        }
        return result.sorted(by: { $0.0 < $1.0 })
    }

    func scanDrafts() -> [(file: String, size: Int64)] {
        var result: [(String, Int64)] = []
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: modelsDir) {
            for f in files {
                if f.hasSuffix(".gguf") && hiddenModels.contains(f) {
                    let path = "\(modelsDir)/\(f)"
                    if let attr = try? fm.attributesOfItem(atPath: path),
                       let size = attr[.size] as? Int64 {
                        result.append((f, size))
                    }
                }
            }
        }
        return result
    }

    func formatSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_000_000
        return String(format: "%.0f MB", mb)
    }

    func ctx(_ v: Int) -> String { v >= 1024 ? "\(v/1024)K" : "\(v)" }

    // ─── SAMPLING PRESETS ─────────────────────────────────────────────────────────

    func applySamplingPreset(_ preset: String) {
        samplingPreset = preset
        switch preset {
        case "standard":
            temperature = 0.7; topP = 0.9; topK = 40; minP = 0.05; repeatPenalty = 1.1
            dryMultiplier = 0.8; dryBase = 1.75; xtcProbability = 0.5; xtcThreshold = 0.1
        case "reasoning":
            temperature = 1.0; topP = 1.0; topK = 0; minP = 0.0; repeatPenalty = 1.0
            dryMultiplier = 0.8; dryBase = 1.75; xtcProbability = 0.5; xtcThreshold = 0.1
        case "creative":
            temperature = 0.8; topP = 0.95; topK = 40; minP = 0.02; repeatPenalty = 1.15
            dryMultiplier = 0.8; dryBase = 1.75; dryAllowedLength = 2; xtcProbability = 0.5; xtcThreshold = 0.1
        case "structured":
            temperature = 0.3; topP = 0.7; topK = 20; minP = 0.1; repeatPenalty = 1.0
            dryMultiplier = 0.8; dryBase = 1.75; xtcProbability = 0.5; xtcThreshold = 0.1
        default: break
        }
    }

    func hasSamplingOverrides() -> Bool {
        if samplingPreset != "standard" { return true }
        if temperature != 0.7 || topP != 0.9 || topK != 40 || minP != 0.05 || repeatPenalty != 1.1 { return true }
        if dryMultiplier != 0.8 || dryBase != 1.75 || xtcProbability != 0.5 || xtcThreshold != 0.1 { return true }
        return false
    }

    // ─── METRICS ──────────────────────────────────────────────────────────────────

    func fetchMetrics() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        task.arguments = ["-s", "--max-time", "2", "http://127.0.0.1:\(port)/metrics"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0,
                  let data = try? pipe.fileHandleForReading.readDataToEndOfFile(),
                  let output = String(data: data, encoding: .utf8) else { return }
            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("llama_tokens_per_second") {
                    let parts = trimmed.components(separatedBy: " ")
                    if parts.count >= 2, let val = Double(parts[1]) {
                        tokensPerSecond = val
                    }
                } else if trimmed.hasPrefix("llama_tokens_predicted_total") {
                    let parts = trimmed.components(separatedBy: " ")
                    if parts.count >= 2, let val = Int(parts[1]) {
                        totalTokensGenerated = val
                    }
                }
            }
        } catch { return }
    }

    // ─── LIFECYCLE ───────────────────────────────────────────────────────────────

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🤖"
        statusItem.button?.font = NSFont.systemFont(ofSize: 14)
        _ = shell("launchctl unload ~/Library/LaunchAgents/com.llama.server.plist 2>/dev/null")
        updateMenu()
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkHealth()
            self?.fetchMetrics()
        }
    }

    // ─── MENU ────────────────────────────────────────────────────────────────────

    @objc func updateMenu() {
        let menu = NSMenu()
        let models = scanModels()

        // Status
        let idleMin = isRunning ? Int(Date().timeIntervalSince(lastActivity) / 60) : 0
        let idleStr = (isRunning && idleMin > 0) ? " idle \(idleMin)m" : ""
        let tpsStr = (isRunning && modelLoaded && tokensPerSecond > 0) ? String(format: " ~%.0f tok/s", tokensPerSecond) : ""
        let statusTitle: String
        if isRunning && modelLoaded {
            statusTitle = "● Running (\(currentModel))\(idleStr)\(tpsStr)"
        } else if isRunning {
            statusTitle = "● Idle (\(currentModel))"
        } else {
            statusTitle = "○ Stopped"
        }
        menu.addItem(NSMenuItem(title: statusTitle, action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        // Model list with sizes
        for m in models {
            let check = (isRunning && modelLoaded && currentModel == m.file) ? " ✓" : ""
            let item = NSMenuItem(title: "\(m.file) (\(formatSize(m.size)))\(check)", action: #selector(switchModel(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = m.file; menu.addItem(item)
        }
        if models.isEmpty {
            let i = NSMenuItem(title: "No .gguf files in ~/.models/", action: nil, keyEquivalent: "")
            i.isEnabled = false; menu.addItem(i)
        }

        menu.addItem(NSMenuItem.separator())

        // Advanced submenu — all selectable, no modals
        let adv = NSMenu(title: "Advanced Settings")
        adv.addItem(toggleItem("Memory Lock", on: useMlock, action: #selector(tMlock)))
        adv.addItem(toggleItem("High Priority", on: useHighPrio, action: #selector(tPrio)))
        adv.addItem(toggleItem("Flash Attention", on: useFlashAttn, action: #selector(tFA)))
        adv.addItem(NSMenuItem.separator())

        // Context Size submenu
        let ctxMenu = NSMenu(title: "Context Size")
        for (label,val) in [("4K",4096),("8K",8192),("16K",16384),("32K",32768),("64K",65536),("128K",131072)] {
            let item = NSMenuItem(title: label + (contextSize == val ? " ✓" : ""), action: #selector(setCtx(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = val; ctxMenu.addItem(item)
        }
        let ctxItem = NSMenuItem(title: "Context: \(ctx(contextSize))", action: nil, keyEquivalent: "")
        ctxItem.submenu = ctxMenu; adv.addItem(ctxItem)

        // KV Cache submenu
        let kvMenu = NSMenu(title: "KV Cache")
        for (label,val) in [("F16","f16"),("Q8_0","q8_0"),("Q4_0","q4_0"),("Q4_1","q4_1"),("Q5_0","q5_0"),("Q5_1","q5_1"),("IQ4_NL","iq4_nl")] {
            let item = NSMenuItem(title: label + (kvCacheType == val ? " ✓" : ""), action: #selector(setKV(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = val; kvMenu.addItem(item)
        }
        let kvItem = NSMenuItem(title: "KV Cache: \(kvCacheType)", action: nil, keyEquivalent: "")
        kvItem.submenu = kvMenu; adv.addItem(kvItem)

        // Batch Size submenu
        let batchMenu = NSMenu(title: "Batch Size")
        for val in [512,1024,2048,4096] {
            let item = NSMenuItem(title: "\(val)" + (2048 == val ? " ✓" : ""), action: #selector(setBatch(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = val; batchMenu.addItem(item)
        }
        let batchItem = NSMenuItem(title: "Batch Size: 2048", action: nil, keyEquivalent: "")
        batchItem.submenu = batchMenu; adv.addItem(batchItem)

        // Speculative decoding
        let drafts = scanDrafts()
        if !drafts.isEmpty {
            adv.addItem(NSMenuItem.separator())
            let specMenu = NSMenu(title: "Speculative Decoding")
            let specToggle = NSMenuItem(title: "Enable", action: #selector(toggleSpec), keyEquivalent: "")
            specToggle.target = self; specMenu.addItem(specToggle)
            for d in drafts {
                let dItem = NSMenuItem(title: "\(d.file) (\(formatSize(d.size)))", action: #selector(pickDraft(_:)), keyEquivalent: "")
                dItem.target = self; dItem.representedObject = d.file; specMenu.addItem(dItem)
            }
            let specItem = NSMenuItem(title: "Speculative Decoding", action: nil, keyEquivalent: "")
            specItem.submenu = specMenu; adv.addItem(specItem)
        }

        // Sampling presets
        adv.addItem(NSMenuItem.separator())
        let samplingMenu = NSMenu(title: "Sampling Presets")
        for (label, preset) in [("Standard", "standard"), ("Reasoning", "reasoning"), ("Creative", "creative"), ("Structured", "structured")] {
            let check = (samplingPreset == preset) ? " ✓" : ""
            let item = NSMenuItem(title: label + check, action: #selector(setSamplingPreset(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = preset; samplingMenu.addItem(item)
        }
        samplingMenu.addItem(NSMenuItem.separator())
        samplingMenu.addItem(NSMenuItem(title: "Temperature: \(temperature)", action: nil, keyEquivalent: ""))
        samplingMenu.addItem(NSMenuItem(title: "Top-P: \(topP)", action: nil, keyEquivalent: ""))
        samplingMenu.addItem(NSMenuItem(title: "Min-P: \(minP)", action: nil, keyEquivalent: ""))
        samplingMenu.addItem(NSMenuItem(title: "Repeat Penalty: \(repeatPenalty)", action: nil, keyEquivalent: ""))
        let samplingTitle = "Sampling: " + samplingPreset.capitalized
        let samplingItem = NSMenuItem(title: samplingTitle, action: nil, keyEquivalent: "")
        samplingItem.submenu = samplingMenu; adv.addItem(samplingItem)

        adv.addItem(NSMenuItem.separator())
        let cf = NSMenuItem(title: "Custom Flags...", action: #selector(customCmd), keyEquivalent: "e"); cf.target = self; adv.addItem(cf)
        let rd = NSMenuItem(title: "Reset to Defaults", action: #selector(resetAll), keyEquivalent: ""); rd.target = self; adv.addItem(rd)

        let ai = NSMenuItem(title: "Advanced Settings", action: nil, keyEquivalent: "")
        ai.submenu = adv; menu.addItem(ai)

        // Server control
        menu.addItem(NSMenuItem.separator())
        let ul = NSMenuItem(title: "Unload Model", action: #selector(unload), keyEquivalent: "u"); ul.target = self; ul.isEnabled = isRunning; menu.addItem(ul)
        menu.addItem(NSMenuItem.separator())
        let s = NSMenuItem(title: "Start Server", action: #selector(startServer), keyEquivalent: "s"); s.target = self; menu.addItem(s)
        let x = NSMenuItem(title: "Stop Server", action: #selector(stopServer), keyEquivalent: "x"); x.target = self; menu.addItem(x)
        let r = NSMenuItem(title: "Restart Server", action: #selector(restartServer), keyEquivalent: "r"); r.target = self; menu.addItem(r)
        menu.addItem(NSMenuItem.separator())
        let wl = NSMenuItem(title: "Open Web Chat", action: #selector(openWeb), keyEquivalent: "w"); wl.target = self; menu.addItem(wl)
        let ref = NSMenuItem(title: "Refresh", action: #selector(updateMenu), keyEquivalent: ""); ref.target = self; menu.addItem(ref)
        let q = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"); q.target = self; menu.addItem(q)

        statusItem.menu = menu
    }

    func toggleItem(_ t: String, on: Bool, action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: "\(t): \(on ? "ON" : "OFF")", action: action, keyEquivalent: ""); i.target = self; return i
    }

    // ─── TOGGLES ─────────────────────────────────────────────────────────────────

    @objc func tMlock() { useMlock.toggle(); if isRunning { restartServer() } else { updateMenu() } }
    @objc func tPrio() { useHighPrio.toggle(); if isRunning { restartServer() } else { updateMenu() } }
    @objc func tFA() { useFlashAttn.toggle(); if isRunning { restartServer() } else { updateMenu() } }
    @objc func toggleSpec() { useSpeculative.toggle(); if isRunning { restartServer() } else { updateMenu() } }
    @objc func pickDraft(_ s: NSMenuItem) { if let f = s.representedObject as? String { draftModel = f; updateMenu() } }
    @objc func setCtx(_ s: NSMenuItem) { if let v = s.representedObject as? Int { contextSize = v }; if isRunning { restartServer() } else { updateMenu() } }
    @objc func setKV(_ s: NSMenuItem) { if let v = s.representedObject as? String { kvCacheType = v }; if isRunning { restartServer() } else { updateMenu() } }
    @objc func setBatch(_ s: NSMenuItem) { if let v = s.representedObject as? Int { _ = v }; if isRunning { restartServer() } else { updateMenu() } }
    @objc func setSamplingPreset(_ s: NSMenuItem) { if let p = s.representedObject as? String { applySamplingPreset(p) }; if isRunning { restartServer() } else { updateMenu() } }

    @objc func resetAll() {
        contextSize = 16384; kvCacheType = "q8_0"; useMlock = false; useHighPrio = false
        useFlashAttn = true; useSpeculative = false; draftModel = ""; customFlags = []; useCustomFlags = false
        applySamplingPreset("standard"); tokensPerSecond = 0; totalTokensGenerated = 0
        updateMenu()
    }

    @objc func customCmd() {
        let a = NSAlert(); a.messageText = "Custom Flags"; a.informativeText = "Enter flags, include -m path:"
        let i = NSTextField(frame: NSRect(x:0,y:0,width:500,height:60))
        i.stringValue = "-m \(modelsDir)/\(currentModel) -ngl 99 --ctx-size 16384 -fa auto --tools all --jinja --ui-mcp-proxy --host 127.0.0.1 --port 11434"
        a.accessoryView = i; a.addButton(withTitle: "Start"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn {
            customFlags = i.stringValue.split(separator: " ").map(String.init); useCustomFlags = true; restartServer()
        }
    }

    // ─── MODEL SWITCHING ─────────────────────────────────────────────────────────

    @objc func switchModel(_ s: NSMenuItem) {
        guard let f = s.representedObject as? String else { return }
        currentModel = f; useCustomFlags = false
        if isRunning { restartServer() } else { startServer() }
    }

    // ─── SERVER CONTROL ─────────────────────────────────────────────────────────

    @objc func startServer() {
        guard !isRunning else { return }
        let mp = "\(modelsDir)/\(currentModel)"
        guard FileManager.default.fileExists(atPath: mp) else { sa("Not found", "File: \(mp)"); return }
        var flags: [String]
        if useCustomFlags && !customFlags.isEmpty { flags = customFlags }
        else {
            flags = ["-m", mp, "-ngl","99","--ctx-size","\(contextSize)","--threads","8",
                     "--cache-type-k",kvCacheType,"--cache-type-v",kvCacheType,
                     "--tools","all","--jinja","--ui-mcp-proxy",
                     "--host","127.0.0.1","--port",port,"--sleep-idle-seconds","180"]
            if useFlashAttn { flags += ["-fa","auto"] }
            if useMlock { flags += ["--mlock"] }
            if useHighPrio { flags += ["--prio","2"] }
            if useSpeculative && !draftModel.isEmpty {
                let dp = "\(modelsDir)/\(draftModel)"
                if FileManager.default.fileExists(atPath: dp) {
                    flags += ["--spec-draft-model", dp, "--spec-draft-type-k", "q8_0", "--spec-draft-type-v", "q8_0", "--spec-type", "draft-simple"]
                }
            }
            if hasSamplingOverrides() || samplingPreset != "standard" {
                flags += ["--temp", String(format: "%.2f", temperature)]
                flags += ["--top-p", String(format: "%.2f", topP)]
                flags += ["--top-k", "\(topK)"]
                flags += ["--min-p", String(format: "%.2f", minP)]
                flags += ["--repeat-penalty", String(format: "%.2f", repeatPenalty)]
                if samplingPreset == "creative" {
                    flags += ["--dry-multiplier", String(format: "%.2f", dryMultiplier)]
                    flags += ["--dry-base", String(format: "%.2f", dryBase)]
                    flags += ["--dry-allowed-length", "\(dryAllowedLength)"]
                    flags += ["--xtc-probability", String(format: "%.2f", xtcProbability)]
                    flags += ["--xtc-threshold", String(format: "%.2f", xtcThreshold)]
                }
            }
        }
        let t = Process(); t.executableURL = URL(fileURLWithPath: serverBinary); t.arguments = flags
        do {
            try t.run(); serverTask = t; lastActivity = Date()
            t.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.isRunning = false; self?.modelLoaded = false; self?.serverTask = nil; self?.updateMenu() } }
            DispatchQueue.global().async { [weak self] in
                for _ in 0..<60 {
                    if self?.healthy() == true { DispatchQueue.main.async { self?.isRunning = true; self?.modelLoaded = true; self?.updateMenu() }; return }
                    sleep(1)
                }
                DispatchQueue.main.async { self?.sa("Timeout", "Not responding after 60s") }
            }
            updateMenu()
        } catch { sa("Failed", error.localizedDescription) }
    }

    @objc func stopServer() {
        serverTask?.terminate(); serverTask = nil; modelLoaded = false; tokensPerSecond = 0; totalTokensGenerated = 0
        _ = shell("pkill -f llama-server 2>/dev/null"); sleep(1)
        isRunning = false; updateMenu()
    }

    @objc func restartServer() { stopServer(); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.startServer() } }
    @objc func unload() { stopServer() }
    @objc func openWeb() { NSWorkspace.shared.open(URL(string: "http://127.0.0.1:\(port)")!) }
    @objc func quitApp() { stopServer(); NSApp.terminate(nil) }

    // ─── HEALTH ─────────────────────────────────────────────────────────────────

    @objc func checkHealth() {
        let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        t.arguments = ["-s","--max-time","2","http://127.0.0.1:\(port)/health"]
        let p = Pipe(); t.standardOutput = p; t.standardError = p
        do { try t.run(); t.waitUntilExit()
            let was = isRunning; isRunning = (t.terminationStatus == 0)
            if was != isRunning { DispatchQueue.main.async { [weak self] in self?.updateMenu() } }
        } catch { if isRunning { isRunning = false; modelLoaded = false; tokensPerSecond = 0; DispatchQueue.main.async { [weak self] in self?.updateMenu() } } }
    }

    func healthy() -> Bool {
        let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        t.arguments = ["-s","--max-time","2","http://127.0.0.1:\(port)/health"]
        let p = Pipe(); t.standardOutput = p; t.standardError = p
        do { try t.run(); t.waitUntilExit(); return t.terminationStatus == 0 }
        catch { return false }
    }

    func sa(_ t: String, _ m: String) { DispatchQueue.main.async { let a = NSAlert(); a.messageText = t; a.informativeText = m; a.runModal() } }

    @discardableResult func shell(_ c: String) -> String {
        let t = Process(); t.executableURL = URL(fileURLWithPath: "/bin/bash"); t.arguments = ["-c",c]
        let p = Pipe(); t.standardOutput = p; t.standardError = p
        do { try t.run(); t.waitUntilExit(); return String(data: p.fileHandleForReading.readDataToEndOfFile(), encoding:.utf8) ?? "" }
        catch { return "" }
    }
}

let app = NSApplication.shared
let d = AppDelegate(); app.delegate = d; app.setActivationPolicy(.accessory); app.run()
