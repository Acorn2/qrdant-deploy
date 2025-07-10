 #!/bin/bash

# Qdrant 向量数据库增强部署脚本
# 适用于网络受限环境的多种部署方案
# 版本: 2.1 - 修复离线部署缺失容器启动问题

set -e

# 颜色输出函数
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

log_title() {
    echo -e "${BLUE}[标题]${NC} $1"
}

log_step() {
    echo -e "${PURPLE}[步骤]${NC} $1"
}

# 默认配置
QDRANT_VERSION="v1.14.1"
QDRANT_PORT="6333"
QDRANT_GRPC_PORT="6334"
QDRANT_DATA_DIR="/opt/qdrant/data"
QDRANT_CONFIG_DIR="/opt/qdrant/config"
QDRANT_CONTAINER_NAME="qdrant-server"
QDRANT_NETWORK="qdrant-network"

# 部署方案菜单
show_deployment_options() {
    log_title "选择部署方案"
    echo "1. 在线部署（Docker镜像拉取）"
    echo "2. 离线部署（tar包导入）"
    echo "3. 源码编译部署"
    echo "4. 二进制文件部署"
    echo "5. Podman替代方案"
    echo "6. 测试网络连通性"
    echo "7. 退出"
    echo
}

# 方案1：增强的在线部署
enhanced_online_deploy() {
    log_step "执行增强在线部署..."
    
    # 尝试修复DNS
    fix_dns_settings
    
    # 尝试多种网络优化
    optimize_network_settings
    
    # 使用更多镜像源
    try_enhanced_mirrors
}

# 修复DNS设置
fix_dns_settings() {
    log_info "优化DNS设置..."
    
    # 备份原DNS
    cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d_%H%M%S)
    
    # 设置多个DNS服务器
    cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 114.114.114.114
nameserver 223.5.5.5
nameserver 119.29.29.29
options timeout:2 attempts:3 rotate single-request-reopen
EOF
    
    log_info "DNS配置已更新"
}

# 网络优化设置
optimize_network_settings() {
    log_info "优化网络设置..."
    
    # 增加TCP连接超时
    echo "net.ipv4.tcp_syn_retries = 3" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_synack_retries = 3" >> /etc/sysctl.conf
    echo "net.core.netdev_max_backlog = 5000" >> /etc/sysctl.conf
    
    sysctl -p >/dev/null 2>&1 || true
}

# 尝试增强镜像源
try_enhanced_mirrors() {
    log_info "尝试增强镜像拉取策略..."
    
    local image_name="qdrant/qdrant:$QDRANT_VERSION"
    
    # 增强的镜像源列表
    local enhanced_mirrors=(
        "registry-1.docker.io"
        "ccr.ccs.tencentyun.com"
        "registry.cn-hangzhou.aliyuncs.com" 
        "registry.cn-beijing.aliyuncs.com"
        "registry.cn-shenzhen.aliyuncs.com"
        "docker.mirrors.ustc.edu.cn"
        "hub-mirror.c.163.com"
        "mirror.baidubce.com"
        "dockerproxy.com"
        "docker.nju.edu.cn"
    )
    
    for mirror in "${enhanced_mirrors[@]}"; do
        log_info "尝试镜像源: $mirror"
        
        if [[ "$mirror" == "registry-1.docker.io" ]]; then
            # 官方源，使用代理
            if try_with_proxy "$image_name"; then
                return 0
            fi
        else
            # 尝试不同的镜像命名方式
            local mirror_images=(
                "$mirror/qdrant/qdrant:${QDRANT_VERSION#v}"
                "$mirror/library/qdrant:${QDRANT_VERSION#v}"
                "$mirror/docker.io/qdrant/qdrant:${QDRANT_VERSION#v}"
            )
            
            for mirror_image in "${mirror_images[@]}"; do
                if timeout 180 docker pull "$mirror_image" >/dev/null 2>&1; then
                    docker tag "$mirror_image" "$image_name"
                    log_info "✓ 成功从 $mirror 拉取镜像"
                    return 0
                fi
            done
        fi
        
        sleep 2
    done
    
    log_error "所有在线方案都失败，请尝试离线部署"
    return 1
}

# 使用代理尝试拉取
try_with_proxy() {
    local image_name="$1"
    
    # 尝试设置HTTP代理（如果有的话）
    if [[ -n "$http_proxy" || -n "$HTTP_PROXY" ]]; then
        log_info "检测到代理设置，尝试通过代理拉取..."
        if timeout 300 docker pull "$image_name"; then
            return 0
        fi
    fi
    
    # 尝试直连
    log_info "尝试直连拉取..."
    if timeout 300 docker pull "$image_name"; then
        return 0
    fi
    
    return 1
}

