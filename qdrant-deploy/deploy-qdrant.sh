#!/bin/bash

# Qdrant 向量数据库部署脚本
# 适用于腾讯云服务器 OpenCloudOS 系统
# 版本: 1.2 - 更新到最新版本并解决网络问题
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

# 默认配置 - 更新到最新版本
QDRANT_VERSION="v1.14.1"  # 最新稳定版本
QDRANT_PORT="6333"
QDRANT_GRPC_PORT="6334"
QDRANT_DATA_DIR="/opt/qdrant/data"
QDRANT_CONFIG_DIR="/opt/qdrant/config"
QDRANT_CONTAINER_NAME="qdrant-server"
QDRANT_NETWORK="qdrant-network"

# 更新的版本列表（包含最新版本）
AVAILABLE_VERSIONS=("v1.14.1" "v1.13.2" "v1.12.4" "v1.11.3" "v1.10.2" "latest")

# 镜像源列表（包含腾讯云和阿里云）
REGISTRY_MIRRORS=(
    "registry-1.docker.io"  # 默认官方源
    "ccr.ccs.tencentyun.com"  # 腾讯云镜像
    "registry.cn-hangzhou.aliyuncs.com"  # 阿里云镜像
    "docker.mirrors.ustc.edu.cn"  # 中科大镜像
    "hub-mirror.c.163.com"  # 网易镜像
)

# 显示版本选择菜单
show_version_menu() {
    log_title "选择 Qdrant 版本"
    echo "可用版本（从新到旧）："
    for i in "${!AVAILABLE_VERSIONS[@]}"; do
        if [[ $i -eq 0 ]]; then
            echo "$((i+1)). ${AVAILABLE_VERSIONS[$i]} (推荐最新版)"
        else
            echo "$((i+1)). ${AVAILABLE_VERSIONS[$i]}"
        fi
    done
    echo "$((${#AVAILABLE_VERSIONS[@]}+1)). 自定义版本"
    echo
}

