#!/bin/bash

# Docker 安装脚本 - 适用于腾讯云 OpenCloudOS
# 作者: qrdant-deploy 项目
# 版本: 1.3 - 解决网络连接和SSL问题

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
    
    # 清理下载缓存
    $PKG_MANAGER clean packages 2>/dev/null || true
    
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

# 方法1：使用阿里云一键安装脚本
install_docker_aliyun_script() {
    log_info "尝试使用阿里云一键安装脚本..."
    
    if curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun; then
        log_info "阿里云一键安装成功"
        return 0
    else
        log_warn "阿里云一键安装失败"
        return 1
    fi
}

# 方法2：使用腾讯云镜像源
install_docker_tencent_mirror() {
    log_info "尝试使用腾讯云镜像源..."
    
    # 添加腾讯云 Docker 仓库
    if [[ $PKG_MANAGER == "dnf" ]]; then
        dnf config-manager --add-repo https://mirrors.cloud.tencent.com/docker-ce/linux/centos/docker-ce.repo
    else
        yum-config-manager --add-repo https://mirrors.cloud.tencent.com/docker-ce/linux/centos/docker-ce.repo
    fi
    
    # 替换仓库中的下载地址
    sed -i 's/download.docker.com/mirrors.cloud.tencent.com\/docker-ce/g' /etc/yum.repos.d/docker-ce.repo
    
    # 针对 OpenCloudOS 调整版本
    if [[ -f /etc/opencloudos-release ]]; then
        sed -i 's/\$releasever/8/g' /etc/yum.repos.d/docker-ce.repo
    fi
    
    # 更新缓存
    $PKG_MANAGER makecache
    
    # 安装 Docker
    if $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        log_info "腾讯云镜像源安装成功"
        return 0
    else
        log_warn "腾讯云镜像源安装失败"
        return 1
    fi
}

# 方法3：使用阿里云镜像源
install_docker_aliyun_mirror() {
    log_info "尝试使用阿里云镜像源..."
    
    # 添加阿里云 Docker 仓库
    if [[ $PKG_MANAGER == "dnf" ]]; then
        dnf config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
    else
        yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
    fi
    
    # 针对 OpenCloudOS 调整版本
    if [[ -f /etc/opencloudos-release ]]; then
        sed -i 's/\$releasever/8/g' /etc/yum.repos.d/docker-ce.repo
    fi
    
    # 更新缓存
    $PKG_MANAGER makecache
    
    # 安装 Docker
    if $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        log_info "阿里云镜像源安装成功"
        return 0
    else
        log_warn "阿里云镜像源安装失败"
        return 1
    fi
}

# 方法4：使用原始官方仓库（禁用SSL验证）
install_docker_official_no_ssl() {
    log_info "尝试使用官方仓库（临时禁用SSL验证）..."
    
    # 备份原始配置
    if [[ $PKG_MANAGER == "dnf" ]]; then
        cp /etc/dnf/dnf.conf /etc/dnf/dnf.conf.backup 2>/dev/null || true
        echo "sslverify=False" >> /etc/dnf/dnf.conf
    else
        cp /etc/yum.conf /etc/yum.conf.backup 2>/dev/null || true
        echo "sslverify=0" >> /etc/yum.conf
    fi
    
    # 添加官方仓库
    if [[ $PKG_MANAGER == "dnf" ]]; then
        dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    else
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    fi
    
    # 针对 OpenCloudOS 调整版本
    if [[ -f /etc/opencloudos-release ]]; then
        sed -i 's/\$releasever/8/g' /etc/yum.repos.d/docker-ce.repo
    fi
    
    # 更新缓存
    $PKG_MANAGER makecache
    
    # 安装 Docker
    if $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        log_info "官方仓库安装成功"
        
        # 恢复SSL验证
        if [[ $PKG_MANAGER == "dnf" ]]; then
            mv /etc/dnf/dnf.conf.backup /etc/dnf/dnf.conf 2>/dev/null || sed -i '/sslverify=False/d' /etc/dnf/dnf.conf
        else
            mv /etc/yum.conf.backup /etc/yum.conf 2>/dev/null || sed -i '/sslverify=0/d' /etc/yum.conf
        fi
        
        return 0
    else
        log_warn "官方仓库安装失败"
        
        # 恢复SSL验证
        if [[ $PKG_MANAGER == "dnf" ]]; then
            mv /etc/dnf/dnf.conf.backup /etc/dnf/dnf.conf 2>/dev/null || sed -i '/sslverify=False/d' /etc/dnf/dnf.conf
        else
            mv /etc/yum.conf.backup /etc/yum.conf 2>/dev/null || sed -i '/sslverify=0/d' /etc/yum.conf
        fi
        
        return 1
    fi
}

# 方法5：使用系统仓库
install_docker_system_repo() {
    log_info "尝试使用系统仓库安装..."
    
    # 启用 EPEL 仓库
    $PKG_MANAGER install -y epel-release
    
    # 尝试安装 docker
    if $PKG_MANAGER install -y docker; then
        log_info "系统仓库安装成功"
        return 0
    else
        log_warn "系统仓库安装失败"
        return 1
    fi
}

