# API Sequences

## 目的

利用者が API の呼び出し順を誤らないように、代表的な利用シーケンスを示す。

## この文書に含める内容

- 初期化シーケンス
- 接続開始シーケンス
- `latest` モード利用シーケンス
- `queue` モード利用シーケンス
- 停止と破棄のシーケンス
- エラー時の分岐

## 初期シーケンス案

### 起動

```text
create
  -> configure
  -> start
  -> poll
  -> stop
```

### latest

```text
configure(mode=latest)
  -> start
  -> poll_latest
  -> poll_latest
  -> stop
```

### queue

```text
configure(mode=queue)
  -> start
  -> poll_next
  -> poll_next
  -> stop
```
