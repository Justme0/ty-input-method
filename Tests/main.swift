import Foundation

let dictPath = CommandLine.arguments.dropFirst().first ?? "Resources/pinyin.dict"
let lexicon: PinyinLexicon
do {
    lexicon = try PinyinLexicon(contentsOf: URL(fileURLWithPath: dictPath))
} catch {
    fputs("无法读取词库 \(dictPath): \(error)\n", stderr)
    exit(1)
}

var failed = 0

func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    if condition {
        print("通过  \(name)")
    } else {
        failed += 1
        print("失败  \(name) \(detail)")
    }
}

func key(
    _ typed: String,
    code: UInt16 = 0,
    shift: Bool = false,
    command: Bool = false,
    caps: Bool = false,
    kind: KeyEvent.Kind = .keyDown
) -> KeyEvent {
    KeyEvent(
        kind: kind,
        keyCode: code,
        base: typed.lowercased(),
        typed: typed,
        shift: shift,
        control: false,
        option: false,
        command: command,
        capsLock: caps
    )
}

final class Harness {
    let composer: Composer
    var text = ""
    var marked = ""
    var candidates: [String] = []
    var page = 0
    var pageCount = 0
    var isChinese = true

    init() {
        composer = Composer(lexicon: lexicon)
    }

    func apply(_ event: KeyEvent) {
        switch composer.handle(event) {
        case .pass(let clear):
            if clear {
                marked = ""
                candidates = []
                page = 0
                pageCount = 0
            }
            if event.kind == .keyDown && !event.command && !event.control && !event.option {
                text += event.typed
            }
        case .update(let snap):
            text += snap.commit
            marked = snap.marked
            candidates = snap.candidates
            page = snap.page
            pageCount = snap.pageCount
            isChinese = snap.isChinese
        }
    }

    func type(_ string: String) {
        for character in string {
            if character == " " {
                space()
            } else if character == "\n" {
                enter()
            } else {
                apply(key(String(character)))
            }
        }
    }

    func space() { apply(key(" ", code: 49)) }
    func enter() { apply(key("\r", code: 36)) }
    func backspace() { apply(key("", code: 51)) }
    func escape() { apply(key("", code: 53)) }
    func right() { apply(key("", code: 124)) }
    func shiftDown() { apply(key("", code: 56, shift: true, kind: .flagsChanged)) }
    func shiftUp() { apply(key("", code: 56, shift: false, kind: .flagsChanged)) }

    var all: [String] { composer.candidateTexts }
}

check("词库有拼音音节", lexicon.syllableCount > 100, "syllables=\(lexicon.syllableCount)")

do {
    let h = Harness()
    h.type("nihao")
    check("nihao 首选是你好", h.candidates.first == "你好", "candidates=\(h.candidates.prefix(8)) marked=\(h.marked)")
    check("nihao 候选里有你", h.all.contains("你"), "all=\(h.all.prefix(12))")
    h.space()
    check("nihao 空格上屏你好", h.text == "你好" && h.marked.isEmpty, "text=\(h.text) marked=\(h.marked)")
}

do {
    let h = Harness()
    h.type("nihao")
    if h.candidates.count >= 2 {
        let second = h.candidates[1]
        h.type("2")
        check("数字键选择第二候选", h.text == second && h.marked.isEmpty, "second=\(second) text=\(h.text) marked=\(h.marked)")
    } else {
        check("nihao 至少两个候选", false, "\(h.candidates)")
    }
}

do {
    let h = Harness()
    h.type("nihao")
    h.right()
    let picked = h.candidates.dropFirst().first ?? ""
    h.space()
    check("方向键移动后空格", !picked.isEmpty && h.text == picked, "picked=\(picked) text=\(h.text)")
}

do {
    let h = Harness()
    h.type("niha")
    check("未输完的 niha 预测你好", h.candidates.first == "你好", "\(h.candidates.prefix(6))")
    h.space()
    check("niha 空格得到你好", h.text == "你好", h.text)
}

do {
    let h = Harness()
    h.type("zhongguo ")
    check("zhongguo 得到中国", h.text == "中国", h.text)
}

do {
    let h = Harness()
    h.type("wo ")
    check("wo 得到我", h.text == "我", "text=\(h.text) cands=\(h.all.prefix(6))")
}

do {
    let h = Harness()
    h.type("de ")
    check("de 得到的", h.text == "的", "text=\(h.text) cands=\(h.all.prefix(8))")
}

do {
    let h = Harness()
    h.type("ta")
    check("ta 首选他", h.candidates.first == "他", "\(h.candidates.prefix(8))")
    check("ta 候选包含她", h.all.contains("她"), "\(h.all.prefix(12))")
}

do {
    let h = Harness()
    h.type("xi'an ")
    check("xi'an 得到西安", h.text == "西安", "text=\(h.text) cands=\(h.all.prefix(8))")
}

do {
    let h = Harness()
    h.type("women ")
    check("women 得到我们", h.text == "我们", "text=\(h.text) cands=\(h.all.prefix(6))")
}

do {
    let h = Harness()
    h.type("shenme ")
    check("shenme 得到什么", h.text == "什么", "text=\(h.text) cands=\(h.all.prefix(6))")
}

