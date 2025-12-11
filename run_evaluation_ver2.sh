#!/bin/bash

# iperf3 自動繰り返し実行スクリプト
# 350秒おきに10回実行し、結果をCSVに保存
# JSON形式で各回の結果を保存し、遅延情報も取得

# 設定
TOTAL_RUNS=10
INTERVAL=10  # 秒
DURATION=10  # iperf3の実行時間（計測期間）
WARMUP=5     # ウォームアップ時間（秒）- 計測しない帯域を流す

# 転送先IPアドレス
QFLM_TEST_IP=${QFLM_TEST_IP:-"fd00:1::12"}
SERVER_IP=${SERVER_IP:-"fd03:1::2"}

# 結果保存ディレクトリ
RESULT_DIR="srv6_evaluation2_udp/trial2"
CSV_FILE="$RESULT_DIR/srv6_eval2_udp_trial.csv"

# Ctrl+C で全プロセスを停止する処理
cleanup() {
    echo ""
    echo "=== Ctrl+C が押されました。スクリプトを停止します ==="
    kill $PID1 $PID2 $PID3 $PID_WARMUP1 $PID_WARMUP2 $PID_WARMUP3 2>/dev/null
    wait $PID1 $PID2 $PID3 $PID_WARMUP1 $PID_WARMUP2 $PID_WARMUP3 2>/dev/null
    echo "停止完了"
    echo "終了時刻: $(date)"
    exit 0
}

trap cleanup SIGINT SIGTERM

# JSONからスループットを抽出する関数 (Mbps)
# 引数: $1=JSONファイル
extract_throughput_json() {
    local json_file=$1
    
    # UDP/TCPの両方に対応してスループットを抽出
    # UDP: .end.streams[0].udp.bits_per_second
    # TCP: .end.sum_sent.bits_per_second または .end.streams[0].sender.bits_per_second
    local sender_bps=$(jq -r '.end.streams[0].udp.bits_per_second // .end.sum_sent.bits_per_second // .end.streams[0].sender.bits_per_second // 0' "$json_file" 2>/dev/null)
    local receiver_bps=$(jq -r '.end.sum_received.bits_per_second // .end.streams[0].receiver.bits_per_second // 0' "$json_file" 2>/dev/null)
    
    # UDPの場合、receiverはsenderと同じ値を使用（片方向なのでreceiverの値は別で取得）
    if [[ "$receiver_bps" == "0" ]]; then
        receiver_bps=$sender_bps
    fi
    
    # bits/sec を Mbps に変換
    local sender_mbps=$(echo "scale=2; $sender_bps / 1000000" | bc 2>/dev/null || echo "0")
    local receiver_mbps=$(echo "scale=2; $receiver_bps / 1000000" | bc 2>/dev/null || echo "0")
    
    echo "$sender_mbps,$receiver_mbps"
}

# JSONから遅延(RTT)を抽出する関数 (ms)
# 引数: $1=JSONファイル
extract_rtt_json() {
    local json_file=$1
    
    # UDPの場合: jitterを取得 (ms)
    local jitter=$(jq -r '.end.sum.jitter_ms // .end.streams[0].udp.jitter_ms // "N/A"' "$json_file" 2>/dev/null)
    
    # TCPの場合: mean_rttを取得 (usをmsに変換)
    local mean_rtt_us=$(jq -r '.end.streams[0].sender.mean_rtt // "N/A"' "$json_file" 2>/dev/null)
    
    if [[ "$mean_rtt_us" != "N/A" && "$mean_rtt_us" != "null" ]]; then
        # TCP: mean_rtt (マイクロ秒) をミリ秒に変換
        local rtt_ms=$(echo "scale=3; $mean_rtt_us / 1000" | bc 2>/dev/null || echo "N/A")
        echo "$rtt_ms"
    elif [[ "$jitter" != "N/A" && "$jitter" != "null" ]]; then
        # UDP: jitter (ミリ秒)
        echo "$jitter"
    else
        echo "N/A"
    fi
}

echo "=========================================="
echo "  iperf3 自動繰り返し実行スクリプト"
echo "=========================================="
echo "総実行回数: $TOTAL_RUNS 回"
echo "実行間隔: $INTERVAL 秒"
echo "ウォームアップ: $WARMUP 秒"
echo "計測時間: $DURATION 秒"
echo "転送先: $SERVER_IP"
echo "結果保存先: $RESULT_DIR"
echo "CSVファイル: $CSV_FILE"
echo "開始時刻: $(date)"
echo "=========================================="
echo ""

# 結果ディレクトリを作成
mkdir -p "$RESULT_DIR"

# 各回のJSONを保存するディレクトリを作成 (run1, run2, ..., run10)
for i in $(seq 1 $TOTAL_RUNS); do
    mkdir -p "$RESULT_DIR/run$i"
done

