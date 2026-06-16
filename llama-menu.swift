// llama-menu.swift — clean rewrite
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

    // Defaults: mlock and prio OFF (can be enabled in Advanced)
    var contextSize: Int = 16384
    var kvCacheType: String = "q8_0"
    var useMlock: Bool = false
    var useHighPrio: Bool = false
    var useFlashAttn: Bool = true

    let knownModels: [String: String] = [
        "Qwen_Qwen3.5-9B-Q4_K_M.gguf": "Qwen3.5-9B-Instruct",
        "gemma-4-12B-it-Q4_K_M.gguf": "Gemma 4 12B Instruct",
        "google_gemma-4-26B-A4B-it-Q4_K_M.gguf": "Gemma 4 26B-A4B",
        "Qwen_Qwen3.5-0.8B-Q4_K_M.gguf": "Qwen3.5-0.8B (draft)",
    ]

    let modelsDir = "\(NSHomeDirectory())/.models"
    let serverBinary = "/opt/homebrew/bin/llama-server"
    let port = "11434"

    func scanModels() -> [(file: String, name: String)] {
        var result: [(String, String)] = []
        if let e = FileManager.default.enumerator(atPath: modelsDir) {
            for case let f as String in e {
                if f.hasSuffix(".gguf") && !f.hasPrefix(".cache") {
                    result.append((f, knownModels[f] ?? f.replacingOccurrences(of: ".gguf", with: "")))
                }
            }
        }
        return result.sorted(by: { $0.1 < $1.1 })
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

        menu.addItem(NSMenuItem(title: isRunning ? "● Running (\(currentModel))" : "○ Stopped", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        for m in models {
            let item = NSMenuItem(title: m.name + (isRunning && currentModel == m.file ? " ✓" : ""), action: #selector(switchModel(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = m.file; menu.addItem(item)
        }
        if models.isEmpty { let i = NSMenuItem(title: "No models", action: nil, keyEquivalent: ""); i.isEnabled = false; menu.addItem(i) }

        menu.addItem(NSMenuItem.separator())

        // Advanced submenu
        let adv = NSMenu(title: "Advanced")
        adv.addItem(watch("Memory Lock", on: useMlock, action: #selector(tMlock)))
        adv.addItem(watch("High Priority", on: useHighPrio, action: #selector(tPrio)))
        adv.addItem(watch("Flash Attention", on: useFlashAttn, action: #selector(tFA)))
        adv.addItem(watch("Batch Size: 2048", on: true, action: #selector(advBatch)))
        adv.addItem(watch("KV Cache: \(kvCacheType)", on: true, action: #selector(advKV)))
        adv.addItem(watch("Context: \(ctx(contextSize))", on: true, action: #selector(advCtx)))
        adv.addItem(NSMenuItem.separator())
        let cf = NSMenuItem(title: "Custom Flags...", action: #selector(customCmd), keyEquivalent: "e"); cf.target = self; adv.addItem(cf)
        let rd = NSMenuItem(title: "Reset Defaults", action: #selector(resetAll), keyEquivalent: ""); rd.target = self; adv.addItem(rd)
        let ai = NSMenuItem(title: "Advanced Settings", action: nil, keyEquivalent: ""); ai.submenu = adv; menu.addItem(ai)

        menu.addItem(NSMenuItem.separator())
        let ul = NSMenuItem(title: "Unload Model", action: #selector(unload), keyEquivalent: "u"); ul.target = self; ul.isEnabled = isRunning; menu.addItem(ul)
        menu.addItem(NSMenuItem.separator())
        let s = NSMenuItem(title: "Start Server", action: #selector(startServer), keyEquivalent: "s"); s.target = self; menu.addItem(s)
        let x = NSMenuItem(title: "Stop Server", action: #selector(stopServer), keyEquivalent: "x"); x.target = self; menu.addItem(x)
        let r = NSMenuItem(title: "Restart Server", action: #selector(restartServer), keyEquivalent: "r"); r.target = self; menu.addItem(r)
        menu.addItem(NSMenuItem.separator())
        let wl = NSMenuItem(title: "Web Chat", action: #selector(openWeb), keyEquivalent: "w"); wl.target = self; menu.addItem(wl)
        let q = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"); q.target = self; menu.addItem(q)
        statusItem.menu = menu
    }

    func watch(_ t: String, on: Bool, action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: t + (on ? " ✓" : " ○"), action: action, keyEquivalent: ""); i.target = self; return i
    }
    func ctx(_ v: Int) -> String { v >= 1024 ? "\(v/1024)K" : "\(v)" }

    @objc func tMlock() { useMlock.toggle(); if isRunning { restartServer() } else { updateMenu() } }
    @objc func tPrio() { useHighPrio.toggle(); if isRunning { restartServer() } else { updateMenu() } }
    @objc func tFA() { useFlashAttn.toggle(); if isRunning { restartServer() } else { updateMenu() } }
    @objc func advBatch() { updateMenu() }
    @objc func advKV() { updateMenu() }
    @objc func advCtx() { updateMenu() }

    @objc func resetAll() {
        contextSize = 16384; kvCacheType = "q8_0"; useMlock = false; useHighPrio = false; useFlashAttn = true
        customFlags = []; useCustomFlags = false; updateMenu()
    }

    @objc func customCmd() {
        let a = NSAlert(); a.messageText = "Custom Flags"; a.informativeText = "Enter flags, include -m path:"
        let i = NSTextField(frame: NSRect(x:0,y:0,width:500,height:60))
        i.stringValue = "-m \(modelsDir)/\(currentModel) -ngl 99 -fa auto --tools all --jinja --host 127.0.0.1 --port 11434"
        a.accessoryView = i; a.addButton(withTitle: "Start"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn {
            customFlags = i.stringValue.split(separator: " ").map(String.init); useCustomFlags = true; restartServer()
        }
    }

    @objc func switchModel(_ s: NSMenuItem) {
        guard let f = s.representedObject as? String else { return }
        currentModel = f; useCustomFlags = false
        isRunning ? restartServer() : updateMenu()
    }

    @objc func startServer() {
        guard !isRunning else { return }
        var mp = "\(modelsDir)/\(currentModel)"
        if !FileManager.default.fileExists(atPath: mp) {
            let ms = scanModels(); if let first = ms.first { currentModel = first.file; mp = "\(modelsDir)/\(currentModel)" }
            else { sa("No models", "Download: models download qwen9"); return }
        }
        var flags: [String]
        if useCustomFlags && !customFlags.isEmpty { flags = customFlags }
        else {
            flags = ["-m", mp, "-ngl","99","--ctx-size","\(contextSize)","--threads","8",
                     "--cache-type-k",kvCacheType,"--cache-type-v",kvCacheType,
                     "--tools","all","--jinja","--ui-mcp-proxy","--host","127.0.0.1","--port",port]
            if useFlashAttn { flags += ["-fa","auto"] }
            if useMlock { flags += ["--mlock"] }
            if useHighPrio { flags += ["--prio","2"] }
        }
        let t = Process(); t.executableURL = URL(fileURLWithPath: serverBinary); t.arguments = flags
        do {
            try t.run(); serverTask = t; lastActivity = Date()
            t.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.isRunning = false; self?.serverTask = nil; self?.updateMenu() } }
            // Health check
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
