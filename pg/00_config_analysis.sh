#!/bin/bash

# PostgreSQL 配置分析脚本
# 专门排查可能导致数据表丢失的配置问题

echo "=== PostgreSQL 配置深度分析 ==="
echo "执行时间: $(date)"
echo "目标: 排查可能导致数据表丢失的配置问题"
echo

# 检查PostgreSQL是否运行
if ! sudo systemctl is-active --quiet postgresql; then
    echo "❌ PostgreSQL服务未运行，请先启动服务"
    exit 1
fi

# 1. 检查PostgreSQL数据目录和权限
echo "1. PostgreSQL 数据目录分析:"
echo "=================================================="
PG_DATA_DIR="/var/lib/pgsql/data"

echo "数据目录信息:"
echo "路径: $PG_DATA_DIR"
if [[ -d "$PG_DATA_DIR" ]]; then
    echo "✅ 数据目录存在"
    echo "权限: $(ls -ld $PG_DATA_DIR | awk '{print $1, $3, $4}')"
    echo "大小: $(du -sh $PG_DATA_DIR | cut -f1)"
    
    # 检查关键文件
    echo
    echo "关键文件检查:"
    for file in postgresql.conf pg_hba.conf pg_ident.conf; do
        if [[ -f "$PG_DATA_DIR/$file" ]]; then
            echo "✅ $file 存在"
            echo "   权限: $(ls -l $PG_DATA_DIR/$file | awk '{print $1, $3, $4}')"
            echo "   大小: $(ls -lh $PG_DATA_DIR/$file | awk '{print $5}')"
            echo "   修改时间: $(stat -c %y $PG_DATA_DIR/$file)"
        else
            echo "❌ $file 不存在"
        fi
    done
else
    echo "❌ 数据目录不存在！"
fi
echo

# 2. 分析当前PostgreSQL配置
echo "2. PostgreSQL 核心配置分析:"
echo "=================================================="

# 获取当前运行配置
echo "获取当前运行配置参数..."
sudo -u postgres psql -d document_analysis -c "
SELECT 
    '配置参数分析' as 分析项目,
    '当前值' as 值,
    '风险评估' as 风险;

SELECT 
    name as 配置参数,
    setting as 当前值,
    CASE 
        WHEN name = 'restart_after_crash' AND setting = 'off' THEN '⚠️ 高风险: 崩溃后不重启可能导致数据丢失'
        WHEN name = 'fsync' AND setting = 'off' THEN '🚨 极高风险: 关闭同步可能导致数据丢失'
        WHEN name = 'synchronous_commit' AND setting = 'off' THEN '⚠️ 中风险: 异步提交可能导致数据丢失'
        WHEN name = 'full_page_writes' AND setting = 'off' THEN '⚠️ 高风险: 关闭可能导致页面损坏'
        WHEN name = 'wal_level' AND setting = 'minimal' THEN '⚠️ 中风险: 最小WAL级别'
        WHEN name = 'max_wal_size' AND setting::bigint < 64 THEN '⚠️ 风险: WAL大小过小可能导致频繁checkpoint'
        WHEN name = 'checkpoint_timeout' AND setting::int < 30 THEN '⚠️ 风险: checkpoint间隔过短'
        WHEN name = 'autovacuum' AND setting = 'off' THEN '⚠️ 风险: 关闭自动清理可能导致表膨胀'
        ELSE '✅ 正常'
    END as 风险评估
FROM pg_settings 
WHERE name IN (
    'restart_after_crash',
    'fsync', 
    'synchronous_commit',
    'full_page_writes',
    'wal_level',
    'max_wal_size',
    'checkpoint_timeout',
    'checkpoint_completion_target',
    'autovacuum',
    'shared_buffers',
    'max_connections'
)
ORDER BY 
    CASE 
        WHEN 风险评估 LIKE '%极高风险%' THEN 1
        WHEN 风险评估 LIKE '%高风险%' THEN 2
        WHEN 风险评估 LIKE '%中风险%' THEN 3
        WHEN 风险评估 LIKE '%风险%' THEN 4
        ELSE 5
    END,
    name;
" 2>/dev/null || echo "❌ 无法获取配置信息"
echo

# 3. 检查数据完整性相关配置
echo "3. 数据完整性关键配置检查:"
echo "=================================================="

