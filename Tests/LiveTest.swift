import Cocoa
import Carbon

let previewOnly = CommandLine.arguments.contains("--preview")
let lexicon: PinyinLexicon = {
    let path = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("--") } ?? "Resources/pinyin.dict"
    do {
        return try PinyinLexicon(contentsOf: URL(fileURLWithPath: path))
    } catch {
        fputs("无法读取词库 \(path): \(error)\n", stderr)
        exit(1)
    }
}()

final class IMETextView: NSTextView {
    let composer = Composer(lexicon: lexicon)

    func apply(_ event: NSEvent) {
        let result = composer.handle(KeyEvent(
            kind: event.type == .flagsChanged ? .flagsChanged : .keyDown,
            keyCode: event.keyCode,
            base: (event.charactersIgnoringModifiers ?? "").lowercased(),
            typed: event.characters ?? "",
            shift: event.modifierFlags.contains(.shift),
            control: event.modifierFlags.contains(.control),
            option: event.modifierFlags.contains(.option),
            command: event.modifierFlags.contains(.command),
            capsLock: event.modifierFlags.contains(.capsLock)
        ))
        let notFound = NSRange(location: NSNotFound, length: NSNotFound)
        switch result {
        case .pass(let clear):
            if clear {
                setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: notFound)
                CandidatePanel.shared.hide()
            }
            if event.type == .keyDown, !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control), !event.modifierFlags.contains(.option) {
                insertText(event.characters ?? "", replacementRange: notFound)
            }
        case .update(let snap):
            if !snap.commit.isEmpty {
                insertText(snap.commit, replacementRange: notFound)
            }
            if snap.marked.isEmpty {
                setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: notFound)
                CandidatePanel.shared.hide()
            } else {
                let attr = NSAttributedString(string: snap.marked, attributes: [
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .font: font ?? NSFont.systemFont(ofSize: 28),
                ])
                let length = (snap.marked as NSString).length
                setMarkedText(attr, selectedRange: NSRange(location: length, length: 0), replacementRange: notFound)
                if snap.candidates.isEmpty {
                    CandidatePanel.shared.hide()
                } else {
                    var caret = firstRect(forCharacterRange: NSRange(location: NSNotFound, length: NSNotFound), actualRange: nil)
                    if caret == .zero, let window = window {
                        caret = window.convertToScreen(NSRect(x: 24, y: 40, width: 2, height: 28))
                    }
                    CandidatePanel.shared.show(
                        candidates: snap.candidates,
                        highlight: snap.highlight,
                        page: snap.page,
                        pageCount: snap.pageCount,
                        caret: caret
                    )
                }
            }
        }
    }

    override func keyDown(with event: NSEvent) { apply(event) }
    override func flagsChanged(with event: NSEvent) { apply(event) }
}

func keyEvent(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: flags,
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: false,
        keyCode: code
    )!
}

func flagsEvent(code: UInt16, flags: NSEvent.ModifierFlags) -> NSEvent {
    NSEvent.keyEvent(
        with: .flagsChanged,
        location: .zero,
        modifierFlags: flags,
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0,
        context: nil,
        characters: "",
        charactersIgnoringModifiers: "",
        isARepeat: false,
        keyCode: code
    )!
}

final class Driver: NSObject, NSApplicationDelegate {
    private var textView: IMETextView!
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        window.makeKeyAndOrderFront(nil)
        if previewOnly {
            print("预览窗口已打开，可直接打拼音。Shift 切换中英文。")
            return
        }
        DispatchQueue.main.async { self.runTest() }
    }

    private func buildWindow() {
        let view = IMETextView(frame: NSRect(x: 0, y: 0, width: 640, height: 160))
        view.font = NSFont.systemFont(ofSize: 28)
        view.isRichText = true
        view.string = ""
        textView = view
        window = NSWindow(
            contentRect: NSRect(x: 240, y: 280, width: 680, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = previewOnly ? "TyInput 预览" : "TyInput 自测"
        window.contentView = view
    }

    private func runTest() {
        var failed = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            if ok {
                print("通过  \(name)")
            } else {
                failed += 1
                print("失败  \(name) \(detail)")
            }
        }

        type("nihao")
        window.display()
        textView.display()
        fflush(stdout)
        check("拼音出现候选", CandidatePanel.shared.visibleCandidates.first == "你好", "\(CandidatePanel.shared.visibleCandidates.prefix(6))")
        _ = saveCandidateShot()
        type(" ")
        check("空格上屏你好", plainText() == "你好", "text=[\(plainText())]")
        type("hello")
        type("\r")
        check("回车上屏英文", plainText() == "你好hello", "text=[\(plainText())]")
        type(",")
        check("中文逗号", plainText() == "你好hello，", "text=[\(plainText())]")

        if registerInstalledInputMethod() {
            print("通过  系统已登记输入法")
        } else {
            print("说明  系统没有把这个输入法放进输入源列表")
        }

        if failed == 0 {
            print("界面自测全部通过")
            exit(0)
        }
        print("界面自测失败 \(failed) 项")
        exit(1)
    }

    private func plainText() -> String {
        textView.string
    }

    private func type(_ text: String) {
        let codes: [Character: UInt16] = [
            "n": 45, "i": 34, "h": 4, "a": 0, "o": 31, "e": 14, "l": 37,
            " ": 49, ",": 43,
        ]
        for character in text {
            if character == "\r" {
                textView.apply(keyEvent("\r", code: 36))
            } else if let code = codes[character] {
                textView.apply(keyEvent(String(character), code: code))
            }
        }
    }

    private func saveCandidateShot() -> Bool {
        guard let png = CandidatePanel.shared.snapshotPNG() else { return false }
        let url = URL(fileURLWithPath: "build/candidate.png")
        do {
            try png.write(to: url)
            print("候选条截图: \(url.path)")
            return true
        } catch {
            print("截图写入失败 \(error)")
            return false
        }
    }

    private func registerInstalledInputMethod() -> Bool {
        let app = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Input Methods/TyInput.app")
        guard FileManager.default.fileExists(atPath: app.path) else {
            print("未安装到 ~/Library/Input Methods")
            return false
        }
        let status = TISRegisterInputSource(app as CFURL)
        print("TISRegisterInputSource status=\(status)")
        let query = [kTISPropertyBundleID as String: "com.tyinput.inputmethod"] as CFDictionary
        let count = TISCreateInputSourceList(query, true).map { CFArrayGetCount($0.takeRetainedValue()) } ?? 0
        print("已登记的 TyInput 输入源数量: \(count)")
        return count > 0
    }
}

@main
struct LiveMain {
    static func main() {
        let app = NSApplication.shared
        let driver = Driver()
        app.setActivationPolicy(.regular)
        app.delegate = driver
        app.run()
    }
}
