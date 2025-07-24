#!/bin/bash

# PostgreSQL 启动所有监控脚本
# 一键启动表监控和连接监控

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== 启动PostgreSQL监控系统 ==="
echo "执行时间: $(date)"
echo "脚本目录: $SCRIPT_DIR"
echo

# 检查脚本文件是否存在
check_script() {
    local script="$1"
    if [[ ! -f "$script" ]]; then
        echo "❌ 脚本文件不存在: $script"
        return 1
    fi
    
    if [[ ! -x "$script" ]]; then
        echo "⚠️  脚本没有执行权限，正在添加: $script"
        chmod +x "$script"
    fi
    return 0
}

# 停止现有监控
stop_existing_monitors() {
    echo "1. 停止现有监控进程..."
    
    # 停止表监控
    if [[ -f /var/run/table_monitor.pid ]]; then
        local table_pid=$(cat /var/run/table_monitor.pid 2>/dev/null)
        if [[ -n "$table_pid" ]] && ps -p "$table_pid" > /dev/null 2>&1; then
            echo "  停止表监控 (PID: $table_pid)"
            sudo kill "$table_pid" 2>/dev/null || true
            sleep 2
        fi
        sudo rm -f /var/run/table_monitor.pid
    fi
    
    # 停止连接监控
    if [[ -f /var/run/connection_monitor.pid ]]; then
        local conn_pid=$(cat /var/run/connection_monitor.pid 2>/dev/null)
        if [[ -n "$conn_pid" ]] && ps -p "$conn_pid" > /dev/null 2>&1; then
            echo "  停止连接监控 (PID: $conn_pid)"
            sudo kill "$conn_pid" 2>/dev/null || true
            sleep 2
        fi
        sudo rm -f /var/run/connection_monitor.pid
    fi
    
    echo "✓ 现有监控已停止"
}

# 启动表监控
start_table_monitor() {
    echo "2. 启动表监控..."
    
    local script="$SCRIPT_DIR/03_table_monitor.sh"
    if check_script "$script"; then
        # 询问监控间隔
        read -p "表监控间隔 (秒，默认60): " table_interval
        table_interval=${table_interval:-60}
        
        echo "  启动表监控，间隔: $table_interval 秒"
        nohup bash "$script" "$table_interval" > /dev/null 2>&1 &
        local pid=$!
        sleep 2
        
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "✅ 表监控启动成功 (PID: $pid)"
            echo "   日志文件: /var/log/table_monitor.log"
            echo "   实时查看: tail -f /var/log/table_monitor.log"
        else
            echo "❌ 表监控启动失败"
            return 1
        fi
    else
        return 1
    fi
}

# 启动连接监控
start_connection_monitor() {
    echo "3. 启动连接监控..."
    
    local script="$SCRIPT_DIR/04_connection_monitor.sh"
    if check_script "$script"; then
        # 询问监控间隔
        read -p "连接监控间隔 (秒，默认300): " conn_interval
        conn_interval=${conn_interval:-300}
        
        echo "  启动连接监控，间隔: $conn_interval 秒"
        nohup bash "$script" "$conn_interval" > /dev/null 2>&1 &
        local pid=$!
        sleep 2
        
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "✅ 连接监控启动成功 (PID: $pid)"
            echo "   日志文件: /var/log/pg_connections.log"
            echo "   实时查看: tail -f /var/log/pg_connections.log"
        else
            echo "❌ 连接监控启动失败"
            return 1
        fi
    else
        return 1
    fi
}

