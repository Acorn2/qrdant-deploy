 #!/bin/bash

# Qdrant Docker Compose 部署脚本
# 适用于腾讯云服务器 OpenCloudOS 系统

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

# 检查Docker和Docker Compose
check_prerequisites() {
    log_info "检查前置条件..."
    
    # 检查Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker未安装！请先运行 ../scripts/install-docker.sh"
        exit 1
    fi
    
    # 检查Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose未安装！请先运行 ../scripts/install-docker-compose.sh"
        exit 1
    fi
    
    # 检查Docker服务状态
    if ! systemctl is-active --quiet docker; then
        log_error "Docker服务未运行！"
        log_info "请运行: sudo systemctl start docker"
        exit 1
    fi
    
    log_info "✓ 前置条件检查通过"
}

# 创建必要目录
create_directories() {
    log_info "创建数据和配置目录..."
    
    sudo mkdir -p /opt/qdrant/data
    sudo mkdir -p /opt/qdrant/config
    sudo mkdir -p /opt/qdrant/snapshots
    
    # 设置权限
    sudo chown -R 1000:1000 /opt/qdrant
    
    log_info "✓ 目录创建完成"
}

# 检查端口占用
check_ports() {
    log_info "检查端口占用..."
    
    if netstat -tulpn | grep -q ":6333 "; then
        log_error "端口 6333 已被占用！"
        netstat -tulpn | grep ":6333 "
        exit 1
    fi
    
    if netstat -tulpn | grep -q ":6334 "; then
        log_error "端口 6334 已被占用！"
        netstat -tulpn | grep ":6334 "
        exit 1
    fi
    
    log_info "✓ 端口检查通过"
}

# 停止现有服务
stop_existing() {
    log_info "停止现有Qdrant服务..."
    
    if docker-compose ps | grep -q qdrant; then
        docker-compose down
        log_info "现有服务已停止"
    fi
}

# 拉取镜像
pull_images() {
    log_info "拉取Qdrant镜像..."
    docker-compose pull
    log_info "✓ 镜像拉取完成"
}

# 启动服务
start_service() {
    log_info "启动Qdrant服务..."
    docker-compose up -d
    log_info "✓ 服务启动完成"
}

# 等待服务就绪
wait_for_service() {
    log_info "等待服务就绪..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s http://localhost:6333/health > /dev/null 2>&1; then
            log_info "✓ 服务就绪！"
            return 0
        fi
        
        log_info "等待中... ($attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done
    
    log_error "服务启动超时！"
    docker-compose logs
    exit 1
}

# 验证部署
verify_deployment() {
    log_info "验证部署..."
    
    # 检查容器状态
    if docker-compose ps | grep -q "Up"; then
        log_info "✓ 容器运行正常"
    else
        log_error "✗ 容器异常"
        docker-compose ps
        exit 1
    fi
    
    # 检查API
    local api_response
    api_response=$(curl -s http://localhost:6333/ 2>/dev/null || echo "error")
    if [[ "$api_response" != "error" ]]; then
        log_info "✓ API服务正常"
    else
        log_error "✗ API服务异常"
        exit 1
    fi
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."
    
    if systemctl is-active --quiet firewalld; then
        sudo firewall-cmd --permanent --add-port=6333/tcp 2>/dev/null || true
        sudo firewall-cmd --permanent --add-port=6334/tcp 2>/dev/null || true
        sudo firewall-cmd --reload 2>/dev/null || true
        log_info "✓ 防火墙配置完成"
    else
        log_warn "防火墙未运行，跳过防火墙配置"
    fi
}

# 显示部署信息
show_info() {
    log_title "=== Qdrant 部署完成 ==="
    
    echo
    log_info "服务访问地址："
    echo "  HTTP API: http://localhost:6333"
    echo "  gRPC API: localhost:6334"
    echo "  管理面板: http://localhost:6333/dashboard"
    
    echo
    log_info "数据目录："
    echo "  数据: /opt/qdrant/data"
    echo "  配置: /opt/qdrant/config"
    echo "  快照: /opt/qdrant/snapshots"
    
    echo
    log_info "管理命令："
    echo "  查看状态: docker-compose ps"
    echo "  查看日志: docker-compose logs -f"
    echo "  停止服务: docker-compose down"
    echo "  重启服务: docker-compose restart"
    
    echo
    log_info "API测试："
    echo "  curl http://localhost:6333/"
    echo "  curl http://localhost:6333/collections"
    echo "  curl http://localhost:6333/health"
}

# 创建管理脚本
create_compose_manager() {
    log_info "创建Compose管理脚本..."
    
    cat > "./manage-compose.sh" << 'EOF'
#!/bin/bash

# Qdrant Docker Compose 管理脚本

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

show_menu() {
    echo "=== Qdrant Compose 管理 ==="
    echo "1. 查看服务状态"
    echo "2. 启动服务"
    echo "3. 停止服务"
    echo "4. 重启服务"
    echo "5. 查看日志"
    echo "6. 更新服务"
    echo "7. 清理数据"
    echo "8. 备份数据"
    echo "9. 退出"
    echo
}

case_handler() {
    case $1 in
        1) docker-compose ps ;;
        2) docker-compose up -d ;;
        3) docker-compose down ;;
        4) docker-compose restart ;;
        5) docker-compose logs -f ;;
        6) docker-compose pull && docker-compose up -d ;;
        7) 
            echo "警告：这将删除所有数据！"
            read -p "确认继续？(输入YES): " confirm
            if [[ "$confirm" == "YES" ]]; then
                docker-compose down -v
                sudo rm -rf /opt/qdrant/data/*
            fi
            ;;
        8)
            timestamp=$(date +%Y%m%d-%H%M%S)
            backup_file="/opt/qdrant/backup-$timestamp.tar.gz"
            sudo tar -czf "$backup_file" -C /opt/qdrant data
            log_info "备份完成: $backup_file"
            ;;
        9) exit 0 ;;
        *) echo "无效选择" ;;
    esac
}

while true; do
    show_menu
    read -p "请选择 (1-9): " choice
    case_handler $choice
    echo
    read -p "按Enter继续..."
    echo
done
EOF
    
    chmod +x "./manage-compose.sh"
    log_info "✓ Compose管理脚本创建完成"
}

# 主函数
main() {
    log_title "=== Qdrant Docker Compose 部署 ==="
    
    # 检查权限
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        exit 1
    fi
    
    # 执行部署
    check_prerequisites
    create_directories
    check_ports
    stop_existing
    pull_images
    start_service
    wait_for_service
    verify_deployment
    configure_firewall
    create_compose_manager
    
    # 显示信息
    show_info
    
    log_title "=== 部署完成 ==="
    log_info "使用 ./manage-compose.sh 管理服务"
}

main "$@"
EOF