#!/bin/bash

# Docker 完全卸载脚本
# 适用于腾讯云 OpenCloudOS

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 确认卸载
confirm_uninstall() {
    log_warn "此操作将完全卸载 Docker 及其相关组件"
    log_warn "所有 Docker 容器、镜像、卷和网络都将被删除"
    
    read -p "确认继续？(输入 YES 确认): " confirm
    if [[ "$confirm" != "YES" ]]; then
        log_info "取消卸载操作"
        exit 0
    fi
}

# 停止所有容器和服务
stop_all() {
    log_info "停止所有 Docker 容器和服务..."
    
    # 停止所有运行的容器
    docker stop $(docker ps -aq) 2>/dev/null || true
    
    # 停止 Docker 服务
    systemctl stop docker 2>/dev/null || true
    systemctl stop docker.socket 2>/dev/null || true
    systemctl disable docker 2>/dev/null || true
}

# 清理 Docker 数据
cleanup_data() {
    log_info "清理 Docker 数据..."
    
    # 删除所有容器
    docker rm $(docker ps -aq) 2>/dev/null || true
    
    # 删除所有镜像
    docker rmi $(docker images -q) 2>/dev/null || true
    
    # 清理系统
    docker system prune -af 2>/dev/null || true
}

# 卸载 Docker 包
remove_packages() {
    log_info "卸载 Docker 相关包..."
    
    yum remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
}

# 删除 Docker 文件和目录
remove_files() {
    log_info "删除 Docker 文件和目录..."
    
    # 删除 Docker 数据目录
    rm -rf /var/lib/docker
    rm -rf /var/lib/containerd
    
    # 删除配置文件
    rm -rf /etc/docker
    
    # 删除仓库文件
    rm -f /etc/yum.repos.d/docker-ce.repo
    
    # 删除 Docker Compose
    rm -f /usr/local/bin/docker-compose
    rm -f /usr/bin/docker-compose
}

# 清理用户组
cleanup_groups() {
    log_info "清理 Docker 用户组..."
    
    # 删除 docker 用户组
    groupdel docker 2>/dev/null || true
}

# 主函数
main() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        exit 1
    fi
    
    confirm_uninstall
    stop_all
    cleanup_data
    remove_packages
    remove_files
    cleanup_groups
    
    log_info "Docker 卸载完成！"
    log_info "建议重启系统以确保完全清理"
}

main "$@"