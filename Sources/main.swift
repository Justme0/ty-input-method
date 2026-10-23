import Cocoa
import InputMethodKit

enum LexiconStore {
    static let shared = PinyinLexicon.loadFromBundle()
}

final class InputBus {
    static let shared = InputBus()

    var chinese = true
    weak var active: TyInputController?
    var onRefresh: ((Bool) -> Void)?

    func toggleFromUI() {
        chinese.toggle()
        active?.setChinese(chinese)
        refresh()
    }

    func refresh() {
        onRefresh?(chinese)
    }

    func makeMenu(target: AnyObject?, action: Selector) -> NSMenu {
        let menu = NSMenu(title: "TyInput")
        let mode = NSMenuItem(
            title: chinese ? "切换到英文（Shift）" : "切换到中文（Shift）",
            action: action,
            keyEquivalent: ""
        )
        mode.target = target
        menu.addItem(mode)
        menu.addItem(.separator())
        for tip in [
            "空格：上屏当前候选",
            "回车：上屏原始拼音",
            "1-9：选择候选，- / = 翻页",
            "Shift：切换中英文",
        ] {
            let item = NSMenuItem(title: tip, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        return menu
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status = item
        InputBus.shared.onRefresh = { [weak self] _ in
            self?.updateStatus()
        }
        CandidatePanel.shared.onPick = { index in
            InputBus.shared.active?.pick(index)
        }
        updateStatus()
        NSLog("[TyInput] 已启动")
    }

    @objc func toggleMode(_ sender: Any?) {
        InputBus.shared.toggleFromUI()
    }

    private func updateStatus() {
        guard let button = status?.button else { return }
        let chinese = InputBus.shared.chinese
        button.title = chinese ? "中" : "EN"
        button.toolTip = chinese ? "TyInput 中文" : "TyInput 英文"
        let menu = InputBus.shared.makeMenu(target: self, action: #selector(toggleMode(_:)))
        status?.menu = menu
    }
}

let connectionName = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String ?? "TyInput_Connection"
let server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
_ = LexiconStore.shared
if server == nil {
    NSLog("[TyInput] IMKServer 创建失败")
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