# 创建监控管理脚本
create_monitor_manager() {
    echo "4. 创建监控管理脚本..."
    
    local manager_script="/usr/local/bin/pg_monitor_manager.sh"
    sudo tee "$manager_script" << 'EOF'
#!/bin/bash

# PostgreSQL 监控管理脚本

show_status() {
    echo "=== PostgreSQL 监控状态 ==="
    echo "时间: $(date)"
    echo
    
    # 检查表监控
    if [[ -f /var/run/table_monitor.pid ]]; then
        local table_pid=$(cat /var/run/table_monitor.pid 2>/dev/null)
        if [[ -n "$table_pid" ]] && ps -p "$table_pid" > /dev/null 2>&1; then
            echo "✅ 表监控运行中 (PID: $table_pid)"
            echo "   日志: /var/log/table_monitor.log"
            echo "   最后更新: $(stat -c %y /var/log/table_monitor.log 2>/dev/null || echo '未知')"
        else
            echo "❌ 表监控未运行"
        fi
    else
        echo "❌ 表监控未运行"
    fi
    
    # 检查连接监控
    if [[ -f /var/run/connection_monitor.pid ]]; then
        local conn_pid=$(cat /var/run/connection_monitor.pid 2>/dev/null)
        if [[ -n "$conn_pid" ]] && ps -p "$conn_pid" > /dev/null 2>&1; then
            echo "✅ 连接监控运行中 (PID: $conn_pid)"
            echo "   日志: /var/log/pg_connections.log"
            echo "   最后更新: $(stat -c %y /var/log/pg_connections.log 2>/dev/null || echo '未知')"
        else
            echo "❌ 连接监控未运行"
        fi
    else
        echo "❌ 连接监控未运行"
    fi
    
    echo
    echo "日志文件大小:"
    ls -lh /var/log/table_monitor.log /var/log/pg_connections.log 2>/dev/null || echo "无日志文件"
}

stop_monitors() {
    echo "停止所有监控..."
    
    # 停止表监控
    if [[ -f /var/run/table_monitor.pid ]]; then
        local table_pid=$(cat /var/run/table_monitor.pid 2>/dev/null)
        if [[ -n "$table_pid" ]] && ps -p "$table_pid" > /dev/null 2>&1; then
            kill "$table_pid" 2>/dev/null || true
            echo "表监控已停止"
        fi
        rm -f /var/run/table_monitor.pid
    fi
    
    # 停止连接监控
    if [[ -f /var/run/connection_monitor.pid ]]; then
        local conn_pid=$(cat /var/run/connection_monitor.pid 2>/dev/null)
        if [[ -n "$conn_pid" ]] && ps -p "$conn_pid" > /dev/null 2>&1; then
            kill "$conn_pid" 2>/dev/null || true
            echo "连接监控已停止"
        fi
        rm -f /var/run/connection_monitor.pid
    fi
}

show_logs() {
    echo "=== 最新监控日志 ==="
    echo
    echo "表监控最新10条记录:"
    echo "--------------------"
    tail -20 /var/log/table_monitor.log 2>/dev/null | grep -A2 -B2 "===" | tail -10 || echo "无表监控日志"
    
    echo
    echo "连接监控最新5条记录:"
    echo "--------------------"
    tail -30 /var/log/pg_connections.log 2>/dev/null | grep -A5 -B1 "===" | tail -15 || echo "无连接监控日志"
}

case "${1:-status}" in
    "status"|"s")
        show_status
        ;;
    "stop")
        stop_monitors
        ;;
    "logs"|"l")
        show_logs
        ;;
    "tail"|"t")
        echo "实时查看监控日志 (按Ctrl+C退出):"
        echo "表监控: tail -f /var/log/table_monitor.log"
        echo "连接监控: tail -f /var/log/pg_connections.log"
        echo
        read -p "选择查看 [t]表监控 或 [c]连接监控: " choice
        case "$choice" in
            "t"|"table")
                tail -f /var/log/table_monitor.log
                ;;
            "c"|"connection")
                tail -f /var/log/pg_connections.log
                ;;
            *)
                echo "无效选择"
                ;;
        esac
        ;;
    "help"|"h")
        echo "PostgreSQL 监控管理脚本"
        echo "用法: $0 [命令]"
        echo
        echo "命令:"
        echo "  status, s    - 显示监控状态 (默认)"
        echo "  stop         - 停止所有监控"
        echo "  logs, l      - 显示最新日志"
        echo "  tail, t      - 实时查看日志"
        echo "  help, h      - 显示帮助"
        ;;
    *)
        echo "未知命令: $1"
        echo "使用 '$0 help' 查看帮助"
        ;;
esac
EOF

    sudo chmod +x "$manager_script"
    echo "✅ 监控管理脚本已创建: $manager_script"
    echo "   使用方法: sudo pg_monitor_manager.sh [status|stop|logs|tail|help]"
}

# 显示使用说明
show_usage() {
    echo "5. 监控系统使用说明:"
    echo "=========================================="
    echo "管理命令:"
    echo "  sudo pg_monitor_manager.sh status  - 查看监控状态"
    echo "  sudo pg_monitor_manager.sh stop    - 停止所有监控"
    echo "  sudo pg_monitor_manager.sh logs    - 查看最新日志"
    echo "  sudo pg_monitor_manager.sh tail    - 实时查看日志"
    echo
    echo "日志文件:"
    echo "  表监控日志: /var/log/table_monitor.log"
    echo "  连接监控日志: /var/log/pg_connections.log"
    echo
    echo "实时查看命令:"
    echo "  tail -f /var/log/table_monitor.log"
    echo "  tail -f /var/log/pg_connections.log"
    echo
    echo "停止监控:"
    echo "  sudo pg_monitor_manager.sh stop"
    echo
    echo "重要提醒:"
    echo "- 监控会持续运行直到手动停止"
    echo "- 日志文件会不断增长，定期清理"
    echo "- 如发现表被清空，立即查看日志文件"
}

# 主执行流程
main() {
    # 检查权限
    if [[ $EUID -ne 0 ]]; then
        echo "❌ 此脚本需要root权限运行"
        echo "请使用: sudo $0"
        exit 1
    fi
    
    # 检查PostgreSQL是否运行
    if ! systemctl is-active --quiet postgresql; then
        echo "❌ PostgreSQL服务未运行"
        echo "请先启动PostgreSQL: sudo systemctl start postgresql"
        exit 1
    fi
    
    # 询问是否继续
    read -p "是否启动PostgreSQL监控系统？(y/N): " confirm
    if [[ $confirm != [yY] ]]; then
        echo "取消启动监控"
        exit 0
    fi
    
    # 执行启动流程
    stop_existing_monitors
    echo
    
    start_table_monitor
    echo
    
    start_connection_monitor  
    echo
    
    create_monitor_manager
    echo
    
    show_usage
    echo
    
    echo "=== 监控系统启动完成 ==="
    echo "✅ 所有监控已启动并在后台运行"
    echo "📊 使用 'sudo pg_monitor_manager.sh status' 查看状态"
    echo "📋 使用 'sudo pg_monitor_manager.sh logs' 查看最新日志"
    echo "⏹️  使用 'sudo pg_monitor_manager.sh stop' 停止监控"
}

# 执行主函数
main "$@" 