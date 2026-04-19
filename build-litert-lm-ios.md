# LiteRT-LM iOS ビルド手順

LiteRT-LM を iOS 向けにビルドして Xcode プロジェクトに組み込む手順。

## 前提条件

| ツール | 確認コマンド |
|---|---|
| Bazelisk | `bazelisk version` |
| Xcode (フルインストール) | `xcodebuild -version` |
| git-lfs | `git lfs version` |

Xcode は CLT (Command Line Tools) ではなく、フル版が必要。

```bash
sudo xcode-select -s /Applications/Xcode-*.app/Contents/Developer
```

---

## Step 1: リポジトリ準備

```bash
git clone https://github.com/google-ai-edge/LiteRT-LM.git
cd LiteRT-LM
git checkout v0.10.1       # 最新安定版
git lfs checkout           # GPU 用プリビルドバイナリ取得（CPU のみなら不要）
```

---

## Step 2: ダミーバイナリターゲットを追加

`c/BUILD` の末尾に以下を追加する（Rust クレートを含む完全リンクを強制するため）。

```python
# Temporary: force full link to collect all transitive archives including Rust
cc_binary(
    name = "litert_lm_ios_link",
    srcs = ["ios_main.cc"],
    deps = [":engine_cpu"],
)
```

`c/ios_main.cc` を作成：

```cpp
#include "c/engine.h"
int main() {
    litert_lm_set_min_log_level(3);
    return 0;
}
```

---

## Step 3: Bazel ビルド

デバイス (arm64) とシミュレータ (arm64) の両方をビルドする。

```bash
# iOS デバイス向け
bazelisk build //c:litert_lm_ios_link --config=ios_arm64

# iOS シミュレータ向け
bazelisk build //c:litert_lm_ios_link --config=ios_sim_arm64
```

初回は 30〜60 分程度かかる。

### なぜ `engine_cpu` ではなく `litert_lm_ios_link` か

`cc_library` ターゲット (`//c:engine_cpu`) をビルドしただけでは Rust クレート（minijinja、tokenizers、llguidance など）がコンパイルされない。`cc_binary` ターゲットをビルドすることで完全なリンク処理が走り、全 Rust アーカイブが生成される。

---

## Step 4: 静的ライブラリ作成

リンクパラメータファイルから全アーカイブ（Rust 含む）を抽出して結合する。

```bash
EXECROOT=/private/var/tmp/_bazel_$(whoami)/$(ls /private/var/tmp/_bazel_$(whoami))/execroot/litert_lm

# デバイス用
grep -E '\.(a|lo|o)$' \
  "$EXECROOT/bazel-out/ios_arm64-opt/bin/c/litert_lm_ios_link-2.params" \
  | sed 's|-Wl,-force_load,||g' \
  | sed "s|^bazel-out|$EXECROOT/bazel-out|" \
  | grep -v "ios_main.o" \
  > /tmp/arm64_archives.txt

libtool -static -filelist /tmp/arm64_archives.txt \
  -o LiteRTLM_arm64.a 2>&1 | grep -v "warning:"

# シミュレータ用
grep -E '\.(a|lo|o)$' \
  "$EXECROOT/bazel-out/ios_sim_arm64-opt/bin/c/litert_lm_ios_link-2.params" \
  | sed 's|-Wl,-force_load,||g' \
  | sed "s|^bazel-out|$EXECROOT/bazel-out|" \
  | grep -v "ios_main.o" \
  > /tmp/sim_archives.txt

libtool -static -filelist /tmp/sim_archives.txt \
  -o LiteRTLM_sim_arm64.a 2>&1 | grep -v "warning:"
```

期待サイズ: デバイス用 ~280MB、シミュレータ用 ~282MB（Rust クレート込み）。

---

## Step 5: XCFramework 作成

### LiteRTLM.xcframework（静的ライブラリ）

`engine.h` を Headers ディレクトリに用意してから XCFramework 化する。

```bash
mkdir -p LiteRTLM/Headers
cp /path/to/LiteRT-LM/c/engine.h LiteRTLM/Headers/

xcodebuild -create-xcframework \
  -library LiteRTLM_arm64.a     -headers LiteRTLM/Headers \
  -library LiteRTLM_sim_arm64.a -headers LiteRTLM/Headers \
  -output LiteRTLM/LiteRTLM.xcframework
```

### GemmaModelConstraintProvider.xcframework（dylib ラッパー）

プリビルドの dylib を framework にラップしてから XCFramework 化する。