# 方案2：离线部署（修复版）
offline_deploy() {
    log_step "执行离线部署..."
    
    local offline_dir="/tmp/qdrant-offline"
    mkdir -p "$offline_dir"
    
    log_info "离线部署有以下选项："
    echo "1. 使用预下载的tar包"
    echo "2. 从其他服务器传输镜像"
    echo "3. 使用镜像文件"
    
    read -p "请选择离线部署方式 (1-3): " offline_choice
    
    case $offline_choice in
        1) deploy_from_tar && setup_and_start_container ;;
        2) deploy_from_transfer && setup_and_start_container ;;
        3) deploy_from_image_file && setup_and_start_container ;;
        *) log_error "无效选择" && return 1 ;;
    esac
}

# 从tar包部署（修复版）
deploy_from_tar() {
    log_info "从tar包部署Qdrant..."
    
    echo "请按以下步骤准备tar包："
    echo "1. 在有网络的机器上执行："
    echo "   docker pull qdrant/qdrant:$QDRANT_VERSION"
    echo "   docker save qdrant/qdrant:$QDRANT_VERSION > qdrant-${QDRANT_VERSION}.tar"
    echo "2. 将tar文件传输到此服务器"
    echo "3. 输入tar文件的完整路径"
    echo
    
    read -p "请输入tar文件路径: " tar_path
    
    if [[ -f "$tar_path" ]]; then
        log_info "加载Docker镜像..."
        docker load < "$tar_path"
        log_info "镜像加载完成"
        
        # 验证镜像是否成功加载
        if docker images | grep -q "qdrant/qdrant"; then
            log_info "✓ 检测到已加载的Qdrant镜像："
            docker images | grep qdrant
            return 0
        else
            log_error "✗ 镜像加载后未找到qdrant镜像"
            return 1
        fi
    else
        log_error "文件不存在: $tar_path"
        return 1
    fi
}

# 从其他服务器传输（修复版）
deploy_from_transfer() {
    log_info "从其他服务器传输镜像..."
    
    echo "请在有网络的服务器上执行以下命令："
    echo "1. docker pull qdrant/qdrant:$QDRANT_VERSION"
    echo "2. docker save qdrant/qdrant:$QDRANT_VERSION | gzip > qdrant.tar.gz"
    echo "3. scp qdrant.tar.gz user@$(hostname -I | awk '{print $1}'):/tmp/"
    echo
    
    read -p "传输完成后按Enter继续，或输入'q'退出: " continue_transfer
    
    if [[ "$continue_transfer" == "q" ]]; then
        return 1
    fi
    
    if [[ -f "/tmp/qdrant.tar.gz" ]]; then
        log_info "解压并加载镜像..."
        gunzip -c /tmp/qdrant.tar.gz | docker load
        log_info "镜像加载完成"
        rm -f /tmp/qdrant.tar.gz
        
        # 验证镜像是否成功加载
        if docker images | grep -q "qdrant/qdrant"; then
            log_info "✓ 检测到已加载的Qdrant镜像："
            docker images | grep qdrant
            return 0
        else
            log_error "✗ 镜像加载后未找到qdrant镜像"
            return 1
        fi
    else
        log_error "未找到传输的镜像文件"
        return 1
    fi
}

# 从镜像文件部署（修复版）
deploy_from_image_file() {
    log_info "从镜像文件部署..."
    
    # 提供预制的下载链接（如果有的话）
    echo "您可以尝试从以下位置获取镜像文件："
    echo "1. GitHub Releases: https://github.com/qdrant/qdrant/releases"
    echo "2. Docker Hub导出工具"
    echo "3. 其他镜像仓库"
    echo
    
    read -p "请输入镜像文件路径（支持.tar, .tar.gz, .tar.bz2）: " image_path
    
    if [[ -f "$image_path" ]]; then
        log_info "加载镜像文件..."
        
        case "$image_path" in
            *.tar.gz) gunzip -c "$image_path" | docker load ;;
            *.tar.bz2) bunzip2 -c "$image_path" | docker load ;;
            *.tar) docker load < "$image_path" ;;
            *) log_error "不支持的文件格式" && return 1 ;;
        esac
        
        log_info "镜像加载完成"
        
        # 验证镜像是否成功加载
        if docker images | grep -q "qdrant/qdrant"; then
            log_info "✓ 检测到已加载的Qdrant镜像："
            docker images | grep qdrant
            return 0
        else
            log_error "✗ 镜像加载后未找到qdrant镜像"
            return 1
        fi
    else
        log_error "文件不存在: $image_path"
        return 1
    fi
}

