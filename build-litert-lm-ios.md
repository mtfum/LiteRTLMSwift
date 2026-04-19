# LiteRT-LM ビルド手順

LiteRT-LM を iOS / macOS 向けにビルドして xcframework を作成する手順。

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

### iOS（arm64 + simulator）

```bash
bazelisk build //c:litert_lm_ios_link --config=ios_arm64
bazelisk build //c:litert_lm_ios_link --config=ios_sim_arm64
```

### macOS（arm64）

```bash
bazelisk build //c:litert_lm_ios_link --config=macos_arm64
```

> **Note**: macOS ビルドでは `--config=macos_arm64` を使用。`.bazelrc` で `cpu=darwin_arm64`, `macos_minimum_os=11.0` が設定されている。

初回は 30〜60 分程度かかる。

### なぜ `engine_cpu` ではなく `litert_lm_ios_link` か

`cc_library` ターゲット (`//c:engine_cpu`) をビルドしただけでは Rust クレート（minijinja、tokenizers、llguidance など）がコンパイルされない。`cc_binary` ターゲットをビルドすることで完全なリンク処理が走り、全 Rust アーカイブが生成される。

---

## Step 4: 静的ライブラリ作成

リンクパラメータファイルから全アーカイブ（Rust 含む）を抽出して結合する。

```bash
EXECROOT=/private/var/tmp/_bazel_$(whoami)/$(ls /private/var/tmp/_bazel_$(whoami))/execroot/litert_lm
```

### iOS デバイス用

```bash
grep -E '\.(a|lo|o)$' \
  "$EXECROOT/bazel-out/ios_arm64-opt/bin/c/litert_lm_ios_link-2.params" \
  | sed 's|-Wl,-force_load,||g' \
  | sed "s|^bazel-out|$EXECROOT/bazel-out|" \
  | grep -v "ios_main.o" \
  > /tmp/arm64_archives.txt

libtool -static -filelist /tmp/arm64_archives.txt \
  -o LiteRTLM_arm64.a 2>&1 | grep -v "warning:"
```

### iOS シミュレータ用

```bash
grep -E '\.(a|lo|o)$' \
  "$EXECROOT/bazel-out/ios_sim_arm64-opt/bin/c/litert_lm_ios_link-2.params" \
  | sed 's|-Wl,-force_load,||g' \
  | sed "s|^bazel-out|$EXECROOT/bazel-out|" \
  | grep -v "ios_main.o" \
  > /tmp/sim_archives.txt

libtool -static -filelist /tmp/sim_archives.txt \
  -o LiteRTLM_sim_arm64.a 2>&1 | grep -v "warning:"
```

### macOS arm64 用

```bash
grep -E '\.(a|lo|o)$' \
  "$EXECROOT/bazel-out/darwin_arm64-opt/bin/c/litert_lm_ios_link-2.params" \
  | sed 's|-Wl,-force_load,||g' \
  | sed "s|^bazel-out|$EXECROOT/bazel-out|" \
  | grep -v "ios_main.o" \
  > /tmp/macos_arm64_archives.txt

libtool -static -filelist /tmp/macos_arm64_archives.txt \
  -o LiteRTLM_macos_arm64.a 2>&1 | grep -v "warning:"
```

期待サイズ: 各アーキテクチャ ~280MB（Rust クレート込み）。

---

## Step 5: XCFramework 作成

`engine.h` を Headers ディレクトリに用意してから XCFramework 化する。

```bash
mkdir -p LiteRTLM/Headers
cp /path/to/LiteRT-LM/c/engine.h LiteRTLM/Headers/
```

### iOS のみ（0.1.0）

```bash
xcodebuild -create-xcframework \
  -library LiteRTLM_arm64.a     -headers LiteRTLM/Headers \
  -library LiteRTLM_sim_arm64.a -headers LiteRTLM/Headers \
  -output LiteRTLM.xcframework
```

### iOS + macOS（0.2.0）

```bash
xcodebuild -create-xcframework \
  -library LiteRTLM_arm64.a       -headers LiteRTLM/Headers \
  -library LiteRTLM_sim_arm64.a   -headers LiteRTLM/Headers \
  -library LiteRTLM_macos_arm64.a -headers LiteRTLM/Headers \
  -output LiteRTLM.xcframework
```

---

## Step 6: リリース作成

```bash
# zip 作成
zip -r LiteRTLM.xcframework.zip LiteRTLM.xcframework

# checksum 算出
swift package compute-checksum LiteRTLM.xcframework.zip

# GitHub Release 作成
gh release create <version> LiteRTLM.xcframework.zip \
  --title "<version>" \
  --notes "Based on LiteRT-LM v0.10.1"

# Package.swift の url と checksum を更新
```

---

## Xcode プロジェクト設定（利用者向け）

### Build Settings

| 設定 | 値 |
|---|---|
| Swift Objective-C Bridging Header | `YourApp/YourApp-Bridging-Header.h` |
| Header Search Paths | `$(BUILD_DIR)/../../SourcePackages/artifacts/litertmlswift/LiteRTLM/LiteRTLM.xcframework/ios-arm64/Headers` |
| Other Linker Flags (iphoneos) | `-lc++ -force_load $(BUILD_DIR)/../../SourcePackages/artifacts/litertmlswift/LiteRTLM/LiteRTLM.xcframework/ios-arm64/LiteRTLM_arm64.a` |
| Other Linker Flags (iphonesimulator) | `-lc++ -force_load $(BUILD_DIR)/../../SourcePackages/artifacts/litertmlswift/LiteRTLM/LiteRTLM.xcframework/ios-arm64-simulator/LiteRTLM_sim_arm64.a` |
| Other Linker Flags (macosx) | `-lc++ -force_load $(BUILD_DIR)/../../SourcePackages/artifacts/litertmlswift/LiteRTLM/LiteRTLM.xcframework/macos-arm64/LiteRTLM_macos_arm64.a` |

### Frameworks, Libraries の追加

- `LiteRTLM.xcframework` (Do Not Embed)
- `AVFoundation.framework`
- `AudioToolbox.framework`

### Bridging Header

```objc
// YourApp-Bridging-Header.h
#import "engine.h"
```

---

## 既知の問題・注意点

### 1. `-force_load` が必須

LiteRT-LM は CPU/GPU エグゼキュータを静的イニシャライザで登録している。リンカの最適化で削除されると実行時に `Engine type not found: 1` エラーが出る。`-force_load` で全シンボルを強制インクルードすること。

### 2. 推論スレッドのスタックサイズ

LiteRT-LM の推論はデフォルトのスレッドスタック（512KB〜1MB）では不足して `EXC_BAD_ACCESS` クラッシュが起きる。推論を実行するスレッドは **16MB** 以上のスタックを確保すること。

```swift
let thread = Thread { /* inference */ }
thread.stackSize = 16 * 1024 * 1024
thread.start()
```

### 3. GPU サポート（現状）

v0.10.1 時点で GPU 実行に必要な Metal Sampler dylib は未提供（issue #1050）。CPU バックエンドのみ動作する。

### 4. パフォーマンス目安

Gemma 4 E2B-it モデル（CPU）:
- iPhone: 約 9〜10 tokens/sec
- メモリ: 約 961MB

---

## 参考

- [Zenn 記事: Gemma 4 E4B-it を iOS で動かす](https://zenn.dev/yoshitetsu/articles/ac05dc4a71650d)
- [LiteRT-LM リリース](https://github.com/google-ai-edge/LiteRT-LM/releases)
- [LiteRT-LM C API リファレンス](https://github.com/google-ai-edge/LiteRT-LM/blob/main/c/engine.h)
