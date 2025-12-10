#!/bin/bash

# iperf3 3フロー同時転送スクリプト

# Ctrl+C で全プロセスを停止する処理
cleanup() {
    echo ""
    echo "=== Ctrl+C が押されました。全フローを停止します ==="
    # まず通常のkillを試み、その後強制終了
    kill $PID1 $PID2 $PID3 2>/dev/null
    sleep 0.5
    kill -9 $PID1 $PID2 $PID3 2>/dev/null
    wait $PID1 $PID2 $PID3 2>/dev/null
    echo "全フロー停止完了"
    echo "終了時刻: $(date)"
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# 転送先IPアドレス（環境変数から取得、未設定の場合はデフォルト値を使用）
QFLM_TEST_IP=${QFLM_TEST_IP:-"fd00:1::12"}
SERVER_IP=${SERVER_IP:-"fd03:1::2"}

echo "=== iperf3 3フロー同時転送開始 ==="
echo "転送先: $QFLM_TEST_IP"
echo "開始時刻: $(date)"
echo ""

# 3つのフローを同時に開始
iperf3 -c $SERVER_IP -p 5201 --cport 50000 -t 300 -b 300M -l 1012 -w 4M &
#iperf3 -c $QFLM_TEST_IP -p 5201 --cport 50000 -t 10 -M 1000 -b 300M -l 1400 -J > evaluation2_tcp/1.json &
PID1=$!

iperf3 -c $SERVER_IP -p 5202 --cport 50001 -t 300 -b 300M -l 1012 -w 4M &
PID2=$!

iperf3 -c $SERVER_IP -p 5203 --cport 50002 -t 300 -b 300M -l 1012 -w 4M &
PID3=$!

echo "フロー1 (ポート5201) PID: $PID1"
echo "フロー2 (ポート5202) PID: $PID2"
echo "フロー3 (ポート5203) PID: $PID3"
echo ""

# 全てのフローが完了するまで待機
wait $PID1 $PID2 #$PID3

echo ""
echo "=== 全フロー転送完了 ==="
echo "終了時刻: $(date)"
