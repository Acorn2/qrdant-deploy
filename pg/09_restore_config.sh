#!/bin/bash

# PostgreSQL 配置恢复脚本
# 恢复PostgreSQL到正常配置状态

echo "=== PostgreSQL 配置恢复脚本 ==="
echo "执行时间: $(date)"
echo

# 查找备份配置文件
find_backup_configs() {
    echo "1. 查找可用的配置备份文件:"
    echo "----------------------------------------"
    
    local config_dir="/var/lib/pgsql/data"
    local backup_files=()
    
    # 查找所有备份文件
    while IFS= read -r -d '' file; do
        backup_files+=("$file")
    done < <(find "$config_dir" -name "postgresql.conf.backup*" -o -name "postgresql.conf.*backup*" -print0 2>/dev/null | sort -z)
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        echo "❌ 未找到任何配置备份文件"
        echo "请手动检查 $config_dir 目录"
        return 1
    fi
    
    echo "找到 ${#backup_files[@]} 个备份文件:"
    for i in "${!backup_files[@]}"; do
        local file="${backup_files[$i]}"
        local file_date=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
        local file_size=$(stat -c %s "$file" 2>/dev/null)
        echo "  $((i+1)). $(basename "$file") - $file_date - ${file_size} bytes"
    done
    
    echo
    read -p "选择要恢复的备份文件 (1-${#backup_files[@]}，回车选择最新): " choice
    
    if [[ -z "$choice" ]]; then
        # 选择最新的备份文件
        SELECTED_BACKUP="${backup_files[-1]}"
        echo "已选择最新备份: $(basename "$SELECTED_BACKUP")"
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#backup_files[@]} ]]; then
        SELECTED_BACKUP="${backup_files[$((choice-1))]}"
        echo "已选择: $(basename "$SELECTED_BACKUP")"
    else
        echo "❌ 无效选择"
        return 1
    fi
    
    return 0
}

# 备份当前配置
backup_current_config() {
    echo "2. 备份当前配置文件:"
    echo "----------------------------------------"
    
    local current_config="/var/lib/pgsql/data/postgresql.conf"
    local backup_name="postgresql.conf.before_restore.$(date +%Y%m%d_%H%M%S)"
    local backup_path="/var/lib/pgsql/data/$backup_name"
    
    if sudo cp "$current_config" "$backup_path"; then
        echo "✅ 当前配置已备份到: $backup_name"
        CURRENT_BACKUP="$backup_path"
    else
        echo "❌ 备份当前配置失败"
        return 1
    fi
}

# 恢复配置文件
restore_config() {
    echo "3. 恢复配置文件:"
    echo "----------------------------------------"
    
    local current_config="/var/lib/pgsql/data/postgresql.conf"
    
    echo "从备份恢复配置文件..."
    if sudo cp "$SELECTED_BACKUP" "$current_config"; then
        echo "✅ 配置文件已恢复"
        
        # 显示恢复的配置信息
        echo "恢复的配置文件信息:"
        echo "  源文件: $(basename "$SELECTED_BACKUP")"
        echo "  大小: $(stat -c %s "$current_config" 2>/dev/null) bytes"
        echo "  修改时间: $(stat -c %y "$current_config" 2>/dev/null)"
        
        return 0
    else
        echo "❌ 恢复配置文件失败"
        return 1
    fi
}

# 移除调试配置
remove_debug_config() {
    echo "4. 移除调试配置:"
    echo "----------------------------------------"
    
    local config_file="/var/lib/pgsql/data/postgresql.conf"
    local temp_file="/tmp/postgresql_clean.conf"
    
    echo "移除详细日志配置..."
    
    # 创建临时文件，排除调试相关配置
    sudo grep -v -E "^(log_statement|log_duration|log_min_duration_statement|log_connections|log_disconnections|log_lock_waits|log_checkpoints|log_autovacuum_min_duration|log_error_verbosity)" "$config_file" > "$temp_file" 2>/dev/null
    
    # 检查是否有变化
    if ! sudo diff -q "$config_file" "$temp_file" > /dev/null 2>&1; then
        echo "发现调试配置，正在移除..."
        sudo cp "$temp_file" "$config_file"
        echo "✅ 调试配置已移除"
    else
        echo "✅ 无需移除调试配置"
    fi
    
    # 清理临时文件
    rm -f "$temp_file"
}

