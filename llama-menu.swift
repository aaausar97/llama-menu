// llama-menu.swift — clean rewrite v2
// Build: swiftc -o llama-menu-bin llama-menu.swift -framework Cocoa

import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var serverTask: Process?
    var currentModel: String = "Qwen_Qwen3.5-9B-Q4_K_M.gguf"
    var isRunning: Bool = false
    var lastActivity: Date = Date()
    var customFlags: [String] = []
    var useCustomFlags: Bool = false

    // Defaults: mlock and prio OFF
    var contextSize: Int = 16384
    var kvCacheType: String = "q8_0"
    var useMlock: Bool = false
    var useHighPrio: Bool = false
    var useFlashAttn: Bool = true
    var batchSize: Int = 2048
    var useSpeculative: Bool = false

    let knownModels: [String: String] = [
        "Qwen_Qwen3.5-9B-Q4_K_M.gguf": "Qwen3.5-9B-Instruct",
        "gemma-4-12B-it-Q4_K_M.gguf": "Gemma 4 12B Instruct",
        "google_gemma-4-26B-A4B-it-Q4_K_M.gguf": "Gemma 4 26B-A4B",
    ]

    // Draft models (hidden from main list, used for speculative decoding)
    let draftModels: [String: String] = [
        "Qwen_Qwen3.5-0.8B-Q4_K_M.gguf": "Qwen3.5-0.8B (draft)",
    ]

    let modelsDir = "\(NSHomeDirectory())/.models"
    let serverBinary = "/opt/homebrew/bin/llama-server"
    let port = "11434"

    // Scan only main models (no drafts)
    func scanModels() -> [(file: String, name: String)] {
        var result: [(String, String)] = []
        if let e = FileManager.default.enumerator(atPath: modelsDir) {
            for case let f as String in e {
                if f.hasSuffix(".gguf") && !f.hasPrefix(".cache") && knownModels[f] != nil {
                    result.append((f, knownModels[f]!))
                }
            }
        }
        return result.sorted(by: { $0.1 < $1.1 })
    }

    // Scan draft models
    func scanDrafts() -> [(file: String, name: String)] {
        var result: [(String, String)] = []
        if let e = FileManager.default.enumerator(atPath: modelsDir) {
            for case let f as String in e {
                if f.hasSuffix(".gguf") && draftModels[f] != nil {
                    result.append((f, draftModels[f]!))
                }
            }
        }
        return result
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🤖"
        statusItem.button?.font = NSFont.systemFont(ofSize: 14)
        _ = shell("launchctl unload ~/Library/LaunchAgents/com.llama.server.plist 2>/dev/null")
        updateMenu()
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.checkHealth() }
    }

    func updateMenu() {
        let menu = NSMenu()
        let models = scanModels()

        // Status line
        let idleMin = isRunning ? Int(Date().timeIntervalSince(lastActivity) / 60) : 0
        let idleStr = (isRunning && idleMin > 0) ? " idle \(idleMin)m" : ""
        menu.addItem(NSMenuItem(title: isRunning ? "● Running (\(currentModel))\(idleStr)" : "○ Stopped", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        // Main model list (no drafts)
        for m in models {
            let item = NSMenuItem(title: m.1 + (isRunning && currentModel == m.0 ? " ✓" : ""), action: #selector(switchModel(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = m.0; menu.addItem(item)
        }
        if models.isEmpty { let i = NSMenuItem(title: "No models in ~/.models/", action: nil, keyEquivalent: ""); i.isEnabled = false; menu.addItem(i) }

        menu.addItem(NSMenuItem.separator())

        // Advanced submenu
        let adv = NSMenu(title: "Advanced Settings")

        // Quick toggles
        adv.addItem(toggleItem("Memory Lock", on: useMlock, action: #selector(tMlock)))
        adv.addItem(toggleItem("High Priority", on: useHighPrio, action: #selector(tPrio)))
        adv.addItem(toggleItem("Flash Attention", on: useFlashAttn, action: #selector(tFA)))
        adv.addItem(NSMenuItem.separator())

        // Configurable values with selectable submenus
        // Context Size submenu
        let ctxMenu = NSMenu(title: "Context Size")
        for opt in [("4K",4096),("8K",8192),("16K",16384),("32K",32768),("64K",65536),("128K",131072)] {
            let item = NSMenuItem(title: opt.0 + (contextSize == opt.1 ? " ✓" : ""), action: #selector(setCtx(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = opt.1; ctxMenu.addItem(item)
        }
        let ctxItem = NSMenuItem(title: "Context: \(ctx(contextSize))", action: nil, keyEquivalent: "")
        ctxItem.submenu = ctxMenu; adv.addItem(ctxItem)

        // KV Cache submenu
        let kvMenu = NSMenu(title: "KV Cache")
        for opt in [("F16","f16"),("Q8_0","q8_0"),("Q4_K_S","q4_k_s"),("Q4_K_M","q4_k_m"),("Q5_K_M","q5_k_m")] {
            let item = NSMenuItem(title: opt.0 + (kvCacheType == opt.1 ? " ✓" : ""), action: #selector(setKV(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = opt.1; kvMenu.addItem(item)
        }
        let kvItem = NSMenuItem(title: "KV Cache: \(kvCacheType)", action: nil, keyEquivalent: "")
        kvItem.submenu = kvMenu; adv.addItem(kvItem)

        // Batch Size submenu
        let batchMenu = NSMenu(title: "Batch Size")
        for opt in [("512",512),("1024",1024),("2048",2048),("4096",4096)] {
            let item = NSMenuItem(title: "\(opt.1)" + (batchSize == opt.1 ? " ✓" : ""), action: #selector(setBatch(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = opt.1; batchMenu.addItem(item)
        }
        let batchItem = NSMenuItem(title: "Batch Size: \(batchSize)", action: nil, keyEquivalent: "")
        batchItem.submenu = batchMenu; adv.addItem(batchItem)
        adv.addItem(NSMenuItem.separator())

        // Speculative decoding (draft models)
        let drafts = scanDrafts()
        if !drafts.isEmpty {
            let specMenu = NSMenu(title: "Speculative Decoding")
            let specToggle = NSMenuItem(title: useSpeculative ? "Enable ✓" : "Enable ○", action: #selector(toggleSpec), keyEquivalent: "")
            specToggle.target = self; specMenu.addItem(specToggle)
            for d in drafts {
                let dItem = NSMenuItem(title: "Draft: \(d.1)", action: #selector(pickDraft(_:)), keyEquivalent: "")
                dItem.target = self; dItem.representedObject = d.0; specMenu.addItem(dItem)
            }
            let specItem = NSMenuItem(title: "Speculative Decoding", action: nil, keyEquivalent: "")
            specItem.submenu = specMenu; adv.addItem(specItem)
            adv.addItem(NSMenuItem.separator())
        }

        // Custom flags and reset
        let cf = NSMenuItem(title: "Custom Flags...", action: #selector(customCmd), keyEquivalent: "e"); cf.target = self; adv.addItem(cf)
        let rd = NSMenuItem(title: "Reset to Defaults", action: #selector(resetAll), keyEquivalent: ""); rd.target = self; adv.addItem(rd)

        let ai = NSMenuItem(title: "Advanced Settings", action: nil, keyEquivalent: "")
        ai.submenu = adv; menu.addItem(ai)

        menu.addItem(NSMenuItem.separator())

        // Server control
        let ul = NSMenuItem(title: "Unload Model", action: #selector(unload), keyEquivalent: "u"); ul.target = self; ul.isEnabled = isRunning; menu.addItem(ul)
        menu.addItem(NSMenuItem.separator())
        let s = NSMenuItem(title: "Start Server", action: #selector(startServer), keyEquivalent: "s"); s.target = self; menu.addItem(s)
        let x = NSMenuItem(title: "Stop Server", action: #selector(stopServer), keyEquivalent: "x"); x.target = self; menu.addItem(x)
        let r = NSMenuItem(title: "Restart Server", action: #selector(restartServer), keyEquivalent: "r"); r.target = self; menu.addItem(r)
        menu.addItem(NSMenuItem.separator())

        // Bottom: Web Chat, Refresh, Quit
        let wl = NSMenuItem(title: "Open Web Chat", action: #selector(openWeb), keyEquivalent: "w"); wl.target = self; menu.addItem(wl)
        let ref = NSMenuItem(title: "Refresh", action: #selector(refreshMenu), keyEquivalent: ""); ref.target = self; menu.addItem(ref)
        let q = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"); q.target = self; menu.addItem(q)

        statusItem.menu = menu
    }

    func toggleItem(_ t: String, on: Bool, action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: "\(t): \(on ? "ON" : "OFF")", action: action, keyEquivalent: ""); i.target = self; return i
    }
    func ctx(_ v: Int) -> String { v >= 1024 ? "\(v/1024)K" : "\(v)" }

    @objc func refreshMenu() { updateMenu() }

    // ─── TOGGLES ────────────────────────────────────────────────────────────────

    @objc func tMlock() { useMlock.toggle(); if isRunning { restartServer() } else { updateMenu() } }
    @objc func tPrio() { useHighPrio.toggle(); if isRunning { restartServer() } else { updateMenu() } }
    @objc func tFA() { useFlashAttn.toggle(); if isRunning { restartServer() } else { updateMenu() } }
    @objc func toggleSpec() { useSpeculative.toggle(); if isRunning { restartServer() } else { updateMenu() } }
    @objc func pickDraft(_ s: NSMenuItem) { if let f = s.representedObject as? String { currentModel = f; updateMenu() } }

    // ─── ADVANCED DIALOGS ───────────────────────────────────────────────────────

    @objc func setCtx(_ s: NSMenuItem) { if let v = s.representedObject as? Int { contextSize = v }; if isRunning { restartServer() } else { updateMenu() } }
    @objc func setKV(_ s: NSMenuItem) { if let v = s.representedObject as? String { kvCacheType = v }; if isRunning { restartServer() } else { updateMenu() } }
    @objc func setBatch(_ s: NSMenuItem) { if let v = s.representedObject as? Int { batchSize = v }; if isRunning { restartServer() } else { updateMenu() } }

    @objc func resetAll() {
        contextSize = 16384; kvCacheType = "q8_0"; useMlock = false; useHighPrio = false
        useFlashAttn = true; useSpeculative = false; customFlags = []; useCustomFlags = false; updateMenu()
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

    // ─── MODEL SWITCHING ────────────────────────────────────────────────────────

    @objc func switchModel(_ s: NSMenuItem) {
        guard let f = s.representedObject as? String else { return }
        currentModel = f; useCustomFlags = false
        isRunning ? restartServer() : updateMenu()
    }

    // ─── SERVER CONTROL ─────────────────────────────────────────────────────────

    @objc func startServer() {
        guard !isRunning else { return }
        var mp = "\(modelsDir)/\(currentModel)"
        if !FileManager.default.fileExists(atPath: mp) {
            let ms = scanModels(); if let first = ms.first { currentModel = first.0; mp = "\(modelsDir)/\(currentModel)" }
            else { sa("No models", "Download: models download qwen9"); return }
        }
        var flags: [String]
        if useCustomFlags && !customFlags.isEmpty { flags = customFlags }
        else {
            flags = ["-m", mp, "-ngl","99","--ctx-size","\(contextSize)","--batch-size","\(batchSize)","--ubatch-size","\(batchSize)","--threads","8",
                     "--cache-type-k",kvCacheType,"--cache-type-v",kvCacheType,
                     "--tools","all","--jinja","--ui-mcp-proxy",
                     "--host","127.0.0.1","--port",port,"--sleep-idle-seconds","180"]
            if useFlashAttn { flags += ["-fa","auto"] }
            if useMlock { flags += ["--mlock"] }
            if useHighPrio { flags += ["--prio","2"] }
        }
        let t = Process(); t.executableURL = URL(fileURLWithPath: serverBinary); t.arguments = flags
        do {
            try t.run(); serverTask = t; lastActivity = Date()
            t.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.isRunning = false; self?.serverTask = nil; self?.updateMenu() } }
            DispatchQueue.global().async { [weak self] in
                for _ in 0..<60 {
                    if self?.healthy() == true { DispatchQueue.main.async { self?.isRunning = true; self?.updateMenu() }; return }
                    sleep(1)
                }
                DispatchQueue.main.async { self?.sa("Timeout", "Not responding after 60s") }
            }
            updateMenu()
        } catch { sa("Failed", error.localizedDescription) }
    }

    @objc func stopServer() {
        serverTask?.terminate(); serverTask = nil
        _ = shell("pkill -f llama-server 2>/dev/null"); sleep(1)
        isRunning = false; updateMenu()
    }

    @objc func restartServer() { stopServer(); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.startServer() } }

    @objc func unload() { serverTask?.terminate(); serverTask = nil; isRunning = false; updateMenu() }
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
        } catch { if isRunning { isRunning = false; DispatchQueue.main.async { [weak self] in self?.updateMenu() } } }
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