```bash
for ARCH in ios_arm64 ios_sim_arm64; do
  PLATFORM=$( [ "$ARCH" = "ios_arm64" ] && echo "iPhoneOS" || echo "iPhoneSimulator" )
  DIR=$( [ "$ARCH" = "ios_arm64" ] && echo "device" || echo "simulator" )
  mkdir -p "LiteRTLM/$DIR/GemmaModelConstraintProvider.framework"
  cp "prebuilt/$ARCH/libGemmaModelConstraintProvider.dylib" \
     "LiteRTLM/$DIR/GemmaModelConstraintProvider.framework/GemmaModelConstraintProvider"
  cat > "LiteRTLM/$DIR/GemmaModelConstraintProvider.framework/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>GemmaModelConstraintProvider</string>
  <key>CFBundleIdentifier</key><string>com.google.litert.GemmaModelConstraintProvider</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleExecutable</key><string>GemmaModelConstraintProvider</string>
  <key>MinimumOSVersion</key><string>13.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$PLATFORM</string></array>
</dict>
</plist>
EOF
done

xcodebuild -create-xcframework \
  -framework LiteRTLM/device/GemmaModelConstraintProvider.framework \
  -framework LiteRTLM/simulator/GemmaModelConstraintProvider.framework \
  -output LiteRTLM/GemmaModelConstraintProvider.xcframework
```

---

## Step 6: Xcode プロジェクト設定

### ファイル配置

```
Gemma4Demo/Gemma4Demo/LiteRTLM/
├── LiteRTLM.xcframework/
├── GemmaModelConstraintProvider.xcframework/
├── LiteRTLM_arm64.a          # force_load 用
└── LiteRTLM_sim_arm64.a      # force_load 用
```

### Build Settings

| 設定 | 値 |
|---|---|
| Swift Objective-C Bridging Header | `Gemma4Demo/Gemma4Demo-Bridging-Header.h` |
| Header Search Paths | `$(SRCROOT)/Gemma4Demo/LiteRTLM/LiteRTLM.xcframework/ios-arm64/Headers` |
| Other Linker Flags (iphoneos) | `-lc++ -force_load $(SRCROOT)/Gemma4Demo/LiteRTLM/LiteRTLM_arm64.a` |
| Other Linker Flags (iphonesimulator) | `-lc++ -force_load $(SRCROOT)/Gemma4Demo/LiteRTLM/LiteRTLM_sim_arm64.a` |

### Frameworks, Libraries の追加

- `LiteRTLM.xcframework` (Do Not Embed)
- `GemmaModelConstraintProvider.xcframework` (Embed & Sign, Weak)
- `AVFoundation.framework`
- `AudioToolbox.framework`

### Bridging Header

```objc
// Gemma4Demo-Bridging-Header.h
#import "engine.h"
```

---

## Step 7: モデルファイルの配置

`.litertlm` ファイルをアプリの Documents ディレクトリに配置する。

**Info.plist に追加（iTunes File Sharing 有効化）:**

```xml
<key>UIFileSharingEnabled</key><true/>
<key>LSSupportsOpeningDocumentsInPlace</key><true/>
```

配置方法:
- **シミュレータ**: Finder からシミュレータアプリの Documents フォルダへドラッグ
- **実機**: Files アプリ経由でアプリの On My iPhone > Gemma4Demo フォルダへコピー

---

## 既知の問題・注意点

### 1. `-force_load` が必須（Tips 7-1）

LiteRT-LM は CPU/GPU エグゼキュータを静的イニシャライザで登録している。リンカの最適化で削除されると実行時に `Engine type not found: 1` エラーが出る。`-force_load` で全シンボルを強制インクルードすること。

### 2. 推論スレッドのスタックサイズ（Tips 7-3）

LiteRT-LM の推論はデフォルトのスレッドスタック（512KB〜1MB）では不足して `EXC_BAD_ACCESS` クラッシュが起きる。推論を実行するスレッドは **16MB** 以上のスタックを確保すること。

```swift
let thread = Thread { /* inference */ }
thread.stackSize = 16 * 1024 * 1024
thread.start()
```

### 3. GPU サポート（現状）

`prebuilt/ios_arm64/` には `libGemmaModelConstraintProvider.dylib` のみ。GPU 実行に必要な Metal Sampler dylib やその他プリビルドは v0.10.1 時点で未提供（issue #1050）。CPU バックエンドのみ動作する。

### 4. パフォーマンス目安

Gemma 4 E2B-it モデル（CPU）:
- iPhone: 約 9〜10 tokens/sec
- メモリ: 約 961MB

---

## 参考

- [Zenn 記事: Gemma 4 E4B-it を iOS で動かす](https://zenn.dev/yoshitetsu/articles/ac05dc4a71650d)
- [LiteRT-LM リリース](https://github.com/google-ai-edge/LiteRT-LM/releases)
- [LiteRT-LM C API リファレンス](https://github.com/google-ai-edge/LiteRT-LM/blob/main/c/engine.h)
