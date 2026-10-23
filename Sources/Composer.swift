import Foundation

struct KeyEvent: Equatable {
    enum Kind: Equatable {
        case keyDown
        case flagsChanged
    }

    var kind: Kind
    var keyCode: UInt16
    var base: String
    var typed: String
    var shift: Bool
    var control: Bool
    var option: Bool
    var command: Bool
    var capsLock: Bool
}

struct InputSnapshot: Equatable {
    var isChinese: Bool
    var commit: String
    var marked: String
    var candidates: [String]
    var highlight: Int
    var page: Int
    var pageCount: Int
}

enum HandleResult: Equatable {
    case pass(clear: Bool)
    case update(InputSnapshot)
}

final class Composer {
    let pageSize = 9
    let lexicon: PinyinLexicon

    var isChinese = true
    private(set) var raw = ""
    private var choices: [Choice] = []
    private var page = 0
    private var highlight = 0
    private var shiftHeld = false
    private var shiftUsedForText = false
    private var doubleQuoteOpen = true
    private var singleQuoteOpen = true

    init(lexicon: PinyinLexicon) {
        self.lexicon = lexicon
    }

    var candidateTexts: [String] { choices.map(\.text) }

    func handle(_ event: KeyEvent) -> HandleResult {
        if event.kind == .flagsChanged {
            return handleFlags(event)
        }
        guard isChinese else { return .pass(clear: false) }
        if event.command || event.control || event.option {
            return passClearingComposition()
        }
        if event.keyCode == 51 || event.typed == "\u{7f}" {
            return backspace()
        }
        if event.keyCode == 117 {
            guard !raw.isEmpty else { return .pass(clear: false) }
            clear()
            return .update(snapshot())
        }
        if event.keyCode == 53 {
            guard !raw.isEmpty else { return .pass(clear: false) }
            clear()
            return .update(snapshot())
        }
        if event.keyCode == 36 || event.keyCode == 76 || event.typed == "\r" || event.typed == "\n" {
            guard !raw.isEmpty else { return .pass(clear: false) }
            return .update(commitRaw())
        }
        if event.keyCode == 49 || event.typed == " " || event.base == " " {
            return space()
        }
        if isArrow(event) {
            guard !raw.isEmpty else { return .pass(clear: false) }
            let delta = (event.keyCode == 123 || event.keyCode == 126) ? -1 : 1
            move(delta)
            return .update(snapshot())
        }
        if event.keyCode == 48 {
            guard !raw.isEmpty else { return .pass(clear: false) }
            return page(by: event.shift ? -1 : 1)
        }
        if !raw.isEmpty, let index = digitIndex(event) {
            return select(pageIndex: index)
        }
        if isPageKey(event), !raw.isEmpty, pageCount > 1 {
            let next = event.typed == "=" || event.typed == "]" || event.base == "=" || event.base == "]"
            return page(by: next ? 1 : -1)
        }
        if event.base.count == 1, let ch = event.base.first, ch >= "a", ch <= "z" {
            return letter(ch, event)
        }
        if event.typed == "'" && !event.shift {
            return apostrophe()
        }
        if let punct = punctuation(for: event) {
            if raw.isEmpty {
                return .update(snapshot(commit: punct))
            }
            return .update(commitConverted(and: punct))
        }
        return .pass(clear: false)
    }

    func setMode(chinese: Bool) -> HandleResult {
        isChinese = chinese
        clear()
        return .update(snapshot())
    }

    func commitBestOrRaw() -> HandleResult {
        guard !raw.isEmpty else { return .update(snapshot()) }
        if let best = choices.filter({ !$0.lookahead && $0.consumed == raw.count }).max(by: { $0.freq < $1.freq }) {
            return .update(commitChoice(best))
        }
        return .update(commitRaw())
    }

    func select(pageIndex: Int) -> HandleResult {
        let index = page * pageSize + pageIndex
        guard index >= 0, index < choices.count else { return .update(snapshot()) }
        return .update(commitChoice(choices[index]))
    }

    private func handleFlags(_ event: KeyEvent) -> HandleResult {
        let isShift = event.keyCode == 56 || event.keyCode == 60
        guard isShift else { return .pass(clear: false) }
        if event.shift {
            shiftHeld = true
            shiftUsedForText = false
            return .pass(clear: false)
        }
        if shiftHeld {
            shiftHeld = false
            if !shiftUsedForText && !event.command && !event.option && !event.control {
                isChinese.toggle()
                clear()
                return .update(snapshot())
            }
        }
        return .pass(clear: false)
    }

    private func letter(_ ch: Character, _ event: KeyEvent) -> HandleResult {
        if event.capsLock && raw.isEmpty {
            return .pass(clear: false)
        }
        if event.shift && raw.isEmpty {
            shiftUsedForText = true
            return .pass(clear: false)
        }
        if event.shift {
            shiftUsedForText = true
        }
        guard raw.count < 40 else { return .update(snapshot()) }
        raw.append(ch)
        rebuild()
        return .update(snapshot())
    }

    private func apostrophe() -> HandleResult {
        if raw.isEmpty {
            return .update(snapshot(commit: nextSingleQuote()))
        }
        if raw.last != "'" {
            raw.append("'")
            rebuild()
        }
        return .update(snapshot())
    }

    private func space() -> HandleResult {
        guard !raw.isEmpty else { return .pass(clear: false) }
        if let choice = selectedChoice {
            return .update(commitChoice(choice))
        }
        return .update(commitRaw(extra: " "))
    }

