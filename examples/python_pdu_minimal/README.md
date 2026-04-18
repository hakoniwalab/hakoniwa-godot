# Godot + Python Minimal PDU Example

このディレクトリには、`HakoniwaSimNode` を使って **Godot と Python が `std_msgs/UInt64` を双方向にやり取りする最小素材**を置きます。

含まれるもの:

- `sample.gd`
  - Godot 側の最小 script
- `python_controller.py`
  - Python 側の最小 controller
- `python_sample.py`
  - `sample.gd` 相当の Python peer
- `config/`
  - PDU 定義と endpoint 設定
  - Godot 側と Python 側で別々の SHM poll config を使う

## 何が分かるか

- `HakoniwaSimNode` を 1 つ置けば internal SHM endpoint を持てる
- Godot 側は `simulation_step` で `send_message()` できる
- Godot 側は `create_subscription_message()` で Python からの受信を扱える
- Python 側は `hakopy + Endpoint` で PDU を読む / 書く

## 使う PDU

- `godot_to_python`
  - `std_msgs/UInt64`
- `python_to_godot`
  - `std_msgs/UInt64`

## 前提

最低限 `std_msgs` codec が必要です。

```bash
cmake -S . -B build -DHAKONIWA_GODOT_CODEC_PACKAGES="std_msgs"
cmake --build build -j4
```

`std_msgs` 以外もまとめて揃えたい場合は、代わりにこれでも構いません。

```bash
bash tools/build_all_codecs.sh
```

Python 側は `hakopy` と `hakoniwa-pdu-endpoint` が installer 済みである前提です。

- `hakopy`
  - 箱庭 core との接続に使う
- `hakoniwa-pdu-endpoint`
  - PDU 通信に使う

`hakoniwa-pdu-endpoint` は installer のインストール先に Python package と native library 一式が入っている前提で、`python_controller.py` は repo 内 `third_party/` を直接参照しません。

## Godot 側の internal endpoint 設定

`Use Internal Shm Endpoint` を有効化する場合、`Internal Endpoint Codec Packages` に internal endpoint で使う package 名を設定します。

この example では `std_msgs/UInt64` だけを使うので、設定値は次の 1 つです。

```text
std_msgs
```

コードで設定する場合の例:

```gdscript
_sim.internal_endpoint_codec_packages = PackedStringArray([
	"std_msgs"
])
```

複数の message type を internal endpoint で使う場合は、必要な package 名を配列に追加します。

## 使い方

1. 既存 Godot project に `HakoniwaSimNode` を置く
2. scene の root node に [sample.gd](sample.gd) 相当の script を attach する
3. `config/` を project 側へコピーする
4. `HakoniwaSimNode` に次を設定する
   - `Use Internal Shm Endpoint = On`
   - `Shm Endpoint Config Path = res://config/endpoint_shm_with_pdu.json`
   - `Internal Endpoint Codec Packages = ["std_msgs"]`
5. Python 側では [python_controller.py](python_controller.py) を使う
6. Python 側の起動引数には [endpoint_shm_with_pdu_python.json](config/endpoint_shm_with_pdu_python.json) を渡す

## 起動手順

```bash
# terminal 1
bash tools/run_core_pro_conductor.sh

# terminal 2
python python_controller.py config/endpoint_shm_with_pdu_python.json

# terminal 3
<GODOT_BIN> --path /path/to/your_godot_project
```

Python 側には `config/endpoint_shm_with_pdu_python.json` を渡します。  
Godot 側には `config/endpoint_shm_with_pdu.json` を使います。  
この example 自体は repo 内の完成済み Godot project ではなく、既存 project に持ち込む素材として扱います。

## Python 同士で閉じる確認

Godot を介さず、まず Python 側だけで相互通信を確認したい場合は `python_sample.py` を使います。

```bash
# terminal 1
bash tools/run_core_pro_conductor.sh

# terminal 2
bash tools/run_python_pdu_minimal_controller.sh

# terminal 3
bash tools/run_python_pdu_minimal_peer.sh
```

成功時の目印:

- controller 側: `HAKO_PYTHON_PDU_MINIMAL_PY_OK`
- peer 側: `HAKO_PYTHON_PDU_MINIMAL_PEER_OK`

## 成功時ログ

Godot:

```text
HAKO_PYTHON_PDU_MINIMAL_GODOT_READY
HAKO_PYTHON_PDU_MINIMAL_GODOT_START_FEEDBACK_OK
HAKO_PYTHON_PDU_MINIMAL_GODOT_SEND:1:...
HAKO_PYTHON_PDU_MINIMAL_GODOT_RECV:1:...
HAKO_PYTHON_PDU_MINIMAL_GODOT_OK
```

Python:

```text
HAKO_PYTHON_PDU_MINIMAL_PY_ENDPOINT_READY
HAKO_PYTHON_PDU_MINIMAL_PY_SEND:1:...
HAKO_PYTHON_PDU_MINIMAL_PY_RECV:1:...
HAKO_PYTHON_PDU_MINIMAL_PY_OK
```