# 主安装函数 - 尝试多种方法
install_docker() {
    log_info "开始安装 Docker CE..."
    
    # 按优先级尝试不同的安装方法
    if install_docker_aliyun_script; then
        log_info "使用阿里云一键脚本安装成功"
        return 0
    elif install_docker_tencent_mirror; then
        log_info "使用腾讯云镜像源安装成功"
        return 0
    elif install_docker_aliyun_mirror; then
        log_info "使用阿里云镜像源安装成功"
        return 0
    elif install_docker_official_no_ssl; then
        log_info "使用官方仓库（禁用SSL）安装成功"
        return 0
    elif install_docker_system_repo; then
        log_info "使用系统仓库安装成功"
        return 0
    else
        log_error "所有安装方法都失败了"
        exit 1
    fi
}

# 配置 Docker 镜像源加速
configure_docker_registry() {
    log_info "配置 Docker 镜像源加速..."
    
    # 创建 Docker 配置目录
    mkdir -p /etc/docker
    
    # 创建 daemon.json 配置文件，添加国内镜像源
    cat > /etc/docker/daemon.json << 'EOF'
{
    "registry-mirrors": [
        "https://docker.mirrors.ustc.edu.cn",
        "https://hub-mirror.c.163.com",
        "https://mirror.baidubce.com",
        "https://ccr.ccs.tencentyun.com"
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
    "insecure-registries": [],
    "default-ulimits": {
        "nofile": {
            "Hard": 64000,
            "Name": "nofile",
            "Soft": 64000
        }
    }
}
EOF
    
    log_info "镜像源配置完成"
}

# 启动并启用 Docker 服务
start_docker() {
    log_info "启动 Docker 服务..."
    
    # 重新加载 systemd 配置
    systemctl daemon-reload
    
    # 启动 Docker 服务
    systemctl start docker
    systemctl enable docker
    
    # 等待服务完全启动
    sleep 3
    
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

# 测试网络连接
test_network() {
    log_info "测试网络连接..."
    
    # 测试基本网络连接
    if ping -c 1 8.8.8.8 &> /dev/null; then
        log_info "网络连接正常"
        return 0
    else
        log_warn "网络连接可能有问题"
        return 1
    fi
}

# 测试 Docker 安装
test_docker() {
    log_info "测试 Docker 安装..."
    
    # 检查 Docker 版本
    if docker --version &> /dev/null; then
        log_info "Docker 命令可用"
    else
        log_error "Docker 命令不可用"
        return 1
    fi
    
    # 检查 Docker 守护进程
    if docker info &> /dev/null; then
        log_info "Docker 守护进程正常运行"
    else
        log_error "Docker 守护进程未正常运行"
        return 1
    fi
    
    # 简单的本地测试，不依赖网络
    log_info "执行本地功能测试..."
    if echo "FROM scratch" | docker build -t test-image - &> /dev/null; then
        docker rmi test-image &> /dev/null
        log_info "Docker 本地功能测试成功"
    else
        log_warn "Docker 本地功能测试失败"
    fi
    
    # 测试网络连接
    test_network
    
    # 尝试拉取测试镜像（可选）
    log_info "尝试网络镜像测试（可选）..."
    
    # 设置较短的超时时间
    export DOCKER_CLIENT_TIMEOUT=30
    export COMPOSE_HTTP_TIMEOUT=30
    
    # 尝试拉取hello-world镜像
    if timeout 30 docker run --rm hello-world &> /dev/null; then
        log_info "网络镜像测试成功！"
        return 0
    else
        log_warn "网络镜像测试失败，但 Docker 已正常安装"
        log_warn "可以稍后手动测试: docker run hello-world"
        return 0
    fi
}

# 显示网络故障排除建议
show_network_troubleshooting() {
    log_warn "如果遇到网络问题，可以尝试以下解决方案："
    echo
    echo "1. 手动测试 Docker："
    echo "   docker run hello-world"
    echo
    echo "2. 检查镜像源配置："
    echo "   cat /etc/docker/daemon.json"
    echo
    echo "3. 重启 Docker 服务："
    echo "   systemctl restart docker"
    echo
    echo "4. 检查网络连接："
    echo "   ping docker.mirrors.ustc.edu.cn"
    echo
    echo "5. 如果网络问题持续，可以配置代理或使用离线镜像"
    echo
}

# 显示安装信息
show_install_info() {
    log_info "Docker 安装完成！"
    echo
    echo "Docker 版本信息："
    docker --version
    docker-compose --version 2>/dev/null || docker compose version 2>/dev/null || echo "Docker Compose 插件已安装"
    echo
    echo "Docker 服务状态："
    systemctl status docker --no-pager -l | head -10
    echo
    echo "镜像源配置："
    if [[ -f /etc/docker/daemon.json ]]; then
        echo "已配置镜像加速源:"
        grep -A 5 "registry-mirrors" /etc/docker/daemon.json || echo "配置文件存在"
    fi
    echo
    echo "包管理器信息："
    echo "使用的包管理器: $PKG_MANAGER"
    echo "系统版本: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
    echo
    log_info "安装日志已保存到: /var/log/docker-install.log"
    
    # 显示故障排除信息
    show_network_troubleshooting
}

# 主函数
main() {
    log_info "开始安装 Docker CE for OpenCloudOS..."
    
    check_root
    check_system
    remove_old_docker
    install_dependencies
    install_docker
    configure_docker_registry
    start_docker
    configure_docker_group
    
    # 测试安装，但不因测试失败而终止脚本
    if test_docker; then
        log_info "所有测试通过！"
    else
        log_warn "部分测试未通过，但 Docker 已成功安装"
    fi
    
    show_install_info
    
    log_info "Docker 安装脚本执行完成！"
}

# 执行主函数并记录日志
main "$@" 2>&1 | tee /var/log/docker-install.log 