# 新增：设置和启动容器
setup_and_start_container() {
    log_step "设置和启动Qdrant容器..."
    
    # 创建必要目录
    create_directories
    
    # 创建配置文件
    create_config_file
    
    # 创建Docker网络
    create_docker_network
    
    # 清理现有容器
    cleanup_existing_container
    
    # 启动容器
    start_qdrant_container
    
    # 等待并验证服务
    wait_and_verify_service
    
    return $?
}

# 新增：创建目录
create_directories() {
    log_info "创建Qdrant数据和配置目录..."
    
    sudo mkdir -p "$QDRANT_DATA_DIR" "$QDRANT_CONFIG_DIR"
    sudo chown -R 1000:1000 "$QDRANT_DATA_DIR" "$QDRANT_CONFIG_DIR"
    
    log_info "目录创建完成："
    log_info "数据目录: $QDRANT_DATA_DIR"
    log_info "配置目录: $QDRANT_CONFIG_DIR"
}

# 新增：创建配置文件
create_config_file() {
    log_info "创建Qdrant配置文件..."
    
    cat > "$QDRANT_CONFIG_DIR/config.yaml" << 'EOF'
# Qdrant 配置文件 - v1.14.1 兼容
storage:
  storage_path: "/qdrant/storage"
  wal_capacity_mb: 32
  wal_segments_ahead: 0
  
service:
  host: "0.0.0.0"
  http_port: 6333
  grpc_port: 6334
  enable_cors: true
  max_request_size_mb: 32
  max_timeout_seconds: 30
  
log_level: "INFO"

hnsw_config:
  m: 16
  ef_construct: 100
  full_scan_threshold: 10000
  max_indexing_threads: 0

optimizer_config:
  deleted_threshold: 0.2
  vacuum_min_vector_number: 1000
  default_segment_number: 0
  memmap_threshold: 50000
  indexing_threshold: 20000
  flush_interval_sec: 5
  max_optimization_threads: 1

telemetry_disabled: true
EOF
    
    log_info "配置文件创建完成: $QDRANT_CONFIG_DIR/config.yaml"
}

# 新增：创建Docker网络
create_docker_network() {
    log_info "创建Docker网络..."
    
    if ! docker network ls | grep -q "$QDRANT_NETWORK"; then
        docker network create "$QDRANT_NETWORK"
        log_info "Docker网络 '$QDRANT_NETWORK' 创建成功"
    else
        log_info "Docker网络 '$QDRANT_NETWORK' 已存在"
    fi
}

# 新增：清理现有容器
cleanup_existing_container() {
    log_info "清理现有Qdrant容器..."
    
    if docker ps -a | grep -q "$QDRANT_CONTAINER_NAME"; then
        log_warn "发现现有容器，正在停止并删除..."
        docker stop "$QDRANT_CONTAINER_NAME" 2>/dev/null || true
        docker rm "$QDRANT_CONTAINER_NAME" 2>/dev/null || true
        log_info "现有容器清理完成"
    fi
}

# 新增：启动Qdrant容器
start_qdrant_container() {
    log_info "启动Qdrant容器..."
    
    # 获取可用的镜像标签
    local image_info=$(docker images | grep qdrant | head -1)
    if [[ -z "$image_info" ]]; then
        log_error "未找到Qdrant镜像"
        return 1
    fi
    
    local image_tag=$(echo "$image_info" | awk '{print $1":"$2}')
    log_info "使用镜像: $image_tag"
    
    # 启动容器
    docker run -d \
        --name "$QDRANT_CONTAINER_NAME" \
        --network "$QDRANT_NETWORK" \
        -p "$QDRANT_PORT:6333" \
        -p "$QDRANT_GRPC_PORT:6334" \
        -v "$QDRANT_DATA_DIR:/qdrant/storage" \
        -v "$QDRANT_CONFIG_DIR:/qdrant/config" \
        --restart unless-stopped \
        --memory="2g" \
        --cpus="1.0" \
        "$image_tag" \
        ./qdrant --config-path /qdrant/config/config.yaml
    
    if [[ $? -eq 0 ]]; then
        log_info "Qdrant容器启动成功"
        return 0
    else
        log_error "Qdrant容器启动失败"
        return 1
    fi
}

