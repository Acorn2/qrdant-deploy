#!/bin/bash

# Docker 内存配置脚本
# 设置 Docker 守护进程和容器的内存限制

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
    echo -e "${BLUE}[配置]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 检查当前系统内存
check_system_memory() {
    log_title "检查系统内存"
    
    TOTAL_MEM=$(free -m | grep Mem | awk '{print $2}')
    AVAILABLE_MEM=$(free -m | grep Mem | awk '{print $7}')
    
    echo "总内存: ${TOTAL_MEM}MB"
    echo "可用内存: ${AVAILABLE_MEM}MB"
    echo "建议为 Docker 分配的内存: $((TOTAL_MEM * 50 / 100))MB (总内存的50%)"
    
    return $TOTAL_MEM
}

# 配置 Docker 守护进程内存
configure_docker_daemon_memory() {
    log_title "配置 Docker 守护进程内存限制"
    
    # 备份原配置
    if [[ -f /etc/docker/daemon.json ]]; then
        cp /etc/docker/daemon.json /etc/docker/daemon.json.backup.$(date +%Y%m%d_%H%M%S)
        log_info "已备份原配置文件"
    fi
    
    # 获取用户输入
    echo "请选择 Docker 守护进程内存配置："
    echo "1. 自动配置（推荐，使用总内存的70%）"
    echo "2. 手动设置内存大小"
    echo "3. 不限制内存（默认）"
    
    read -p "请选择 (1-3): " choice
    
    case $choice in
        1)
            DOCKER_MEM=$((TOTAL_MEM * 70 / 100))
            configure_memory_limit $DOCKER_MEM
            ;;
        2)
            read -p "请输入内存限制（MB）: " DOCKER_MEM
            if [[ $DOCKER_MEM -gt $((TOTAL_MEM * 90 / 100)) ]]; then
                log_warn "设置的内存超过系统内存的90%，这可能导致系统不稳定"
                read -p "确认继续？(y/n): " confirm
                if [[ $confirm != "y" ]]; then
                    log_info "取消配置"
                    return
                fi
            fi
            configure_memory_limit $DOCKER_MEM
            ;;
        3)
            log_info "不设置内存限制"
            ;;
        *)
            log_error "无效选择"
            return 1
            ;;
    esac
}

# 配置内存限制
configure_memory_limit() {
    local mem_limit=$1
    
    log_info "设置 Docker 内存限制为: ${mem_limit}MB"
    
    # 创建或更新 daemon.json
    mkdir -p /etc/docker
    
    # 如果配置文件存在，则合并配置
    if [[ -f /etc/docker/daemon.json ]]; then
        # 使用 jq 合并配置，如果没有 jq 则手动处理
        if command -v jq &> /dev/null; then
            jq --arg mem "${mem_limit}m" '.["default-ulimits"]["memlock"] = {"Hard": ($mem), "Name": "memlock", "Soft": ($mem)}' /etc/docker/daemon.json > /tmp/daemon.json.tmp
            mv /tmp/daemon.json.tmp /etc/docker/daemon.json
        else
            # 手动添加内存配置
            add_memory_config_manual $mem_limit
        fi
    else
        # 创建新的配置文件
        create_daemon_config $mem_limit
    fi
}

# 手动添加内存配置
add_memory_config_manual() {
    local mem_limit=$1
    
    # 读取现有配置并添加内存限制
    python3 -c "
import json
import sys

try:
    with open('/etc/docker/daemon.json', 'r') as f:
        config = json.load(f)
except:
    config = {}

# 添加内存限制配置
if 'default-ulimits' not in config:
    config['default-ulimits'] = {}

config['default-ulimits']['memlock'] = {
    'Hard': '${mem_limit}m',
    'Name': 'memlock', 
    'Soft': '${mem_limit}m'
}

# 添加其他内存相关配置
config['default-shm-size'] = '64m'

with open('/etc/docker/daemon.json', 'w') as f:
    json.dump(config, f, indent=2)
" 2>/dev/null || create_daemon_config $mem_limit
}

# 创建新的守护进程配置
create_daemon_config() {
    local mem_limit=$1
    
    cat > /etc/docker/daemon.json << EOF
{
    "registry-mirrors": [
        "https://docker.mirrors.ustc.edu.cn",
        "https://hub-mirror.c.163.com",
        "https://mirror.baidubce.com"
    ],
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "data-root": "/var/lib/docker",
    "live-restore": true,
    "default-ulimits": {
        "nofile": {
            "Hard": 64000,
            "Name": "nofile",
            "Soft": 64000
        },
        "memlock": {
            "Hard": "${mem_limit}m",
            "Name": "memlock",
            "Soft": "${mem_limit}m"
        }
    },
    "default-shm-size": "64m"
}
EOF
}

