#!/bin/bash

# PostgreSQL 综合健康检查脚本
# 全面检查PostgreSQL的运行状态和健康状况

echo "=== PostgreSQL 综合健康检查 ==="
echo "检查时间: $(date)"
echo "主机名: $(hostname)"
echo "系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
echo

# 1. 服务状态检查
echo "1. PostgreSQL 服务状态:"
echo "=========================================="
if sudo systemctl is-active --quiet postgresql; then
    echo "✅ PostgreSQL 服务运行正常"
    sudo systemctl status postgresql --no-pager -l | head -10
else
    echo "❌ PostgreSQL 服务异常"
    sudo systemctl status postgresql --no-pager -l
fi
echo

# 2. 数据库连接测试
echo "2. 数据库连接测试:"
echo "=========================================="
if sudo -u postgres psql -d document_analysis -c "SELECT current_timestamp as 连接时间, version() as 版本;" 2>/dev/null; then
    echo "✅ 数据库连接正常"
else
    echo "❌ 数据库连接失败"
fi
echo

# 3. 数据库大小和表信息
echo "3. 数据库信息统计:"
echo "=========================================="
echo "数据库大小:"
sudo -u postgres psql -d document_analysis -c "
SELECT 
    pg_database.datname as 数据库名称,
    pg_size_pretty(pg_database_size(pg_database.datname)) as 大小
FROM pg_database 
WHERE datname = 'document_analysis';
" 2>/dev/null || echo "❌ 无法获取数据库大小"

echo
echo "表统计信息:"
sudo -u postgres psql -d document_analysis -c "
SELECT 
    schemaname as 模式,
    tablename as 表名,
    n_tup_ins as 插入数,
    n_tup_upd as 更新数,
    n_tup_del as 删除数,
    n_live_tup as 活跃行数,
    n_dead_tup as 死行数,
    last_vacuum as 最后清理时间,
    last_analyze as 最后分析时间
FROM pg_stat_user_tables
ORDER BY tablename;
" 2>/dev/null || echo "❌ 无法获取表统计信息"
echo

# 4. 系统资源使用情况
echo "4. 系统资源使用情况:"
echo "=========================================="
echo "内存使用情况:"
free -h | awk 'NR==1{print "类型\t\t总计\t\t已用\t\t可用\t\t使用率"} NR==2{printf "物理内存\t%s\t\t%s\t\t%s\t\t%.1f%%\n", $2, $3, $7, ($3/$2)*100}'

echo
echo "磁盘使用情况:"
df -h | grep -E "(文件系统|Filesystem|/var/lib/pgsql|/$)" | awk 'NR==1{print} NR>1 && /pgsql|^\/$/{print}'

echo
echo "PostgreSQL进程资源使用:"
ps aux | head -1
ps aux | grep postgres | grep -v grep | head -5
echo

# 5. 数据库配置检查
echo "5. 重要配置参数检查:"
echo "=========================================="
sudo -u postgres psql -d document_analysis -c "
SELECT 
    name as 参数名,
    setting as 当前值,
    unit as 单位,
    context as 上下文
FROM pg_settings 
WHERE name IN (
    'shared_buffers',
    'effective_cache_size', 
    'work_mem',
    'maintenance_work_mem',
    'max_connections',
    'wal_level',
    'max_wal_size',
    'checkpoint_completion_target',
    'autovacuum'
)
ORDER BY name;
" 2>/dev/null || echo "❌ 无法获取配置信息"
echo

# 6. 连接和活动检查
echo "6. 数据库连接和活动状态:"
echo "=========================================="
echo "连接统计:"
sudo -u postgres psql -c "
SELECT 
    datname as 数据库,
    count(*) as 连接数,
    count(*) filter (where state = 'active') as 活跃连接,
    count(*) filter (where state = 'idle') as 空闲连接
FROM pg_stat_activity 
GROUP BY datname
ORDER BY count(*) DESC;
" 2>/dev/null || echo "❌ 无法获取连接统计"

echo
echo "长时间运行的查询 (>5分钟):"
sudo -u postgres psql -d document_analysis -c "
SELECT 
    pid,
    usename as 用户,
    state as 状态,
    EXTRACT(EPOCH FROM (now() - query_start))::int as 运行秒数,
    LEFT(query, 80) as 查询内容
FROM pg_stat_activity 
WHERE datname = 'document_analysis' 
    AND state != 'idle' 
    AND query_start < now() - interval '5 minutes'
ORDER BY query_start;
" 2>/dev/null || echo "无长时间运行的查询"
echo

# 7. 锁和阻塞检查
echo "7. 锁等待和阻塞检查:"
echo "=========================================="
sudo -u postgres psql -d document_analysis -c "
SELECT 
    blocked_locks.pid AS blocked_pid,
    blocked_activity.usename AS blocked_user,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    LEFT(blocked_activity.query, 50) AS blocked_statement
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks 
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.DATABASE IS NOT DISTINCT FROM blocked_locks.DATABASE
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.GRANTED;
" 2>/dev/null || echo "✅ 无锁等待"
echo