# 恢复systemd配置
restore_systemd_config() {
    echo "5. 恢复systemd配置:"
    echo "----------------------------------------"
    
    local resource_config="/etc/systemd/system/postgresql.service.d/resource-optimize.conf"
    local cpu_config="/etc/systemd/system/postgresql.service.d/cpu-limit.conf"
    
    read -p "是否恢复systemd资源限制到保守配置？(y/N): " restore_systemd
    
    if [[ $restore_systemd == [yY] ]]; then
        echo "创建保守的systemd配置..."
        
        sudo mkdir -p /etc/systemd/system/postgresql.service.d
                 sudo tee "$resource_config" << 'EOF'
[Service]
# 保守的资源限制配置 (适用于4G内存服务器)
CPUQuota=70%
MemoryLimit=2G
TasksMax=200

# 基本重启策略
Restart=on-failure
RestartSec=5

# 日志配置
StandardOutput=journal
StandardError=journal
SyslogIdentifier=postgresql
EOF
        
        echo "✅ systemd配置已恢复到保守设置"
        SYSTEMD_CHANGED=true
    else
        echo "⏭️  跳过systemd配置恢复"
        SYSTEMD_CHANGED=false
    fi
}

# 创建基本的生产配置
create_production_config() {
    echo "6. 应用生产环境配置:"
    echo "----------------------------------------"
    
    read -p "是否应用推荐的生产环境配置？(y/N): " apply_prod
    
    if [[ $apply_prod == [yY] ]]; then
        echo "添加生产环境优化配置..."
        
        sudo tee -a /var/lib/pgsql/data/postgresql.conf << 'EOF'

# === 生产环境配置 (恢复脚本添加) ===
# 基本性能配置 (适用于4G内存服务器)
shared_buffers = 128MB
effective_cache_size = 512MB
work_mem = 2MB
maintenance_work_mem = 32MB

# WAL配置 (适用于4G内存服务器)
wal_level = replica
max_wal_size = 512MB
min_wal_size = 80MB
checkpoint_completion_target = 0.9

# 连接配置 (适用于4G内存服务器)
max_connections = 50

# 自动清理
autovacuum = on
autovacuum_naptime = 1min

# 基本日志配置
log_min_messages = warning
log_min_error_statement = error
log_min_duration_statement = 1000

# 统计信息
track_activities = on
track_counts = on
EOF
        
        echo "✅ 生产环境配置已应用"
    else
        echo "⏭️  跳过生产环境配置"
    fi
}

# 验证配置文件
validate_config() {
    echo "7. 验证配置文件:"
    echo "----------------------------------------"
    
    echo "检查配置文件语法..."
    if sudo -u postgres /usr/bin/postgres --describe-config > /dev/null 2>&1; then
        echo "✅ 配置文件语法正确"
        return 0
    else
        echo "❌ 配置文件语法错误"
        echo "尝试恢复到之前的配置..."
        
        if [[ -n "$CURRENT_BACKUP" ]]; then
            sudo cp "$CURRENT_BACKUP" /var/lib/pgsql/data/postgresql.conf
            echo "⚠️  已恢复到操作前的配置"
        fi
        return 1
    fi
}

# 重启PostgreSQL服务
restart_postgresql() {
    echo "8. 重启PostgreSQL服务:"
    echo "----------------------------------------"
    
    read -p "是否重启PostgreSQL以应用配置？(y/N): " restart_confirm
    
    if [[ $restart_confirm == [yY] ]]; then
        echo "重启PostgreSQL服务..."
        
        # 如果systemd配置有变化，先重新加载
        if [[ "$SYSTEMD_CHANGED" == true ]]; then
            echo "重新加载systemd配置..."
            sudo systemctl daemon-reload
        fi
        
        # 重启PostgreSQL
        sudo systemctl restart postgresql
        
        # 等待服务启动
        sleep 5
        
        # 检查服务状态
        if sudo systemctl is-active --quiet postgresql; then
            echo "✅ PostgreSQL服务重启成功"
            
            # 测试数据库连接
            if sudo -u postgres psql -d document_analysis -c "SELECT 'Configuration restored successfully' as status;" 2>/dev/null; then
                echo "✅ 数据库连接正常"
            else
                echo "⚠️  数据库连接可能有问题"
            fi
        else
            echo "❌ PostgreSQL服务重启失败"
            echo "服务状态:"
            sudo systemctl status postgresql --no-pager -l
            return 1
        fi
    else
        echo "⚠️  配置已准备就绪，需要重启PostgreSQL才能生效"
        echo "手动重启命令: sudo systemctl restart postgresql"
    fi
}

