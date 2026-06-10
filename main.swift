import AppKit
import Carbon
import ApplicationServices

let logPath = NSString(string: "~/Library/Logs/atlas-claude-tab.log").expandingTildeInPath

func logLine(_ s: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
    guard let d = line.data(using: .utf8) else { return }
    if let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile(); h.write(d); try? h.close()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: d)
    }
}

struct Config {
    var mode = "smart"           // smart | switch | create
    var bookmarkTitle = "Claude"
    var createDelayMs = 250.0
}
func loadConfig() -> Config {
    var c = Config()
    let p = NSString(string: "~/.local/atlas-claude-tab/config.json").expandingTildeInPath
    guard let d = FileManager.default.contents(atPath: p),
          let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return c }
    if let v = j["mode"] as? String { c.mode = v }
    if let v = j["bookmarkTitle"] as? String { c.bookmarkTitle = v }
    if let v = j["createDelayMs"] as? Double { c.createDelayMs = v }
    return c
}
let config = loadConfig()

let atlasBundleID = "com.openai.atlas"
var hotKeyRef: EventHotKeyRef? = nil
var observerToken: NSObjectProtocol? = nil

func registerHotKey() {
    guard hotKeyRef == nil else { return }
    var ref: EventHotKeyRef? = nil
    let hotKeyID = EventHotKeyID(signature: OSType(0x41434C54), id: 1)
    let status = RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(cmdKey), hotKeyID, GetApplicationEventTarget(), 0, &ref)
    if status == noErr { hotKeyRef = ref; logLine("registered cmd-T") } else { logLine("register FAILED status=\(status)") }
}

func unregisterHotKey() {
    if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil; logLine("unregistered cmd-T") }
}

func syncToFrontmost() {
    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    if front == atlasBundleID { registerHotKey() } else { unregisterHotKey() }
}

func axChildren(_ el: AXUIElement) -> [AXUIElement] {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &v) == .success,
          let arr = v as? [AXUIElement] else { return [] }
    return arr
}

func axTitle(_ el: AXUIElement) -> String {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &v) == .success,
          let s = v as? String else { return "" }
    return s
}

func atlasAXApp() -> AXUIElement? {
    guard let atlas = NSRunningApplication.runningApplications(withBundleIdentifier: atlasBundleID).first else { return nil }
    return AXUIElementCreateApplication(atlas.processIdentifier)
}

// instant path: raise an existing claude.ai tab
func raiseClaudeTab() -> Bool {
    guard AXIsProcessTrusted(), let app = atlasAXApp() else { return false }
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v) == .success,
          let wins = v as? [AXUIElement] else { return false }
    for w in wins {
        let t = axTitle(w)
        if t == "Claude" || t.hasSuffix(" - Claude") {
            let err = AXUIElementPerformAction(w, "AXRaise" as CFString)
            logLine("raise [\(t)] -> \(err == .success ? "OK" : "err \(err.rawValue)")")
            return err == .success
        }
    }
    return false
}

func axPressMenuItem(menuTitle: String, itemTitle: String) -> Bool {
    guard AXIsProcessTrusted() else { logLine("AX not trusted"); return false }
    guard let app = atlasAXApp() else { logLine("atlas not running"); return false }
    var mb: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &mb) == .success else {
        logLine("no menu bar"); return false
    }
    let menuBar = mb as! AXUIElement
    guard let topItem = axChildren(menuBar).first(where: { axTitle($0) == menuTitle }),
          let menu = axChildren(topItem).first else {
        logLine("no \(menuTitle) menu"); return false
    }
    guard let item = axChildren(menu).first(where: { axTitle($0) == itemTitle }) else {
        logLine("no '\(itemTitle)' in \(menuTitle)"); return false
    }
    let err = AXUIElementPerformAction(item, kAXPressAction as CFString)
    logLine("AXPress \(menuTitle)>\(itemTitle) -> \(err == .success ? "OK" : "err \(err.rawValue)")")
    return err == .success
}

func isClaudeTitle(_ t: String) -> Bool {
    return t == "Claude" || t.hasSuffix(" - Claude")
}

func mainWindowTitle() -> String {
    guard let app = atlasAXApp() else { return "" }
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, "AXMainWindow" as CFString, &v) == .success else { return "" }
    return axTitle(v as! AXUIElement)
}

func createClaudeTab() {
    if axPressMenuItem(menuTitle: "File", itemTitle: "New Tab") {
        DispatchQueue.main.asyncAfter(deadline: .now() + config.createDelayMs / 1000.0) {
            if !axPressMenuItem(menuTitle: "Bookmarks", itemTitle: config.bookmarkTitle) {
                logLine("bookmark press failed; tab left on NTP")
            }
        }
        return
    }
    logLine("falling back to open -b")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    p.arguments = ["-b", atlasBundleID, "https://claude.ai/new"]
    try? p.run()
}

func openClaude() {
    logLine("hotkey fired (mode=\(config.mode))")
    switch config.mode {
    case "create":
        createClaudeTab()
    case "switch":
        if !raiseClaudeTab() { createClaudeTab() }
    default: // smart
        if isClaudeTitle(mainWindowTitle()) {
            if !axPressMenuItem(menuTitle: "Tabs", itemTitle: "Duplicate Tab") { createClaudeTab() }
        } else if !raiseClaudeTab() {
            createClaudeTab()
        }
    }
}

var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
    openClaude()
    return noErr
}, 1, &eventSpec, nil, nil)

observerToken = NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
) { _ in syncToFrontmost() }

let timer = Timer(timeInterval: 2.0, repeats: true) { _ in syncToFrontmost() }
RunLoop.main.add(timer, forMode: .common)

let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
syncToFrontmost()
logLine("atlas-claude-tab v5 started (mode=\(config.mode)) (AX trusted=\(trusted), frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"))")

NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
