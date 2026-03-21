# 📦 hakoniwa-godot

(以下の方向性で、現在開発中..)

## 🧠 What is hakoniwa-godot?

**hakoniwa-godot** は、
Godot Engine を
箱庭（Hakoniwa）と接続するための統合パッケージです。

ゲームエンジンを単なる可視化ツールとしてではなく、
**分散シミュレーションの一部として動作させる** ことを目的としています。

---

## 🎯 What you can do

* 外部シミュレーションと Godot を接続
* リアルタイムに状態を受信・表示
* 外部システムへ操作（RPC）を送信
* 箱庭の時刻同期に従って動作

---

## 🧩 Architecture Overview

hakoniwa-godot は、以下の3つのコア機能で構成されています。

### ⏱ 1. hakoniwa-core-pro（時間）

箱庭の時刻同期機構。
Godot を外部シミュレーションと同じ時間軸で動作させます。

---

### 📡 2. hakoniwa-pdu-endpoint（状態）

PDUベースのデータ通信。

* latest（最新値のみ取得）
* queue（履歴を順次取得）

👉 用途に応じて選択可能

---

### ⚙️ 3. hakoniwa-pdu-rpc（操作）

RPC通信により、

* 外部システムの制御
* 状態取得リクエスト

を行います。

---

## 🧠 Concept

```text
時間（Time）
＋
状態（State）
＋
操作（Control）
```

この3つにより、Godotは単なる描画エンジンではなく、

> **箱庭に接続された1つの実行ノード**

として動作します。

---

## 🚀 Quick Start

### 1. Clone

```bash
git clone --recursive https://github.com/hakoniwalab/hakoniwa-godot.git
cd hakoniwa-godot
```

---

### 2. Build Native Extension

```bash
cmake -B build
cmake --build build
```

---

### 3. Run Godot

```bash
godot project/
```

---

### 4. Observe

* 外部シミュレーションの状態が反映される
* Godotから操作可能

---

## 🔁 Data Handling Modes

### Latest Mode

```text
最新の状態のみ取得
```

* 可視化
* UI更新
* 軽量処理

---

### Queue Mode

```text
全イベントを順次処理
```

* 状態遷移
* ログ処理
* 制御

---

## 🧠 Godot Integration Model

Godotのフレームループと連携します。

| Godot Loop           | 推奨モード  |
| -------------------- | ------ |
| `_process()`         | latest |
| `_physics_process()` | queue  |

---

## 📦 Repository Structure

```text
hakoniwa-godot/
├─ godot/           # Godot project
├─ native/          # GDExtension (C++)
├─ third_party/
│  ├─ hakoniwa-core-pro
│  ├─ hakoniwa-pdu-endpoint
│  └─ hakoniwa-pdu-rpc
├─ examples/
└─ docs/
```

---

## 🎮 Example

* Godot上でドローンの状態を表示
* 外部制御プログラムと連携
* 分散シミュレーションの可視化

---

## 🧭 Target Users

* ロボット / ドローン研究者
* シミュレーション開発者
* Godotユーザーで外部連携したい人

---

## 💡 Why hakoniwa?

> **シミュレータはある。でも、つながらない。**

hakoniwa はその問題を解決します。

---

## 🔗 Related Projects

* [hakoniwa-core-pro](https://github.com/hakoniwalab/hakoniwa-core-pro)
* [hakoniwa-pdu-endpoint](https://github.com/hakoniwalab/hakoniwa-pdu-endpoint)
* [hakoniwa-pdu-rpc](https://github.com/hakoniwalab/hakoniwa-pdu-rpc)

---

## ✨ Summary

> **hakoniwa-godot = Godotを箱庭に接続する最小構成**

