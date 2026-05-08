# GPU (Metal) バックエンド 現状まとめ

**最終更新: 2026-05-07 / LiteRT-LM v0.11.0 / LiteRTLMSwift 0.2.0**

---

## 結論

`gemma-4-E2B-it.litertlm` (HuggingFace: litert-community/gemma-4-E2B-it-litert-lm) は
**iOS Metal GPU バックエンドに未対応**。iPhone 17 Pro でも同様。

現時点では **CPU バックエンドを使用すること**。

```swift
let engine = try LiteRTLMEngine(modelPath: path, backend: .cpu)
```

---

## 詳細

### モデルファイルの構造（.litertlm 内部）

| section | type | サイズ | backend constraint |
|---|---|---|---|
| 9 | `tf_lite_prefill_decode` | **6 KB** | なし（GPU 向けのはず） |
| 10 | `tf_lite_mtp_drafter` | 818 MB | **cpu** |
| 11 | (unknown) | 44 MB | — |

`tf_lite_prefill_decode` が 6KB しかなく、GPU 向けウェイトが実質的に含まれていない。
Qualcomm 専用モデル（SM8750/QCS8275）は別ファイルとして提供されているが、
Apple Metal (iOS/macOS) 専用ファイルは現時点で未提供。

### エラーログ

```
Failed to create DelegateKernelLiteRtMetal: UNKNOWN: Failed to allocate id<MTLTexture>.
  third_party/ml_drift/metal/metal_spatial_tensor.mm:459
  ...
Failed to create engine: INTERNAL:
```

2つ目の Metal サブグラフ（31 external tensors）で Metal テクスチャの確保に失敗する。
デバイスメモリ不足ではなく、GPU 向けウェイトが存在しないことが原因。

### LiteRTLMSwift の動作

`backend: .gpu` 指定時の挙動（`LiteRTLMEngine.swift`）:

1. `enable_speculative_decoding: true` でエンジン作成を試みる
2. 失敗した場合、`enable_speculative_decoding: false` でリトライ
3. それでも失敗した場合、`LiteRTError.engineCreationFailed` をスロー

GPU が使えない場合は呼び出し側で `engineCreationFailed` を捕捉し、
`backend: .cpu` で再初期化する。

```swift
do {
    engine = try LiteRTLMEngine(modelPath: path, backend: .gpu)
} catch LiteRTLMEngine.LiteRTError.engineCreationFailed {
    engine = try LiteRTLMEngine(modelPath: path, backend: .cpu)
}
```

---

## 今後の対応

- litert-community が Apple Metal 向けモデルファイルを提供した時点で GPU 対応を検証する
- 参考: [litert-community/gemma-4-E2B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm)
- Qualcomm 向けと同様に、Apple チップ専用 `.litertlm` が公開されれば動作する見込み
