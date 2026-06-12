#!/bin/bash
# dbiptv 扫描增强版：并发 + 网络检测 + 重试机制

start_id=$1
end_id=$2
base_url="http://dbiptv.sn.chinamobile.com/PLTV/88888890/224"
max_jobs=5        # 最大并发数量
retry_times=2     # 每个频道重试次数
timeout=3         # curl 超时秒数

if [ -z "$start_id" ] || [ -z "$end_id" ]; then
    echo "用法: bash $0 <起始ID> <结束ID>"
    exit 1
fi

echo "扫描范围：$start_id 到 $end_id"
echo "" > valid_channels.txt

# ------------------------ #
#   网络连通性检查函数
# ------------------------ #
check_network() {
    ping -c 1 -W 1 223.5.5.5 >/dev/null 2>&1  # 用 DNS 判断网络是否连通
    return $?
}

# ------------------------ #
#   扫描单个 ID
# ------------------------ #
scan_one() {
    local id=$1
    local url="$base_url/$id/index.m3u8"

    local attempt=0
    local success=0

    while (( attempt <= retry_times )); do
        attempt=$((attempt + 1))

        # 网络掉线时暂停并等待恢复
        if ! check_network; then
            echo "⚠️ 网络中断，暂停扫描... (等待恢复)"
            while ! check_network; do
                sleep 2
            done
            echo "🌐 网络已恢复，继续扫描..."
        fi

        # 扫描链接
        content=$(curl -s --max-time $timeout -L "$url")

        if [[ $? -eq 0 && "$content" == *"#EXTM3U"* ]]; then
            echo "✅ 有效频道: $url"
            echo "$url" >> valid_channels.txt
            success=1
            break
        else
            echo "❌ 无效: $id (尝试 $attempt/$retry_times)"
            sleep 0.3
        fi
    done

    if [[ $success -eq 0 ]]; then
        echo "🚫 最终失败: $id"
    fi
}

export -f scan_one
export base_url retry_times timeout
export -f check_network

# ------------------------ #
#   并发控制
# ------------------------ #
for ((i=$start_id; i<=$end_id; i++)); do
    scan_one "$i" &

    while (( $(jobs | wc -l) >= max_jobs )); do
        sleep 0.2
    done
done

wait

echo ""
echo "扫描结束，有效频道保存在 valid_channels.txt"

# 生成 M3U
echo "#EXTM3U" > playlist.m3u
n=1
while read -r line; do
    echo "#EXTINF:-1,Channel-$n" >> playlist.m3u
    echo "$line" >> playlist.m3u
    ((n++))
done < valid_channels.txt

echo "已生成 playlist.m3u"

# ---- 频道变化对比 ---- #
if [[ -f valid_channels_prev.txt ]]; then
    echo "正在计算频道变化..."

    sort valid_channels_prev.txt -o prev_sorted.txt
    sort valid_channels.txt       -o new_sorted.txt

    comm -13 prev_sorted.txt new_sorted.txt > added.txt
    comm -23 prev_sorted.txt new_sorted.txt > removed.txt
    comm -12 prev_sorted.txt new_sorted.txt > unchanged.txt

    echo "新增频道已保存到 added.txt"
    echo "下线频道已保存到 removed.txt"
    echo "未变化频道已保存到 unchanged.txt"
else
    echo "无上次扫描记录，将当前结果保存为 valid_channels_prev.txt"
fi

cp valid_channels.txt valid_channels_prev.txt
