# atlas-claude-tab

**Make ⌘T in ChatGPT Atlas open claude.ai — instantly.**

A ~200-line Swift menu-bar-less helper that captures ⌘T *only while Atlas is frontmost* and routes it to Claude, with three context-aware behaviors:

| You are on… | ⌘T does | Feel |
|---|---|---|
| any non-Claude tab | switches to your existing Claude tab | instant, zero flash |
| a Claude tab already | duplicates it into a fresh Claude tab | native, no ChatGPT flash |
| (no Claude tab anywhere) | creates one (new tab → bookmark navigation) | one brief NTP flash, once |

The native ChatGPT new-tab page stays available on **⌥⌘T** (via the optional menu remap below).

## Why is this 200-line problem a whole saga?

Atlas is *not* a normal Chromium browser. Its new-tab page is a **native SwiftUI view** (`AuraHomePage`) that preloads chatgpt.com web content — it never navigates `chrome://newtab`. That single architectural fact kills every standard approach, and the workarounds kept hitting walls:

1. **No setting.** Atlas has no "new tab URL" preference — confirmed by dumping `defaults`, profile `Preferences`, and binary strings of `Aura.framework` (only `default_search_preference`, tab layout keys, etc.).
2. **Chrome extensions can't help.** `chrome_url_overrides.newtab` machinery exists in the embedded engine (Chromium 149), but ⌘T never goes through `chrome://newtab`, so an override never fires.
3. **Enterprise policies can't help.** `NewTabPageLocation` is compiled in — and equally moot for a native NTP.
4. **macOS menu-shortcut remapping half-works.** `NSUserKeyEquivalents` can bind ⌘T to a bookmark menu item (and the menus *do* honor it — verified via `AXMenuItemCmdChar`), but Atlas's shell handles the raw keypress *before* AppKit menu dispatch, so a real ⌘T behaves inconsistently. Worse: Atlas bookmark menu items **navigate the current tab** instead of opening a new one.
5. **`--load-extension` is unreachable.** The shell spawns the engine binary with a fixed argv; `open --args` never reaches Chromium's command line.
6. **Chromium singleton URL handoff gets dropped.** Running the engine binary with `--user-data-dir … URL` notifies the running instance (classic `chrome <url>` behavior), but the native shell silently discards the open-URL command.
7. **The engine's AppleScript dictionary survives** (`com.openai.atlas.web`, `NSAppleScriptEnabled=1`, full Chromium `scripting.sdef`!) and reveals the architecture — *each Atlas tab is one engine "window"* — but `set index of window` doesn't move the shell's tab selection, and `execute javascript` is permanently disabled: OpenAI removed the *View ▸ Developer ▸ Allow JavaScript from Apple Events* toggle, and writing `browser.allow_javascript_apple_events` into Preferences/Local State is ignored (the pref is unregistered, so Chromium's pref system never reads it).
8. **`open -a "ChatGPT Atlas" <url>` opens a separate window** (⌘N-like), not a tab. Bonus trap: by-name `-a` resolution can latch onto the **embedded** engine app (also named "ChatGPT Atlas", registered with LaunchServices after any accidental direct launch) and crash-loop with a bare-engine SIGSEGV. Always use `open -b com.openai.atlas`.

What *does* work, reliably, is the combination in this repo: a **Carbon global hotkey** (needs no permissions, captured before Atlas ever sees the key) + the **Accessibility API** to drive Atlas's own menus and windows (raise tab / new tab / duplicate tab / bookmark navigation).

## Tricks worth stealing

