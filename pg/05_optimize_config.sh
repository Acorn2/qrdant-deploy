#!/bin/bash

# PostgreSQL 配置优化脚本
# 优化系统配置以提高稳定性

echo "=== PostgreSQL 配置优化 ==="
echo "执行时间: $(date)"
echo

# 1. 检查当前systemd配置
echo "1. 检查当前systemd资源限制配置:"
echo "----------------------------------------"
if [[ -f /etc/systemd/system/postgresql.service.d/cpu-limit.conf ]]; then
    echo "当前配置:"
    cat /etc/systemd/system/postgresql.service.d/cpu-limit.conf
else
    echo "未找到现有的资源限制配置"
fi
echo

# 2. 备份当前PostgreSQL配置
echo "2. 备份PostgreSQL配置文件..."
sudo cp /var/lib/pgsql/data/postgresql.conf /var/lib/pgsql/data/postgresql.conf.optimize_backup.$(date +%Y%m%d_%H%M%S)
echo "✓ 配置文件已备份"
echo

# 3. 创建优化的systemd配置
echo "3. 创建优化的systemd资源配置..."
sudo mkdir -p /etc/systemd/system/postgresql.service.d

sudo tee /etc/systemd/system/postgresql.service.d/resource-optimize.conf << 'EOF'
[Service]
# 优化资源限制配置 (适用于4G内存服务器)
CPUQuota=80%
MemoryLimit=2G
TasksMax=300

# 添加重启策略
Restart=on-failure
RestartSec=10
StartLimitInterval=300
StartLimitBurst=3

# 提高服务优先级
OOMScoreAdjust=-100

# 日志配置
StandardOutput=journal
StandardError=journal
SyslogIdentifier=postgresql
EOF

echo "✓ systemd配置已优化"
echo

# 4. 添加PostgreSQL性能优化配置
echo "4. 添加PostgreSQL性能优化配置..."
sudo tee -a /var/lib/pgsql/data/postgresql.conf << 'EOF'

# === PostgreSQL 性能和稳定性优化配置 ===
# 添加时间: 
# 内存配置优化 (适用于4G内存服务器)
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 4MB
maintenance_work_mem = 64MB

# WAL 配置优化 (适用于4G内存服务器)
wal_level = replica
max_wal_size = 1GB
min_wal_size = 80MB
checkpoint_completion_target = 0.9
checkpoint_timeout = 15min
wal_buffers = 8MB

# 连接配置 (适用于4G内存服务器)
max_connections = 100
superuser_reserved_connections = 3

# 自动清理配置 (适用于4G内存服务器)
autovacuum = on
autovacuum_max_workers = 2
autovacuum_naptime = 1min
autovacuum_vacuum_threshold = 50
autovacuum_analyze_threshold = 50

# 统计信息收集
track_activities = on
track_counts = on
track_io_timing = on
track_functions = all

# 查询性能优化
random_page_cost = 1.1
effective_io_concurrency = 200

# 稳定性配置
restart_after_crash = on
shared_preload_libraries = 'auto_explain'

# 自动解释长查询
auto_explain.log_min_duration = '10s'
auto_explain.log_analyze = on
auto_explain.log_buffers = on
EOF

echo "✓ PostgreSQL配置已优化"
echo

# 5. 优化系统内核参数
echo "5. 优化系统内核参数..."
sudo tee -a /etc/sysctl.conf << 'EOF'

# PostgreSQL 内核参数优化
vm.swappiness = 10
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 500
kernel.shmmax = 1073741824
kernel.shmall = 262144
fs.file-max = 65536
EOF

# 应用内核参数
sudo sysctl -p
echo "✓ 内核参数已优化"
echo

# 6. 询问是否重启服务
echo "6. 应用配置..."
read -p "是否立即重启PostgreSQL服务以应用所有配置？(y/N): " confirm
if [[ $confirm == [yY] ]]; then
    echo "重新加载systemd配置..."
    sudo systemctl daemon-reload
    
    echo "重启PostgreSQL服务..."
    sudo systemctl restart postgresql
    
    # 等待服务启动
    sleep 10
    
    # 检查服务状态
    if sudo systemctl is-active --quiet postgresql; then
        echo "✅ PostgreSQL服务重启成功"
        
        # 显示服务状态
        echo "服务状态:"
        sudo systemctl status postgresql --no-pager -l
        
        # 测试数据库连接
        echo "测试数据库连接:"
        if sudo -u postgres psql -d document_analysis -c "SELECT 'PostgreSQL优化配置应用成功' as status;"; then
            echo "✅ 数据库连接正常"
        else
            echo "❌ 数据库连接失败"
        fi
    else
        echo "❌ PostgreSQL服务重启失败"
        echo "检查服务状态:"
        sudo systemctl status postgresql --no-pager -l
        echo "检查配置文件语法:"
        sudo -u postgres /usr/bin/postgres --describe-config || echo "配置文件可能有语法错误"
    fi
else
    echo "⚠️  配置已准备就绪，下次重启PostgreSQL时将生效"
    echo "手动重启命令: sudo systemctl restart postgresql"
fi

echo
echo "=== 配置优化完成 ==="
echo "优化内容："
echo "- systemd资源限制调整"
echo "- PostgreSQL内存和性能参数优化"
echo "- WAL配置优化"
echo "- 自动清理策略优化"
echo "- 系统内核参数优化" 