    private func backspace() -> HandleResult {
        guard !raw.isEmpty else { return .pass(clear: false) }
        raw.removeLast()
        rebuild()
        return .update(snapshot())
    }

    private func page(by delta: Int) -> HandleResult {
        guard !raw.isEmpty else { return .pass(clear: false) }
        let pages = pageCount
        guard pages > 1 else { return .update(snapshot()) }
        page = min(max(0, page + delta), pages - 1)
        highlight = 0
        return .update(snapshot())
    }

    private func move(_ delta: Int) {
        guard !choices.isEmpty else { return }
        var index = page * pageSize + highlight + delta
        index = min(max(0, index), choices.count - 1)
        page = index / pageSize
        highlight = index % pageSize
    }

    private func passClearingComposition() -> HandleResult {
        if raw.isEmpty { return .pass(clear: false) }
        clear()
        return .pass(clear: true)
    }

    private func commitChoice(_ choice: Choice) -> InputSnapshot {
        let text = choice.text
        let count = min(choice.consumed, raw.count)
        raw.removeFirst(count)
        while raw.first == "'" { raw.removeFirst() }
        rebuild()
        return snapshot(commit: text)
    }

    private func commitRaw(extra: String = "") -> InputSnapshot {
        let text = raw + extra
        clear()
        return snapshot(commit: text)
    }

    private func commitConverted(and suffix: String) -> InputSnapshot {
        let body: String
        if let best = choices.filter({ !$0.lookahead && $0.consumed == raw.count }).max(by: { $0.freq < $1.freq }) {
            body = best.text
        } else if let choice = selectedChoice {
            let rest = raw.dropFirst(min(choice.consumed, raw.count)).replacingOccurrences(of: "'", with: "")
            body = choice.text + rest
        } else {
            body = raw
        }
        clear()
        return snapshot(commit: body + suffix)
    }

    private func punctuation(for event: KeyEvent) -> String? {
        let typed = event.typed
        if typed == "\"" { return nextDoubleQuote() }
        let table: [String: String] = [
            ",": "，",
            ".": "。",
            "?": "？",
            "!": "！",
            ":": "：",
            ";": "；",
            "(": "（",
            ")": "）",
            "[": "【",
            "]": "】",
            "{": "｛",
            "}": "｝",
            "<": "《",
            ">": "》",
            "/": "、",
            "\\": "、",
            "`": "·",
            "~": "～",
            "$": "￥",
            "^": "……",
            "_": "——",
        ]
        if let mapped = table[typed] { return mapped }
        if typed == "-" || typed == "=" || typed == "+" { return typed }
        return nil
    }

    private func nextDoubleQuote() -> String {
        let text = doubleQuoteOpen ? "“" : "”"
        doubleQuoteOpen.toggle()
        return text
    }

    private func nextSingleQuote() -> String {
        let text = singleQuoteOpen ? "‘" : "’"
        singleQuoteOpen.toggle()
        return text
    }

    private func digitIndex(_ event: KeyEvent) -> Int? {
        let source = event.typed.isEmpty ? event.base : event.typed
        guard source.count == 1, let value = Int(source), (1...9).contains(value) else { return nil }
        return value - 1
    }

    private func isArrow(_ event: KeyEvent) -> Bool {
        (123...126).contains(Int(event.keyCode))
    }

    private func isPageKey(_ event: KeyEvent) -> Bool {
        if event.shift { return false }
        return event.typed == "-" || event.typed == "=" || event.typed == "[" || event.typed == "]"
            || event.base == "-" || event.base == "=" || event.base == "[" || event.base == "]"
    }

    private var pageCount: Int {
        guard !choices.isEmpty else { return 0 }
        return (choices.count + pageSize - 1) / pageSize
    }

    private var selectedChoice: Choice? {
        let index = page * pageSize + highlight
        guard index >= 0, index < choices.count else { return nil }
        return choices[index]
    }

    private var markedText: String {
        guard !raw.isEmpty else { return "" }
        guard let choice = selectedChoice else { return raw }
        let rest = raw.dropFirst(min(choice.consumed, raw.count))
        return choice.text + rest
    }

    private func rebuild() {
        if raw.isEmpty {
            choices = []
            page = 0
            highlight = 0
            return
        }
        choices = lexicon.candidates(for: raw)
        page = 0
        highlight = 0
    }

    private func clear() {
        raw = ""
        choices = []
        page = 0
        highlight = 0
    }

    private func snapshot(commit: String = "") -> InputSnapshot {
        normalizePage()
        let pages = pageCount
        let start = page * pageSize
        let visible = pages == 0 ? [] : Array(choices.dropFirst(start).prefix(pageSize))
        return InputSnapshot(
            isChinese: isChinese,
            commit: commit,
            marked: markedText,
            candidates: visible.map(\.text),
            highlight: visible.isEmpty ? 0 : highlight,
            page: pages == 0 ? 0 : page,
            pageCount: pages
        )
    }

    private func normalizePage() {
        let pages = pageCount
        if pages == 0 {
            page = 0
            highlight = 0
            return
        }
        if page >= pages { page = pages - 1 }
        if page < 0 { page = 0 }
        let onPage = min(pageSize, choices.count - page * pageSize)
        if highlight >= onPage { highlight = max(0, onPage - 1) }
        if highlight < 0 { highlight = 0 }
    }
}
