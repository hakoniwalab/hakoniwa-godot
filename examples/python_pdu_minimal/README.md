# Godot + Python Minimal PDU Example

この example は、`HakoniwaSimNode` を使って **Godot と Python が `std_msgs/UInt64` を双方向にやり取りする最小構成**です。

## 何が分かるか

- `HakoniwaSimNode` を 1 つ置けば internal SHM endpoint を持てる
- Godot 側は `simulation_step` で `send_message()` できる
- Godot 側は `create_subscription_message()` で Python からの受信を扱える
- Python 側は `hakopy + PduManager` で PDU を読む / 書く

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

## 起動手順

```bash
# terminal 1
bash tools/run_core_pro_conductor.sh

# terminal 2
bash tools/run_python_pdu_minimal_controller.sh

# terminal 3
<GODOT_BIN> --headless --path examples/python_pdu_minimal
```

Python 側には `config/comm/pdu_def.json` を渡します。  
Godot 側には `config/endpoint_shm_with_pdu.json` を使います。

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
HAKO_PYTHON_PDU_MINIMAL_PY_REGISTER_RECV_EVENT:0
HAKO_PYTHON_PDU_MINIMAL_PY_SEND:1:...
HAKO_PYTHON_PDU_MINIMAL_PY_RECV:1:...
HAKO_PYTHON_PDU_MINIMAL_PY_OK
```
