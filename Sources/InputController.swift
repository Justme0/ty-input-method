import Cocoa
import InputMethodKit

extension KeyEvent {
    init(_ event: NSEvent) {
        let flags = event.modifierFlags
        let kind: KeyEvent.Kind = event.type == .flagsChanged ? .flagsChanged : .keyDown
        self.init(
            kind: kind,
            keyCode: event.keyCode,
            base: (event.charactersIgnoringModifiers ?? "").lowercased(),
            typed: event.characters ?? "",
            shift: flags.contains(.shift),
            control: flags.contains(.control),
            option: flags.contains(.option),
            command: flags.contains(.command),
            capsLock: flags.contains(.capsLock)
        )
    }
}

@objc(TyInputController)
class TyInputController: IMKInputController {
    private let composer: Composer

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        composer = Composer(lexicon: LexiconStore.shared)
        composer.isChinese = InputBus.shared.chinese
        super.init(server: server, delegate: delegate, client: inputClient)
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        let mask = NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue
        return Int(mask)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }
        if event.type != .keyDown && event.type != .flagsChanged { return false }
        guard let target = currentClient(sender) else { return false }
        let result = composer.handle(KeyEvent(event))
        return render(result, client: target)
    }

    override func commitComposition(_ sender: Any!) {
        guard let target = currentClient(sender) else { return }
        _ = render(composer.commitBestOrRaw(), client: target)
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        composer.isChinese = InputBus.shared.chinese
        InputBus.shared.active = self
    }

    override func deactivateServer(_ sender: Any!) {
        if !composer.raw.isEmpty, let target = currentClient(sender) {
            _ = render(composer.commitBestOrRaw(), client: target)
        }
        CandidatePanel.shared.hide()
        if InputBus.shared.active === self {
            InputBus.shared.active = nil
        }
        super.deactivateServer(sender)
    }

    override func hidePalettes() {
        CandidatePanel.shared.hide()
        super.hidePalettes()
    }

    override func inputControllerWillClose() {
        CandidatePanel.shared.hide()
        super.inputControllerWillClose()
    }

    override func menu() -> NSMenu! {
        InputBus.shared.makeMenu(target: self, action: #selector(menuToggle(_:)))
    }

    @objc func menuToggle(_ sender: Any?) {
        InputBus.shared.toggleFromUI()
    }

    func setChinese(_ chinese: Bool) {
        guard let target = currentClient(nil) else {
            composer.isChinese = chinese
            _ = composer.setMode(chinese: chinese)
            return
        }
        _ = render(composer.setMode(chinese: chinese), client: target)
    }

    func pick(_ index: Int) {
        guard let target = currentClient(nil) else { return }
        _ = render(composer.select(pageIndex: index), client: target)
    }

    private func currentClient(_ sender: Any!) -> (any IMKTextInput)? {
        if let existing = client() { return existing }
        return sender as? any IMKTextInput
    }

    @discardableResult
    private func render(_ result: HandleResult, client: any IMKTextInput) -> Bool {
        switch result {
        case .pass(let clear):
            if clear {
                setMarked("", client: client)
                CandidatePanel.shared.hide()
            }
            return false
        case .update(let snap):
            if !snap.commit.isEmpty {
                client.insertText(snap.commit as NSString, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            }
            if snap.marked.isEmpty {
                setMarked("", client: client)
                CandidatePanel.shared.hide()
            } else {
                setMarked(snap.marked, client: client)
                if snap.candidates.isEmpty {
                    CandidatePanel.shared.hide()
                } else {
                    let caret = client.firstRect(
                        forCharacterRange: NSRange(location: NSNotFound, length: NSNotFound),
                        actualRange: nil
                    )
                    CandidatePanel.shared.show(
                        candidates: snap.candidates,
                        highlight: snap.highlight,
                        page: snap.page,
                        pageCount: snap.pageCount,
                        caret: caret
                    )
                }
            }
            InputBus.shared.chinese = snap.isChinese
            InputBus.shared.refresh()
            return true
        }
    }

    private func setMarked(_ text: String, client: any IMKTextInput) {
        let attr = NSAttributedString(string: text, attributes: [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        let length = (text as NSString).length
        client.setMarkedText(
            attr,
            selectionRange: NSRange(location: length, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
    }
}
