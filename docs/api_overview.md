# API Overview

## 目的

利用者が `hakoniwa-godot` の入口 API を短時間で理解できるようにする。

## この文書に含める内容

- 公開クラスの一覧
- 各クラスの責務
- `latest` / `queue` の使い分け
- 利用開始までの最短パス
- 典型的な利用パターン

## 初期方針

最初の公開 API は最小限に抑える。

候補:

- `HakoniwaPduEndpoint`

このクラスを入口にして、設定、開始、受信、停止が完結する形を基本とする。

## 利用形態

`HakoniwaPduEndpoint` は Godot の `Node` として提供する。

利用者は以下のどちらかの形で使う。

1. シーンに `HakoniwaPduEndpoint` ノードを配置する
2. スクリプトから `HakoniwaPduEndpoint` を生成する

このクラスは、Godot アプリケーションにおける「外部通信専用ノード」として扱う。

## 基本責務

`HakoniwaPduEndpoint` の責務は以下とする。

- endpoint の生成と破棄
- config に基づく open / close
- start / stop
- `process_recv_events()` の呼び出し
- `recv()` / `recv_next()` 相当の pull API 提供

Godot オブジェクト更新そのものは、このノードの責務ではない。

受信結果をどう各ゲームオブジェクトへ反映するかは、利用者側のスクリプトまたは上位ノードが行う。

## 利用者から見た最小パターン

```text
Node を作る
  -> config を設定する
  -> start する
  -> 毎フレーム process_recv_events する
  -> 必要に応じて recv / recv_next する
  -> stop / close する
```

## 複数インスタンス方針

`HakoniwaPduEndpoint` は複数インスタンス可能とする。

基本単位は以下。

```text
1 Node = 1 native endpoint handle
```

したがって、以下のような構成を許可する。

- 1 つの endpoint をアプリ全体で共有する
- transport ごとに endpoint を分ける
- mode ごとに endpoint を分ける
- scene ごとに endpoint を分ける

例:

- WebSocket 用 endpoint
- SHM 用 endpoint
- `latest` 用 endpoint
- `queue` 用 endpoint

## 1アプリに1個だけ置くべきか

単純な用途では 1 アプリに 1 個でもよい。

ただし、この制約を API 側で強制しない。

理由:

- transport が異なる endpoint を分離したいケースがある
- 受信モードを分けたいケースがある
- シーン構成や責務分離の単位で分けたいケースがある

## 通信時の基本制約

Godot 向け統合では、以下を基本制約とする。

### 1. 受信は pull 型を基本にする

Godot 側の主 API は callback 主体ではなく、利用者が明示的に呼ぶ pull API とする。

理由:

- Godot の main loop に揃えやすい
- transport ごとの callback タイミング差を隠蔽できる
- `hakoniwa-pdu-endpoint` の設計方針と一致する

### 2. `process_recv_events()` を main loop から呼べるようにする

特に SHM poll 系では、`process_recv_events()` が受信進行に必要になる。

そのため、利用者は `_process()` または `_physics_process()` からこれを呼べる必要がある。

### 3. 別スレッド callback から直接 Godot オブジェクトを触らない

native 側で callback が発火しうるとしても、Godot の scene tree や Node を直接更新する API にはしない。

Godot 側の更新は、caller-controlled なタイミングで行う。

## 推奨利用モデル

初期実装では、以下を推奨利用モデルとする。

- 初期化は `_ready()`
- 定期処理は `_process()` または `_physics_process()`
- 終了処理は `_exit_tree()`

## Node ライフサイクル対応

Godot 利用者が迷わないように、`HakoniwaPduEndpoint` は以下のライフサイクル対応を前提に設計する。

### `_ready()`

- endpoint を `open(...)` する
- 必要なら `set_recv_event(...)` を設定する
- `start()` する
- transport に応じて `post_start()` を呼ぶ余地を残す

### `_process()` または `_physics_process()`

- `process_recv_events()` を呼ぶ
- `recv_by_name(...)` または `recv_next()` を呼ぶ
- 受信した結果を上位ノードへ渡す

### `_exit_tree()`

- `stop()` する
- `close()` する

## 利用者コードの責務

利用者コードは以下を担当する。

- どのフレームループで endpoint を回すか決める
- どの key を読むか決める
- 受信した `Dictionary` や `PackedByteArray` をアプリ側の型へ変換する
- シーン内の各 Node に結果を反映する

`HakoniwaPduEndpoint` 自体は通信ノードであり、ゲームロジックや表示更新を持たない。

## 利用者は endpoint をどう取得するか

Godot 利用者は、通常の Node 参照と同じ方法で `HakoniwaPduEndpoint` を取得する。

想定する取得パターンは以下。

### 1. 同一シーン内の Node を直接参照する

もっとも単純な形。

```gdscript
@onready var endpoint = $HakoniwaPduEndpoint
```

または:

```gdscript
@onready var endpoint = get_node("HakoniwaPduEndpoint")
```

### 2. 親ノードまたは manager ノードから受け取る

責務分離をしたい場合は、endpoint の所有者と利用者を分ける。

```gdscript
var endpoint: HakoniwaPduEndpoint

func setup(ep: HakoniwaPduEndpoint) -> void:
	endpoint = ep
```

この形では、上位ノードが endpoint の open / start / stop を管理する。

### 3. アプリ全体の共有 endpoint として参照する

アプリ全体で 1 個の endpoint を共有したい場合は、Autoload または共有 manager ノード経由で参照する。

この場合でも、API 上は単なる `HakoniwaPduEndpoint` 参照として扱う。

## 利用者はどう送受信するか

利用者は、取得した `HakoniwaPduEndpoint` 参照に対してメソッドを呼ぶ。

### 受信

受信の基本形:

```gdscript
func _process(delta: float) -> void:
	endpoint.process_recv_events()

	while endpoint.get_pending_count() > 0:
		var record = endpoint.recv_next()
		if record.is_empty():
			break
		print(record)
```

最新値を読む形:

```gdscript
func _process(delta: float) -> void:
	endpoint.process_recv_events()
	var value = endpoint.recv_by_name("drone0", "pose")
	if not value.is_empty():
		print(value)
```

### 送信

送信 API を追加した後は、以下のように利用する。

```gdscript
func send_command(payload: PackedByteArray) -> void:
	endpoint.send_by_name("drone0", "cmd_vel", payload)
```

## 所有者と利用者を分ける方針

設計上は、endpoint を生成・開始する Node と、実際に送受信を利用する Node を分けてもよい。

推奨方針:

- endpoint の所有者が `open / start / stop / close` を担当する
- 利用者 Node は endpoint 参照を受け取って `send / recv` を使う

これにより、複数 Node が同じ endpoint を安全に共有しやすくなる。

## 将来の拡張

将来的に signal ベースの convenience API を追加する可能性はある。

ただし、それは pull 型 API の上に載る補助機能として扱う。