# 配置系统内存设置
configure_system_memory() {
    log_title "配置系统内存设置"
    
    # 配置 swap
    echo "当前 swap 使用情况："
    free -h | grep Swap
    
    read -p "是否优化 swap 设置？(y/n): " optimize_swap
    if [[ $optimize_swap == "y" ]]; then
        # 设置 swappiness
        echo "vm.swappiness=10" >> /etc/sysctl.conf
        sysctl vm.swappiness=10
        log_info "已设置 swappiness=10 (减少 swap 使用)"
        
        # 设置内存过载保护
        echo "vm.overcommit_memory=1" >> /etc/sysctl.conf
        sysctl vm.overcommit_memory=1
        log_info "已启用内存过载保护"
    fi
}

# 创建容器内存限制示例
create_memory_examples() {
    log_title "创建容器内存限制示例"
    
    mkdir -p /opt/docker-examples
    
    cat > /opt/docker-examples/memory-limit-examples.sh << 'EOF'
#!/bin/bash

# Docker 容器内存限制示例

echo "=== Docker 容器内存限制示例 ==="

# 1. 运行容器时设置内存限制
echo "1. 限制容器内存为 512MB："
echo "docker run -m 512m nginx:alpine"

# 2. 设置内存和交换分区限制
echo "2. 限制内存 512MB，交换分区 1GB："
echo "docker run -m 512m --memory-swap 1g nginx:alpine"

# 3. 禁用交换分区
echo "3. 限制内存 512MB，禁用交换："
echo "docker run -m 512m --memory-swap 512m nginx:alpine"

# 4. 设置内存预留
echo "4. 设置内存预留 256MB："
echo "docker run --memory-reservation 256m nginx:alpine"

# 5. 设置 OOM 终止优先级
echo "5. 设置 OOM 终止优先级："
echo "docker run --oom-kill-disable nginx:alpine"

# 6. Docker Compose 内存限制示例
echo "6. Docker Compose 内存限制："
cat << 'COMPOSE_EOF'
version: '3'
services:
  web:
    image: nginx:alpine
    mem_limit: 512m
    mem_reservation: 256m
    memswap_limit: 1g
COMPOSE_EOF

# 7. 监控容器内存使用
echo "7. 监控容器内存使用："
echo "docker stats --format 'table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}'"

# 8. 查看容器内存限制
echo "8. 查看容器内存限制："
echo "docker inspect <container_id> | grep -i memory"

EOF

    chmod +x /opt/docker-examples/memory-limit-examples.sh
    log_info "内存限制示例脚本已创建: /opt/docker-examples/memory-limit-examples.sh"
}

# 重启 Docker 服务
restart_docker_service() {
    log_title "重启 Docker 服务"
    
    log_info "重新加载系统配置..."
    systemctl daemon-reload
    
    log_info "重启 Docker 服务..."
    systemctl restart docker
    
    # 验证服务状态
    if systemctl is-active --quiet docker; then
        log_info "Docker 服务重启成功"
        
        # 显示配置信息
        echo
        echo "当前 Docker 配置："
        docker system info | grep -A 20 "Memory:"
        
        echo
        echo "守护进程配置文件："
        cat /etc/docker/daemon.json
        
    else
        log_error "Docker 服务重启失败"
        log_error "请检查配置文件语法: /etc/docker/daemon.json"
        exit 1
    fi
}

# 显示内存监控命令
show_monitoring_commands() {
    log_title "内存监控命令"
    
    echo "以下是一些有用的内存监控命令："
    echo
    echo "1. 查看系统内存使用："
    echo "   free -h"
    echo "   cat /proc/meminfo"
    echo
    echo "2. 查看 Docker 系统使用："
    echo "   docker system df"
    echo "   docker system events"
    echo
    echo "3. 监控所有容器资源使用："
    echo "   docker stats"
    echo
    echo "4. 查看特定容器内存使用："
    echo "   docker stats <container_name>"
    echo
    echo "5. 查看容器内存限制："
    echo "   docker inspect <container_name> | grep -i memory"
    echo
    echo "6. 实时监控系统资源："
    echo "   htop"
    echo "   top"
    echo
    echo "7. 查看内存使用历史："
    echo "   sar -r 1 10"
}

# 主函数
main() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        exit 1
    fi
    
    log_info "开始配置 Docker 内存设置..."
    echo
    
    # 检查 Docker 是否已安装
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    check_system_memory
    TOTAL_MEM=$?
    
    configure_docker_daemon_memory
    configure_system_memory
    create_memory_examples
    restart_docker_service
    show_monitoring_commands
    
    log_info "Docker 内存配置完成！"
}

main "$@" 