#!/bin/bash

# Qdrant 向量数据库增强部署脚本
# 适用于网络受限环境的多种部署方案
# 版本: 2.2 - 修复tar文件识别和部署问题

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

# 增强：验证Docker镜像tar文件
validate_docker_tar() {
    local tar_path="$1"
    
    log_info "验证tar文件格式..."
    
    # 检查文件是否为tar格式
    if ! file "$tar_path" | grep -q "tar archive"; then
        log_error "文件不是有效的tar格式"
        return 1
    fi
    
    # 检查是否为Docker镜像文件（更严格的检查）
    log_info "检查Docker镜像格式特征..."
    if tar -tf "$tar_path" 2>/dev/null | grep -q "^manifest\.json$"; then
        log_info "✓ 检测到Docker镜像文件（包含manifest.json）"
        return 0
    elif tar -tf "$tar_path" 2>/dev/null | grep -q "\.json$" | head -1 | grep -q "/"; then
        log_info "✓ 检测到可能的Docker镜像文件（包含层文件）"
        return 0
    else
        log_warn "✗ 不是Docker镜像文件格式"
        return 1
    fi
}

# 增强：诊断tar文件类型
diagnose_tar_file() {
    local tar_path="$1"
    
    log_info "=== 诊断tar文件 ==="
    
    echo "文件信息："
    echo "  路径: $tar_path"
    echo "  大小: $(du -h "$tar_path" | cut -f1)"
    echo "  类型: $(file "$tar_path")"
    echo
    
    log_info "文件内容结构（前20行）："
    local file_list
    file_list=$(tar -tf "$tar_path" 2>/dev/null | head -20)
    echo "$file_list"
    echo
    
    # 更精确的文件类型判断
    if echo "$file_list" | grep -q "^manifest\.json$"; then
        log_info "✓ Docker镜像格式（包含manifest.json）"
        return 0
    elif echo "$file_list" | grep -q "^[a-f0-9]\{64\}/"; then
        log_info "✓ Docker镜像格式（包含层目录）"
        return 0
    elif echo "$file_list" | grep -q "^qdrant$" || echo "$file_list" | grep -q "^qdrant/"; then
        log_info "✓ 检测到Qdrant二进制程序包"
        echo "这是一个包含Qdrant可执行文件的tar包"
        return 2  # 返回2表示是二进制包
    else
        log_warn "? 未识别的tar文件格式"
        echo "文件内容不符合Docker镜像或Qdrant二进制包的特征"
        return 1
    fi
}