echo "检查关键的数据安全配置..."
CRITICAL_CONFIGS=$(sudo -u postgres psql -d document_analysis -t -c "
SELECT 
    name || ' = ' || setting || 
    CASE 
        WHEN name = 'fsync' AND setting = 'off' THEN ' 🚨 极危险!'
        WHEN name = 'restart_after_crash' AND setting = 'off' THEN ' ⚠️ 危险!'
        WHEN name = 'full_page_writes' AND setting = 'off' THEN ' ⚠️ 危险!'
        WHEN name = 'synchronous_commit' AND setting = 'off' THEN ' ⚠️ 注意!'
        ELSE ' ✅'
    END
FROM pg_settings 
WHERE name IN ('fsync', 'restart_after_crash', 'full_page_writes', 'synchronous_commit')
ORDER BY name;
" 2>/dev/null)

if [[ -n "$CRITICAL_CONFIGS" ]]; then
    echo "$CRITICAL_CONFIGS"
else
    echo "❌ 无法获取关键配置"
fi
echo

# 4. 检查自动清理配置
echo "4. 自动清理(VACUUM)配置分析:"
echo "=================================================="

sudo -u postgres psql -d document_analysis -c "
SELECT 
    '自动清理配置检查' as 检查项目;

SELECT 
    name as 配置参数,
    setting as 当前值,
    unit as 单位,
    CASE 
        WHEN name = 'autovacuum' AND setting = 'off' THEN '🚨 风险: 关闭自动清理可能导致表膨胀和性能问题'
        WHEN name = 'autovacuum_naptime' AND setting::int > 300 THEN '⚠️ 注意: 清理间隔过长'
        WHEN name = 'autovacuum_vacuum_threshold' AND setting::int > 1000 THEN '⚠️ 注意: 清理阈值过高'
        ELSE '✅ 正常'
    END as 状态评估
FROM pg_settings 
WHERE name LIKE 'autovacuum%'
ORDER BY name;
" 2>/dev/null || echo "❌ 无法获取自动清理配置"
echo

# 5. 检查WAL和checkpoint配置
echo "5. WAL和检查点配置分析:"
echo "=================================================="

sudo -u postgres psql -d document_analysis -c "
SELECT 
    'WAL和检查点配置' as 配置类型;

SELECT 
    name as 配置参数,
    setting as 当前值,
    unit as 单位,
    CASE 
        WHEN name = 'wal_level' AND setting = 'minimal' THEN '⚠️ 注意: 最小WAL级别可能影响恢复'
        WHEN name = 'max_wal_size' AND setting::bigint < 64 THEN '⚠️ 风险: WAL大小过小'
        WHEN name = 'checkpoint_timeout' AND setting::int < 30 THEN '⚠️ 风险: 检查点间隔过短'
        WHEN name = 'checkpoint_completion_target' AND setting::float > 0.95 THEN '⚠️ 注意: 检查点完成目标过高'
        ELSE '✅ 正常'
    END as 状态评估
FROM pg_settings 
WHERE name IN (
    'wal_level', 'max_wal_size', 'min_wal_size', 'wal_buffers',
    'checkpoint_timeout', 'checkpoint_completion_target', 'checkpoint_warning'
)
ORDER BY name;
" 2>/dev/null || echo "❌ 无法获取WAL配置"
echo

# 6. 检查内存配置是否合理
echo "6. 内存配置合理性分析:"
echo "=================================================="

# 获取系统内存
TOTAL_MEM=$(free -m | awk 'NR==2{print $2}')
echo "系统总内存: ${TOTAL_MEM}MB"

# 获取PostgreSQL内存配置
sudo -u postgres psql -d document_analysis -c "
SELECT 
    '内存配置分析' as 分析类型,
    '系统内存: ${TOTAL_MEM}MB' as 系统信息;

SELECT 
    name as 内存配置,
    setting as 当前值,
    unit as 单位,
    CASE 
        WHEN name = 'shared_buffers' THEN 
            CASE 
                WHEN unit = '8kB' AND (setting::bigint * 8 / 1024) > (${TOTAL_MEM} * 0.4) THEN '⚠️ 过高: 超过系统内存40%'
                WHEN unit = '8kB' AND (setting::bigint * 8 / 1024) < (${TOTAL_MEM} * 0.1) THEN '⚠️ 过低: 低于系统内存10%'
                WHEN setting LIKE '%MB' AND setting::int > (${TOTAL_MEM} * 0.4) THEN '⚠️ 过高: 超过系统内存40%'
                WHEN setting LIKE '%MB' AND setting::int < (${TOTAL_MEM} * 0.1) THEN '⚠️ 过低: 低于系统内存10%'
                ELSE '✅ 合理'
            END
        WHEN name = 'work_mem' THEN
            CASE 
                WHEN setting LIKE '%MB' AND setting::int > 50 THEN '⚠️ 注意: work_mem过大可能导致内存耗尽'
                WHEN setting LIKE '%kB' AND setting::int > 51200 THEN '⚠️ 注意: work_mem过大'
                ELSE '✅ 合理'
            END
        ELSE '✅ 检查完成'
    END as 评估结果
FROM pg_settings 
WHERE name IN ('shared_buffers', 'work_mem', 'maintenance_work_mem', 'effective_cache_size')
ORDER BY name;
" 2>/dev/null || echo "❌ 无法获取内存配置"
echo

# 7. 检查日志配置
echo "7. 日志配置分析:"
echo "=================================================="

sudo -u postgres psql -d document_analysis -c "
SELECT 
    '日志配置检查' as 检查类型;

SELECT 
    name as 日志配置,
    setting as 当前值,
    CASE 
        WHEN name = 'logging_collector' AND setting = 'off' THEN '⚠️ 注意: 未启用日志收集'
        WHEN name = 'log_statement' AND setting = 'all' THEN '⚠️ 注意: 记录所有语句，可能影响性能'
        WHEN name = 'log_min_duration_statement' AND setting = '0' THEN '⚠️ 注意: 记录所有语句执行时间'
        WHEN name = 'log_connections' AND setting = 'on' THEN 'ℹ️ 信息: 记录连接信息'
        WHEN name = 'log_disconnections' AND setting = 'on' THEN 'ℹ️ 信息: 记录断开连接'
        ELSE '✅ 正常'
    END as 状态
FROM pg_settings 
WHERE name IN (
    'logging_collector', 'log_statement', 'log_min_duration_statement',
    'log_connections', 'log_disconnections', 'log_checkpoints'
)
ORDER BY name;
" 2>/dev/null || echo "❌ 无法获取日志配置"
echo

# 8. 分析配置文件中的自定义配置
echo "8. 配置文件自定义设置分析:"
echo "=================================================="

CONFIG_FILE="$PG_DATA_DIR/postgresql.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    echo "分析 postgresql.conf 中的自定义配置..."
    echo
    
    echo "已启用的非默认配置:"
    echo "----------------------------"
    # 查找所有非注释的配置行
    grep -v "^#" "$CONFIG_FILE" | grep -v "^$" | while read line; do
        if [[ "$line" =~ ^[[:space:]]*([^=]+)=[[:space:]]*(.+)$ ]]; then
            param=$(echo "${BASH_REMATCH[1]}" | xargs)
            value=$(echo "${BASH_REMATCH[2]}" | xargs)
            echo "  $param = $value"
            
            # 检查危险配置
            case "$param" in
                "fsync")
                    if [[ "$value" =~ (off|false) ]]; then
                        echo "    🚨 极危险: fsync=off 可能导致数据丢失!"
                    fi
                    ;;
                "restart_after_crash")
                    if [[ "$value" =~ (off|false) ]]; then
                        echo "    ⚠️ 风险: 崩溃后不自动重启"
                    fi
                    ;;
                "full_page_writes")
                    if [[ "$value" =~ (off|false) ]]; then
                        echo "    ⚠️ 风险: 可能导致页面损坏"
                    fi
                    ;;
                "synchronous_commit")
                    if [[ "$value" =~ (off|false) ]]; then
                        echo "    ⚠️ 注意: 异步提交模式"
                    fi
                    ;;
            esac
        fi
    done
    
    echo
    echo "检查是否有重复配置..."
    echo "----------------------------"
    # 检查重复的配置参数
    grep -v "^#" "$CONFIG_FILE" | grep -v "^$" | grep "=" | sed 's/[[:space:]]*=.*//' | sort | uniq -d | while read param; do
        echo "⚠️ 发现重复配置: $param"
        echo "   出现位置:"
        grep -n "^[[:space:]]*$param[[:space:]]*=" "$CONFIG_FILE" | sed 's/^/     /'
    done
    
