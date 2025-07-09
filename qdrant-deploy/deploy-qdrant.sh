#!/bin/bash

# Qdrant 向量数据库部署脚本
# 适用于腾讯云服务器 OpenCloudOS 系统
# 版本: 1.1 - 修复镜像拉取超时问题
# 要求: Docker 已安装

set -e

# 颜色输出函数
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# 默认配置 - 修改为稳定版本
QDRANT_VERSION="v1.7.4"  # 指定稳定版本，避免网络问题
QDRANT_PORT="6333"
QDRANT_GRPC_PORT="6334"
QDRANT_DATA_DIR="/opt/qdrant/data"
QDRANT_CONFIG_DIR="/opt/qdrant/config"
QDRANT_CONTAINER_NAME="qdrant-server"
QDRANT_NETWORK="qdrant-network"

# 可选的镜像版本列表
AVAILABLE_VERSIONS=("v1.7.4" "v1.7.3" "v1.6.1" "v1.5.1" "latest")

# 显示版本选择菜单
show_version_menu() {
    log_title "选择 Qdrant 版本"
    echo "可用版本："
    for i in "${!AVAILABLE_VERSIONS[@]}"; do
        echo "$((i+1)). ${AVAILABLE_VERSIONS[$i]}"
    done
    echo "$((${#AVAILABLE_VERSIONS[@]}+1)). 自定义版本"
    echo
}

