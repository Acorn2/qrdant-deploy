#!/bin/bash

# Docker Compose 独立安装脚本
# 适用于腾讯云 OpenCloudOS

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 获取最新 Docker Compose 版本
get_latest_version() {
    log_info "获取 Docker Compose 最新版本..."
    
    # 从 GitHub API 获取最新版本
    LATEST_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    
    if [[ -z "$LATEST_VERSION" ]]; then
        log_error "无法获取最新版本，使用默认版本 v2.20.3"
        LATEST_VERSION="v2.20.3"
    fi
    
    log_info "最新版本: $LATEST_VERSION"
}

# 安装 Docker Compose
install_compose() {
    log_info "安装 Docker Compose..."
    
    # 下载 Docker Compose
    curl -L "https://github.com/docker/compose/releases/download/${LATEST_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    
    # 添加执行权限
    chmod +x /usr/local/bin/docker-compose
    
    # 创建软链接
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    log_info "Docker Compose 安装完成"
}

# 验证安装
verify_installation() {
    log_info "验证 Docker Compose 安装..."
    
    if command -v docker-compose &> /dev/null; then
        log_info "Docker Compose 版本："
        docker-compose --version
        log_info "安装验证成功！"
    else
        log_error "Docker Compose 安装验证失败"
        exit 1
    fi
}

# 主函数
main() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        exit 1
    fi
    
    get_latest_version
    install_compose
    verify_installation
}

main "$@"