#!/bin/bash

# 快速检查命令集合

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

log_title() {
    echo -e "${BLUE}[检查]${NC} $1"
}

# 快速系统检查
quick_system_check() {
    log_title "系统快速检查"
    
    echo "主机名: $(hostname)"
    echo "当前时间: $(date)"
    echo "系统负载: $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
    echo "内存使用: $(free -h | grep Mem | awk '{print $3"/"$2" ("$3/$2*100"%)"}')"
    echo "磁盘使用: $(df -h / | tail -1 | awk '{print $5}')"
    echo "运行时间: $(uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')"
}

# 快速 Docker 检查
quick_docker_check() {
    log_title "Docker 快速检查"
    
    if command -v docker &> /dev/null; then
        echo "Docker 版本: $(docker --version | awk '{print $3}' | sed 's/,//')"
        echo "服务状态: $(systemctl is-active docker)"
        echo "运行容器: $(docker ps --format 'table {{.Names}}\t{{.Status}}' | wc -l) 个"
        echo "总镜像数: $(docker images -q | wc -l) 个"
        echo "磁盘使用: $(docker system df --format 'table {{.Type}}\t{{.Size}}')"
    else
        echo "Docker 未安装"
    fi
}

# 主函数
main() {
    echo "=================== 快速检查 ==================="
    quick_system_check
    echo
    quick_docker_check
    echo "=============================================="
}

main "$@"