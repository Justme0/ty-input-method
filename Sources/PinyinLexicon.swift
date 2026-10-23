import Foundation

struct Choice: Equatable {
    var text: String
    var consumed: Int
    var freq: Int
    var lookahead: Bool
}

final class PinyinLexicon {
    static let empty = PinyinLexicon(syllables: [], chars: [:], root: Node())

    let syllableCount: Int
    private let syllables: Set<String>
    private let allSyllables: [String]
    private let extendable: Set<String>
    private let chars: [String: [(String, Int)]]
    private let root: Node

    final class Node {
        var children: [String: Node] = [:]
        var words: [(String, Int)] = []
    }

    private init(syllables: Set<String>, chars: [String: [(String, Int)]], root: Node) {
        let list = syllables.sorted()
        var extendable = Set<String>()
        for syllable in list where list.contains(where: { $0.count > syllable.count && $0.hasPrefix(syllable) }) {
            extendable.insert(syllable)
        }
        self.syllables = syllables
        self.allSyllables = list
        self.extendable = extendable
        self.chars = chars
        self.root = root
        self.syllableCount = syllables.count
    }

    convenience init(contentsOf url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var syllables = Set<String>()
        var chars: [String: [(String, Int)]] = [:]
        let root = Node()

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }
            let kind = cols[0]
            let key = String(cols[1])
            let payload = cols[2]
            let items = PinyinLexicon.parseItems(payload)
            if kind == "C" {
                syllables.insert(key)
                chars[key] = items.sorted { $0.1 > $1.1 }
            } else if kind == "W" {
                let parts = key.split(separator: " ").map(String.init)
                guard !parts.isEmpty else { continue }
                for part in parts { syllables.insert(part) }
                var node = root
                for part in parts {
                    if node.children[part] == nil { node.children[part] = Node() }
                    node = node.children[part]!
                }
                node.words.append(contentsOf: items)
                node.words.sort { $0.1 > $1.1 }
                if node.words.count > 24 {
                    node.words = Array(node.words.prefix(24))
                }
            }
        }
        self.init(syllables: syllables, chars: chars, root: root)
    }

    static func loadFromBundle() -> PinyinLexicon {
        guard let url = Bundle.main.url(forResource: "pinyin", withExtension: "dict") else {
            NSLog("[TyInput] 没有找到词库 pinyin.dict")
            return .empty
        }
        do {
            let lexicon = try PinyinLexicon(contentsOf: url)
            NSLog("[TyInput] 词库已加载，音节 %d", lexicon.syllableCount)
            return lexicon
        } catch {
            NSLog("[TyInput] 词库读取失败 %@", String(describing: error))
            return .empty
        }
    }

    func candidates(for raw: String, limit: Int = 90) -> [Choice] {
        let code = raw.lowercased()
        let parses = analyze(code)
        if parses.isEmpty { return [] }

        var best: [String: Choice] = [:]
        func add(_ text: String, _ consumed: Int, _ freq: Int, lookahead: Bool) {
            guard !text.isEmpty, consumed > 0 else { return }
            let choice = Choice(text: text, consumed: min(consumed, code.count), freq: freq, lookahead: lookahead)
            if let old = best[text] {
                let betterSpan = choice.consumed > old.consumed
                let sameSpan = choice.consumed == old.consumed
                let betterKind = sameSpan && old.lookahead && !choice.lookahead
                let betterFreq = sameSpan && old.lookahead == choice.lookahead && choice.freq > old.freq
                if betterSpan || betterKind || betterFreq {
                    best[text] = choice
                }
            } else {
                best[text] = choice
            }
        }

        let ranked = parses.sorted { lhs, rhs in
            let lFull = lhs.partial.isEmpty ? 1 : 0
            let rFull = rhs.partial.isEmpty ? 1 : 0
            if lFull != rFull { return lFull > rFull }
            let lEnd = lhs.ends.last ?? 0
            let rEnd = rhs.ends.last ?? 0
            if lEnd != rEnd { return lEnd > rEnd }
            let lScore = lhs.syllables.reduce(0) { $0 + $1.count }
            let rScore = rhs.syllables.reduce(0) { $0 + $1.count }
            return lScore > rScore
        }

        for (index, parse) in ranked.enumerated() {
            let allowLookahead = index == 0
            addParse(parse, rawCount: code.count, lookahead: allowLookahead, add: add)
        }
        return order(Array(best.values), limit: limit)
    }

    private func addParse(_ parse: Parse, rawCount: Int, lookahead: Bool, add: (String, Int, Int, Bool) -> Void) {
        var node = root
        var walkedAll = true
        for (index, syllable) in parse.syllables.enumerated() {
            if index == 0 {
                for (text, freq) in chars[syllable] ?? [] {
                    add(text, parse.ends[index], freq, false)
                }
            }
            guard let next = node.children[syllable] else {
                walkedAll = false
                break
            }
            node = next
            for (text, freq) in node.words {
                add(text, parse.ends[index], freq, false)
            }
        }

        if parse.syllables.isEmpty && !parse.partial.isEmpty {
            var bag: [(String, Int)] = []
            for syllable in allSyllables where syllable.hasPrefix(parse.partial) {
                bag.append(contentsOf: (chars[syllable] ?? []).prefix(6))
            }
            bag.sort { $0.1 > $1.1 }
            var seen = Set<String>()
            var kept = 0
            for (text, freq) in bag where seen.insert(text).inserted {
                add(text, rawCount, freq, false)
                kept += 1
                if kept >= 48 { break }
            }
            return
        }

        if parse.partial.isEmpty,
           parse.syllables.count >= 2,
           let last = parse.syllables.last,
           extendable.contains(last),
           let parent = walk(Array(parse.syllables.dropLast())) {
            for (key, child) in parent.children where key.count > last.count && key.hasPrefix(last) {
                for (text, freq) in child.words.prefix(8) {
                    add(text, rawCount, freq, false)
                }
            }
        }

        guard lookahead, walkedAll else { return }
        if parse.partial.isEmpty {
            for child in node.children.values {
                for (text, freq) in child.words.prefix(2) {
                    add(text, rawCount, freq, true)
                }
            }
        } else if node.children.isEmpty == false {
            for (key, child) in node.children where key.hasPrefix(parse.partial) {
                for (text, freq) in child.words.prefix(8) {
                    add(text, rawCount, freq, false)
                }
            }
        }
    }

    private func walk(_ parts: [String]) -> Node? {
        var node = root
        for part in parts {
            guard let next = node.children[part] else { return nil }
            node = next
        }
        return node
    }

    private func order(_ items: [Choice], limit: Int) -> [Choice] {
        guard !items.isEmpty else { return [] }
        let maxConsumed = items.map(\.consumed).max() ?? 0
        let top = items
            .filter { $0.consumed == maxConsumed && !$0.lookahead }
            .sorted { lhs, rhs in
                if lhs.freq != rhs.freq { return lhs.freq > rhs.freq }
                return lhs.text < rhs.text
            }
        let ahead = items
            .filter(\.lookahead)
            .sorted { lhs, rhs in
                if lhs.freq != rhs.freq { return lhs.freq > rhs.freq }
                return lhs.text < rhs.text
            }
        var seen = Set<String>()
        var result: [Choice] = []
        func push(_ choice: Choice) {
            if seen.insert(choice.text).inserted {
                result.append(choice)
            }
        }
        if let first = top.first {
            push(first)
            for choice in ahead.prefix(6) { push(choice) }
            for choice in top.dropFirst() { push(choice) }
        } else {
            for choice in ahead.prefix(8) { push(choice) }
        }
        let rest = items
            .filter { !seen.contains($0.text) }
            .sorted { lhs, rhs in
                if lhs.consumed != rhs.consumed { return lhs.consumed > rhs.consumed }
                if lhs.lookahead != rhs.lookahead { return !lhs.lookahead && rhs.lookahead }
                if lhs.freq != rhs.freq { return lhs.freq > rhs.freq }
                return lhs.text < rhs.text
            }
        for choice in rest { push(choice) }
        if result.count > limit {
            return Array(result.prefix(limit))
        }
        return result
    }

    private struct Parse {
        var syllables: [String]
        var partial: String
        var ends: [Int]
    }

    private func analyze(_ raw: String) -> [Parse] {
        let chars = Array(raw)
        let count = chars.count
        if count == 0 || count > 40 { return [] }

        struct State {
            var index: Int
            var syllables: [String]
            var ends: [Int]
            var score: Int
        }

        var queue = [State(index: 0, syllables: [], ends: [], score: 0)]
        var found: [Parse] = []
        var steps = 0

        while !queue.isEmpty && steps < 80 && found.count < 8 {
            queue.sort { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.index > rhs.index
            }
            let state = queue.removeFirst()
            steps += 1
            var index = state.index
            while index < count && chars[index] == "'" { index += 1 }
            if index >= count {
                found.append(Parse(syllables: state.syllables, partial: "", ends: state.ends))
                continue
            }

            var matched = false
            let maxLen = min(6, count - index)
            if maxLen >= 1 {
                for len in stride(from: maxLen, through: 1, by: -1) {
                    let syllable = String(chars[index..<(index + len)])
                    guard syllables.contains(syllable) else { continue }
                    matched = true
                    var end = index + len
                    if end < count && chars[end] == "'" { end += 1 }
                    var next = state
                    next.index = end
                    next.syllables.append(syllable)
                    next.ends.append(end)
                    next.score += len * 10
                    queue.append(next)
                }
            }
            if !matched {
                let rest = String(chars[index...])
                if isPartial(rest) {
                    found.append(Parse(syllables: state.syllables, partial: rest, ends: state.ends))
                }
            }
            if queue.count > 24 {
                queue.sort { $0.score > $1.score }
                queue = Array(queue.prefix(24))
            }
        }

        var seen = Set<String>()
        var unique: [Parse] = []
        for parse in found {
            let key = parse.syllables.joined(separator: " ") + "|" + parse.partial
            if seen.insert(key).inserted {
                unique.append(parse)
            }
        }
        return unique
    }

    private func isPartial(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 6 else { return false }
        for ch in text {
            if ch < "a" || ch > "z" { return false }
        }
        return allSyllables.contains { $0.hasPrefix(text) }
    }

    private static func parseItems(_ payload: Substring) -> [(String, Int)] {
        var items: [(String, Int)] = []
        for piece in payload.split(separator: " ") {
            guard let colon = piece.firstIndex(of: ":") else { continue }
            let freq = Int(piece[..<colon]) ?? 0
            let text = String(piece[piece.index(after: colon)...])
            if !text.isEmpty {
                items.append((text, freq))
            }
        }
        return items
    }
}