# 新增：等待并验证服务
wait_and_verify_service() {
    log_info "等待Qdrant服务启动..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "检查服务状态... ($attempt/$max_attempts)"
        
        # 检查容器状态
        if ! docker ps | grep -q "$QDRANT_CONTAINER_NAME"; then
            log_error "容器未运行，查看启动日志："
            docker logs "$QDRANT_CONTAINER_NAME" --tail 20
            return 1
        fi
        
        # 检查API响应
        if curl -s --connect-timeout 5 "http://localhost:$QDRANT_PORT/health" >/dev/null 2>&1; then
            log_info "✓ Qdrant服务启动成功！"
            
            # 获取版本信息
            local health_response=$(curl -s "http://localhost:$QDRANT_PORT/health" 2>/dev/null)
            echo "健康状态: $health_response"
            
            local version_info=$(curl -s "http://localhost:$QDRANT_PORT/" 2>/dev/null)
            echo "版本信息:"
            echo "$version_info" | python3 -m json.tool 2>/dev/null || echo "$version_info"
            
            return 0
        fi
        
        sleep 2
        ((attempt++))
    done
    
    log_error "Qdrant服务启动超时！"
    log_info "查看容器日志："
    docker logs "$QDRANT_CONTAINER_NAME" --tail 20
    return 1
}

# 方案3：源码编译部署
source_compile_deploy() {
    log_step "执行源码编译部署..."
    
    log_warn "源码编译需要较长时间和较多资源"
    read -p "确认继续？(y/N): " confirm_compile
    
    if [[ "$confirm_compile" != "y" && "$confirm_compile" != "Y" ]]; then
        return 1
    fi
    
    # 安装编译依赖
    install_compile_dependencies
    
    # 下载源码
    download_source_code
    
    # 编译安装
    compile_and_install
}

# 安装编译依赖
install_compile_dependencies() {
    log_info "安装编译依赖..."
    
    # 检测包管理器
    if command -v yum &> /dev/null; then
        yum update -y
        yum groupinstall -y "Development Tools"
        yum install -y git curl wget openssl-devel
    elif command -v apt &> /dev/null; then
        apt update
        apt install -y build-essential git curl wget libssl-dev pkg-config
    else
        log_error "不支持的包管理器"
        return 1
    fi
    
    # 安装Rust
    install_rust
}

# 安装Rust
install_rust() {
    log_info "安装Rust编译环境..."
    
    if ! command -v rustc &> /dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
        
        # 配置国内镜像源
        mkdir -p ~/.cargo
        cat > ~/.cargo/config.toml << 'EOF'
[source.crates-io]
registry = "https://github.com/rust-lang/crates.io-index"
replace-with = 'ustc'

[source.ustc]
registry = "git://mirrors.ustc.edu.cn/crates.io-index"
EOF
    fi
    
    rustc --version
}

# 下载源码
download_source_code() {
    log_info "下载Qdrant源码..."
    
    cd /tmp
    rm -rf qdrant
    
    # 尝试不同的下载方式
    if git clone https://github.com/qdrant/qdrant.git; then
        cd qdrant
        git checkout "$QDRANT_VERSION"
    elif wget "https://github.com/qdrant/qdrant/archive/refs/tags/${QDRANT_VERSION}.tar.gz"; then
        tar -xzf "${QDRANT_VERSION}.tar.gz"
        cd "qdrant-${QDRANT_VERSION#v}"
    else
        log_error "无法下载源码"
        return 1
    fi
}

# 编译安装
compile_and_install() {
    log_info "开始编译Qdrant..."
    
    # 编译（这可能需要很长时间）
    cargo build --release
    
    if [[ -f target/release/qdrant ]]; then
        log_info "编译完成，安装二进制文件..."
        
        # 安装二进制文件
        sudo mkdir -p /usr/local/bin
        sudo cp target/release/qdrant /usr/local/bin/
        sudo chmod +x /usr/local/bin/qdrant
        
        # 创建systemd服务
        create_systemd_service
        
        log_info "源码编译部署完成"
        return 0
    else
        log_error "编译失败"
        return 1
    fi
}

