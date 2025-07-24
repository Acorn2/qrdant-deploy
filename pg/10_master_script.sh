#!/bin/bash

# PostgreSQL 故障排查主控制脚本
# 提供一站式PostgreSQL问题诊断和解决方案

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 显示带颜色的消息
log_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

log_title() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

log_step() {
    echo -e "${PURPLE}[步骤]${NC} $1"
}

# 显示主菜单
show_main_menu() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
  ____           _                   ____  _____ _     
 |  _ \ ___  ___| |_ __ _ _ __ ___   / ___||  ___| |    
 | |_) / _ \/ __| __/ _` | '__/ _ \  \___ \| |_  | |    
 |  __/ (_) \__ \ || (_| | | |  __/   ___) |  _| | |___ 
 |_|   \___/|___/\__\__, |_|  \___|  |____/|_|   |_____|
                    |___/                              
PostgreSQL 故障排查工具套件
EOF
    echo -e "${NC}"
    
    echo "选择操作："
    echo
    echo "🔍 诊断检查："
    echo "  1. 立即诊断检查          - 快速检查当前状态"
    echo "  2. 综合健康检查          - 全面系统健康分析"
    echo "  3. 检查清理任务          - 查找可疑的清理脚本"
    echo
    echo "📊 监控系统："
    echo "  4. 启用详细日志监控      - 开启调试级别日志"
    echo "  5. 启动实时监控          - 表和连接监控"
    echo "  6. 查看监控状态          - 检查监控运行状态"
    echo "  7. 停止所有监控          - 停止监控并清理"
    echo
    echo "⚙️  系统优化："
    echo "  8. 配置优化             - 性能和稳定性优化"
    echo "  9. 恢复正常配置          - 移除调试配置"
    echo
    echo "📋 日志分析："
    echo "  10. 查看最新日志         - 显示最近的错误和活动"
    echo "  11. 分析监控数据         - 分析表变化趋势"
    echo
    echo "🔧 工具管理："
    echo "  12. 脚本权限设置         - 设置所有脚本执行权限"
    echo "  13. 生成完整报告         - 生成系统状态报告"
    echo "  14. 清理临时文件         - 清理日志和临时文件"
    echo
    echo "  0. 退出"
    echo
}

# 检查脚本权限
check_and_fix_permissions() {
    log_step "检查和修复脚本权限..."
    
    local scripts=(
        "01_immediate_check.sh"
        "02_enable_monitoring.sh"
        "03_table_monitor.sh"
        "04_connection_monitor.sh"
        "05_optimize_config.sh"
        "06_check_cleanup_tasks.sh"
        "07_health_check.sh"
        "08_start_all_monitoring.sh"
        "09_restore_config.sh"
    )
    
    for script in "${scripts[@]}"; do
        local script_path="$SCRIPT_DIR/$script"
        if [[ -f "$script_path" ]]; then
            if [[ ! -x "$script_path" ]]; then
                chmod +x "$script_path"
                echo "✅ 已设置执行权限: $script"
            else
                echo "✓ 权限正常: $script"
            fi
        else
            echo "⚠️  脚本不存在: $script"
        fi
    done
}

# 运行脚本的通用函数
run_script() {
    local script_name="$1"
    local description="$2"
    local script_path="$SCRIPT_DIR/$script_name"
    
    if [[ ! -f "$script_path" ]]; then
        log_error "脚本文件不存在: $script_name"
        return 1
    fi
    
    if [[ ! -x "$script_path" ]]; then
        log_warn "脚本没有执行权限，正在添加..."
        chmod +x "$script_path"
    fi
    
    log_title "$description"
    echo "执行脚本: $script_name"
    echo
    
    bash "$script_path"
    local exit_code=$?
    
    echo
    if [[ $exit_code -eq 0 ]]; then
        log_info "脚本执行完成"
    else
        log_error "脚本执行失败 (退出代码: $exit_code)"
    fi
    
    echo
    read -p "按Enter键返回主菜单..."
    return $exit_code
}

# 显示监控状态
show_monitoring_status() {
    log_title "监控系统状态"
    
    # 检查表监控
    if [[ -f /var/run/table_monitor.pid ]]; then
        local table_pid=$(cat /var/run/table_monitor.pid 2>/dev/null)
        if [[ -n "$table_pid" ]] && ps -p "$table_pid" > /dev/null 2>&1; then
            log_info "表监控运行中 (PID: $table_pid)"
            if [[ -f /var/log/table_monitor.log ]]; then
                local last_update=$(stat -c %y /var/log/table_monitor.log 2>/dev/null | cut -d'.' -f1)
                echo "   最后更新: $last_update"
                echo "   日志大小: $(du -h /var/log/table_monitor.log | cut -f1)"
            fi
        else
            log_warn "表监控进程不存在"
        fi
    else
        log_warn "表监控未运行"
    fi
    
    # 检查连接监控
    if [[ -f /var/run/connection_monitor.pid ]]; then
        local conn_pid=$(cat /var/run/connection_monitor.pid 2>/dev/null)
        if [[ -n "$conn_pid" ]] && ps -p "$conn_pid" > /dev/null 2>&1; then
            log_info "连接监控运行中 (PID: $conn_pid)"
            if [[ -f /var/log/pg_connections.log ]]; then
                local last_update=$(stat -c %y /var/log/pg_connections.log 2>/dev/null | cut -d'.' -f1)
                echo "   最后更新: $last_update"
                echo "   日志大小: $(du -h /var/log/pg_connections.log | cut -f1)"
            fi
        else
            log_warn "连接监控进程不存在"
        fi
    else
        log_warn "连接监控未运行"
    fi
    
    # 检查PostgreSQL状态
    echo
    log_step "PostgreSQL服务状态:"
    if sudo systemctl is-active --quiet postgresql; then
        log_info "PostgreSQL服务运行正常"
    else
        log_error "PostgreSQL服务异常"
    fi
    
    # 检查数据库连接
    log_step "数据库连接测试:"
    if sudo -u postgres psql -d document_analysis -c "SELECT 1;" >/dev/null 2>&1; then
        log_info "数据库连接正常"
    else
        log_error "数据库连接失败"
    fi
    
    echo
    read -p "按Enter键返回主菜单..."
}

# 停止所有监控
stop_all_monitoring() {
    log_title "停止所有监控"
    
    local stopped=false
    
    # 停止表监控
    if [[ -f /var/run/table_monitor.pid ]]; then
        local table_pid=$(cat /var/run/table_monitor.pid 2>/dev/null)
        if [[ -n "$table_pid" ]] && ps -p "$table_pid" > /dev/null 2>&1; then
            sudo kill "$table_pid" 2>/dev/null || true
            log_info "表监控已停止 (PID: $table_pid)"
            stopped=true
        fi
        sudo rm -f /var/run/table_monitor.pid
    fi
    
    # 停止连接监控
    if [[ -f /var/run/connection_monitor.pid ]]; then
        local conn_pid=$(cat /var/run/connection_monitor.pid 2>/dev/null)
        if [[ -n "$conn_pid" ]] && ps -p "$conn_pid" > /dev/null 2>&1; then
            sudo kill "$conn_pid" 2>/dev/null || true
            log_info "连接监控已停止 (PID: $conn_pid)"
            stopped=true
        fi
        sudo rm -f /var/run/connection_monitor.pid
    fi
    
    if [[ "$stopped" == false ]]; then
        log_info "没有运行中的监控进程"
    fi
    
    echo
    read -p "按Enter键返回主菜单..."
}

# 查看最新日志
show_recent_logs() {
    log_title "最新日志分析"
    
    echo "PostgreSQL错误日志 (最近20条):"
    echo "================================"
    sudo find /var/lib/pgsql/data/log -name "postgresql-*.log" -mtime -1 -exec tail -50 {} \; 2>/dev/null | grep -i -E "(error|fatal|panic|warning)" | tail -20 || echo "无最近错误日志"
    
    echo
    echo "表监控日志 (最近5次检查):"
    echo "========================"
    if [[ -f /var/log/table_monitor.log ]]; then
        tail -50 /var/log/table_monitor.log | grep -A3 -B1 "===" | tail -20
    else
        echo "无表监控日志"
    fi
    
    echo
    echo "连接监控日志 (最近3次检查):"
    echo "=========================="
    if [[ -f /var/log/pg_connections.log ]]; then
        tail -50 /var/log/pg_connections.log | grep -A5 -B1 "===" | tail -15
    else
        echo "无连接监控日志"
    fi
    
    echo
    read -p "按Enter键返回主菜单..."
}

# 分析监控数据
analyze_monitoring_data() {
    log_title "监控数据分析"
    
    if [[ ! -f /var/log/table_monitor.log ]]; then
        log_warn "表监控日志文件不存在"
        echo
        read -p "按Enter键返回主菜单..."
        return
    fi
    
    echo "表变化趋势分析:"
    echo "=============="
    
    # 统计监控记录数
    local total_records=$(grep -c "===" /var/log/table_monitor.log 2>/dev/null || echo "0")
    echo "总监控记录数: $total_records"
    
    # 统计连接失败次数
    local conn_failures=$(grep -c "数据库连接失败" /var/log/table_monitor.log 2>/dev/null || echo "0")
    echo "连接失败次数: $conn_failures"
    
    # 统计表清空事件
    local empty_tables=$(grep -c "没有用户表" /var/log/table_monitor.log 2>/dev/null || echo "0")
    echo "表清空事件: $empty_tables"
    
    # 显示最近24小时的活动
    echo
    echo "最近24小时活动摘要:"
    echo "=================="
    local yesterday=$(date -d "yesterday" "+%Y-%m-%d")
    local today=$(date "+%Y-%m-%d")
    
    grep -E "($yesterday|$today)" /var/log/table_monitor.log 2>/dev/null | grep -E "(表名|没有用户表|连接失败)" | tail -10 || echo "无最近活动记录"
    
    echo
    echo "建议:"
    echo "===="
    if [[ $conn_failures -gt 0 ]]; then
        echo "⚠️  发现数据库连接失败，检查PostgreSQL服务状态"
    fi
    
    if [[ $empty_tables -gt 0 ]]; then
        echo "🚨 发现表清空事件，需要立即调查原因"
    fi
    
    if [[ $total_records -gt 0 ]]; then
        echo "✅ 监控系统正常运行"
    else
        echo "⚠️  监控数据不足，建议启动监控系统"
    fi
    
    echo
    read -p "按Enter键返回主菜单..."
}

# 生成完整报告
generate_full_report() {
    log_title "生成完整系统报告"
    
    local report_file="/tmp/pg_full_report_$(date +%Y%m%d_%H%M%S).txt"
    
    log_step "正在生成报告..."
    
    {
        echo "PostgreSQL 完整系统报告"
        echo "======================="
        echo "生成时间: $(date)"
        echo "主机: $(hostname)"
        echo "系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' 2>/dev/null || echo "Unknown")"
        echo
        
        echo "1. 服务状态"
        echo "==========="
        echo "PostgreSQL: $(sudo systemctl is-active postgresql 2>/dev/null || echo "unknown")"
        echo "数据库连接: $(sudo -u postgres psql -d document_analysis -c "SELECT 1;" >/dev/null 2>&1 && echo "正常" || echo "异常")"
        echo
        
        echo "2. 系统资源"
        echo "==========="
        free -h
        echo
        df -h | grep -E "(Filesystem|/var/lib/pgsql|/$)"
        echo
        
        echo "3. 数据库信息"
        echo "============"
        sudo -u postgres psql -d document_analysis -c "
        SELECT 
            schemaname,
            tablename,
            n_live_tup as 活跃行数,
            n_dead_tup as 死行数
        FROM pg_stat_user_tables 
        ORDER BY tablename;
        " 2>/dev/null || echo "无法获取表信息"
        
        echo
        echo "4. 监控状态"
        echo "==========="
        if [[ -f /var/run/table_monitor.pid ]]; then
            local table_pid=$(cat /var/run/table_monitor.pid 2>/dev/null)
            if ps -p "$table_pid" > /dev/null 2>&1; then
                echo "表监控: 运行中 (PID: $table_pid)"
            else
                echo "表监控: 未运行"
            fi
        else
            echo "表监控: 未运行"
        fi
        
        if [[ -f /var/run/connection_monitor.pid ]]; then
            local conn_pid=$(cat /var/run/connection_monitor.pid 2>/dev/null)
            if ps -p "$conn_pid" > /dev/null 2>&1; then
                echo "连接监控: 运行中 (PID: $conn_pid)"
            else
                echo "连接监控: 未运行"
            fi
        else
            echo "连接监控: 未运行"
        fi
        
        echo
        echo "5. 最近错误日志"
        echo "==============="
        sudo find /var/lib/pgsql/data/log -name "postgresql-*.log" -mtime -1 -exec tail -20 {} \; 2>/dev/null | grep -i error | tail -10 || echo "无最近错误"
        
        echo
        echo "6. 配置检查"
        echo "==========="
        sudo -u postgres psql -d document_analysis -c "
        SELECT name, setting 
        FROM pg_settings 
        WHERE name IN ('shared_buffers', 'max_connections', 'autovacuum', 'log_statement')
        ORDER BY name;
        " 2>/dev/null || echo "无法获取配置信息"
        
    } > "$report_file"
    
    log_info "完整报告已生成: $report_file"
    
    echo
    echo "报告内容预览:"
    echo "============"
    head -30 "$report_file"
    echo "..."
    echo "(完整内容请查看文件: $report_file)"
    
    echo
    read -p "按Enter键返回主菜单..."
}

# 清理临时文件
cleanup_temp_files() {
    log_title "清理临时文件和日志"
    
    echo "查找临时文件..."
    
    # 清理报告文件
    local reports=$(find /tmp -name "pg_*_report_*.txt" -mtime +7 2>/dev/null)
    if [[ -n "$reports" ]]; then
        echo "发现旧报告文件:"
        echo "$reports"
        read -p "是否删除这些文件？(y/N): " confirm
        if [[ $confirm == [yY] ]]; then
            echo "$reports" | xargs rm -f
            log_info "旧报告文件已清理"
        fi
    else
        log_info "无需清理的报告文件"
    fi
    
    # 清理大日志文件
    echo
    echo "检查日志文件大小..."
    local large_logs=""
    
    if [[ -f /var/log/table_monitor.log ]]; then
        local size=$(stat -c%s /var/log/table_monitor.log 2>/dev/null || echo "0")
        if [[ $size -gt 104857600 ]]; then  # 100MB
            large_logs="$large_logs /var/log/table_monitor.log"
        fi
    fi
    
    if [[ -f /var/log/pg_connections.log ]]; then
        local size=$(stat -c%s /var/log/pg_connections.log 2>/dev/null || echo "0")
        if [[ $size -gt 104857600 ]]; then  # 100MB
            large_logs="$large_logs /var/log/pg_connections.log"
        fi
    fi
    
    if [[ -n "$large_logs" ]]; then
        echo "发现大日志文件:"
        for log in $large_logs; do
            local size=$(du -h "$log" | cut -f1)
            echo "  $log ($size)"
        done
        
        read -p "是否截断这些日志文件？(y/N): " confirm
        if [[ $confirm == [yY] ]]; then
            for log in $large_logs; do
                sudo truncate -s 100M "$log"  # 保留最后100MB
            done
            log_info "大日志文件已截断"
        fi
    else
        log_info "无需清理的大日志文件"
    fi
    
    echo
    read -p "按Enter键返回主菜单..."
}

# 主函数
main() {
    # 检查权限
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        echo "请使用: sudo $0"
        exit 1
    fi
    
    # 初始化检查
    check_and_fix_permissions > /dev/null 2>&1
    
    while true; do
        show_main_menu
        read -p "请选择操作 (0-14): " choice
        
        case $choice in
            1)
                run_script "01_immediate_check.sh" "立即诊断检查"
                ;;
            2)
                run_script "07_health_check.sh" "综合健康检查"
                ;;
            3)
                run_script "06_check_cleanup_tasks.sh" "检查清理任务"
                ;;
            4)
                run_script "02_enable_monitoring.sh" "启用详细日志监控"
                ;;
            5)
                run_script "08_start_all_monitoring.sh" "启动实时监控"
                ;;
            6)
                show_monitoring_status
                ;;
            7)
                stop_all_monitoring
                ;;
            8)
                run_script "05_optimize_config.sh" "配置优化"
                ;;
            9)
                run_script "09_restore_config.sh" "恢复正常配置"
                ;;
            10)
                show_recent_logs
                ;;
            11)
                analyze_monitoring_data
                ;;
            12)
                check_and_fix_permissions
                log_info "脚本权限设置完成"
                echo
                read -p "按Enter键返回主菜单..."
                ;;
            13)
                generate_full_report
                ;;
            14)
                cleanup_temp_files
                ;;
            0)
                log_info "退出PostgreSQL故障排查工具"
                exit 0
                ;;
            *)
                log_error "无效选择，请重新输入"
                sleep 2
                ;;
        esac
    done
}

# 执行主函数
main "$@" 