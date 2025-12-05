#!/bin/bash

# iperf3 自動繰り返し実行スクリプト
# 350秒おきに10回実行し、結果を各ディレクトリに保存

# 設定
TOTAL_RUNS=10
INTERVAL=350  # 秒
DURATION=300  # iperf3の実行時間

# 転送先IPアドレス
QFLM_TEST_IP=${QFLM_TEST_IP:-"fd00:1::12"}
SERVER_IP=${SERVER_IP:-"fd03:1::2"}

# Ctrl+C で全プロセスを停止する処理
cleanup() {
    echo ""
    echo "=== Ctrl+C が押されました。スクリプトを停止します ==="
    kill $PID1 $PID2 $PID3 2>/dev/null
    wait $PID1 $PID2 $PID3 2>/dev/null
    echo "停止完了"
    echo "終了時刻: $(date)"
    exit 0
}

trap cleanup SIGINT SIGTERM

echo "=========================================="
echo "  iperf3 自動繰り返し実行スクリプト"
echo "=========================================="
echo "総実行回数: $TOTAL_RUNS 回"
echo "実行間隔: $INTERVAL 秒"
echo "転送先: $SERVER_IP"
echo "開始時刻: $(date)"
echo "=========================================="
echo ""

for RUN in $(seq 1 $TOTAL_RUNS); do
    echo "=== 実行 $RUN / $TOTAL_RUNS 開始 ==="
    echo "開始時刻: $(date)"
    echo "保存先: evaluation2_udp/$RUN/"
    echo ""

    # ディレクトリが存在しない場合は作成
    mkdir -p "evaluation2_udp/$RUN"

    # 3つのフローを同時に開始
    iperf3 -c $SERVER_IP -p 5201 --cport 50000 -t $DURATION  -b 300M -u -l 1012 -J > "evaluation2_udp/$RUN/1.json" &
    PID1=$!

    iperf3 -c $SERVER_IP -p 5202 --cport 50001 -t $DURATION  -b 300M -u -l 1012 -J > "evaluation2_udp/$RUN/2.json" &
    PID2=$!

    iperf3 -c $SERVER_IP -p 5203 --cport 50002 -t $DURATION  -b 300M -u -l 1012 -J > "evaluation2_udp/$RUN/3.json" &
    PID3=$!

    echo "フロー1 (ポート5201) PID: $PID1"
    echo "フロー2 (ポート5202) PID: $PID2"
    echo "フロー3 (ポート5203) PID: $PID3"
    echo ""

    # 全てのフローが完了するまで待機
    wait $PID1 $PID2 $PID3

    echo "=== 実行 $RUN / $TOTAL_RUNS 完了 ==="
    echo "終了時刻: $(date)"
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
echo "終了時刻: $(date)"