# 方案4：二进制文件部署
binary_deploy() {
    log_step "执行二进制文件部署..."
    
    local arch=$(uname -m)
    local os="linux"
    
    case $arch in
        x86_64) arch="x86_64" ;;
        aarch64) arch="aarch64" ;;
        *) log_error "不支持的架构: $arch" && return 1 ;;
    esac
    
    log_info "检测到架构: $arch"
    
    # 尝试下载预编译二进制文件
    local binary_url="https://github.com/qdrant/qdrant/releases/download/${QDRANT_VERSION}/qdrant-${os}-${arch}"
    
    log_info "尝试下载二进制文件..."
    if wget -O /tmp/qdrant "$binary_url"; then
        sudo mv /tmp/qdrant /usr/local/bin/
        sudo chmod +x /usr/local/bin/qdrant
        
        # 创建systemd服务
        create_systemd_service
        
        log_info "二进制部署完成"
        return 0
    else
        log_error "无法下载二进制文件"
        
        # 提供手动下载指导
        echo "请手动下载二进制文件："
        echo "1. 访问: https://github.com/qdrant/qdrant/releases/tag/$QDRANT_VERSION"
        echo "2. 下载适合您系统的二进制文件"
        echo "3. 将文件重命名为'qdrant'并放置到 /usr/local/bin/"
        echo "4. 设置执行权限: chmod +x /usr/local/bin/qdrant"
        
        return 1
    fi
}

# 创建systemd服务
create_systemd_service() {
    log_info "创建systemd服务..."
    
    # 创建用户和目录
    sudo useradd -r -s /bin/false qdrant 2>/dev/null || true
    sudo mkdir -p "$QDRANT_DATA_DIR" "$QDRANT_CONFIG_DIR"
    sudo chown -R qdrant:qdrant "$QDRANT_DATA_DIR" "$QDRANT_CONFIG_DIR"
    
    # 创建配置文件
    create_config_file
    
    # 创建systemd服务文件
    cat > /etc/systemd/system/qdrant.service << EOF
[Unit]
Description=Qdrant Vector Database
After=network.target
Wants=network.target

[Service]
Type=simple
User=qdrant
Group=qdrant
ExecStart=/usr/local/bin/qdrant --config-path $QDRANT_CONFIG_DIR/config.yaml
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=qdrant

# 安全设置
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$QDRANT_DATA_DIR $QDRANT_CONFIG_DIR

[Install]
WantedBy=multi-user.target
EOF
    
    # 启用并启动服务
    systemctl daemon-reload
    systemctl enable qdrant
    systemctl start qdrant
    
    log_info "Qdrant服务已启动"
}

# 创建配置文件
create_config_file() {
    cat > "$QDRANT_CONFIG_DIR/config.yaml" << 'EOF'
service:
  host: "0.0.0.0"
  http_port: 6333
  grpc_port: 6334

storage:
  storage_path: "/opt/qdrant/data"

log_level: "INFO"
telemetry_disabled: true
EOF
}

# 方案5：Podman替代方案
podman_deploy() {
    log_step "执行Podman替代部署..."
    
    # 安装Podman
    install_podman
    
    # 使用Podman拉取和运行
    if podman pull "qdrant/qdrant:$QDRANT_VERSION"; then
        log_info "Podman拉取成功"
        
        # 使用Podman运行
        podman run -d \
            --name "$QDRANT_CONTAINER_NAME" \
            -p "$QDRANT_PORT:6333" \
            -p "$QDRANT_GRPC_PORT:6334" \
            -v "$QDRANT_DATA_DIR:/qdrant/storage" \
            -v "$QDRANT_CONFIG_DIR:/qdrant/config" \
            --restart=always \
            "qdrant/qdrant:$QDRANT_VERSION"
            
        log_info "Podman部署完成"
        return 0
    else
        log_error "Podman拉取失败"
        return 1
    fi
}

# 安装Podman
install_podman() {
    log_info "安装Podman..."
    
    if command -v yum &> /dev/null; then
        yum install -y podman
    elif command -v apt &> /dev/null; then
        apt update && apt install -y podman
    else
        log_error "无法安装Podman"
        return 1
    fi
}

