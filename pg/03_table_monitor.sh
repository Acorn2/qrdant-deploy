#!/bin/bash

# PostgreSQL 表监控脚本
# 实时监控数据表的变化情况

LOG_FILE="/var/log/table_monitor.log"
PID_FILE="/var/run/table_monitor.pid"

# 检查是否已经在运行
if [[ -f "$PID_FILE" ]]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p "$OLD_PID" > /dev/null 2>&1; then
        echo "表监控脚本已在运行 (PID: $OLD_PID)"
        echo "如需重启监控，请先运行: sudo kill $OLD_PID"
        exit 1
    else
        # 清理无效的PID文件
        sudo rm -f "$PID_FILE"
    fi
fi

# 检查参数
INTERVAL=${1:-60}  # 默认60秒间隔
echo "=== 启动表监控 ==="
echo "监控间隔: $INTERVAL 秒"
echo "日志文件: $LOG_FILE"
echo "PID文件: $PID_FILE"
echo

# 创建日志文件并设置权限
sudo touch "$LOG_FILE"
sudo chmod 644 "$LOG_FILE"

# 保存当前PID
echo $$ | sudo tee "$PID_FILE" > /dev/null

# 信号处理函数
cleanup() {
    echo "收到停止信号，正在清理..."
    sudo rm -f "$PID_FILE"
    exit 0
}

trap cleanup SIGTERM SIGINT

echo "表监控已启动，按 Ctrl+C 停止"
echo "实时查看日志: tail -f $LOG_FILE"
echo

# 主监控循环
while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    {
        echo "=== $TIMESTAMP ==="
        
        # 检查数据库连接
        if ! sudo -u postgres psql -d document_analysis -c "SELECT 1;" > /dev/null 2>&1; then
            echo "❌ 数据库连接失败！"
        else
            echo "✅ 数据库连接正常"
            
            # 检查表存在性和统计信息
            sudo -u postgres psql -d document_analysis -t -c "
            SELECT 
                CASE 
                    WHEN COUNT(*) = 0 THEN '⚠️  没有用户表'
                    ELSE '📊 表统计信息:'
                END
            FROM information_schema.tables 
            WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
            "
            
            # 详细表信息
            sudo -u postgres psql -d document_analysis -t -c "
            SELECT 
                '表名: ' || t.table_name ||
                ' | 插入: ' || COALESCE(s.n_tup_ins::text, '0') ||
                ' | 删除: ' || COALESCE(s.n_tup_del::text, '0') ||
                ' | 活跃行: ' || COALESCE(s.n_live_tup::text, '0') ||
                ' | 死行: ' || COALESCE(s.n_dead_tup::text, '0')
            FROM information_schema.tables t
            LEFT JOIN pg_stat_user_tables s ON t.table_name = s.relname
            WHERE t.table_schema = 'public' AND t.table_type = 'BASE TABLE'
            ORDER BY t.table_name;
            " 2>/dev/null || echo "❌ 查询表信息失败"
            
            # 检查当前活动连接数
            CONN_COUNT=$(sudo -u postgres psql -d document_analysis -t -c "
            SELECT COUNT(*) FROM pg_stat_activity WHERE datname = 'document_analysis';
            " 2>/dev/null || echo "0")
            echo "🔗 当前连接数: $CONN_COUNT"
        fi
        
        echo "---"
        echo
    } >> "$LOG_FILE" 2>&1
    
    sleep "$INTERVAL"
done 