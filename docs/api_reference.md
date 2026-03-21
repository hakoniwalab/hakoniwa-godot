# API Reference

## 目的

公開 API の仕様を、実装と対応づけて参照できるようにする。

## この文書に含める内容

- クラス名
- メソッド名
- 引数
- 戻り値
- 前提条件
- エラー条件
- モード別の挙動

## 初期対象

### `HakoniwaPduEndpoint`

想定している記載対象:

- `configure(config: Dictionary) -> void`
- `start() -> int`
- `stop() -> void`
- `poll_latest(key: String = "") -> Variant`
- `poll_next() -> Variant`
- `is_running() -> bool`

実装開始後は、この文書を API の正本として更新する。
