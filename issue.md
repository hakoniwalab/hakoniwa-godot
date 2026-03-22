# Issue

## 背景

このプロジェクトの目的は、`hakoniwa-godot` を Godot 用パッケージとして整備し、第三者が導入して使える形まで持っていくことです。

最初のスコープは `hakoniwa-pdu-endpoint` の統合に限定し、Godot から外部シミュレーションの状態を受信できるところまでを完成対象にします。

## 目標

以下を満たす最小プロダクトを作ること。

1. Godot プロジェクトへ組み込めるパッケージ構成になっている
2. `hakoniwa-pdu-endpoint` を使って PDU を受信できる
3. `latest` / `queue` の両モードを Godot から利用できる
4. サンプルとドキュメントを見れば第三者が導入できる
5. ビルド方法と対応環境が明確である

## 今回の完成定義

`hakoniwa-pdu-endpoint` について、以下が成立していることを完成とみなします。

1. GDExtension としてビルドできる
2. Godot から endpoint の生成、接続、受信、終了ができる
3. `latest` / `queue` の API 方針が定まり、実装されている
4. 最低 1 つのサンプルシーンで受信結果を確認できる
5. 導入手順が README と `docs/` に整理されている

今回の区切りは、箱庭 endpoint として **バイナリデータを Godot へ送受信できるところまで** とする。

PDU payload を Godot 利用者向けの型へ decode する層は、このマイルストーンの対象外とする。

## スコープ

### 対象

- Godot 向け native extension の土台
- `hakoniwa-pdu-endpoint` のラップ
- Godot 側 API 設計
- 受信データの取り扱いモデル
- サンプル、最低限のテスト、導入ドキュメント

### 対象外

- `hakoniwa-core-pro` の時間同期統合
- `hakoniwa-pdu-rpc` の操作系 API
- 高度なエディタ統合
- 複数プラットフォーム向け最適化の完了

## 解くべき課題

### 1. 配布形態が未定

Godot パッケージとして誰でも使える形にするには、配布単位を明確にする必要があります。

候補:

- addon として配布する
- native library と GDScript ラッパを同梱する
- examples / docs / binaries の分離方針を決める
- OS / architecture ごとの artifact 分割方針を決める

### 2. Godot API が未設計

`hakoniwa-pdu-endpoint` の機能を、そのまま露出するのではなく、Godot 利用者にとって自然な API に整理する必要があります。

論点:

- Node ベースにするか Resource ベースにするか
- poll 型にするか signal 型にするか
- `latest` / `queue` をどう表現するか
- データを `Dictionary` で返すか、型付きクラスにするか
- バイナリ payload の decode 層をどこで持つか

### 3. ネイティブ実装境界が未整理

どこまでを C++ GDExtension 側で持ち、どこからを Godot スクリプト層で扱うかを決める必要があります。

### 4. サンプルと検証方法が未整備

ユーザーが使える状態にするには、最小の接続例と検証手順が必要です。

### 5. ドキュメント構造が未整備

README、設計、導入、開発メモの役割分担を固定する必要があります。

### 6. バイナリ payload の扱い

現時点の API は `PackedByteArray` ベースで成立しているが、一般利用者向けには decode 層が必要になる。

ただし、この課題は今回の区切りでは解かない。

今回のスコープでは、まず以下を成立させる。

- endpoint の open / start / stop
- `latest` / `queue` の送受信
- `set_recv_event()` / `get_pending_count()`
- Godot でのバイナリ payload 受け渡し

将来課題:

- `PackedByteArray` を Godot の値へ decode する helper
- PDU definition に応じた自動 decode
- 利用者向け typed wrapper / codec 層

### 7. message layer の配布とロード方式

箱庭が扱う全メッセージを 1 つの Godot パッケージに同梱すると、サイズ、保守性、利用者体験の面で重くなりやすい。

そのため、message decode 層は本体から分離する必要がある。

現時点の有力案:

- `hakoniwa-godot` 本体は endpoint runtime に責務を絞る
- message package ごとに shared library plugin を分ける
- 生成済み `GDScript` typed classes は message layer 側に置く
- 必要な package だけを選択的に導入する

技術論点:

- plugin 境界の C ABI
- macOS / Linux / Windows の loader 抽象化
- package 単位の命名規則
- plugin 未導入時の raw fallback

### 8. platform ごとの配布

addon は論理的には 1 つでも、native binary を含むため配布物は platform ごとに分離する必要がある。

論点:

- macOS / Ubuntu / Windows のどこから先に official artifact を出すか
- `arm64` / `x86_64` をどう切るか
- 本体 binary と codec plugin 群を同じ artifact に含めるか
- source build と binary release のどちらを正本とするか

## 成果物

- `issue.md`: 何を解くか
- `task.md`: 何をどの順で進めるか
- `docs/architecture.md`: 全体構成
- `docs/pdu_endpoint_design.md`: endpoint の設計
- `docs/packaging_strategy.md`: Godot パッケージ化方針
- `docs/installation.md`: 導入手順
- `docs/api_overview.md`: API 全体像
- `docs/api_reference.md`: API 仕様
- `docs/api_sequences.md`: API 利用シーケンス

## 利用者向けドキュメント要件

第三者が使える状態にするため、以下の利用者向け情報を整備対象に含める。

### 1. API の明確化

どのクラスを入口として、何ができて、どのモードをどう使い分けるのかが一目で分かること。

### 2. 導入手順

必要な前提条件、取得方法、ビルド方法、Godot への組み込み方法、初回確認手順が分かること。

### 3. API 仕様

各クラス、メソッド、引数、戻り値、エラー条件、前提状態が参照できること。

### 4. API 利用シーケンス

初期化、接続、開始、受信、停止までの呼び出し順が分かること。

## 当面の判断

現時点では、まず `hakoniwa-pdu-endpoint` を成立させることを優先し、時間同期と RPC は設計で触れるだけに留めます。

次の設計段階では、`hakoniwa-pdu-registry` の Godot 向け生成物を前提に、message layer を本体から分離した構成を検討する。