# 选择版本
select_version() {
    while true; do
        show_version_menu
        read -p "请选择版本 (1-$((${#AVAILABLE_VERSIONS[@]}+1))) [默认: 1]: " choice
        
        # 默认选择第一个版本
        if [[ -z "$choice" ]]; then
            choice=1
        fi
        
        if [[ "$choice" -ge 1 && "$choice" -le ${#AVAILABLE_VERSIONS[@]} ]]; then
            QDRANT_VERSION="${AVAILABLE_VERSIONS[$((choice-1))]}"
            log_info "已选择版本: $QDRANT_VERSION"
            break
        elif [[ "$choice" -eq $((${#AVAILABLE_VERSIONS[@]}+1)) ]]; then
            read -p "请输入自定义版本 (如 v1.7.0): " custom_version
            if [[ -n "$custom_version" ]]; then
                QDRANT_VERSION="$custom_version"
                log_info "已选择自定义版本: $QDRANT_VERSION"
                break
            else
                log_error "版本不能为空"
            fi
        else
            log_error "无效的选择，请重新输入"
        fi
    done
}

# 配置Docker镜像加速
configure_docker_mirrors() {
    log_info "检查Docker镜像加速配置..."
    
    # 检查是否已配置镜像源
    if [[ -f /etc/docker/daemon.json ]] && grep -q "registry-mirrors" /etc/docker/daemon.json; then
        log_info "Docker镜像加速已配置"
        return 0
    fi
    
    log_info "配置Docker镜像加速源..."
    
    # 备份现有配置
    if [[ -f /etc/docker/daemon.json ]]; then
        cp /etc/docker/daemon.json /etc/docker/daemon.json.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # 创建或更新daemon.json
    mkdir -p /etc/docker
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
    "live-restore": true,
    "max-concurrent-downloads": 3,
    "max-concurrent-uploads": 3
}
EOF
    
    # 重启Docker服务应用配置
    log_info "重启Docker服务以应用镜像加速配置..."
    systemctl daemon-reload
    systemctl restart docker
    
    # 等待Docker服务完全启动
    sleep 5
    
    if systemctl is-active --quiet docker; then
        log_info "Docker服务重启成功，镜像加速配置已生效"
    else
        log_error "Docker服务重启失败"
        exit 1
    fi
}

# 检查Docker是否已安装
check_docker() {
    log_info "检查Docker安装状态..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker未安装！请先运行 ../scripts/install-docker.sh 安装Docker"
        exit 1
    fi
    
    if ! systemctl is-active --quiet docker; then
        log_error "Docker服务未运行！请启动Docker服务"
        log_info "运行命令: sudo systemctl start docker"
        exit 1
    fi
    
    log_info "Docker已安装并运行正常"
    docker --version
}

# 检查端口是否被占用
check_ports() {
    log_info "检查端口占用情况..."
    
    if netstat -tulpn | grep -q ":${QDRANT_PORT} "; then
        log_error "端口 ${QDRANT_PORT} 已被占用！"
        netstat -tulpn | grep ":${QDRANT_PORT} "
        exit 1
    fi
    
    if netstat -tulpn | grep -q ":${QDRANT_GRPC_PORT} "; then
        log_error "端口 ${QDRANT_GRPC_PORT} 已被占用！"
        netstat -tulpn | grep ":${QDRANT_GRPC_PORT} "
        exit 1
    fi
    
    log_info "端口检查通过"
}

# 创建必要的目录
create_directories() {
    log_info "创建Qdrant数据和配置目录..."
    
    sudo mkdir -p "$QDRANT_DATA_DIR"
    sudo mkdir -p "$QDRANT_CONFIG_DIR"
    
    # 设置目录权限
    sudo chown -R 1000:1000 "$QDRANT_DATA_DIR"
    sudo chown -R 1000:1000 "$QDRANT_CONFIG_DIR"
    
    log_info "目录创建完成："
    log_info "数据目录: $QDRANT_DATA_DIR"
    log_info "配置目录: $QDRANT_CONFIG_DIR"
}

# 创建Qdrant配置文件
create_config() {
    log_info "创建Qdrant配置文件..."
    
    cat > "$QDRANT_CONFIG_DIR/config.yaml" << 'EOF'
# Qdrant 配置文件
storage:
  # 存储配置
  storage_path: "/qdrant/storage"
  
service:
  # 服务配置
  host: "0.0.0.0"
  http_port: 6333
  grpc_port: 6334
  enable_cors: true
  
log_level: "INFO"

# 集群配置（可选，单机部署时注释掉）
# cluster:
#   enabled: false

# 性能优化配置
hnsw_config:
  # HNSW索引参数
  m: 16
  ef_construct: 100
  full_scan_threshold: 10000

# API密钥（可选，启用身份验证）
# api_key: "your-secret-api-key"

# 备份配置
snapshot_config:
  snapshots_path: "/qdrant/snapshots"
EOF
    
    log_info "配置文件创建完成: $QDRANT_CONFIG_DIR/config.yaml"
}

# 创建Docker网络
create_network() {
    log_info "创建Docker网络..."
    
    if ! docker network ls | grep -q "$QDRANT_NETWORK"; then
        docker network create "$QDRANT_NETWORK"
        log_info "Docker网络 '$QDRANT_NETWORK' 创建成功"
    else
        log_warn "Docker网络 '$QDRANT_NETWORK' 已存在"
    fi
}

# 拉取Qdrant镜像 - 增强版，支持重试和超时设置
pull_image() {
    log_info "拉取Qdrant Docker镜像..."
    
    local max_attempts=3
    local attempt=1
    local pull_timeout=600  # 10分钟超时
    
    while [ $attempt -le $max_attempts ]; do
        log_info "尝试拉取镜像 qdrant/qdrant:$QDRANT_VERSION (第 $attempt/$max_attempts 次)"
        
        # 使用timeout命令设置超时时间
        if timeout $pull_timeout docker pull "qdrant/qdrant:$QDRANT_VERSION"; then
            log_info "镜像拉取成功！"
            docker images | grep qdrant
            return 0
        else
            log_warn "第 $attempt 次拉取失败"
            
            if [ $attempt -lt $max_attempts ]; then
                log_info "等待 10 秒后重试..."
                sleep 10
            fi
            
            ((attempt++))
        fi
    done
    
    log_error "镜像拉取失败！尝试以下解决方案："
    echo "1. 检查网络连接"
    echo "2. 尝试更换Docker镜像源"
    echo "3. 使用手动拉取方式："
    echo "   docker pull qdrant/qdrant:$QDRANT_VERSION"
    echo "4. 或者选择其他版本重新运行脚本"
    
    read -p "是否继续尝试手动拉取？(y/N): " continue_manual
    if [[ "$continue_manual" == "y" || "$continue_manual" == "Y" ]]; then
        log_info "请手动执行以下命令："
        echo "docker pull qdrant/qdrant:$QDRANT_VERSION"
        read -p "拉取完成后按 Enter 继续..."
        
        # 验证镜像是否存在
        if docker images | grep -q "qdrant/qdrant"; then
            log_info "检测到Qdrant镜像，继续部署"
            return 0
        else
            log_error "未检测到Qdrant镜像，部署终止"
            exit 1
        fi
    else
        exit 1
    fi
}

# 停止并删除现有容器
cleanup_existing() {
    log_info "清理现有Qdrant容器..."
    
    if docker ps -a | grep -q "$QDRANT_CONTAINER_NAME"; then
        log_warn "发现现有容器，正在停止并删除..."
        docker stop "$QDRANT_CONTAINER_NAME" 2>/dev/null || true
        docker rm "$QDRANT_CONTAINER_NAME" 2>/dev/null || true
        log_info "现有容器清理完成"
    fi
}

# 启动Qdrant容器
start_qdrant() {
    log_info "启动Qdrant容器..."
    
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
        "qdrant/qdrant:$QDRANT_VERSION" \
        ./qdrant --config-path /qdrant/config/config.yaml
    
    log_info "Qdrant容器启动完成"
}

# 等待服务启动
wait_for_service() {
    log_info "等待Qdrant服务启动..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s "http://localhost:$QDRANT_PORT/collections" > /dev/null 2>&1; then
            log_info "Qdrant服务启动成功！"
            return 0
        fi
        
        log_info "等待中... ($attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done
    
    log_error "Qdrant服务启动超时！"
    log_info "查看容器日志："
    docker logs "$QDRANT_CONTAINER_NAME"
    exit 1
}

# 验证安装
verify_installation() {
    log_info "验证Qdrant安装..."
    
    # 检查容器状态
    if docker ps | grep -q "$QDRANT_CONTAINER_NAME"; then
        log_info "✓ 容器运行状态正常"
    else
        log_error "✗ 容器未正常运行"
        docker logs "$QDRANT_CONTAINER_NAME" --tail 20
        exit 1
    fi
    
    # 检查API响应
    local version_info
    version_info=$(curl -s "http://localhost:$QDRANT_PORT/" | python3 -m json.tool 2>/dev/null || echo "API响应异常")
    if [[ "$version_info" != "API响应异常" ]]; then
        log_info "✓ API服务正常"
        echo "$version_info"
    else
        log_error "✗ API服务异常"
        exit 1
    fi
    
    # 检查集合列表
    local collections
    collections=$(curl -s "http://localhost:$QDRANT_PORT/collections" | python3 -m json.tool 2>/dev/null || echo "集合API异常")
    if [[ "$collections" != "集合API异常" ]]; then
        log_info "✓ 集合API正常"
    else
        log_error "✗ 集合API异常"
    fi
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙规则..."
    
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port="$QDRANT_PORT/tcp" 2>/dev/null || true
        firewall-cmd --permanent --add-port="$QDRANT_GRPC_PORT/tcp" 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        log_info "防火墙规则添加完成"
    else
        log_warn "防火墙未运行，跳过防火墙配置"
    fi
}

# 显示部署信息
show_deployment_info() {
    log_title "=== Qdrant 部署完成 ==="
    
    echo
    log_info "服务信息："
    echo "  容器名称: $QDRANT_CONTAINER_NAME"
    echo "  版本: $QDRANT_VERSION"
    echo "  HTTP API: http://localhost:$QDRANT_PORT"
    echo "  gRPC API: localhost:$QDRANT_GRPC_PORT"
    echo "  管理界面: http://localhost:$QDRANT_PORT/dashboard"
    
    echo
    log_info "目录信息："
    echo "  数据目录: $QDRANT_DATA_DIR"
    echo "  配置目录: $QDRANT_CONFIG_DIR"
    echo "  配置文件: $QDRANT_CONFIG_DIR/config.yaml"
    
    echo
    log_info "常用命令："
    echo "  查看容器状态: docker ps | grep qdrant"
    echo "  查看日志: docker logs $QDRANT_CONTAINER_NAME"
    echo "  停止服务: docker stop $QDRANT_CONTAINER_NAME"
    echo "  启动服务: docker start $QDRANT_CONTAINER_NAME"
    echo "  重启服务: docker restart $QDRANT_CONTAINER_NAME"
    
    echo
    log_info "API测试："
    echo "  服务状态: curl http://localhost:$QDRANT_PORT/"
    echo "  集合列表: curl http://localhost:$QDRANT_PORT/collections"
    echo "  健康检查: curl http://localhost:$QDRANT_PORT/health"
    
    echo
    log_info "性能监控："
    echo "  资源使用: docker stats $QDRANT_CONTAINER_NAME"
    echo "  系统指标: curl http://localhost:$QDRANT_PORT/metrics"
}

# 创建管理脚本
create_management_script() {
    log_info "创建Qdrant管理脚本..."
    
    cat > "./qdrant-manage.sh" << EOF
#!/bin/bash

# Qdrant 服务管理脚本

CONTAINER_NAME="$QDRANT_CONTAINER_NAME"
PORT="$QDRANT_PORT"
VERSION="$QDRANT_VERSION"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "\${GREEN}[信息]\${NC} \$1"
}

log_warn() {
    echo -e "\${YELLOW}[警告]\${NC} \$1"
}

log_error() {
    echo -e "\${RED}[错误]\${NC} \$1"
}

show_menu() {
    echo "=== Qdrant 服务管理 ==="
    echo "版本: \$VERSION"
    echo "1. 查看服务状态"
    echo "2. 启动服务"
    echo "3. 停止服务"
    echo "4. 重启服务"
    echo "5. 查看日志"
    echo "6. 查看资源使用"
    echo "7. 备份数据"
    echo "8. API测试"
    echo "9. 更新镜像"
    echo "10. 退出"
    echo
}

check_status() {
    log_info "检查Qdrant服务状态..."
    
    if docker ps | grep -q "\$CONTAINER_NAME"; then
        log_info "✓ 服务运行正常"
        docker ps | grep "\$CONTAINER_NAME"
        
        if curl -s "http://localhost:\$PORT/health" > /dev/null; then
            log_info "✓ API服务正常"
        else
            log_warn "⚠ API服务异常"
        fi
    else
        log_error "✗ 服务未运行"
    fi
}

start_service() {
    log_info "启动Qdrant服务..."
    docker start "\$CONTAINER_NAME"
    sleep 3
    check_status
}

stop_service() {
    log_info "停止Qdrant服务..."
    docker stop "\$CONTAINER_NAME"
    log_info "服务已停止"
}

restart_service() {
    log_info "重启Qdrant服务..."
    docker restart "\$CONTAINER_NAME"
    sleep 3
    check_status
}

show_logs() {
    log_info "显示Qdrant日志（最近50行）..."
    docker logs "\$CONTAINER_NAME" --tail 50 -f
}

show_stats() {
    log_info "显示资源使用情况..."
    docker stats "\$CONTAINER_NAME" --no-stream
}

backup_data() {
    local backup_dir="/opt/qdrant/backups"
    local timestamp=\$(date +%Y%m%d-%H%M%S)
    local backup_file="qdrant-backup-\$timestamp.tar.gz"
    
    log_info "创建数据备份..."
    
    sudo mkdir -p "\$backup_dir"
    sudo tar -czf "\$backup_dir/\$backup_file" -C /opt/qdrant data
    
    log_info "备份完成: \$backup_dir/\$backup_file"
    log_info "备份大小: \$(du -h \$backup_dir/\$backup_file | cut -f1)"
}

api_test() {
    log_info "执行API测试..."
    
    echo "1. 服务信息:"
    curl -s "http://localhost:\$PORT/" | python3 -m json.tool 2>/dev/null || echo "API请求失败"
    
    echo -e "\n2. 健康检查:"
    curl -s "http://localhost:\$PORT/health" || echo "健康检查失败"
    
    echo -e "\n3. 集合列表:"
    curl -s "http://localhost:\$PORT/collections" | python3 -m json.tool 2>/dev/null || echo "集合API请求失败"
    
    echo -e "\n4. 集群信息:"
    curl -s "http://localhost:\$PORT/cluster" | python3 -m json.tool 2>/dev/null || echo "集群API请求失败"
}

update_image() {
    log_info "更新Qdrant镜像..."
    
    log_warn "这将停止当前服务并更新到最新版本"
    read -p "确认继续？(y/N): " confirm
    
    if [[ "\$confirm" == "y" || "\$confirm" == "Y" ]]; then
        docker stop "\$CONTAINER_NAME"
        docker rm "\$CONTAINER_NAME"
        docker pull "qdrant/qdrant:\$VERSION"
        
        # 重新启动容器（这里需要使用原始启动参数）
        log_info "请手动重新运行部署脚本来启动新版本"
    else
        log_info "取消更新"
    fi
}

main() {
    while true; do
        show_menu
        read -p "请选择操作 (1-10): " choice
        
        case \$choice in
            1) check_status ;;
            2) start_service ;;
            3) stop_service ;;
            4) restart_service ;;
            5) show_logs ;;
            6) show_stats ;;
            7) backup_data ;;
            8) api_test ;;
            9) update_image ;;
            10) 
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

main "\$@"
EOF
    
    chmod +x "./qdrant-manage.sh"
    log_info "管理脚本创建完成: ./qdrant-manage.sh"
}

# 主函数
main() {
    log_title "=== Qdrant 向量数据库部署脚本 ==="
    
    # 检查权限
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行。请使用 sudo 或切换到 root 用户。"
        exit 1
    fi
    
    # 选择版本
    select_version
    
    # 执行部署步骤
    check_docker
    configure_docker_mirrors
    check_ports
    create_directories
    create_config
    create_network
    cleanup_existing
    pull_image
    start_qdrant
    wait_for_service
    verify_installation
    configure_firewall
    create_management_script
    
    # 显示部署信息
    show_deployment_info
    
    log_title "=== 部署完成 ==="
    log_info "Qdrant向量数据库 $QDRANT_VERSION 部署成功！"
    log_info "使用 ./qdrant-manage.sh 来管理服务"
}

# 执行主函数
main "$@"