# 8. 错误日志检查
echo "8. 最近的错误和警告:"
echo "=========================================="
echo "最近1小时的错误日志:"
sudo find /var/lib/pgsql/data/log -name "postgresql-*.log" -mmin -60 -exec tail -50 {} \; 2>/dev/null | grep -i -E "(error|fatal|panic|warning)" | tail -10 || echo "✅ 最近1小时无错误日志"
echo

# 9. 自动清理状态
echo "9. 自动清理 (VACUUM) 状态:"
echo "=========================================="
sudo -u postgres psql -d document_analysis -c "
SELECT 
    schemaname,
    tablename,
    last_vacuum,
    last_autovacuum,
    vacuum_count,
    autovacuum_count,
    n_dead_tup as 死行数
FROM pg_stat_user_tables 
WHERE n_dead_tup > 0
ORDER BY n_dead_tup DESC;
" 2>/dev/null || echo "✅ 无需要清理的表"
echo

# 10. 性能指标
echo "10. 数据库性能指标:"
echo "=========================================="
echo "缓存命中率:"
sudo -u postgres psql -d document_analysis -c "
SELECT 
    'Buffer Cache' as 类型,
    round((blks_hit::float/(blks_hit + blks_read) * 100)::numeric, 2) as 命中率百分比
FROM pg_stat_database 
WHERE datname = 'document_analysis' AND blks_read > 0
UNION ALL
SELECT 
    'Index Cache' as 类型,
    round((sum(idx_blks_hit)::float/(sum(idx_blks_hit) + sum(idx_blks_read)) * 100)::numeric, 2) as 命中率百分比
FROM pg_statio_user_indexes 
WHERE idx_blks_read > 0;
" 2>/dev/null || echo "无足够数据计算命中率"

echo
echo "表访问统计:"
sudo -u postgres psql -d document_analysis -c "
SELECT 
    schemaname,
    tablename,
    seq_scan as 顺序扫描次数,
    seq_tup_read as 顺序读取行数,
    idx_scan as 索引扫描次数,
    idx_tup_fetch as 索引获取行数
FROM pg_stat_user_tables 
ORDER BY seq_scan + idx_scan DESC
LIMIT 10;
" 2>/dev/null || echo "无表访问统计"
echo

# 11. 生成健康检查报告
echo "11. 生成健康检查报告:"
echo "=========================================="
REPORT_FILE="/tmp/pg_health_report_$(date +%Y%m%d_%H%M%S).txt"

# 收集关键指标
SERVICE_STATUS=$(sudo systemctl is-active postgresql 2>/dev/null || echo "inactive")
DB_CONN_STATUS=$(sudo -u postgres psql -d document_analysis -c "SELECT 1;" >/dev/null 2>&1 && echo "OK" || echo "FAIL")
TABLE_COUNT=$(sudo -u postgres psql -d document_analysis -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ' || echo "0")
ACTIVE_CONN=$(sudo -u postgres psql -d document_analysis -t -c "SELECT count(*) FROM pg_stat_activity WHERE datname = 'document_analysis';" 2>/dev/null | tr -d ' ' || echo "0")
MEMORY_USAGE=$(free | awk 'NR==2{printf "%.1f%%", ($3/$2)*100}')
DISK_USAGE=$(df -h / | awk 'NR==2{print $5}')

{
    echo "PostgreSQL 健康检查报告"
    echo "========================"
    echo "检查时间: $(date)"
    echo "主机: $(hostname)"
    echo
    echo "关键指标:"
    echo "- 服务状态: $SERVICE_STATUS"
    echo "- 数据库连接: $DB_CONN_STATUS"
    echo "- 用户表数量: $TABLE_COUNT"
    echo "- 活跃连接数: $ACTIVE_CONN"
    echo "- 内存使用率: $MEMORY_USAGE"
    echo "- 磁盘使用率: $DISK_USAGE"
    echo
    
    if [[ "$SERVICE_STATUS" == "active" && "$DB_CONN_STATUS" == "OK" ]]; then
        echo "✅ 总体状态: 健康"
    else
        echo "❌ 总体状态: 异常"
        echo "建议: 立即检查服务状态和数据库连接"
    fi
    
    echo
    echo "建议监控项目:"
    echo "- 持续监控表数据变化"
    echo "- 监控连接数变化"
    echo "- 关注错误日志"
    echo "- 定期检查自动清理状态"
} > "$REPORT_FILE"

echo "✅ 健康检查报告已保存到: $REPORT_FILE"
echo

# 12. 总结
echo "12. 健康检查总结:"
echo "=========================================="
if [[ "$SERVICE_STATUS" == "active" && "$DB_CONN_STATUS" == "OK" ]]; then
    echo "✅ PostgreSQL 整体运行状况良好"
else
    echo "❌ PostgreSQL 存在问题，需要立即处理"
fi

echo "关键指标: 服务[$SERVICE_STATUS] 连接[$DB_CONN_STATUS] 表数量[$TABLE_COUNT] 连接数[$ACTIVE_CONN]"
echo "系统资源: 内存使用率[$MEMORY_USAGE] 磁盘使用率[$DISK_USAGE]"
echo
echo "=== 健康检查完成 ===" 