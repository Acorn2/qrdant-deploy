#!/bin/bash

# PostgreSQL 连接监控脚本
# 监控数据库连接和活动查询

LOG_FILE="/var/log/pg_connections.log"
PID_FILE="/var/run/connection_monitor.pid"

# 检查是否已经在运行
if [[ -f "$PID_FILE" ]]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p "$OLD_PID" > /dev/null 2>&1; then
        echo "连接监控脚本已在运行 (PID: $OLD_PID)"
        echo "如需重启监控，请先运行: sudo kill $OLD_PID"
        exit 1
    else
        sudo rm -f "$PID_FILE"
    fi
fi

# 检查参数
INTERVAL=${1:-300}  # 默认5分钟间隔
echo "=== 启动连接监控 ==="
echo "监控间隔: $INTERVAL 秒"
echo "日志文件: $LOG_FILE"
echo

# 创建日志文件
sudo touch "$LOG_FILE"
sudo chmod 644 "$LOG_FILE"

# 保存PID
echo $$ | sudo tee "$PID_FILE" > /dev/null

# 信号处理
cleanup() {
    echo "连接监控停止"
    sudo rm -f "$PID_FILE"
    exit 0
}

trap cleanup SIGTERM SIGINT

echo "连接监控已启动，按 Ctrl+C 停止"
echo "实时查看日志: tail -f $LOG_FILE"
echo

# 主监控循环
while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    {
        echo "=== $TIMESTAMP ==="
        
        # 检查总连接数
        TOTAL_CONN=$(sudo -u postgres psql -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null || echo "0")
        DB_CONN=$(sudo -u postgres psql -d document_analysis -t -c "SELECT count(*) FROM pg_stat_activity WHERE datname = 'document_analysis';" 2>/dev/null || echo "0")
        
        echo "📊 连接统计: 总连接数=$TOTAL_CONN, document_analysis连接数=$DB_CONN"
        
        # 详细连接信息
        echo "🔗 document_analysis 数据库连接详情:"
        sudo -u postgres psql -d document_analysis -c "
        SELECT 
            pid,
            usename as 用户,
            application_name as 应用,
            client_addr as 客户端IP,
            state as 状态,
            query_start as 查询开始时间,
            LEFT(query, 80) as 查询预览
        FROM pg_stat_activity 
        WHERE datname = 'document_analysis'
        ORDER BY query_start DESC;
        " 2>/dev/null || echo "❌ 无法获取连接信息"
        
        # 检查长时间运行的查询
        echo "⏰ 长时间运行的查询 (>30秒):"
        sudo -u postgres psql -d document_analysis -c "
        SELECT 
            pid,
            usename,
            state,
            EXTRACT(EPOCH FROM (now() - query_start))::int as 运行秒数,
            LEFT(query, 100) as 查询
        FROM pg_stat_activity 
        WHERE datname = 'document_analysis' 
            AND state != 'idle' 
            AND query_start < now() - interval '30 seconds'
        ORDER BY query_start;
        " 2>/dev/null || echo "无长时间运行的查询"
        
        # 检查锁等待
        echo "🔒 当前锁等待情况:"
        sudo -u postgres psql -d document_analysis -c "
        SELECT 
            blocked_locks.pid AS blocked_pid,
            blocked_activity.usename AS blocked_user,
            blocking_locks.pid AS blocking_pid,
            blocking_activity.usename AS blocking_user,
            blocked_activity.query AS blocked_statement,
            blocking_activity.query AS current_statement_in_blocking_process
        FROM pg_catalog.pg_locks blocked_locks
        JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
        JOIN pg_catalog.pg_locks blocking_locks 
            ON blocking_locks.locktype = blocked_locks.locktype
            AND blocking_locks.DATABASE IS NOT DISTINCT FROM blocked_locks.DATABASE
            AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
            AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
            AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
            AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
            AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
            AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
            AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
            AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
            AND blocking_locks.pid != blocked_locks.pid
        JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
        WHERE NOT blocked_locks.GRANTED;
        " 2>/dev/null || echo "无锁等待"
        
        echo "---"
        echo
    } >> "$LOG_FILE" 2>&1
    
    sleep "$INTERVAL"
done 