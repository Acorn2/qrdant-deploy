#!/bin/bash

# PostgreSQL 清理任务检查脚本
# 检查可能导致数据表被清空的定时任务和脚本

echo "=== 检查清理任务和可疑脚本 ==="
echo "执行时间: $(date)"
echo

# 1. 检查系统定时任务
echo "1. 检查系统级定时任务 (crontab):"
echo "----------------------------------------"
echo "root用户的定时任务:"
sudo crontab -l 2>/dev/null || echo "root用户无定时任务"
echo

echo "当前用户的定时任务:"
crontab -l 2>/dev/null || echo "当前用户无定时任务"
echo

echo "所有用户的定时任务:"
sudo find /var/spool/cron -name "*" 2>/dev/null | while read cronfile; do
    if [[ -f "$cronfile" ]]; then
        echo "=== $cronfile ==="
        sudo cat "$cronfile"
        echo
    fi
done
echo

# 2. 检查systemd定时器
echo "2. 检查systemd定时器:"
echo "----------------------------------------"
sudo systemctl list-timers --all | grep -E "(timer|Timer)"
echo

echo "检查可疑的systemd服务:"
sudo find /etc/systemd/system /usr/lib/systemd/system -name "*.timer" -o -name "*.service" | grep -E "(clean|clear|purge|delete|drop)" | while read service; do
    echo "发现可疑服务: $service"
    echo "内容:"
    sudo cat "$service"
    echo "---"
done
echo

# 3. 检查可疑脚本文件
echo "3. 搜索可疑的清理脚本:"
echo "----------------------------------------"
echo "搜索包含数据库清理关键词的脚本..."

# 搜索包含DROP, DELETE, TRUNCATE等关键词的脚本
sudo find /home /root /opt /usr/local -type f \( -name "*.sh" -o -name "*.py" -o -name "*.sql" \) -exec grep -l -i -E "(drop table|delete from|truncate|document_analysis.*delete|document_analysis.*drop)" {} \; 2>/dev/null | while read file; do
    echo "🚨 发现可疑文件: $file"
    echo "相关内容:"
    sudo grep -n -i -E "(drop table|delete from|truncate|document_analysis.*delete|document_analysis.*drop)" "$file" 2>/dev/null | head -5
    echo "---"
done
echo

# 4. 检查最近修改的脚本
echo "4. 检查最近7天内修改的脚本文件:"
echo "----------------------------------------"
sudo find /home /root /opt /usr/local -type f \( -name "*.sh" -o -name "*.py" -o -name "*.sql" \) -mtime -7 -exec ls -la {} \; 2>/dev/null | head -20
echo

# 5. 检查进程中的可疑命令
echo "5. 检查当前运行的可疑进程:"
echo "----------------------------------------"
ps aux | grep -E "(drop|delete|truncate|psql|postgres)" | grep -v grep
echo

# 6. 检查应用程序日志
echo "6. 检查应用程序日志目录:"
echo "----------------------------------------"
echo "搜索包含DROP/DELETE的日志文件..."
sudo find /var/log -name "*.log" -type f -exec grep -l -i -E "(drop table|delete from.*document_analysis|truncate.*document_analysis)" {} \; 2>/dev/null | head -10 | while read logfile; do
    echo "发现相关日志: $logfile"
    echo "最近的相关条目:"
    sudo grep -i -E "(drop table|delete from.*document_analysis|truncate.*document_analysis)" "$logfile" | tail -3
    echo "---"
done
echo

# 7. 检查Python应用程序
echo "7. 检查Python应用程序和虚拟环境:"
echo "----------------------------------------"
echo "查找Python项目目录..."
sudo find /home /opt -name "*.py" -path "*/venv/*" -o -path "*/env/*" -o -name "requirements.txt" | head -10 | while read pyfile; do
    if [[ -f "$pyfile" ]]; then
        dir=$(dirname "$pyfile")
        echo "Python项目目录: $dir"
        
        # 检查是否有数据库相关配置
        if sudo find "$dir" -name "*.py" -exec grep -l -i "document_analysis\|postgresql\|psycopg" {} \; 2>/dev/null | head -1 >/dev/null; then
            echo "  -> 发现数据库相关代码"
            sudo find "$dir" -name "*.py" -exec grep -l -i -E "(drop_all|truncate|delete.*all)" {} \; 2>/dev/null | head -3
        fi
        echo
    fi
done
echo

# 8. 检查数据库连接配置文件
echo "8. 检查数据库连接配置文件:"
echo "----------------------------------------"
sudo find /home /opt /etc -name "*.conf" -o -name "*.ini" -o -name "*.env" -o -name "*.yaml" -o -name "*.yml" | xargs sudo grep -l -i "document_analysis\|postgresql\|postgres" 2>/dev/null | head -10 | while read configfile; do
    echo "配置文件: $configfile"
    sudo grep -i -E "(document_analysis|postgresql|postgres)" "$configfile" 2>/dev/null | head -3
    echo "---"
done
echo

# 9. 检查Docker容器
echo "9. 检查Docker容器和脚本:"
echo "----------------------------------------"
if command -v docker >/dev/null 2>&1; then
    echo "运行中的容器:"
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
    echo
    
    echo "检查容器中的PostgreSQL连接:"
    docker ps --format "{{.Names}}" | while read container; do
        if docker exec "$container" env 2>/dev/null | grep -q -i postgres; then
            echo "容器 $container 可能连接到PostgreSQL"
        fi
    done
else
    echo "Docker未安装或不可用"
fi
echo

# 10. 生成检查报告
echo "10. 生成检查报告:"
echo "----------------------------------------"
REPORT_FILE="/tmp/cleanup_check_report_$(date +%Y%m%d_%H%M%S).txt"

{
    echo "PostgreSQL清理任务检查报告"
    echo "生成时间: $(date)"
    echo "=========================================="
    echo
    
    echo "检查项目:"
    echo "1. ✓ 系统定时任务检查"
    echo "2. ✓ systemd定时器检查"
    echo "3. ✓ 可疑脚本文件搜索"
    echo "4. ✓ 最近修改文件检查"
    echo "5. ✓ 运行进程检查"
    echo "6. ✓ 应用程序日志检查"
    echo "7. ✓ Python项目检查"
    echo "8. ✓ 配置文件检查"
    echo "9. ✓ Docker容器检查"
    echo
    
    echo "建议后续操作:"
    echo "- 检查上述输出中标记为🚨的可疑文件"
    echo "- 检查任何定时任务的具体内容"
    echo "- 监控后端应用程序的行为"
    echo "- 查看PostgreSQL详细日志"
} > "$REPORT_FILE"

echo "✅ 检查报告已保存到: $REPORT_FILE"
echo

echo "=== 清理任务检查完成 ==="
echo "如发现可疑文件或任务，请仔细分析其内容和执行时间"
echo "重点关注标记为🚨的项目" 