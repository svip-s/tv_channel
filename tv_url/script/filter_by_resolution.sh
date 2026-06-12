#!/bin/bash
# IPTV 按真实分辨率分类脚本（单线程 + 解析失败自动重试）
# 使用方法：
# 1. 将有效 IPTV 链接放在 valid_channels.txt，每行一个
# 2. 运行: bash filter_by_resolution_retry.sh

input_file="valid_channels.txt"
max_retry=2  # 解析失败重试次数

# 检查 ffprobe 是否安装
if ! command -v ffprobe &>/dev/null; then
    echo "❌ 请先安装 ffmpeg (pkg install ffmpeg)"
    exit 1
fi

[ ! -f "$input_file" ] && { echo "❌ $input_file 不存在"; exit 1; }

declare -A counters   # 每个分辨率序号

retry_list=()  # 存储需要重试的链接

process_url() {
    local url="$1"
    local attempt="$2"

    url=$(echo "$url" | tr -d '\r\n ')
    [ -z "$url" ] && return

    # 尝试 ffprobe 获取分辨率
    resolution=$(ffprobe -v error -protocol_whitelist "file,http,https,tcp,tls" \
        -select_streams v:0 -show_entries stream=width,height \
        -of csv=p=0 "$url" 2>/dev/null)

    if [ -n "$resolution" ]; then
        # 成功解析
        res_line=$(echo "$resolution" | head -n1 | tr -d ' ')
        width=$(echo "$res_line" | cut -d',' -f1)
        height=$(echo "$res_line" | cut -d',' -f2)
    else
        # 解析失败 → URL关键字备选
        if echo "$url" | grep -iq "2160"; then
            width=3840; height=2160
        elif echo "$url" | grep -iq "1080"; then
            width=1920; height=1080
        elif echo "$url" | grep -iq "720"; then
            width=1280; height=720
        else
            width=unknown
            height=unknown
        fi
        res_line="${width}x${height}"
    fi

    # 文件名和播放列表
    file_name="${width}x${height}.txt"
    playlist_name="playlist_${width}x${height}.m3u"

    # 初始化播放列表（第一次出现该分辨率）
    if [ ! -f "$playlist_name" ]; then
        echo "#EXTM3U" > "$playlist_name"
        counters["$res_line"]=1
    fi

    # 当前序号
    n=${counters["$res_line"]}

    # 输出到文件和播放列表
    echo "$url" >> "$file_name"
    echo "#EXTINF:-1,Channel-$n" >> "$playlist_name"
    echo "$url" >> "$playlist_name"

    # 序号加1
    counters["$res_line"]=$((n+1))

    # 输出状态
    if [ "$width" = "unknown" ]; then
        if [ "$attempt" -lt "$max_retry" ]; then
            echo "⚠️ [Retry $((attempt+1))] $url"
            retry_list+=("$url")
        else
            echo "❌ [Failed] $url -> 保存到 unknown_retry.txt"
            echo "$url" >> unknown_retry.txt
        fi
    else
        echo "✅ [$width x $height] $url"
    fi
}

# 第一轮处理
while read -r url; do
    process_url "$url" 0
done < "$input_file"

# 重试解析失败链接
for ((i=1;i<=max_retry;i++)); do
    if [ ${#retry_list[@]} -eq 0 ]; then
        break
    fi
    echo ""
    echo "🔄 第 $i 次重试 ${#retry_list[@]} 个链接..."
    temp_list=("${retry_list[@]}")
    retry_list=()
    for url in "${temp_list[@]}"; do
        process_url "$url" "$i"
    done
done

echo ""
echo "✅ 分类完成！"
echo "每个分辨率生成单独的链接文件和播放列表"
echo "最终无法解析的流保存在 unknown_retry.txt"