# 清理调试日志
cleanup_debug_logs() {
    echo "9. 清理调试日志:"
    echo "----------------------------------------"
    
    read -p "是否清理调试期间产生的大日志文件？(y/N): " cleanup_logs
    
    if [[ $cleanup_logs == [yY] ]]; then
        echo "查找大日志文件..."
        
        # 查找大于100MB的日志文件
        local large_logs=$(find /var/lib/pgsql/data/log -name "*.log" -size +100M 2>/dev/null)
        
        if [[ -n "$large_logs" ]]; then
            echo "找到大日志文件:"
            echo "$large_logs" | while read -r logfile; do
                local size=$(du -h "$logfile" | cut -f1)
                echo "  $logfile ($size)"
            done
            
            read -p "是否删除这些大日志文件？(y/N): " delete_confirm
            if [[ $delete_confirm == [yY] ]]; then
                echo "$large_logs" | xargs sudo rm -f
                echo "✅ 大日志文件已清理"
            fi
        else
            echo "✅ 无需清理的大日志文件"
        fi
        
        # 清理监控日志
        if [[ -f /var/log/table_monitor.log ]]; then
            local monitor_size=$(du -h /var/log/table_monitor.log | cut -f1)
            read -p "是否清理表监控日志？当前大小: $monitor_size (y/N): " clean_monitor
            if [[ $clean_monitor == [yY] ]]; then
                sudo truncate -s 0 /var/log/table_monitor.log
                echo "✅ 表监控日志已清理"
            fi
        fi
        
        if [[ -f /var/log/pg_connections.log ]]; then
            local conn_size=$(du -h /var/log/pg_connections.log | cut -f1)
            read -p "是否清理连接监控日志？当前大小: $conn_size (y/N): " clean_conn
            if [[ $clean_conn == [yY] ]]; then
                sudo truncate -s 0 /var/log/pg_connections.log
                echo "✅ 连接监控日志已清理"
            fi
        fi
    else
        echo "⏭️  跳过日志清理"
    fi
}

# 生成恢复报告
generate_restore_report() {
    echo "10. 生成恢复报告:"
    echo "----------------------------------------"
    
    local report_file="/tmp/pg_restore_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "PostgreSQL 配置恢复报告"
        echo "========================"
        echo "恢复时间: $(date)"
        echo "操作者: $(whoami)"
        echo
        echo "恢复操作:"
        echo "- 配置文件: $(basename "$SELECTED_BACKUP") -> postgresql.conf"
        echo "- systemd配置: $([[ "$SYSTEMD_CHANGED" == true ]] && echo "已恢复" || echo "未修改")"
        echo "- 生产配置: $([[ $apply_prod == [yY] ]] && echo "已应用" || echo "未应用")"
        echo
        echo "服务状态:"
        echo "- PostgreSQL: $(sudo systemctl is-active postgresql 2>/dev/null || echo "unknown")"
        echo "- 数据库连接: $(sudo -u postgres psql -d document_analysis -c "SELECT 1;" >/dev/null 2>&1 && echo "正常" || echo "异常")"
        echo
        echo "备份文件:"
        echo "- 恢复前配置: $(basename "$CURRENT_BACKUP")"
        echo
        echo "后续建议:"
        echo "- 监控PostgreSQL性能表现"
        echo "- 确认应用程序连接正常"
        echo "- 如有问题可使用备份文件回滚"
    } > "$report_file"
    
    echo "✅ 恢复报告已保存: $report_file"
}

# 显示恢复后状态
show_final_status() {
    echo "11. 恢复后状态检查:"
    echo "----------------------------------------"
    
    echo "PostgreSQL服务状态:"
    sudo systemctl status postgresql --no-pager -l | head -5
    
    echo
    echo "当前配置关键参数:"
    sudo -u postgres psql -d document_analysis -c "
    SELECT name, setting, unit 
    FROM pg_settings 
    WHERE name IN ('shared_buffers', 'max_connections', 'log_statement', 'autovacuum')
    ORDER BY name;
    " 2>/dev/null || echo "无法获取配置信息"
    
    echo
    echo "数据库表状态:"
    sudo -u postgres psql -d document_analysis -c "
    SELECT 
        schemaname,
        tablename,
        n_live_tup as 活跃行数
    FROM pg_stat_user_tables 
    ORDER BY tablename;
    " 2>/dev/null || echo "无法获取表状态"
}

# 主函数
main() {
    # 检查权限
    if [[ $EUID -ne 0 ]]; then
        echo "❌ 此脚本需要root权限运行"
        echo "请使用: sudo $0"
        exit 1
    fi
    
    echo "此脚本将恢复PostgreSQL配置到正常状态"
    echo "⚠️  这将移除调试配置和详细日志记录"
    echo
    read -p "确认继续恢复配置？(y/N): " confirm
    
    if [[ $confirm != [yY] ]]; then
        echo "取消恢复操作"
        exit 0
    fi
    
    # 执行恢复流程
    find_backup_configs || exit 1
    echo
    
    backup_current_config || exit 1
    echo
    
    restore_config || exit 1
    echo
    
    remove_debug_config
    echo
    
    restore_systemd_config
    echo
    
    create_production_config
    echo
    
    validate_config || exit 1
    echo
    
    restart_postgresql
    echo
    
    cleanup_debug_logs
    echo
    
    generate_restore_report
    echo
    
    show_final_status
    echo
    
    echo "=== 配置恢复完成 ==="
    echo "✅ PostgreSQL已恢复到正常配置"
    echo "📋 恢复报告: /tmp/pg_restore_report_*.txt"
    echo "🔄 如需回滚: 使用备份文件 $(basename "$CURRENT_BACKUP")"
}

# 执行主函数
main "$@" 