else
    echo "❌ 无法找到 postgresql.conf 配置文件"
fi
echo

# 9. 检查最近的配置变更
echo "9. 最近配置变更历史:"
echo "=================================================="

echo "查找最近修改的PostgreSQL相关文件..."
find "$PG_DATA_DIR" -name "*.conf" -mtime -7 -exec ls -la {} \; 2>/dev/null | while read file_info; do
    echo "📝 $file_info"
done

echo
echo "查找配置备份文件..."
find "$PG_DATA_DIR" -name "postgresql.conf.*" -exec ls -la {} \; 2>/dev/null | while read backup_file; do
    echo "📦 备份文件: $backup_file"
done
echo

# 10. SystemD服务配置检查
echo "10. SystemD服务配置检查:"
echo "=================================================="

echo "PostgreSQL systemd服务文件分析..."
SERVICE_FILES=("/usr/lib/systemd/system/postgresql.service" "/etc/systemd/system/postgresql.service")

for service_file in "${SERVICE_FILES[@]}"; do
    if [[ -f "$service_file" ]]; then
        echo "发现服务文件: $service_file"
        echo "修改时间: $(stat -c %y "$service_file")"
        echo "内容摘要:"
        grep -E "(ExecStart|ExecReload|ExecStop|KillMode|Restart)" "$service_file" | sed 's/^/  /'
        echo
    fi