- **Per-app global hotkey without Karabiner/Hammerspoon:** `RegisterEventHotKey` needs *no* Accessibility permission. Register on `NSWorkspace.didActivateApplicationNotification` when the target app comes frontmost, unregister when it leaves — the target app never receives the keystroke, and every other app keeps its normal ⌘T. (Retain the observer token! `addObserver(forName:)` silently dies if you drop the return value.)
- **AX actions pass where synthetic events are blocked.** On a managed Mac whose enterprise agent rejects all synthetic clicks, `AXUIElementPerformAction` (menu `AXPress`, window `AXRaise`) and AX `set value` on text fields still work — they're accessibility messages, not injected events.
- **Atlas tab model:** engine window ⇄ Atlas tab (the engine reported 20 "windows" while macOS showed 3 real ones). `CGWindowListCopyWindowInfo` is the only honest source of real-window truth; the AX `windows` list materializes **lazily** — background tabs vanish from it, so "find tab by title" only works for recently-active tabs (hence the create-fallback).
- **Atlas bookmarks are server-canonical** (synced with your ChatGPT account). The local `bookmarks/BookmarkBar` JSON is a write-through cache — direct edits get overwritten on launch. Create bookmarks through the UI (the "Bookmark This Tab…" popover is AX-scriptable: anchor on `AXFocusedUIElement`, set the name field's value, press the right-most button).
- **TCC vs ad-hoc signing:** every rebuild of an ad-hoc-signed app changes its cdhash, and the existing Accessibility grant silently stops matching — the toggle in System Settings looks ON but `AXIsProcessTrusted()` returns false. Fix: `tccutil reset Accessibility <bundle-id>`, re-add, and **move tunables into a config file** so future tweaks don't need a rebuild.
- **A running process doesn't pick up new TCC grants** — restart it (`launchctl kickstart -k`) after granting.

## Install

Prerequisite: in Atlas, create a bookmark named **`Claude`** → `https://claude.ai/new` (used by the create-fallback path).

```bash
git clone https://github.com/zhouyi-xiaoxiao/atlas-claude-tab.git
cd atlas-claude-tab
./install.sh
```

Then grant Accessibility when prompted (System Settings ▸ Privacy & Security ▸ Accessibility ▸ enable **AtlasClaudeTab**) and restart the helper once:

```bash
launchctl kickstart -k gui/$(id -u)/com.$(whoami).atlas-claude-tab
```

Optional — keep the native NTP reachable and add a no-helper fallback (bookmark menu item on ⌘T):

```bash
defaults write com.openai.atlas NSUserKeyEquivalents -dict-add "New Tab" "@~t" "Claude" "@t"
```

## Configure

`~/.local/atlas-claude-tab/config.json`:

```json
{"mode": "smart", "bookmarkTitle": "Claude", "createDelayMs": 250}
```

- `mode`: `smart` (table above) | `switch` (only switch-or-create) | `create` (a new tab every press)
- Apply changes with `launchctl kickstart -k gui/$(id -u)/com.$(whoami).atlas-claude-tab` — no rebuild, no re-grant.

Log: `~/Library/Logs/atlas-claude-tab.log`.

## Uninstall

```bash
./uninstall.sh
defaults delete com.openai.atlas NSUserKeyEquivalents   # if you added the remap
```

## Caveats

- Title matching (`"Claude"` / `"… - Claude"`) is how the helper finds Claude tabs; renaming the bookmark breaks the create path (update `config.json`).
- Atlas updates may change menu item names ("New Tab", "Duplicate Tab", "Bookmarks") — the helper logs exactly which lookup failed.
- Built/tested against ChatGPT Atlas 1.2026.126.0 on macOS (Apple Silicon), 2026-06.

## 中文速览

把 ChatGPT Atlas 的 ⌘T 换成"立刻给我 Claude"：不在 Claude 页就秒切过去；已在 Claude 页就复制一个新标签；一个都没有才新建。难点在于 Atlas 的新标签页是原生 SwiftUI 页面（不走 `chrome://newtab`），设置项、扩展、企业策略、菜单快捷键重映射、`--load-extension`、Chromium singleton、AppleScript `execute javascript` 全部走不通；最终方案 = Carbon 全局热键（无需任何权限、按 app 前台动态注册）+ Accessibility API 驱动 Atlas 自己的菜单和窗口。过程中的坑详见上文 "Why" 与 "Tricks" 两节。