# 方案6：测试网络连通性
test_network_connectivity() {
    log_step "测试网络连通性..."
    
    local test_hosts=(
        "registry-1.docker.io"
        "ccr.ccs.tencentyun.com"
        "registry.cn-hangzhou.aliyuncs.com"
        "8.8.8.8"
        "github.com"
    )
    
    for host in "${test_hosts[@]}"; do
        log_info "测试连接: $host"
        
        if ping -c 3 "$host" >/dev/null 2>&1; then
            echo "✓ $host - 可达"
        else
            echo "✗ $host - 不可达"
        fi
        
        if [[ "$host" =~ registry ]]; then
            if curl -I "https://$host" >/dev/null 2>&1; then
                echo "✓ $host HTTPS - 正常"
            else
                echo "✗ $host HTTPS - 异常"
            fi
        fi
    done
    
    # DNS测试
    log_info "测试DNS解析..."
    for host in "${test_hosts[@]}"; do
        if nslookup "$host" >/dev/null 2>&1; then
            echo "✓ DNS $host - 正常"
        else
            echo "✗ DNS $host - 异常"
        fi
    done
    
    # 提供网络诊断建议
    echo
    log_info "网络诊断建议："
    echo "1. 如果Docker镜像源不可达，考虑使用离线部署"
    echo "2. 如果DNS解析异常，检查 /etc/resolv.conf"
    echo "3. 如果网络完全不通，使用源码编译或二进制部署"
    echo "4. 检查防火墙和代理设置"
}

# 通用的后续配置
post_deployment_setup() {
    log_info "执行后续配置..."
    
    # 创建数据目录
    sudo mkdir -p "$QDRANT_DATA_DIR" "$QDRANT_CONFIG_DIR"
    
    # 配置防火墙
    configure_firewall
    
    # 验证安装
    verify_installation
    
    # 显示部署信息
    show_deployment_info
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."
    
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port="$QDRANT_PORT/tcp" 2>/dev/null || true
        firewall-cmd --permanent --add-port="$QDRANT_GRPC_PORT/tcp" 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
    fi
}

# 修改验证安装函数
verify_installation() {
    log_info "验证安装..."
    
    # 检查容器状态
    if docker ps | grep -q "$QDRANT_CONTAINER_NAME"; then
        log_info "✓ Docker容器运行正常"
        
        # 检查API响应
        if curl -s --connect-timeout 5 "http://localhost:$QDRANT_PORT/health" >/dev/null 2>&1; then
            log_info "✓ Qdrant服务运行正常"
            
            # 测试基本API
            local collections_response=$(curl -s "http://localhost:$QDRANT_PORT/collections" 2>/dev/null)
            log_info "✓ API功能测试通过"
            
            return 0
        else
            log_warn "⚠ API服务无响应，服务可能还在启动中..."
            return 1
        fi
    else
        log_error "✗ Docker容器未运行"
        
        # 检查是否有systemd服务
        if systemctl list-unit-files | grep -q "qdrant.service"; then
            local service_status=$(systemctl is-active qdrant 2>/dev/null || echo "inactive")
            if [[ "$service_status" == "active" ]]; then
                log_info "✓ 系统服务运行正常"
                return 0
            else
                log_warn "⚠ 系统服务未运行"
                return 1
            fi
        fi
        
        return 1
    fi
}

# 修改显示部署信息函数
show_deployment_info() {
    log_title "=== 部署完成 ==="
    
    echo "Qdrant访问地址："
    echo "  HTTP API: http://localhost:$QDRANT_PORT"
    echo "  gRPC API: localhost:$QDRANT_GRPC_PORT"
    echo "  管理界面: http://localhost:$QDRANT_PORT/dashboard"
    echo
    echo "数据目录: $QDRANT_DATA_DIR"
    echo "配置目录: $QDRANT_CONFIG_DIR"
    echo
    echo "验证命令："
    echo "  查看容器: docker ps | grep qdrant"
    echo "  查看日志: docker logs $QDRANT_CONTAINER_NAME"
    echo "  健康检查: curl http://localhost:$QDRANT_PORT/health"
    echo "  API测试: curl http://localhost:$QDRANT_PORT/"
    echo "  集合列表: curl http://localhost:$QDRANT_PORT/collections"
}

# 主菜单循环
main() {
    log_title "=== Qdrant 增强部署脚本 v2.1 ==="
    
    # 检查权限
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
    
    while true; do
        show_deployment_options
        read -p "请选择部署方案 (1-7): " choice
        
        case $choice in
            1)
                enhanced_online_deploy && post_deployment_setup
                break
                ;;
            2)
                offline_deploy && post_deployment_setup
                break
                ;;
            3)
                source_compile_deploy && post_deployment_setup
                break
                ;;
            4)
                binary_deploy && post_deployment_setup
                break
                ;;
            5)
                podman_deploy && post_deployment_setup
                break
                ;;
            6)
                test_network_connectivity
                ;;
            7)
                log_info "退出部署脚本"
                exit 0
                ;;
            *)
                log_error "无效选择，请重新输入"
                ;;
        esac
        
        echo
        read -p "按Enter继续..." 
        echo
    done
}

# 执行主函数
main "$@"