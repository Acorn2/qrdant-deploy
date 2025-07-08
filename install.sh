#!/bin/bash

# 一键安装 Docker 脚本 - 增强版
# 适用于腾讯云 OpenCloudOS

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

log_title() {
    echo -e "${BLUE}[标题]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

# 显示菜单
show_menu() {
    log_title "=== 腾讯云 OpenCloudOS Docker 管理工具 ==="
    echo "安装选项："
    echo "1. 安装 Docker CE"
    echo "2. 安装 Docker Compose"
    echo "3. 配置 Docker 优化"
    echo "4. 完整安装（Docker + Compose + 配置）"
    echo
    echo "管理选项："
    echo "5. 系统状态检查"
    echo "6. Docker 内存配置"
    echo "7. 快速状态检查"
    echo "8. 生成系统报告"
    echo
    echo "其他选项："
    echo "9. 卸载 Docker"
    echo "10. 显示监控命令"
    echo "11. 退出"
    echo
}

# 执行脚本
run_script() {
    local script_path="$1"
    local script_name="$2"
    
    if [[ -f "$script_path" ]]; then
        log_info "执行 $script_name..."
        chmod +x "$script_path"
        bash "$script_path"
    else
        log_error "脚本文件不存在: $script_path"
        exit 1
    fi
}

# 显示监控命令
show_monitoring_commands() {
    log_title "常用监控命令"
    
    echo "=== 系统监控命令 ==="
    echo "1. 查看系统资源："
    echo "   htop                    # 实时系统监控"
    echo "   free -h                 # 内存使用情况"
    echo "   df -h                   # 磁盘使用情况"
    echo "   iostat -x 1 5          # 磁盘 I/O 监控"
    echo
    echo "2. 查看系统负载："
    echo "   uptime                  # 系统负载和运行时间"
    echo "   cat /proc/loadavg       # 系统负载详情"
    echo "   top                     # 实时进程监控"
    echo
    echo "=== Docker 监控命令 ==="
    echo "3. Docker 资源监控："
    echo "   docker stats            # 所有容器资源使用"
    echo "   docker stats <name>     # 特定容器资源使用"
    echo "   docker system df        # Docker 磁盘使用"
    echo "   docker system events    # Docker 事件日志"
    echo
    echo "4. 容器管理："
    echo "   docker ps               # 运行中的容器"
    echo "   docker ps -a            # 所有容器"
    echo "   docker images           # 本地镜像列表"
    echo "   docker logs <name>      # 容器日志"
    echo
    echo "5. 内存限制相关："
    echo "   docker inspect <name> | grep -i memory    # 查看容器内存配置"
    echo "   docker run -m 512m <image>                # 运行时限制内存"
    echo "   docker update --memory 1g <name>          # 更新容器内存限制"
    echo
    echo "=== 快速检查脚本 ==="
    echo "6. 使用项目脚本："
    echo "   ./scripts/quick-check.sh        # 快速系统检查"
    echo "   ./scripts/check-system.sh       # 详细系统检查"
    echo
}

# 主函数
main() {
    while true; do
        show_menu
        read -p "请选择操作 (1-11): " choice
        
        case $choice in
            1)
                run_script "$SCRIPT_DIR/scripts/install-docker.sh" "Docker CE 安装"
                ;;
            2)
                run_script "$SCRIPT_DIR/scripts/install-docker-compose.sh" "Docker Compose 安装"
                ;;
            3)
                run_script "$SCRIPT_DIR/scripts/configure-docker.sh" "Docker 配置优化"
                ;;
            4)
                log_info "开始完整安装..."
                run_script "$SCRIPT_DIR/scripts/install-docker.sh" "Docker CE 安装"
                run_script "$SCRIPT_DIR/scripts/install-docker-compose.sh" "Docker Compose 安装"
                run_script "$SCRIPT_DIR/scripts/configure-docker.sh" "Docker 配置优化"
                log_info "完整安装完成！"
                ;;
            5)
                run_script "$SCRIPT_DIR/scripts/check-system.sh" "系统状态检查"
                ;;
            6)
                run_script "$SCRIPT_DIR/scripts/configure-docker-memory.sh" "Docker 内存配置"
                ;;
            7)
                run_script "$SCRIPT_DIR/scripts/quick-check.sh" "快速状态检查"
                ;;
            8)
                log_info "生成详细系统报告..."
                bash "$SCRIPT_DIR/scripts/check-system.sh" > "/tmp/system-report-$(date +%Y%m%d-%H%M%S).txt"
                log_info "系统报告已生成到 /tmp/ 目录"
                ;;
            9)
                run_script "$SCRIPT_DIR/scripts/uninstall-docker.sh" "Docker 卸载"
                ;;
            10)
                show_monitoring_commands
                ;;
            11)
                log_info "退出管理工具"
                break
                ;;
            *)
                echo "无效的选择，请重新输入"
                ;;
        esac
        
        echo
        read -p "按 Enter 键继续..."
        echo
    done
}

main "$@" 