# CSVヘッダーを作成（遅延列を追加）
echo "run,flow1(50000)_sender,flow1(50000)_receiver,flow1(50000)_rtt,flow2(50001)_sender,flow2(50001)_receiver,flow2(50001)_rtt,flow3(50002)_sender,flow3(50002)_receiver,flow3(50002)_rtt" > "$CSV_FILE"



# ウォームアップ期間（計測なしで帯域を流す）
    echo "ウォームアップ期間 ($WARMUP 秒) 開始..."
    iperf3 -c $SERVER_IP -p 5201 --cport 50000 -t $WARMUP -b 300M -u -l 1012 > /dev/null 2>&1 &
    PID_WARMUP1=$!
    
    iperf3 -c $SERVER_IP -p 5202 --cport 50001 -t $WARMUP -b 300M -u -l 1012 > /dev/null 2>&1 &
    PID_WARMUP2=$!

    iperf3 -c $SERVER_IP -p 5203 --cport 50002 -t $WARMUP -b 300M -u -l 1012 > /dev/null 2>&1 &
    PID_WARMUP3=$!

    # ウォームアップ完了まで待機
    wait $PID_WARMUP1 $PID_WARMUP2 $PID_WARMUP3
    echo "ウォームアップ完了"
    echo ""


for RUN in $(seq 1 $TOTAL_RUNS); do
    echo "=== 実行 $RUN / $TOTAL_RUNS 開始 ==="
    echo "開始時刻: $(date)"
    echo ""

    # JSON保存先ディレクトリ
    RUN_DIR="$RESULT_DIR/run$RUN"

    # 計測期間開始
    echo "計測期間 ($DURATION 秒) 開始..."
    
    # 3つのフローを同時に開始（JSON形式で出力）
    iperf3 -c $SERVER_IP -p 5201 --cport 50000 -t $DURATION -b 300M -u -l 1012 -J > "$RUN_DIR/flow1.json" &
    # iperf3 -c $SERVER_IP -p 5201 --cport 50000 -t $DURATION -b 300M -M 1000 -J > "$RUN_DIR/flow1.json" &
    PID1=$!
    
    iperf3 -c $SERVER_IP -p 5202 --cport 50001 -t $DURATION -b 300M -u -l 1012 -J > "$RUN_DIR/flow2.json" &
    PID2=$!

    iperf3 -c $SERVER_IP -p 5203 --cport 50002 -t $DURATION -b 300M -u -l 1012 -J > "$RUN_DIR/flow3.json" &
    PID3=$!

    echo "フロー1 (送信元ポート50000, 宛先ポート5201) PID: $PID1"
    echo "フロー2 (送信元ポート50001, 宛先ポート5202) PID: $PID2"
    echo "フロー3 (送信元ポート50002, 宛先ポート5203) PID: $PID3"
    echo ""

    # 全てのフローが完了するまで待機
    wait $PID1 $PID2 $PID3

    echo "=== 実行 $RUN / $TOTAL_RUNS 完了 ==="
    echo "終了時刻: $(date)"
    echo "JSON保存先: $RUN_DIR"
    echo ""

    # 各フローの結果をJSONから抽出
    echo "スループット結果:"
    
    result1=$(extract_throughput_json "$RUN_DIR/flow1.json")
    result2=$(extract_throughput_json "$RUN_DIR/flow2.json")
    result3=$(extract_throughput_json "$RUN_DIR/flow3.json")
    
    # 遅延(RTT/Jitter)を抽出
    rtt1=$(extract_rtt_json "$RUN_DIR/flow1.json")
    rtt2=$(extract_rtt_json "$RUN_DIR/flow2.json")
    rtt3=$(extract_rtt_json "$RUN_DIR/flow3.json")
    
    # 1行にまとめてCSVに追記（遅延情報も含む）
    echo "$RUN,$result1,$rtt1,$result2,$rtt2,$result3,$rtt3" >> "$CSV_FILE"
    
    # 結果を表示
    echo "  フロー1 (50000): sender=$(echo $result1 | cut -d',' -f1) Mbps, receiver=$(echo $result1 | cut -d',' -f2) Mbps, RTT/Jitter=$rtt1 ms"
    echo "  フロー2 (50001): sender=$(echo $result2 | cut -d',' -f1) Mbps, receiver=$(echo $result2 | cut -d',' -f2) Mbps, RTT/Jitter=$rtt2 ms"
    echo "  フロー3 (50002): sender=$(echo $result3 | cut -d',' -f1) Mbps, receiver=$(echo $result3 | cut -d',' -f2) Mbps, RTT/Jitter=$rtt3 ms"
    
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

echo "=========================================="
echo "  全 $TOTAL_RUNS 回の実行が完了しました"
echo "=========================================="
echo "結果は $CSV_FILE に保存されました"
echo "JSONファイルは $RESULT_DIR/run1 ~ $RESULT_DIR/run$TOTAL_RUNS に保存されました"
echo "終了時刻: $(date)"
echo ""
echo "=== CSVファイルの内容 ==="
cat "$CSV_FILE"
