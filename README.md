# iperf3 自動計測スクリプト

iperf3を使用して、複数のフローを同時に実行し、スループットと遅延を自動計測するスクリプト集です。

## 概要

このスクリプトは以下の機能を提供します：

- 3つのフローを同時に送信（ポート5201, 5202, 5203）
- 複数回の試行を自動実行（デフォルト10回）
- ウォームアップ期間の設定
- JSON形式での結果保存
- CSV形式での結果集計
- UDP/TCP両対応

## 必要条件

- Linux環境
- iperf3 (クライアント側)
- iperf3サーバー（宛先で3つのポートで待ち受け）
- jq (JSON解析用)
- bc (計算用)

### 依存パッケージのインストール

```bash
sudo apt install iperf3 jq bc
```

## ファイル構成

```
iperf3-client_scripts/
├── README.md                    # このファイル
├── run_evaluation_ver2.sh       # メイン計測スクリプト
├── send_iperf3.sh               # 単純な3フロー送信スクリプト
└── [結果ディレクトリ]/
    ├── result.csv               # 計測結果CSV
    ├── run1/
    │   ├── flow1.json           # フロー1のiperf3 JSON出力
    │   ├── flow2.json           # フロー2のiperf3 JSON出力
    │   └── flow3.json           # フロー3のiperf3 JSON出力
    ├── run2/
    │   └── ...
    └── run10/
        └── ...
```

## 使用方法

### 1. サーバー側の準備

宛先サーバーで3つのiperf3サーバーを起動：

```bash
iperf3 -s -p 5201 &
iperf3 -s -p 5202 &
iperf3 -s -p 5203 &
```

### 2. スクリプトの設定

`run_evaluation_ver2.sh`の設定項目を編集：

```bash
# 設定
TOTAL_RUNS=10           # 試行回数
INTERVAL=5              # 試行間隔（秒）
DURATION=300            # 計測時間（秒）
WARMUP=60               # ウォームアップ時間（秒）

# プロトコル設定 ("udp" or "tcp")
PROTOCOL="udp"

# 転送先IPアドレス
SERVER_IP="fd03:1::2"

# 結果保存先
RESULT_DIR="srv6_evaluation2_udp/trial1"
CSV_FILE="$RESULT_DIR/result.csv"
```

### 3. 実行

```bash
bash ./run_evaluation_ver2.sh
```

### 4. 中断

`Ctrl+C`で安全に停止できます。

## 出力形式

### CSV形式

```csv
run,flow1(50000)_sender,flow1(50000)_receiver,flow1(50000)_rtt,flow2(50001)_sender,flow2(50001)_receiver,flow2(50001)_rtt,flow3(50002)_sender,flow3(50002)_receiver,flow3(50002)_rtt
1,299.99,299.99,0.014,299.99,299.99,0.011,299.99,299.99,0.010
2,299.99,299.99,0.012,299.99,299.99,0.019,299.99,299.99,0.019
...
```

| 列名 | 説明 |
|------|------|
| run | 試行番号 |
| flowN_sender | 送信側スループット (Mbps) |
| flowN_receiver | 受信側スループット (Mbps) |
| flowN_rtt | 遅延情報 (ms)：TCP=RTT、UDP=Jitter |

### JSON形式

各試行の詳細データは`runN/flowN.json`に保存されます。

## フロー設定

| フロー | 送信元ポート | 宛先ポート | 帯域幅 |
|--------|------------|----------|--------|
| flow1 | 50000 | 5201 | 300Mbps |
| flow2 | 50001 | 5202 | 300Mbps |
| flow3 | 50002 | 5203 | 300Mbps |

## 計測項目

### スループット

- **TCP**: sender/receiver両方の実測値を取得
- **UDP**: sender側は実測値、receiver側はロス率から推定
  ```
  receiver = sender × (1 - lost_percent / 100)
  ```

### 遅延

- **TCP**: `mean_rtt`（平均往復遅延時間）をマイクロ秒からミリ秒に変換
- **UDP**: `jitter_ms`（パケット間遅延のばらつき）

## 実行例

```
==========================================
  iperf3 自動繰り返し実行スクリプト
==========================================
総実行回数: 10 回
実行間隔: 5 秒
ウォームアップ: 60 秒
計測時間: 300 秒
転送先: fd03:1::2
結果保存先: srv6_evaluation2_udp/trial1
CSVファイル: srv6_evaluation2_udp/trial1/result.csv
開始時刻: Thu Dec 11 07:47:33 AM UTC 2025
==========================================

ウォームアップ期間 (60 秒) 開始...
ウォームアップ完了

=== 実行 1 / 10 開始 ===
開始時刻: Thu Dec 11 07:48:33 AM UTC 2025

計測期間 (300 秒) 開始...
フロー1 (送信元ポート50000, 宛先ポート5201) PID: 127359
フロー2 (送信元ポート50001, 宛先ポート5202) PID: 127360
フロー3 (送信元ポート50002, 宛先ポート5203) PID: 127361

=== 実行 1 / 10 完了 ===
終了時刻: Thu Dec 11 07:53:34 AM UTC 2025
JSON保存先: srv6_evaluation2_udp/trial1/run1

スループット結果:
  フロー1 (50000): sender=299.99 Mbps, receiver=299.99 Mbps, RTT/Jitter=0.014 ms
  フロー2 (50001): sender=299.99 Mbps, receiver=299.99 Mbps, RTT/Jitter=0.011 ms
  フロー3 (50002): sender=299.99 Mbps, receiver=299.99 Mbps, RTT/Jitter=0.010 ms
```

## トラブルシューティング

### エラー: "the server has terminated"

サーバー側のiperf3が終了した場合に発生します。サーバー側でiperf3を再起動してください。

### エラー: "unable to send control message: Bad file descriptor"

サーバーとの接続が切断された場合に発生します。ネットワーク接続とサーバーの状態を確認してください。

### スループットが0になる

- JSONファイルが正しく生成されているか確認
- jqがインストールされているか確認
- サーバーが正しく動作しているか確認

## 注意事項

- 長時間の計測を行う場合、サーバー側のiperf3がタイムアウトしないよう注意してください
- UDPのreceiver側スループットはロス率からの推定値です
- 3つのフローで合計900Mbpsの帯域を使用します

## ライセンス

MIT License
