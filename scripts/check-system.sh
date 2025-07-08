#!/bin/bash

# 云服务器系统检查脚本
# 检查系统资源、Docker 状态等信息

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

log_title() {
    echo -e "${BLUE}[检查项]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 分隔线
print_separator() {
    echo "=========================================="
}

# 检查系统基本信息
check_system_info() {
    log_title "系统基本信息"
    
    echo "操作系统信息："
    if [[ -f /etc/os-release ]]; then
        cat /etc/os-release
    elif [[ -f /etc/redhat-release ]]; then
        cat /etc/redhat-release
    fi
    
    echo
    echo "内核版本："
    uname -a
    
    echo
    echo "系统启动时间："
    uptime
    
    print_separator
}

# 检查 CPU 信息
check_cpu_info() {
    log_title "CPU 信息"
    
    echo "CPU 核心数："
    nproc
    
    echo
    echo "CPU 详细信息："
    lscpu | grep -E "(Architecture|CPU\(s\)|Model name|CPU MHz)"
    
    echo
    echo "CPU 负载（1分钟、5分钟、15分钟）："
    cat /proc/loadavg
    
    echo
    echo "CPU 使用率（实时）："
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//'
    
    print_separator
}

# 检查内存信息
check_memory_info() {
    log_title "内存信息"
    
    echo "内存使用情况："
    free -h
    
    echo
    echo "内存详细信息："
    cat /proc/meminfo | grep -E "(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree)"
    
    echo
    echo "内存使用率："
    MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.2f%%", $3/$2 * 100.0)}')
    echo "已使用: $MEMORY_USAGE"
    
    print_separator
}

# 检查磁盘信息
check_disk_info() {
    log_title "磁盘信息"
    
    echo "磁盘使用情况："
    df -h
    
    echo
    echo "磁盘 I/O 统计："
    iostat -d 1 1 2>/dev/null || echo "iostat 未安装，跳过 I/O 统计"
    
    echo
    echo "磁盘分区信息："
    lsblk
    
    print_separator
}

# 检查网络信息
check_network_info() {
    log_title "网络信息"
    
    echo "网络接口信息："
    ip addr show | grep -E "(inet |inet6 )" | grep -v 127.0.0.1
    
    echo
    echo "网络连接统计："
    ss -tuln | head -10
    
    echo
    echo "外网 IP 地址："
    curl -s ifconfig.me || echo "无法获取外网 IP"
    
    echo
    echo
    echo "DNS 配置："
    cat /etc/resolv.conf
    
    print_separator
}

# 检查进程信息
check_process_info() {
    log_title "进程信息"
    
    echo "运行中的进程总数："
    ps aux | wc -l
    
    echo
    echo "CPU 占用前 10 的进程："
    ps aux --sort=-%cpu | head -11
    
    echo
    echo "内存占用前 10 的进程："
    ps aux --sort=-%mem | head -11
    
    print_separator
}

# 检查 Docker 状态
check_docker_status() {
    log_title "Docker 状态检查"
    
    if command -v docker &> /dev/null; then
        echo "Docker 版本："
        docker --version
        
        echo
        echo "Docker Compose 版本："
        docker-compose --version 2>/dev/null || echo "Docker Compose 未安装"
        
        echo
        echo "Docker 服务状态："
        systemctl status docker --no-pager -l | head -10
        
        echo
        echo "Docker 系统信息："
        docker system df 2>/dev/null || echo "Docker 守护进程未运行"
        
        echo
        echo "运行中的容器："
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "无法获取容器信息"
        
        echo
        echo "Docker 镜像列表："
        docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" 2>/dev/null || echo "无法获取镜像信息"
        
        echo
        echo "Docker 网络："
        docker network ls 2>/dev/null || echo "无法获取网络信息"
        
    else
        log_warn "Docker 未安装"
    fi
    
    print_separator
}

# 检查系统服务
check_system_services() {
    log_title "系统服务状态"
    
    echo "重要系统服务状态："
    services=("sshd" "firewalld" "chronyd" "rsyslog")
    
    for service in "${services[@]}"; do
        if systemctl is-enabled $service &>/dev/null; then
            status=$(systemctl is-active $service 2>/dev/null || echo "inactive")
            echo "$service: $status"
        else
            echo "$service: 未安装或未启用"
        fi
    done
    
    print_separator
}

# 检查安全状态
check_security_status() {
    log_title "安全状态检查"
    
    echo "防火墙状态："
    if systemctl is-active --quiet firewalld; then
        echo "防火墙运行中"
        firewall-cmd --get-active-zones 2>/dev/null || true
    else
        echo "防火墙未运行"
    fi
    
    echo
    echo "SELinux 状态："
    getenforce 2>/dev/null || echo "SELinux 未安装"
    
    echo
    echo "最近登录记录："
    last -n 5
    
    echo
    echo "失败登录尝试："
    lastb -n 5 2>/dev/null || echo "无失败登录记录"
    
    print_separator
}

# 生成系统报告
generate_report() {
    log_title "生成系统检查报告"
    
    REPORT_FILE="/tmp/system-check-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "=== 云服务器系统检查报告 ==="
        echo "生成时间: $(date)"
        echo "生成用户: $(whoami)"
        echo "主机名: $(hostname)"
        echo
        
        check_system_info
        check_cpu_info
        check_memory_info
        check_disk_info
        check_network_info
        check_process_info
        check_docker_status
        check_system_services
        check_security_status
        
    } > "$REPORT_FILE"
    
    log_info "系统检查报告已保存到: $REPORT_FILE"
    
    # 显示报告摘要
    echo
    log_title "系统状态摘要"
    echo "内存使用率: $(free | grep Mem | awk '{printf("%.1f%%", $3/$2 * 100.0)}')"
    echo "磁盘使用率: $(df / | tail -1 | awk '{print $5}')"
    echo "系统负载: $(cat /proc/loadavg | awk '{print $1}')"
    echo "运行时间: $(uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')"
}

# 主函数
main() {
    log_info "开始系统检查..."
    echo
    
    check_system_info
    check_cpu_info
    check_memory_info
    check_disk_info
    check_network_info
    check_process_info
    check_docker_status
    check_system_services
    check_security_status
    generate_report
    
    log_info "系统检查完成！"
}

# 如果直接运行脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 