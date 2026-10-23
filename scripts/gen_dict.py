#!/usr/bin/env python3
"""Build a compact pinyin lexicon for TyInput.

Sources (MIT):
- mozillazg/pinyin-data          character readings
- mozillazg/phrase-pinyin-data   phrase readings
- fxsjy/jieba dict.txt           word frequency
"""

import argparse
import re
import sys
from collections import defaultdict

TONE = str.maketrans({
    "ā": "a", "á": "a", "ǎ": "a", "à": "a",
    "ō": "o", "ó": "o", "ǒ": "o", "ò": "o",
    "ē": "e", "é": "e", "ě": "e", "è": "e",
    "ī": "i", "í": "i", "ǐ": "i", "ì": "i",
    "ū": "u", "ú": "u", "ǔ": "u", "ù": "u",
    "ü": "v", "ǖ": "v", "ǘ": "v", "ǚ": "v", "ǜ": "v",
    "ń": "n", "ň": "n", "ǹ": "n",
    "ḿ": "m",
    "ê": "e",
})

# Daily words that must stay easy to type even if the frequency list underrates them.
PINNED = {
    "你好": 2_000_000_000,
    "您好": 1_900_000_000,
    "谢谢": 1_800_000_000,
    "我们": 1_800_000_000,
    "你们": 1_700_000_000,
    "他们": 1_700_000_000,
    "她们": 1_600_000_000,
    "什么": 1_800_000_000,
    "怎么": 1_700_000_000,
    "这个": 1_700_000_000,
    "那个": 1_600_000_000,
    "没有": 1_700_000_000,
    "知道": 1_600_000_000,
    "现在": 1_600_000_000,
    "可以": 1_600_000_000,
    "因为": 1_500_000_000,
    "所以": 1_500_000_000,
    "如果": 1_500_000_000,
    "但是": 1_500_000_000,
    "还是": 1_600_000_000,
    "自己": 1_500_000_000,
    "已经": 1_500_000_000,
    "时候": 1_400_000_000,
    "今天": 1_500_000_000,
    "明天": 1_400_000_000,
    "中国": 2_000_000_000,
    "北京": 1_800_000_000,
    "西安": 1_800_000_000,
    "一个": 1_800_000_000,
    "不是": 1_700_000_000,
    "方案": 1_200_000_000,
    "反感": 900_000_000,
    "你好吗": 1_200_000_000,
}

CHAR_RE = re.compile(r"^U\+[0-9A-Fa-f]+:\s*(.*?)\s+#\s*(\S+)")


def normalize_piece(raw):
    text = raw.strip().lower().translate(TONE)
    text = text.replace("ü", "v").replace("u:", "v")
    return re.sub(r"[^a-z]", "", text)


def is_cjk(ch):
    return 0x4E00 <= ord(ch) <= 0x9FFF


def is_cjk_word(word):
    return 2 <= len(word) <= 8 and all(is_cjk(ch) for ch in word)


def load_characters(path):
    """char -> [syllables], and syllable set."""
    readings = {}
    syllables = set()
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            match = CHAR_RE.match(line)
            if not match:
                continue
            char = match.group(2)
            if not is_cjk(char):
                continue
            pieces = []
            for part in match.group(1).split(","):
                syl = normalize_piece(part)
                if 1 <= len(syl) <= 6:
                    pieces.append(syl)
                    syllables.add(syl)
            if pieces:
                # Keep order, drop duplicates.
                seen = set()
                uniq = []
                for syl in pieces:
                    if syl not in seen:
                        seen.add(syl)
                        uniq.append(syl)
                readings[char] = uniq
    return readings, syllables


def load_phrases(path, syllables):
    phrases = {}
    skipped = 0
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#") or ":" not in line:
                continue
            word, py = line.split(":", 1)
            word = word.strip()
            if not is_cjk_word(word) and not (len(word) == 1 and is_cjk(word)):
                # Pinned words are at least 2 chars; still accept 2-8 only.
                if not is_cjk_word(word):
                    continue
            parts = [normalize_piece(p) for p in py.split()]
            if not parts or any(p not in syllables or not p for p in parts):
                skipped += 1
                continue
            phrases[word] = parts
    return phrases, skipped


