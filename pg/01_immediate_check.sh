#!/bin/bash

# PostgreSQL 立即诊断脚本
# 用于检查当前数据库状态和系统资源

echo "=== PostgreSQL 立即诊断 ==="
echo "执行时间: $(date)"
echo

# 1. 检查PostgreSQL服务状态
echo "1. PostgreSQL服务状态检查:"
echo "----------------------------------------"
sudo systemctl status postgresql
echo

# 2. 检查是否有异常重启
echo "2. 检查最近24小时的服务重启记录:"
echo "----------------------------------------"
sudo journalctl -u postgresql --since "24 hours ago" | grep -E "(start|stop|restart|kill|crash|failed)"
echo

# 3. 查看当前数据库表状态
echo "3. 检查document_analysis数据库表:"
echo "----------------------------------------"
sudo -u postgres psql -d document_analysis -c "\dt"
echo

# 4. 检查表统计信息
echo "4. 表统计信息 (插入/更新/删除记录):"
echo "----------------------------------------"
sudo -u postgres psql -d document_analysis -c "
SELECT 
    schemaname,
    tablename,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes,
    n_live_tup as live_rows,
    n_dead_tup as dead_rows
FROM pg_stat_user_tables
ORDER BY tablename;
"
echo

# 5. 检查系统资源
echo "5. 系统资源使用情况:"
echo "----------------------------------------"
echo "内存使用:"
free -h
echo
echo "磁盘使用:"
df -h
echo
echo "PostgreSQL进程状态:"
ps aux | grep postgres | head -10
echo

# 6. 检查PostgreSQL连接
echo "6. 当前数据库连接:"
echo "----------------------------------------"
sudo -u postgres psql -d document_analysis -c "
SELECT 
    pid,
    usename,
    application_name,
    client_addr,
    state,
    query_start,
    LEFT(query, 50) as query_preview
FROM pg_stat_activity 
WHERE datname = 'document_analysis'
ORDER BY query_start DESC;
"
echo

# 7. 检查最近的错误日志
echo "7. 最近的PostgreSQL错误日志:"
echo "----------------------------------------"
sudo find /var/lib/pgsql/data/log -name "postgresql-*.log" -exec tail -20 {} \; | grep -i -E "(error|fatal|panic)" | tail -10
echo

echo "=== 立即诊断完成 ==="
echo "建议：如果发现异常，请继续运行其他脚本进行深入分析" 