done

# 检查systemd覆盖配置
OVERRIDE_DIR="/etc/systemd/system/postgresql.service.d"
if [[ -d "$OVERRIDE_DIR" ]]; then
    echo "发现systemd覆盖配置:"
    find "$OVERRIDE_DIR" -name "*.conf" -exec echo "文件: {}" \; -exec cat {} \; -exec echo \;
else
    echo "✅ 无systemd覆盖配置"
fi
echo

# 11. 生成风险评估报告
echo "11. 配置风险评估报告:"
echo "=================================================="

REPORT_FILE="/tmp/pg_config_risk_analysis_$(date +%Y%m%d_%H%M%S).txt"

{
    echo "PostgreSQL 配置风险分析报告"
    echo "============================"
    echo "分析时间: $(date)"
    echo "数据库: document_analysis"
    echo "系统内存: ${TOTAL_MEM}MB"
    echo
    
    echo "🚨 高风险配置检查:"
    echo "----------------"
    
    # 检查关键安全配置
    FSYNC_STATUS=$(sudo -u postgres psql -d document_analysis -t -c "SELECT setting FROM pg_settings WHERE name='fsync';" 2>/dev/null | xargs)
    if [[ "$FSYNC_STATUS" == "off" ]]; then
        echo "❌ CRITICAL: fsync=off - 可能导致数据丢失"
    else
        echo "✅ fsync=$FSYNC_STATUS - 正常"
    fi
    
    RESTART_STATUS=$(sudo -u postgres psql -d document_analysis -t -c "SELECT setting FROM pg_settings WHERE name='restart_after_crash';" 2>/dev/null | xargs)
    if [[ "$RESTART_STATUS" == "off" ]]; then
        echo "⚠️ WARNING: restart_after_crash=off - 崩溃后不自动重启"
    else
        echo "✅ restart_after_crash=$RESTART_STATUS - 正常"
    fi
    
    AUTOVACUUM_STATUS=$(sudo -u postgres psql -d document_analysis -t -c "SELECT setting FROM pg_settings WHERE name='autovacuum';" 2>/dev/null | xargs)
    if [[ "$AUTOVACUUM_STATUS" == "off" ]]; then
        echo "⚠️ WARNING: autovacuum=off - 可能导致表膨胀"
    else
        echo "✅ autovacuum=$AUTOVACUUM_STATUS - 正常"
    fi
    
    echo
    echo "📊 建议改进措施:"
    echo "---------------"
    echo "1. 确保 fsync=on (数据安全)"
    echo "2. 确保 restart_after_crash=on (服务稳定性)"
    echo "3. 确保 autovacuum=on (表维护)"
    echo "4. 定期检查日志文件"
    echo "5. 监控内存使用情况"
    echo "6. 备份重要配置文件"
    
} > "$REPORT_FILE"

echo "✅ 配置风险分析报告已生成: $REPORT_FILE"
echo
echo "报告摘要:"
cat "$REPORT_FILE"
echo

echo "=== 配置分析完成 ==="
echo "📋 详细报告: $REPORT_FILE"
echo "🔍 建议: 重点关注上述风险配置项"
echo "⚠️ 如发现高风险配置，建议立即修复" 