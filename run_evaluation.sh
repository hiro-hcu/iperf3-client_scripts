#!/bin/bash

# iperf3 自動繰り返し実行スクリプト
# 350秒おきに10回実行し、結果をCSVに保存

# 設定
TOTAL_RUNS=10
INTERVAL=10  # 秒
DURATION=300  # iperf3の実行時間

# 転送先IPアドレス
QFLM_TEST_IP=${QFLM_TEST_IP:-"fd00:1::12"}
SERVER_IP=${SERVER_IP:-"fd03:1::2"}

# CSVファイル
CSV_FILE="ospf_evaluation3_tcp/result.csv"

# 一時ファイル用ディレクトリ
TEMP_DIR=$(mktemp -d)

# Ctrl+C で全プロセスを停止する処理
cleanup() {
    echo ""
    echo "=== Ctrl+C が押されました。スクリプトを停止します ==="
    kill $PID1 $PID2 $PID3 2>/dev/null
    wait $PID1 $PID2 $PID3 2>/dev/null
    rm -rf "$TEMP_DIR"
    echo "停止完了"
    echo "終了時刻: $(date)"
    exit 0
}

trap cleanup SIGINT SIGTERM

# iperf3の出力からスループットを抽出する関数
# 引数: $1=出力ファイル
extract_throughput() {
    local output_file=$1
    
    # Sender と Receiver のスループットを抽出 (Mbits/sec)
    local sender_bps=$(grep -E "^\[.*\].*sender" "$output_file" | tail -1 | awk '{for(i=1;i<=NF;i++) if($i~/bits\/sec/) print $(i-1)}')
    local receiver_bps=$(grep -E "^\[.*\].*receiver" "$output_file" | tail -1 | awk '{for(i=1;i<=NF;i++) if($i~/bits\/sec/) print $(i-1)}')
    
    # 単位を取得
    local sender_unit=$(grep -E "^\[.*\].*sender" "$output_file" | tail -1 | awk '{for(i=1;i<=NF;i++) if($i~/bits\/sec/) print $i}')
    local receiver_unit=$(grep -E "^\[.*\].*receiver" "$output_file" | tail -1 | awk '{for(i=1;i<=NF;i++) if($i~/bits\/sec/) print $i}')
    
    # Mbits/secに変換
    local sender_mbps=$sender_bps
    local receiver_mbps=$receiver_bps
    
    if [[ "$sender_unit" == "Gbits/sec" ]]; then
        sender_mbps=$(echo "$sender_bps * 1000" | bc)
    elif [[ "$sender_unit" == "Kbits/sec" ]]; then
        sender_mbps=$(echo "scale=3; $sender_bps / 1000" | bc)
    fi
    
    if [[ "$receiver_unit" == "Gbits/sec" ]]; then
        receiver_mbps=$(echo "$receiver_bps * 1000" | bc)
    elif [[ "$receiver_unit" == "Kbits/sec" ]]; then
        receiver_mbps=$(echo "scale=3; $receiver_bps / 1000" | bc)
    fi
    
    echo "$sender_mbps,$receiver_mbps"
}

echo "=========================================="
echo "  iperf3 自動繰り返し実行スクリプト"
echo "=========================================="
echo "総実行回数: $TOTAL_RUNS 回"
echo "実行間隔: $INTERVAL 秒"
echo "転送先: $SERVER_IP"
echo "結果保存先: $CSV_FILE"
echo "開始時刻: $(date)"
echo "=========================================="
echo ""

# CSVヘッダーを作成
mkdir -p "ospf_evaluation2_tcp"
echo "run,flow1(50000)_sender,flow1(50000)_receiver,flow2(50001)_sender,flow2(50001)_receiver,flow3(50002)_sender,flow3(50002)_receiver" > "$CSV_FILE"

for RUN in $(seq 1 $TOTAL_RUNS); do
    echo "=== 実行 $RUN / $TOTAL_RUNS 開始 ==="
    echo "開始時刻: $(date)"
    echo ""

    # 3つのフローを同時に開始（一時ファイルに出力）
    iperf3 -c $SERVER_IP -p 5201 --cport 50000 -t $DURATION -b 300M -M 1000 > "$TEMP_DIR/flow1.txt" &
    PID1=$!
    # iperf3 -c $SERVER_IP -p 5201 --cport 50000 -t $DURATION -b 300M -u -l 1012 > "$TEMP_DIR/flow1.txt" &
    # iperf3 -c $SERVER_IP -p 5201 --cport 50000 -t $DURATION -b 300M -M 1000 > "$TEMP_DIR/flow1.txt" &
    iperf3 -c $SERVER_IP -p 5202 --cport 50001 -t $DURATION -b 300M -M 1000 > "$TEMP_DIR/flow2.txt" &
    PID2=$!

    iperf3 -c $SERVER_IP -p 5203 --cport 50002 -t $DURATION -b 300M -M 1000 > "$TEMP_DIR/flow3.txt" &
    PID3=$!

    echo "フロー1 (送信元ポート50000, 宛先ポート5201) PID: $PID1"
    echo "フロー2 (送信元ポート50001, 宛先ポート5202) PID: $PID2"
    echo "フロー3 (送信元ポート50002, 宛先ポート5203) PID: $PID3"
    echo ""

    # 全てのフローが完了するまで待機
    wait $PID1 $PID2 $PID3

    echo "=== 実行 $RUN / $TOTAL_RUNS 完了 ==="
    echo "終了時刻: $(date)"
    echo ""

    # 各フローの結果を抽出
    echo "スループット結果:"
    
    result1=$(extract_throughput "$TEMP_DIR/flow1.txt")
    result2=$(extract_throughput "$TEMP_DIR/flow2.txt")
    result3=$(extract_throughput "$TEMP_DIR/flow3.txt")
    
    # 1行にまとめてCSVに追記
    echo "$RUN,$result1,$result2,$result3" >> "$CSV_FILE"
    
    # 結果を表示
    echo "  フロー1 (50000): sender=$(echo $result1 | cut -d',' -f1) Mbps, receiver=$(echo $result1 | cut -d',' -f2) Mbps"
    echo "  フロー2 (50001): sender=$(echo $result2 | cut -d',' -f1) Mbps, receiver=$(echo $result2 | cut -d',' -f2) Mbps"
    echo "  フロー3 (50002): sender=$(echo $result3 | cut -d',' -f1) Mbps, receiver=$(echo $result3 | cut -d',' -f2) Mbps"
    
    echo ""

    # 最後の実行でなければ、次の実行まで待機
    if [ $RUN -lt $TOTAL_RUNS ]; then
        WAIT_TIME=$((INTERVAL - DURATION))
        if [ $WAIT_TIME -gt 0 ]; then
            echo "次の実行まで $WAIT_TIME 秒待機します..."
            echo "次回開始予定: $(date -v+${WAIT_TIME}S 2>/dev/null || date -d "+${WAIT_TIME} seconds" 2>/dev/null || echo "約${WAIT_TIME}秒後")"
            sleep $WAIT_TIME
        fi
    fi
    echo ""
done

# 一時ファイルを削除
rm -rf "$TEMP_DIR"

echo "=========================================="
echo "  全 $TOTAL_RUNS 回の実行が完了しました"
echo "=========================================="
echo "結果は $CSV_FILE に保存されました"
echo "終了時刻: $(date)"
echo ""
echo "=== CSVファイルの内容 ==="
cat "$CSV_FILE"