do {
    let h = Harness()
    h.type("yige ")
    check("yige 得到一个", h.text == "一个", "text=\(h.text) cands=\(h.all.prefix(6))")
}

do {
    let h = Harness()
    h.type("beijing ")
    check("beijing 得到北京", h.text == "北京", "text=\(h.text) cands=\(h.all.prefix(6))")
}

do {
    let h = Harness()
    h.type("fangan")
    check("fangan 包含方案和反感", h.all.contains("方案") && h.all.contains("反感"), "\(h.all.prefix(15))")
    check("fangan 首选方案", h.candidates.first == "方案", "\(h.candidates.prefix(6))")
}

do {
    let h = Harness()
    h.type("nihao\n")
    check("回车上屏原始拼音", h.text == "nihao" && h.marked.isEmpty, h.text)
}

do {
    let h = Harness()
    h.type("hello ")
    check("英文单词加空格原样输出", h.text == "hello ", "text=[\(h.text)] cands=\(h.all.prefix(6))")
}

do {
    let h = Harness()
    h.type("nihao.")
    check("句号确认中文并带上标点", h.text == "你好。", "text=\(h.text) marked=\(h.marked)")
}

do {
    let h = Harness()
    h.type(",")
    check("中文逗号", h.text == "，", h.text)
}

do {
    let h = Harness()
    h.type("nihao")
    h.escape()
    check("Esc 取消编码", h.text.isEmpty && h.marked.isEmpty, "text=\(h.text) marked=\(h.marked)")
}

do {
    let h = Harness()
    h.type("nihao")
    h.backspace()
    check("退格后还在编码", !h.marked.isEmpty, "marked=\(h.marked) cands=\(h.candidates.prefix(4))")
    h.escape()
    check("退格后可以取消", h.marked.isEmpty, h.marked)
}

do {
    let h = Harness()
    h.type("de")
    let firstPage = h.candidates
    check("的 的候选超过一页", h.pageCount > 1, "count=\(h.all.count) pageCount=\(h.pageCount)")
    h.type("=")
    check("等号翻到下一页", h.page == 1 && h.candidates != firstPage, "page=\(h.page) \(h.candidates.prefix(4))")
    h.type("-")
    check("减号翻回上一页", h.page == 0 && h.candidates == firstPage, "page=\(h.page)")
}

do {
    let h = Harness()
    h.type("1")
    check("没有编码时数字直接上屏", h.text == "1", h.text)
}

do {
    let h = Harness()
    h.shiftDown()
    h.shiftUp()
    check("Shift 切换到英文", h.isChinese == false, "chinese=\(h.isChinese)")
    h.type("Abc,")
    check("英文模式直接输出", h.text == "Abc," && h.marked.isEmpty, "text=\(h.text) marked=\(h.marked)")
    h.shiftDown()
    h.shiftUp()
    check("再按 Shift 回到中文", h.isChinese == true, "chinese=\(h.isChinese)")
    h.type("ni ")
    check("回到中文后可以继续打字", h.text == "Abc,你", "text=\(h.text)")
}

do {
    let h = Harness()
    h.shiftDown()
    h.apply(KeyEvent(kind: .keyDown, keyCode: 0, base: "a", typed: "A", shift: true, control: false, option: false, command: false, capsLock: false))
    h.shiftUp()
    check("Shift+字母不切换模式", h.isChinese && h.text == "A", "chinese=\(h.isChinese) text=\(h.text)")
}

do {
    let h = Harness()
    h.apply(key("A", caps: true))
    check("大写锁定时直接输出英文", h.text == "A" && h.isChinese && h.marked.isEmpty, "text=\(h.text) marked=\(h.marked)")
}

do {
    let h = Harness()
    h.type("nihao")
    h.apply(key("c", command: true))
    check("快捷键取消未上屏编码", h.text.isEmpty && h.marked.isEmpty, "text=\(h.text) marked=\(h.marked)")
}

do {
    let h = Harness()
    h.type("nihao women ")
    check("连续上屏", h.text == "你好我们", h.text)
}

do {
    let h = Harness()
    h.type("zhongguo")
    switch h.composer.commitBestOrRaw() {
    case .update(let snap):
        check("离开输入框时提交首选", snap.commit == "中国" && snap.marked.isEmpty, "commit=\(snap.commit) marked=\(snap.marked)")
    case .pass:
        check("离开输入框时提交首选", false, "pass")
    }
}

do {
    let h = Harness()
    h.type("nihao")
    if let niIndex = h.all.firstIndex(of: "你") {
        let page = niIndex / 9
        let offset = niIndex % 9
        if page > 0 {
            for _ in 0..<page { h.type("=") }
        }
        h.type(String(offset + 1))
        check("选择你后继续 hao", h.text == "你" && (h.marked == "好" || h.marked.hasPrefix("好")), "text=\(h.text) marked=\(h.marked) page=\(page) offset=\(offset) all=\(h.all.prefix(20))")
        h.space()
        check("接着空格得到好", h.text == "你好", "text=\(h.text) marked=\(h.marked)")
    } else {
        check("可以单独选择你", false, "\(h.all.prefix(20))")
    }
}

if failed == 0 {
    print("全部通过")
    exit(0)
} else {
    print("失败 \(failed) 项")
    exit(1)
}
