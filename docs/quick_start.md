# Quick Start

この文書は、**`hakoniwa-godot` の入口一覧**です。  
最初に何をしたいかに応じて、読むべき場所を分けます。

## 最初に選ぶ導線

### 1. `HakoniwaSimNode` を最小構成で動かしたい

- [../examples/simnode_minimal/README.md](../examples/simnode_minimal/README.md)

ここでは、`HakoniwaSimNode` を既存 Godot project に置いて、

- conductor を起動する
- Godot project を起動する
- `hako-cmd start` を実行する

という最小導線を扱います。

### 2. 既存 Godot project へ addon を導入したい

- [installation.md](installation.md)

ここでは、

- addon の配置
- plugin の有効化
- `HakoniwaSimNode` の配置
- 利用側 script の追加

を扱います。

### 3. Python と最小 PDU 通信を試したい

- [../examples/python_pdu_minimal/README.md](../examples/python_pdu_minimal/README.md)

### 4. smoke / integration test を回したい

- [../tests/README.md](../tests/README.md)
