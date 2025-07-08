#!/bin/bash

# Docker 安装脚本 - 适用于腾讯云 OpenCloudOS
# 作者: qrdant-deploy 项目
# 版本: 1.1 - 修复 yum makecache 兼容性问题

set -e

# 颜色输出函数
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行。请使用 sudo 或切换到 root 用户。"
        exit 1
    fi
}

# 检查系统版本和包管理器
check_system() {
    log_info "检查系统版本..."
    
    if [[ -f /etc/opencloudos-release ]]; then
        log_info "检测到 OpenCloudOS 系统"
        cat /etc/opencloudos-release
    elif [[ -f /etc/centos-release ]]; then
        log_info "检测到 CentOS 兼容系统"
        cat /etc/centos-release
    else
        log_warn "未检测到标准的 OpenCloudOS 标识，但将尝试继续安装"
    fi
    
    # 检查包管理器类型
    if command -v dnf &> /dev/null; then
        log_info "检测到 DNF 包管理器"
        PKG_MANAGER="dnf"
    elif command -v yum &> /dev/null; then
        log_info "检测到 YUM 包管理器"
        PKG_MANAGER="yum"
    else
        log_error "未找到支持的包管理器 (yum/dnf)"
        exit 1
    fi
}

# 卸载旧版本 Docker
remove_old_docker() {
    log_info "移除可能存在的旧版本 Docker..."
    
    # 停止 Docker 服务
    systemctl stop docker 2>/dev/null || true
    systemctl stop docker.socket 2>/dev/null || true
    
    # 卸载旧版本
    $PKG_MANAGER remove -y docker \
        docker-client \
        docker-client-latest \
        docker-common \
        docker-latest \
        docker-latest-logrotate \
        docker-logrotate \
        docker-engine \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin 2>/dev/null || true
    
    log_info "旧版本清理完成"
}

# 安装必要的依赖包
install_dependencies() {
    log_info "安装必要的依赖包..."
    
    $PKG_MANAGER update -y
    
    if [[ $PKG_MANAGER == "dnf" ]]; then
        $PKG_MANAGER install -y dnf-utils device-mapper-persistent-data lvm2 curl wget
    else
        $PKG_MANAGER install -y yum-utils device-mapper-persistent-data lvm2 curl wget
    fi
    
    log_info "依赖包安装完成"
}

# 添加 Docker 官方仓库
add_docker_repo() {
    log_info "添加 Docker 官方仓库..."
    
    if [[ $PKG_MANAGER == "dnf" ]]; then
        # 使用 dnf config-manager
        dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    else
        # 使用 yum-config-manager
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    fi
    
    # 针对 OpenCloudOS，我们可能需要修改仓库配置
    if [[ -f /etc/opencloudos-release ]]; then
        log_info "为 OpenCloudOS 调整仓库配置..."
        # 修改仓库文件以兼容 OpenCloudOS
        sed -i 's/\$releasever/8/g' /etc/yum.repos.d/docker-ce.repo
    fi
    
    # 更新仓库缓存 - 修复兼容性问题
    log_info "更新仓库缓存..."
    if [[ $PKG_MANAGER == "dnf" ]]; then
        dnf makecache
    else
        # 对于较新的 yum 版本，不使用 fast 参数
        yum makecache || yum makecache --timer || yum makecache timer
    fi
    
    log_info "Docker 仓库添加完成"
}

# 安装 Docker CE
install_docker() {
    log_info "安装 Docker CE..."
    
    # 安装最新版本的 Docker CE
    $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    log_info "Docker CE 安装完成"
}

# 启动并启用 Docker 服务
start_docker() {
    log_info "启动 Docker 服务..."
    
    # 启动 Docker 服务
    systemctl start docker
    systemctl enable docker
    
    # 验证 Docker 是否正常运行
    if systemctl is-active --quiet docker; then
        log_info "Docker 服务启动成功"
    else
        log_error "Docker 服务启动失败"
        exit 1
    fi
}

# 配置 Docker 用户组
configure_docker_group() {
    log_info "配置 Docker 用户组..."
    
    # 创建 docker 用户组（如果不存在）
    groupadd docker 2>/dev/null || true
    
    # 询问是否将当前用户添加到 docker 组
    if [[ -n "${SUDO_USER}" ]]; then
        read -p "是否将用户 ${SUDO_USER} 添加到 docker 组？(y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            usermod -aG docker ${SUDO_USER}
            log_info "用户 ${SUDO_USER} 已添加到 docker 组"
            log_warn "请注销并重新登录以使组权限生效"
        fi
    fi
}

# 测试 Docker 安装
test_docker() {
    log_info "测试 Docker 安装..."
    
    # 运行 hello-world 容器
    if docker run --rm hello-world; then
        log_info "Docker 安装测试成功！"
    else
        log_error "Docker 安装测试失败"
        exit 1
    fi
}

# 显示安装信息
show_install_info() {
    log_info "Docker 安装完成！"
    echo
    echo "Docker 版本信息："
    docker --version
    docker-compose --version 2>/dev/null || docker compose version
    echo
    echo "Docker 服务状态："
    systemctl status docker --no-pager -l
    echo
    echo "包管理器信息："
    echo "使用的包管理器: $PKG_MANAGER"
    echo "系统版本: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
    echo
    log_info "安装日志已保存到: /var/log/docker-install.log"
}

# 主函数
main() {
    log_info "开始安装 Docker CE for OpenCloudOS..."
    
    check_root
    check_system
    remove_old_docker
    install_dependencies
    add_docker_repo
    install_docker
    start_docker
    configure_docker_group
    test_docker
    show_install_info
    
    log_info "Docker 安装脚本执行完成！"
}

# 执行主函数并记录日志
main "$@" 2>&1 | tee /var/log/docker-install.log 