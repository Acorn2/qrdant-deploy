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

# 在脚本开头添加tar文件路径变量
QDRANT_TAR_FILE=""

# 在select_version函数之后添加新的函数
# 选择镜像获取方式
select_image_source() {
    log_title "选择镜像获取方式"
    echo "1. 在线拉取镜像（默认）"
    echo "2. 从tar文件导入镜像"
    echo
    
    while true; do
        read -p "请选择镜像获取方式 (1-2) [默认: 1]: " source_choice
        
        # 默认选择在线拉取
        if [[ -z "$source_choice" ]]; then
            source_choice=1
        fi
        
        case $source_choice in
            1)
                log_info "已选择在线拉取镜像"
                QDRANT_TAR_FILE=""
                break
                ;;
            2)
                log_info "已选择从tar文件导入镜像"
                select_tar_file
                break
                ;;
            *)
                log_error "无效的选择，请重新输入"
                ;;
        esac
    done
}

# 选择tar文件
select_tar_file() {
    while true; do
        read -p "请输入Qdrant镜像tar文件的完整路径: " tar_path
        
        if [[ -z "$tar_path" ]]; then
            log_error "文件路径不能为空"
            continue
        fi
        
        # 检查文件是否存在
        if [[ ! -f "$tar_path" ]]; then
            log_error "文件不存在: $tar_path"
            continue
        fi
        
        # 检查文件扩展名
        if [[ ! "$tar_path" =~ \.(tar|tar\.gz|tgz)$ ]]; then
            log_warn "文件扩展名不是标准的tar格式，但将尝试导入"
        fi
        
        QDRANT_TAR_FILE="$tar_path"
        log_info "已选择tar文件: $QDRANT_TAR_FILE"
        break
    done
}

# 从tar文件导入镜像
import_image_from_tar() {
    log_info "从tar文件导入Qdrant镜像..."
    
    if [[ -z "$QDRANT_TAR_FILE" ]]; then
        log_error "未指定tar文件路径"
        return 1
    fi
    
    if [[ ! -f "$QDRANT_TAR_FILE" ]]; then
        log_error "tar文件不存在: $QDRANT_TAR_FILE"
        return 1
    fi
    
    log_info "正在导入镜像文件: $QDRANT_TAR_FILE"
    log_info "文件大小: $(du -h "$QDRANT_TAR_FILE" | cut -f1)"
    
    # 导入镜像
    if docker load -i "$QDRANT_TAR_FILE"; then
        log_info "✓ 镜像导入成功！"
        
        # 显示导入的镜像
        log_info "已导入的镜像："
        docker images | grep qdrant | head -5
        
        # 检查是否需要重新标记镜像
        check_and_retag_image
        
        return 0
    else
        log_error "✗ 镜像导入失败！"
        return 1
    fi
}

# 检查并重新标记镜像
check_and_retag_image() {
    log_info "检查镜像标签..."
    
    local target_image="qdrant/qdrant:$QDRANT_VERSION"
    
    # 检查目标镜像是否存在
    if docker images | grep -q "qdrant/qdrant" | grep -q "${QDRANT_VERSION#v}"; then
        log_info "✓ 找到目标镜像: $target_image"
        return 0
    fi
    
    # 查找可用的qdrant镜像
    local available_images
    available_images=$(docker images | grep qdrant | awk '{print $1":"$2}')
    
    if [[ -z "$available_images" ]]; then
        log_error "未找到任何qdrant镜像"
        return 1
    fi
    
    log_info "找到以下qdrant镜像："
    echo "$available_images"
    echo
    
    # 如果只有一个镜像，询问是否重新标记
    local image_count
    image_count=$(echo "$available_images" | wc -l)
    
    if [[ $image_count -eq 1 ]]; then
        local source_image="$available_images"
        log_warn "当前镜像标签为: $source_image"
        log_warn "期望的镜像标签为: $target_image"
        
        read -p "是否将镜像重新标记为期望的版本？(Y/n): " retag_choice
        if [[ "$retag_choice" != "n" && "$retag_choice" != "N" ]]; then
            if docker tag "$source_image" "$target_image"; then
                log_info "✓ 镜像重新标记成功: $source_image -> $target_image"
                return 0
            else
                log_error "✗ 镜像重新标记失败"
                return 1
            fi
        fi
    else
        # 多个镜像，让用户选择
        log_info "发现多个镜像，请选择要使用的镜像："
        local i=1
        while IFS= read -r image; do
            echo "$i. $image"
            ((i++))
        done <<< "$available_images"
        
        read -p "请选择镜像编号 (1-$((i-1))): " image_choice
        
        if [[ "$image_choice" -ge 1 && "$image_choice" -le $((i-1)) ]]; then
            local selected_image
            selected_image=$(echo "$available_images" | sed -n "${image_choice}p")
            
            if docker tag "$selected_image" "$target_image"; then
                log_info "✓ 镜像重新标记成功: $selected_image -> $target_image"
                return 0
            else
                log_error "✗ 镜像重新标记失败"
                return 1
            fi
        else
            log_error "无效的选择"
            return 1
        fi
    fi
    
    # 如果用户选择不重新标记，询问是否直接使用现有镜像
    read -p "是否直接使用现有镜像？(y/N): " use_existing
    if [[ "$use_existing" == "y" || "$use_existing" == "Y" ]]; then
        # 更新QDRANT_VERSION变量为实际的镜像版本
        local actual_version
        actual_version=$(echo "$available_images" | head -1 | cut -d':' -f2)
        QDRANT_VERSION="$actual_version"
        log_info "已更新版本为: $QDRANT_VERSION"
        return 0
    fi
    
    return 1
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
    # 如果指定了tar文件，使用tar文件导入
    if [[ -n "$QDRANT_TAR_FILE" ]]; then
        import_image_from_tar
        return $?
    fi
    
    # 原有的在线拉取逻辑
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
    echo "4. 使用离线安装方式（tar文件）"
    echo
    
    # 提供使用tar文件的选项
    read -p "是否使用tar文件导入镜像？(y/N): " use_tar
    if [[ "$use_tar" == "y" || "$use_tar" == "Y" ]]; then
        select_tar_file
        import_image_from_tar
        return $?
    fi
    
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
        echo "# 或者使用tar文件导入"
        echo "docker load -i /path/to/qdrant-image.tar"
        echo
        
        read -p "手动操作完成后按 Enter 继续，或输入 'q' 退出: " continue_choice
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
        log_error "镜像获取失败，部署终止"
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
    
    # 选择镜像获取方式
    select_image_source
    
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