# 新增：从二进制tar包部署
deploy_from_binary_tar() {
    local tar_path="$1"
    
    log_info "=== 开始二进制tar包部署 ==="
    
    # 创建临时目录
    local temp_dir="/tmp/qdrant-binary-$(date +%s)"
    mkdir -p "$temp_dir"
    
    # 解压文件
    log_info "解压二进制文件到: $temp_dir"
    if tar -xf "$tar_path" -C "$temp_dir"; then
        log_info "✓ 解压完成"
    else
        log_error "✗ 解压失败"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # 显示解压后的结构
    log_info "解压后的文件结构："
    find "$temp_dir" -type f | head -10
    echo
    
    # 查找qdrant可执行文件
    local qdrant_binary=""
    local search_paths=(
        "$temp_dir/qdrant"
        "$temp_dir/qdrant/qdrant"
        "$temp_dir/bin/qdrant"
        "$(find "$temp_dir" -name "qdrant" -type f -executable 2>/dev/null | head -1)"
    )
    
    for possible_path in "${search_paths[@]}"; do
        if [[ -f "$possible_path" ]]; then
            # 检查是否为可执行文件
            if file "$possible_path" | grep -q "executable"; then
                qdrant_binary="$possible_path"
                break
            fi
        fi
    done
    
    if [[ -z "$qdrant_binary" ]]; then
        log_error "未找到qdrant可执行文件"
        log_info "搜索路径中的文件："
        find "$temp_dir" -type f -name "*qdrant*" 2>/dev/null || echo "未找到包含qdrant的文件"
        log_info "所有可执行文件："
        find "$temp_dir" -type f -executable 2>/dev/null || echo "未找到可执行文件"
        rm -rf "$temp_dir"
        return 1
    fi
    
    log_info "✓ 找到Qdrant二进制文件: $qdrant_binary"
    
    # 验证二进制文件
    log_info "验证二进制文件..."
    if "$qdrant_binary" --help >/dev/null 2>&1; then
        log_info "✓ 二进制文件可以正常执行"
    else
        log_warn "⚠ 二进制文件验证失败，但继续安装"
    fi
    
    # 安装二进制文件
    log_info "安装Qdrant二进制文件到 /usr/local/bin/qdrant"
    sudo mkdir -p /usr/local/bin
    sudo cp "$qdrant_binary" /usr/local/bin/qdrant
    sudo chmod +x /usr/local/bin/qdrant
    
    # 复制静态资源（如果存在）
    local static_dir=""
    for static_path in "$temp_dir/qdrant/static" "$temp_dir/static"; do
        if [[ -d "$static_path" ]]; then
            static_dir="$static_path"
            break
        fi
    done
    
    if [[ -n "$static_dir" ]]; then
        log_info "复制静态资源文件..."
        sudo mkdir -p /opt/qdrant/static
        sudo cp -r "$static_dir"/* /opt/qdrant/static/ 2>/dev/null || true
        log_info "✓ 静态资源复制完成"
    else
        log_info "未找到静态资源目录，跳过"
    fi
    
    # 清理临时目录
    rm -rf "$temp_dir"
    
    # 最终验证安装
    if /usr/local/bin/qdrant --help >/dev/null 2>&1; then
        log_info "✓ Qdrant二进制文件安装成功"
        
        # 显示版本信息
        log_info "Qdrant版本信息："
        /usr/local/bin/qdrant --version 2>/dev/null || echo "版本信息获取失败"
        
        return 0
    else
        log_error "✗ Qdrant二进制文件安装失败"
        return 1
    fi
}

# 修复：从tar包部署（增强的镜像检测逻辑）
deploy_from_tar() {
    log_info "=== 从tar包部署Qdrant ==="
    
    echo "支持的tar包类型："
    echo "1. Docker镜像tar包 - 由'docker save'命令生成"
    echo "2. Qdrant二进制程序tar包 - 包含可执行文件"
    echo
    
    local tar_path=""
    while true; do
        read -p "请输入tar文件完整路径: " tar_path
        
        if [[ ! -f "$tar_path" ]]; then
            log_error "文件不存在: $tar_path"
            read -p "重新输入？(y/n): " retry
            [[ "$retry" != "y" ]] && return 1
            continue
        fi
        
        break
    done
    
    # 强制诊断文件类型
    log_info "正在分析文件类型..."
    local diagnosis_result
    diagnose_tar_file "$tar_path"
    diagnosis_result=$?
    
    case $diagnosis_result in
        0)
            # Docker镜像文件
            log_info "=== 使用Docker镜像部署方式 ==="
            
            # 获取加载前的镜像列表
            local images_before=$(docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" 2>/dev/null || echo "")
            
            log_info "加载Docker镜像..."
            local load_output
            if load_output=$(docker load < "$tar_path" 2>&1); then
                log_info "✓ 镜像加载完成"
                echo "$load_output"
                
                # 获取加载后的镜像列表
                local images_after=$(docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" 2>/dev/null || echo "")
                
                # 检查是否有带qdrant标签的镜像
                if docker images | grep -q "qdrant"; then
                    log_info "✓ 检测到已加载的Qdrant镜像："
                    docker images | grep qdrant
                    return 0
                else
                    # 尝试找到新加载的镜像
                    log_info "未找到qdrant标签的镜像，检查新加载的镜像..."
                    
                    # 显示所有镜像，让用户识别
                    log_info "当前所有Docker镜像："
                    docker images
                    
                    # 从加载输出中提取镜像ID
                    local loaded_image_id=""
                    if echo "$load_output" | grep -q "Loaded image ID:"; then
                        loaded_image_id=$(echo "$load_output" | grep "Loaded image ID:" | sed 's/.*sha256://')
                        log_info "检测到加载的镜像ID: $loaded_image_id"
                        
                        # 为镜像添加标签
                        log_info "为镜像添加qdrant标签..."
                        if docker tag "$loaded_image_id" "qdrant/qdrant:latest"; then
                            log_info "✓ 成功添加标签 qdrant/qdrant:latest"
                            log_info "验证镜像："
                            docker images | grep qdrant
                            return 0
                        else
                            log_error "✗ 添加标签失败"
                        fi
                    elif echo "$load_output" | grep -q "Loaded image:"; then
                        # 镜像已有标签
                        loaded_image_id=$(echo "$load_output" | grep "Loaded image:" | awk '{print $3}')
                        log_info "检测到已标记的镜像: $loaded_image_id"
                        
                        # 如果不是qdrant标签，添加一个
                        if ! echo "$loaded_image_id" | grep -q "qdrant"; then
                            log_info "为镜像添加qdrant标签..."
                            if docker tag "$loaded_image_id" "qdrant/qdrant:latest"; then
                                log_info "✓ 成功添加标签 qdrant/qdrant:latest"
                                return 0
                            fi
                        else
                            log_info "✓ 镜像已具有qdrant标签"
                            return 0
                        fi
                    fi
                    
                    # 如果以上都失败，让用户手动选择
                    log_warn "自动识别失败，需要手动指定镜像"
                    echo "请从上面的镜像列表中找到Qdrant镜像"
                    read -p "请输入镜像ID或名称（如果看到可疑的镜像）: " user_image
                    
                    if [[ -n "$user_image" ]]; then
                        log_info "尝试为镜像 $user_image 添加qdrant标签..."
                        if docker tag "$user_image" "qdrant/qdrant:latest"; then
                            log_info "✓ 成功添加标签"
                            return 0
                        else
                            log_error "✗ 添加标签失败"
                        fi
                    fi
                    
                    log_error "✗ 镜像加载后未能正确设置qdrant标签"
                    return 1
                fi
            else
                log_error "✗ Docker镜像加载失败"
                echo "$load_output"
                return 1
            fi
            ;;
        2)
            # 二进制文件包
            log_info "=== 使用二进制部署方式 ==="
            read -p "检测到二进制文件包，是否继续使用二进制部署方式？(y/n): " use_binary
            if [[ "$use_binary" == "y" || "$use_binary" == "Y" ]]; then
                if deploy_from_binary_tar "$tar_path"; then
                    log_info "✓ 二进制部署完成"
                    return 0
                else
                    log_error "✗ 二进制部署失败"
                    return 1
                fi
            else
                log_error "用户取消二进制部署"
                return 1
            fi
            ;;
        *)
            # 未识别的格式
            log_error "无法识别的tar文件格式"
            echo
            echo "请确保您的文件是以下格式之一："
            echo "1. Docker镜像文件 - 由以下命令生成："
            echo "   docker pull qdrant/qdrant:$QDRANT_VERSION"
            echo "   docker save qdrant/qdrant:$QDRANT_VERSION > qdrant-docker.tar"
            echo
            echo "2. Qdrant二进制程序包 - 包含qdrant可执行文件"
            echo
            
            read -p "重新输入文件路径？(y/n): " retry
            if [[ "$retry" == "y" || "$retry" == "Y" ]]; then
                return 1  # 返回1会触发重新输入
            else
                return 1
            fi
            ;;
    esac
}

# 新增：设置和启动容器的函数
setup_and_start_container() {
    log_info "=== 设置和启动Qdrant容器 ==="
    
    # 停止并删除已存在的容器
    if docker ps -a | grep -q "$QDRANT_CONTAINER_NAME"; then
        log_info "停止并删除已存在的容器..."
        docker stop "$QDRANT_CONTAINER_NAME" 2>/dev/null || true
        docker rm "$QDRANT_CONTAINER_NAME" 2>/dev/null || true
    fi
    
    # 创建网络（如果不存在）
    if ! docker network ls | grep -q "$QDRANT_NETWORK"; then
        log_info "创建Docker网络: $QDRANT_NETWORK"
        docker network create "$QDRANT_NETWORK" 2>/dev/null || true
    fi
    
    # 创建数据目录
    log_info "创建数据目录..."
    mkdir -p "$QDRANT_DATA_DIR"
    
    # 启动容器
    log_info "启动Qdrant容器..."
    
    local qdrant_image="qdrant/qdrant:latest"
    
    # 检查镜像是否存在
    if ! docker images | grep -q "qdrant"; then
        log_error "未找到qdrant镜像"
        return 1
    fi
    
    # 使用找到的第一个qdrant镜像
    qdrant_image=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep qdrant | head -1)
    log_info "使用镜像: $qdrant_image"
    
    if docker run -d \
        --name "$QDRANT_CONTAINER_NAME" \
        --network "$QDRANT_NETWORK" \
        -p "$QDRANT_PORT:6333" \
        -p "$QDRANT_GRPC_PORT:6334" \
        -v "$QDRANT_DATA_DIR:/qdrant/storage" \
        --restart unless-stopped \
        "$qdrant_image"; then
        
        log_info "✓ 容器启动成功"
        
        # 等待服务启动
        log_info "等待服务启动..."
        sleep 10
        
        # 验证服务
        if docker ps | grep -q "$QDRANT_CONTAINER_NAME"; then
            log_info "✓ Qdrant容器运行正常"
            return 0
        else
            log_error "✗ 容器启动失败"
            docker logs "$QDRANT_CONTAINER_NAME"
            return 1
        fi
    else
        log_error "✗ 容器启动失败"
        return 1
    fi
}

# 新增：部署后设置函数
post_deployment_setup() {
    log_info "=== 部署后设置 ==="
    
    # 检查服务状态
    log_info "检查Qdrant服务状态..."
    
    # 等待一段时间让服务完全启动
    sleep 5
    
    # 测试HTTP API
    log_info "测试Qdrant HTTP API..."
    if curl -s "http://localhost:$QDRANT_PORT/health" | grep -q "ok"; then
        log_info "✓ HTTP API响应正常"
    else
        log_warn "⚠ HTTP API测试失败，服务可能还在启动中"
    fi
    
    # 显示访问信息
    log_info "=== 部署完成 ==="
    echo "Qdrant服务信息："
    echo "  HTTP API: http://localhost:$QDRANT_PORT"
    echo "  gRPC API: http://localhost:$QDRANT_GRPC_PORT"
    echo "  管理界面: http://localhost:$QDRANT_PORT/dashboard"
    echo "  数据目录: $QDRANT_DATA_DIR"
    echo
    echo "常用命令："
    if docker ps 2>/dev/null | grep -q "$QDRANT_CONTAINER_NAME"; then
        echo "  查看容器状态: docker ps | grep qdrant"
        echo "  查看日志: docker logs $QDRANT_CONTAINER_NAME"
        echo "  停止服务: docker stop $QDRANT_CONTAINER_NAME"
        echo "  重启服务: docker restart $QDRANT_CONTAINER_NAME"
    elif systemctl is-active --quiet qdrant 2>/dev/null; then
        echo "  查看服务状态: systemctl status qdrant"
        echo "  查看日志: journalctl -u qdrant -f"
        echo "  停止服务: systemctl stop qdrant"
        echo "  重启服务: systemctl restart qdrant"
    fi
    echo
    
    log_info "部署完成！"
}

# 创建systemd服务
create_systemd_service() {
    log_info "创建systemd服务..."
    
    # 创建qdrant用户
    if ! id qdrant &>/dev/null; then
        sudo useradd -r -s /bin/false qdrant 2>/dev/null || true
        log_info "✓ 创建qdrant用户"
    fi
    
    # 创建目录并设置权限
    sudo mkdir -p "$QDRANT_DATA_DIR" "$QDRANT_CONFIG_DIR"
    sudo chown -R qdrant:qdrant "$QDRANT_DATA_DIR" "$QDRANT_CONFIG_DIR"
    
    # 创建配置文件
    sudo tee "$QDRANT_CONFIG_DIR/config.yaml" > /dev/null << 'EOF'
# Qdrant 配置文件 - v1.14.1 兼容
storage:
  storage_path: "/opt/qdrant/data"
  
service:
  host: "0.0.0.0"
  http_port: 6333
  grpc_port: 6334
  enable_cors: true
  
log_level: "INFO"
telemetry_disabled: true
EOF
    
    # 创建systemd服务文件
    sudo tee /etc/systemd/system/qdrant.service > /dev/null << EOF
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
    
    # 重新加载systemd并启用服务
    sudo systemctl daemon-reload
    sudo systemctl enable qdrant
    
    log_info "✓ systemd服务创建完成"
}

# 修改离线部署函数
offline_deploy() {
    log_step "执行离线部署..."
    
    log_info "离线部署选项："
    echo "1. 使用tar包（自动识别类型）"
    echo "2. 从其他服务器传输Docker镜像"
    echo "3. 使用镜像文件"
    
    read -p "请选择离线部署方式 (1-3): " offline_choice
    
    case $offline_choice in
        1) 
            # 使用tar包部署
            while true; do
                if deploy_from_tar; then
                    # 检查部署结果
                    if docker images 2>/dev/null | grep -q "qdrant"; then
                        log_info "检测到Docker镜像，设置容器..."
                        setup_and_start_container
                        break
                    elif [[ -f "/usr/local/bin/qdrant" ]]; then
                        log_info "检测到二进制安装，启动系统服务..."
                        create_systemd_service
                        sudo systemctl start qdrant
                        
                        # 等待服务启动
                        log_info "等待服务启动..."
                        sleep 10
                        
                        # 验证服务
                        if systemctl is-active --quiet qdrant; then
                            log_info "✓ Qdrant服务启动成功"
                        else
                            log_error "✗ Qdrant服务启动失败"
                            sudo systemctl status qdrant --no-pager
                            return 1
                        fi
                        break
                    else
                        log_error "部署未成功，未检测到有效的安装"
                        return 1
                    fi
                else
                    log_error "tar包部署失败"
                    read -p "是否重试？(y/n): " retry
                    [[ "$retry" != "y" ]] && return 1
                fi
            done
            ;;
        2) 
            deploy_from_transfer && setup_and_start_container 
            ;;
        3) 
            deploy_from_image_file && setup_and_start_container 
            ;;
        *) 
            log_error "无效选择" 
            return 1 
            ;;
    esac
}

# 这里需要包含其他原有的函数...
# （为了节省空间，我只展示了主要修改的部分）

# 主菜单循环
main() {
    log_title "=== Qdrant 增强部署脚本 v2.2 ==="
    
    # 检查权限
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
    
    while true; do
        show_deployment_options
        read -p "请选择部署方案 (1-7): " choice
        
        case $choice in
            2)
                if offline_deploy; then
                    post_deployment_setup
                else
                    log_error "离线部署失败"
                fi
                break
                ;;
            7)
                log_info "退出部署脚本"
                exit 0
                ;;
            *)
                log_error "当前只演示离线部署选项，请选择2或7"
                ;;
        esac
        
        echo
        read -p "按Enter继续..." 
        echo
    done
}

# 执行主函数
main "$@" 