# 选择版本
select_version() {
    while true; do
        show_version_menu
        read -p "请选择版本 (1-$((${#AVAILABLE_VERSIONS[@]}+1))) [默认: 1]: " choice
        
        # 默认选择第一个版本（最新版本）
        if [[ -z "$choice" ]]; then
            choice=1
        fi
        
        if [[ "$choice" -ge 1 && "$choice" -le ${#AVAILABLE_VERSIONS[@]} ]]; then
            QDRANT_VERSION="${AVAILABLE_VERSIONS[$((choice-1))]}"
            log_info "已选择版本: $QDRANT_VERSION"
            break
        elif [[ "$choice" -eq $((${#AVAILABLE_VERSIONS[@]}+1)) ]]; then
            read -p "请输入自定义版本 (如 v1.14.0): " custom_version
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
    log_info "配置Docker镜像加速源..."
    
    # 备份现有配置
    if [[ -f /etc/docker/daemon.json ]]; then
        cp /etc/docker/daemon.json /etc/docker/daemon.json.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # 创建或更新daemon.json，包含更多镜像源
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
    "registry-mirrors": [
        "https://ccr.ccs.tencentyun.com",
        "https://registry.cn-hangzhou.aliyuncs.com",
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
    "live-restore": true,
    "max-concurrent-downloads": 1,
    "max-concurrent-uploads": 1,
    "max-download-attempts": 5,
    "insecure-registries": []
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
# Qdrant 配置文件 - v1.14.1 兼容
storage:
  # 存储配置
  storage_path: "/qdrant/storage"
  # 启用写入优化
  wal_capacity_mb: 32
  wal_segments_ahead: 0
  
service:
  # 服务配置
  host: "0.0.0.0"
  http_port: 6333
  grpc_port: 6334
  enable_cors: true
  # 最大请求大小 (32MB)
  max_request_size_mb: 32
  # 最大响应时间
  max_timeout_seconds: 30
  
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
  # 最大索引线程数
  max_indexing_threads: 0

# 优化器配置
optimizer_config:
  # 删除向量阈值
  deleted_threshold: 0.2
  # 真空处理阈值
  vacuum_min_vector_number: 1000
  # 默认段数量
  default_segment_number: 0
  # 内存映射阈值
  memmap_threshold: 50000
  # 索引阈值
  indexing_threshold: 20000
  # 刷新间隔（秒）
  flush_interval_sec: 5
  # 最大优化线程数
  max_optimization_threads: 1

# API密钥（可选，启用身份验证）
# api_key: "your-secret-api-key"

# 快照配置
snapshot_config:
  snapshots_path: "/qdrant/snapshots"
  # 快照间隔（小时，0表示禁用自动快照）
  # snapshot_interval_hours: 24

# 性能配置
performance:
  # 最大搜索请求数
  max_search_requests: 100
  # 搜索超时时间（毫秒）
  search_timeout_ms: 30000

# 禁用遥测
telemetry_disabled: true
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

# 尝试从不同镜像源拉取镜像
try_pull_from_mirror() {
    local image_name="$1"
    local mirror="$2"
    local timeout_seconds=300  # 5分钟超时
    
    log_info "尝试从 $mirror 拉取镜像..."
    
    if [[ "$mirror" == "registry-1.docker.io" ]]; then
        # 官方源直接拉取
        if timeout $timeout_seconds docker pull "$image_name"; then
            return 0
        fi
    else
        # 其他镜像源需要重新标记
        local mirror_image="$mirror/qdrant/qdrant:${QDRANT_VERSION#v}"
        
        # 对于某些镜像源，需要使用不同的命名空间
        if [[ "$mirror" == "ccr.ccs.tencentyun.com" ]]; then
            mirror_image="$mirror/library/qdrant:${QDRANT_VERSION#v}"
        elif [[ "$mirror" == "registry.cn-hangzhou.aliyuncs.com" ]]; then
            mirror_image="$mirror/library/qdrant:${QDRANT_VERSION#v}"
        fi
        
        if timeout $timeout_seconds docker pull "$mirror_image"; then
            # 重新标记为原始镜像名
            docker tag "$mirror_image" "$image_name"
            return 0
        fi
    fi
    
    return 1
}

# 增强的镜像拉取功能
pull_image() {
    log_info "开始拉取Qdrant Docker镜像..."
    
    local image_name="qdrant/qdrant:$QDRANT_VERSION"
    local success=false
    
    # 首先检查镜像是否已存在
    if docker images | grep -q "qdrant/qdrant" | grep -q "${QDRANT_VERSION#v}"; then
        log_info "检测到Qdrant镜像已存在，跳过拉取"
        return 0
    fi
    
    log_info "尝试从多个镜像源拉取 $image_name ..."
    
    # 尝试每个镜像源
    for mirror in "${REGISTRY_MIRRORS[@]}"; do
        log_info "正在尝试镜像源: $mirror"
        
        if try_pull_from_mirror "$image_name" "$mirror"; then
            log_info "✓ 从 $mirror 拉取成功！"
            success=true
            break
        else
            log_warn "✗ 从 $mirror 拉取失败，尝试下一个源..."
            sleep 2
        fi
    done
    
    if [[ "$success" == "true" ]]; then
        log_info "镜像拉取完成！"
        docker images | grep qdrant
        return 0
    fi
    
    # 所有镜像源都失败了，提供手动解决方案
    log_error "所有镜像源拉取都失败！"
    echo
    log_warn "可能的解决方案："
    echo "1. 网络连接问题 - 检查服务器网络"
    echo "2. DNS解析问题 - 尝试更换DNS"
    echo "3. 手动拉取其他版本"
    echo "4. 使用离线安装方式"
    echo
    
    # 提供手动拉取选项
    read -p "是否尝试手动拉取？(y/N): " manual_pull
    if [[ "$manual_pull" == "y" || "$manual_pull" == "Y" ]]; then
        echo
        log_info "请尝试以下命令之一："
        echo "# 尝试不同版本"
        for ver in "${AVAILABLE_VERSIONS[@]}"; do
            echo "docker pull qdrant/qdrant:$ver"
        done
        echo
        echo "# 或者使用腾讯云镜像"
        echo "docker pull ccr.ccs.tencentyun.com/library/qdrant:${QDRANT_VERSION#v}"
        echo "docker tag ccr.ccs.tencentyun.com/library/qdrant:${QDRANT_VERSION#v} qdrant/qdrant:$QDRANT_VERSION"
        echo
        echo "# 或者使用阿里云镜像"
        echo "docker pull registry.cn-hangzhou.aliyuncs.com/library/qdrant:${QDRANT_VERSION#v}"
        echo "docker tag registry.cn-hangzhou.aliyuncs.com/library/qdrant:${QDRANT_VERSION#v} qdrant/qdrant:$QDRANT_VERSION"
        echo
        
        read -p "手动拉取完成后按 Enter 继续，或输入 'q' 退出: " continue_choice
        if [[ "$continue_choice" == "q" ]]; then
            exit 1
        fi
        
        # 再次检查镜像
        if docker images | grep -q "qdrant/qdrant"; then
            log_info "检测到Qdrant镜像，继续部署"
            return 0
        else
            log_error "未检测到Qdrant镜像，部署终止"
            exit 1
        fi
    else
        log_error "镜像拉取失败，部署终止"
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
        if curl -s "http://localhost:$QDRANT_PORT/health" > /dev/null 2>&1; then
            log_info "Qdrant服务启动成功！"
            return 0
        fi
        
        log_info "等待中... ($attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done
    
    log_error "Qdrant服务启动超时！"
    log_info "查看容器日志："
    docker logs "$QDRANT_CONTAINER_NAME" --tail 20
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
    version_info=$(curl -s "http://localhost:$QDRANT_PORT/" 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "API响应异常")
    if [[ "$version_info" != "API响应异常" ]]; then
        log_info "✓ API服务正常"
        echo "$version_info"
    else
        log_error "✗ API服务异常"
        exit 1
    fi
    
    # 检查健康状态
    local health_status
    health_status=$(curl -s "http://localhost:$QDRANT_PORT/health" 2>/dev/null || echo "健康检查失败")
    if [[ "$health_status" != "健康检查失败" ]]; then
        log_info "✓ 健康检查通过"
    else
        log_error "✗ 健康检查失败"
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
    echo "  集群信息: curl http://localhost:$QDRANT_PORT/cluster"
    echo "  指标信息: curl http://localhost:$QDRANT_PORT/metrics"
    
    echo
    log_info "性能监控："
    echo "  资源使用: docker stats $QDRANT_CONTAINER_NAME"
    echo "  实时日志: docker logs -f $QDRANT_CONTAINER_NAME"
}

# 创建管理脚本
create_management_script() {
    log_info "创建Qdrant管理脚本..."
    
    cat > "./qdrant-manage.sh" << EOF
#!/bin/bash

# Qdrant 服务管理脚本 - v1.14.1

CONTAINER_NAME="$QDRANT_CONTAINER_NAME"
PORT="$QDRANT_PORT"
VERSION="$QDRANT_VERSION"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

log_title() {
    echo -e "\${BLUE}[标题]\${NC} \$1"
}

show_menu() {
    log_title "Qdrant 服务管理 - \$VERSION"
    echo "1. 查看服务状态"
    echo "2. 启动服务"
    echo "3. 停止服务"
    echo "4. 重启服务"
    echo "5. 查看日志"
    echo "6. 查看资源使用"
    echo "7. 备份数据"
    echo "8. API测试"
    echo "9. 性能测试"
    echo "10. 更新镜像"
    echo "11. 退出"
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
    
    echo -e "\n5. 指标信息:"
    curl -s "http://localhost:\$PORT/metrics" | head -20 || echo "指标获取失败"
}

performance_test() {
    log_info "执行性能测试..."
    
    # 创建测试集合
    curl -X PUT "http://localhost:\$PORT/collections/test" \
        -H "Content-Type: application/json" \
        -d '{
            "vectors": {
                "size": 128,
                "distance": "Cosine"
            }
        }' 2>/dev/null && echo "测试集合创建成功" || echo "测试集合创建失败"
    
    # 插入测试数据
    curl -X PUT "http://localhost:\$PORT/collections/test/points" \
        -H "Content-Type: application/json" \
        -d '{
            "points": [
                {
                    "id": 1,
                    "vector": [0.1, 0.2, 0.3, 0.4],
                    "payload": {"test": "data"}
                }
            ]
        }' 2>/dev/null && echo "测试数据插入成功" || echo "测试数据插入失败"
    
    # 执行搜索测试
    curl -X POST "http://localhost:\$PORT/collections/test/points/search" \
        -H "Content-Type: application/json" \
        -d '{
            "vector": [0.1, 0.2, 0.3, 0.4],
            "limit": 1
        }' 2>/dev/null && echo "搜索测试成功" || echo "搜索测试失败"
    
    # 清理测试数据
    curl -X DELETE "http://localhost:\$PORT/collections/test" 2>/dev/null && echo "测试数据清理完成"
}

update_image() {
    log_info "更新Qdrant镜像..."
    
    log_warn "这将停止当前服务并更新到最新版本"
    read -p "确认继续？(y/N): " confirm
    
    if [[ "\$confirm" == "y" || "\$confirm" == "Y" ]]; then
        docker stop "\$CONTAINER_NAME"
        docker rm "\$CONTAINER_NAME"
        docker pull "qdrant/qdrant:\$VERSION"
        
        log_info "请手动重新运行部署脚本来启动新版本"
    else
        log_info "取消更新"
    fi
}

main() {
    while true; do
        show_menu
        read -p "请选择操作 (1-11): " choice
        
        case \$choice in
            1) check_status ;;
            2) start_service ;;
            3) stop_service ;;
            4) restart_service ;;
            5) show_logs ;;
            6) show_stats ;;
            7) backup_data ;;
            8) api_test ;;
            9) performance_test ;;
            10) update_image ;;
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

main "\$@"
EOF
    
    chmod +x "./qdrant-manage.sh"
    log_info "管理脚本创建完成: ./qdrant-manage.sh"
}

# 主函数
main() {
    log_title "=== Qdrant 向量数据库部署脚本 v1.2 ==="
    
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