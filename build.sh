#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"
BUILD="$ROOT/build"
mkdir -p "$BUILD"

if [[ ! -f "$ROOT/Resources/pinyin.dict" || "${REGEN:-0}" == "1" ]]; then
  python3 "$ROOT/scripts/gen_dict.py" \
    --chars "${PINYIN_CHARS:-/tmp/pinyin_chars.txt}" \
    --phrases "${PINYIN_PHRASES:-/tmp/pinyin_phrases.txt}" \
    --freq "${JIEBA_DICT:-/tmp/jieba_dict.txt}" \
    --out "$ROOT/Resources/pinyin.dict"
fi

TARGET="arm64-apple-macosx13.0"

swiftc -target "$TARGET" -framework Cocoa -o "$BUILD/makeicon" "$ROOT/scripts/makeicon.swift"
"$BUILD/makeicon" "$BUILD/icon.png"

swiftc -target "$TARGET" -g -o "$BUILD/tyinput-tests" \
  "$ROOT/Sources/PinyinLexicon.swift" \
  "$ROOT/Sources/Composer.swift" \
  "$ROOT/Tests/main.swift"
"$BUILD/tyinput-tests" "$ROOT/Resources/pinyin.dict"

swiftc -target "$TARGET" -O -module-name TyInput \
  -framework Cocoa -framework InputMethodKit \
  -o "$BUILD/TyInput" \
  "$ROOT/Sources/PinyinLexicon.swift" \
  "$ROOT/Sources/Composer.swift" \
  "$ROOT/Sources/CandidatePanel.swift" \
  "$ROOT/Sources/InputController.swift" \
  "$ROOT/Sources/main.swift"

APP="$BUILD/TyInput.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/zh-Hans.lproj"
cp "$BUILD/TyInput" "$APP/Contents/MacOS/TyInput"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/pinyin.dict" "$APP/Contents/Resources/pinyin.dict"
cp "$BUILD/icon.png" "$APP/Contents/Resources/icon.png"
python3 - "$ROOT/Resources/zh-Hans.lproj/InfoPlist.strings" "$APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings" << 'PY'
import pathlib, sys
src, dst = sys.argv[1], sys.argv[2]
pathlib.Path(dst).write_bytes(pathlib.Path(src).read_text(encoding="utf-8").encode("utf-16"))
PY
chmod +x "$APP/Contents/MacOS/TyInput"
codesign --force --sign - --identifier com.tyinput.inputmethod "$APP"
echo "已构建 $APP"
