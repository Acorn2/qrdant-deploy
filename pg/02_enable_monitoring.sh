#!/bin/bash

# PostgreSQL 启用详细监控脚本
# 启用详细日志记录和实时监控

echo "=== 启用PostgreSQL详细监控 ==="
echo "执行时间: $(date)"
echo

# 1. 备份原配置文件
echo "1. 备份PostgreSQL配置文件..."
sudo cp /var/lib/pgsql/data/postgresql.conf /var/lib/pgsql/data/postgresql.conf.backup.$(date +%Y%m%d_%H%M%S)
echo "✓ 配置文件已备份"
echo

# 2. 启用详细日志记录
echo "2. 启用详细日志记录..."
sudo tee -a /var/lib/pgsql/data/postgresql.conf << 'EOF'

# === PostgreSQL 详细日志配置 - 故障排查专用 ===
# 记录所有SQL语句
log_statement = 'all'

# 记录语句执行时间
log_duration = on
log_min_duration_statement = 0

# 记录连接信息
log_connections = on
log_disconnections = on

# 记录锁等待
log_lock_waits = on

# 记录检查点
log_checkpoints = on

# 记录自动清理操作
log_autovacuum_min_duration = 0

# 记录错误详情
log_error_verbosity = verbose

# 日志文件配置
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_file_mode = 0600
log_rotation_age = 1d
log_rotation_size = 100MB
EOF

echo "✓ 详细日志配置已添加"
echo

# 3. 重启PostgreSQL使配置生效
echo "3. 重启PostgreSQL服务以应用配置..."
read -p "确认重启PostgreSQL服务？(y/N): " confirm
if [[ $confirm == [yY] ]]; then
    sudo systemctl restart postgresql
    sleep 5
    
    # 检查服务状态
    if sudo systemctl is-active --quiet postgresql; then
        echo "✓ PostgreSQL服务重启成功"
    else
        echo "✗ PostgreSQL服务重启失败，请检查配置"
        exit 1
    fi
else
    echo "! 跳过重启，配置将在下次重启时生效"
fi
echo

echo "=== 详细监控已启用 ==="
echo "注意：这会产生大量日志，排查完成后请运行 09_restore_config.sh 恢复正常配置" 