def load_frequency(path):
    singles = {}
    words = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            parts = line.split()
            if len(parts) < 2:
                continue
            word, freq_s = parts[0], parts[1]
            try:
                freq = int(freq_s)
            except ValueError:
                continue
            if len(word) == 1 and is_cjk(word):
                singles[word] = max(singles.get(word, 0), freq)
            elif is_cjk_word(word):
                words.append((freq, word))
    words.sort(reverse=True)
    return singles, words


def syllables_for(word, phrases, readings):
    if word in phrases:
        return phrases[word]
    parts = []
    for ch in word:
        options = readings.get(ch)
        if not options:
            return None
        parts.append(options[0])
    return parts


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--chars", required=True)
    parser.add_argument("--phrases", required=True)
    parser.add_argument("--freq", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--max-words", type=int, default=60000)
    args = parser.parse_args()

    readings, syllables = load_characters(args.chars)
    phrases, skipped = load_phrases(args.phrases, syllables)
    singles, ranked_words = load_frequency(args.freq)
    print(f"chars={len(readings)} syllables={len(syllables)} phrases={len(phrases)} skipped_phrases={skipped} freq_words={len(ranked_words)}", file=sys.stderr)

    char_lists = defaultdict(dict)
    for char, syls in readings.items():
        freq = singles.get(char, 1)
        for syl in syls:
            bucket = char_lists[syl]
            bucket[char] = max(bucket.get(char, 0), freq)

    word_lists = defaultdict(dict)

    def add_word(word, freq):
        parts = syllables_for(word, phrases, readings)
        if not parts:
            return False
        if word in PINNED:
            freq = max(freq, PINNED[word])
        key = " ".join(parts)
        bucket = word_lists[key]
        bucket[word] = max(bucket.get(word, 0), freq)
        return True

    kept = 0
    for freq, word in ranked_words:
        if kept >= args.max_words:
            break
        if add_word(word, freq):
            kept += 1

    missing_pins = []
    for word, freq in PINNED.items():
        if not add_word(word, freq):
            missing_pins.append(word)
    if missing_pins:
        print("pinned words without pinyin:", " ".join(missing_pins), file=sys.stderr)

    with open(args.out, "w", encoding="utf-8") as out:
        out.write("# tyinput-dict 1\n")
        out.write("# Character readings: mozillazg/pinyin-data (MIT)\n")
        out.write("# Phrase readings: mozillazg/phrase-pinyin-data (MIT)\n")
        out.write("# Word frequency: fxsjy/jieba (MIT)\n")
        for syl in sorted(char_lists):
            items = sorted(char_lists[syl].items(), key=lambda kv: (-kv[1], kv[0]))[:40]
            payload = " ".join(f"{freq}:{text}" for text, freq in items)
            out.write(f"C\t{syl}\t{payload}\n")
        for key in sorted(word_lists):
            items = sorted(word_lists[key].items(), key=lambda kv: (-kv[1], kv[0]))
            pinned_here = [it for it in items if it[0] in PINNED]
            normal = [it for it in items if it[0] not in PINNED][:20]
            # Pinned entries sort by freq and are kept even if the cap would drop them.
            merged = {}
            for text, freq in pinned_here + normal:
                merged[text] = max(merged.get(text, 0), freq)
            ordered = sorted(merged.items(), key=lambda kv: (-kv[1], kv[0]))
            payload = " ".join(f"{freq}:{text}" for text, freq in ordered)
            out.write(f"W\t{key}\t{payload}\n")

    samples = ["ni hao", "zhong guo", "wo", "de", "xi an", "wo men", "shen me", "yi ge", "bei jing", "fang an", "fan gan", "ta", "ni"]
    print(f"wrote {args.out} words_kept={kept}", file=sys.stderr)
    for key in samples:
        if " " in key or key in word_lists or key in char_lists:
            words = sorted(word_lists.get(key, {}).items(), key=lambda kv: -kv[1])[:4]
            chars = sorted(char_lists.get(key, {}).items(), key=lambda kv: -kv[1])[:4]
            word_s = " ".join(w for w, _ in words)
            char_s = " ".join(c for c, _ in chars)
            print(f"  {key}: {word_s} | {char_s}")


if __name__ == "__main__":
    main()
