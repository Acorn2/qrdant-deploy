#!/bin/bash

# Docker 配置优化脚本
# 针对腾讯云服务器进行优化

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

# 配置 Docker 守护进程
configure_daemon() {
    log_info "配置 Docker 守护进程..."
    
    # 创建 Docker 配置目录
    mkdir -p /etc/docker
    
    # 创建 daemon.json 配置文件
    cat > /etc/docker/daemon.json << 'EOF'
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
        }
    }
}
EOF
    
    log_info "Docker 守护进程配置完成"
}

# 配置系统参数
configure_system() {
    log_info "配置系统参数..."
    
    # 配置内核参数
    cat >> /etc/sysctl.conf << 'EOF'

# Docker 优化参数
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
vm.max_map_count = 262144
EOF
    
    # 应用内核参数
    sysctl -p
    
    log_info "系统参数配置完成"
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."
    
    if systemctl is-active --quiet firewalld; then
        # 添加 Docker 服务到防火墙
        firewall-cmd --permanent --zone=trusted --add-interface=docker0 2>/dev/null || true
        firewall-cmd --permanent --zone=trusted --add-port=2376/tcp 2>/dev/null || true
        firewall-cmd --reload
        log_info "防火墙配置完成"
    else
        log_warn "防火墙未运行，跳过防火墙配置"
    fi
}

# 重启 Docker 服务
restart_docker() {
    log_info "重启 Docker 服务..."
    
    systemctl daemon-reload
    systemctl restart docker
    
    # 验证配置
    if systemctl is-active --quiet docker; then
        log_info "Docker 服务重启成功"
        docker info | grep -E "(Registry Mirrors|Storage Driver|Logging Driver)"
    else
        log_error "Docker 服务重启失败"
        exit 1
    fi
}

# 主函数
main() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        exit 1
    fi
    
    configure_daemon
    configure_system
    configure_firewall
    restart_docker
    
    log_info "Docker 配置优化完成！"
}

main "$@"