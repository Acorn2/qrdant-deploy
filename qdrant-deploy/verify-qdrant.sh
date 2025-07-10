#!/bin/bash

# Qdrant 安装验证脚本
# 全面检查 Qdrant 服务状态

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

# 配置变量
QDRANT_PORT="6333"
QDRANT_GRPC_PORT="6334"
QDRANT_CONTAINER_NAME="qdrant-server"
QDRANT_DATA_DIR="/opt/qdrant/data"
QDRANT_CONFIG_DIR="/opt/qdrant/config"

# 1. 检查Docker容器状态
check_docker_container() {
    log_step "1. 检查Docker容器状态"
    
    if command -v docker &> /dev/null; then
        if docker ps | grep -q "$QDRANT_CONTAINER_NAME"; then
            log_info "✓ Docker容器正在运行"
            echo "容器详情："
            docker ps | grep "$QDRANT_CONTAINER_NAME" | awk '{print "  容器ID: "$1"\n  镜像: "$2"\n  状态: "$3" "$4"\n  端口: "$5}'
            
            # 检查容器健康状态
            local container_id=$(docker ps -q --filter name="$QDRANT_CONTAINER_NAME")
            local container_status=$(docker inspect --format '{{.State.Status}}' "$container_id" 2>/dev/null || echo "unknown")
            log_info "容器状态: $container_status"
            
            return 0
        elif docker ps -a | grep -q "$QDRANT_CONTAINER_NAME"; then
            log_warn "⚠ Docker容器存在但未运行"
            echo "容器状态："
            docker ps -a | grep "$QDRANT_CONTAINER_NAME"
            
            # 尝试启动容器
            read -p "是否尝试启动容器？(y/N): " start_container
            if [[ "$start_container" == "y" || "$start_container" == "Y" ]]; then
                docker start "$QDRANT_CONTAINER_NAME"
                sleep 5
                log_info "已尝试启动容器"
            fi
            return 1
        else
            log_error "✗ 未找到Docker容器"
            return 1
        fi
    else
        log_warn "Docker未安装，跳过容器检查"
        return 1
    fi
}

# 2. 检查进程状态
check_process_status() {
    log_step "2. 检查进程状态"
    
    # 检查qdrant进程
    if pgrep -f "qdrant" > /dev/null; then
        log_info "✓ 找到Qdrant进程"
        echo "进程信息："
        ps aux | grep qdrant | grep -v grep | while read line; do
            echo "  $line"
        done
        return 0
    else
        log_warn "⚠ 未找到Qdrant进程"
        return 1
    fi
}

# 3. 检查端口占用
check_port_status() {
    log_step "3. 检查端口占用"
    
    local http_port_check=false
    local grpc_port_check=false
    
    # 检查HTTP端口
    if netstat -tulpn 2>/dev/null | grep -q ":$QDRANT_PORT "; then
        log_info "✓ HTTP端口 $QDRANT_PORT 已被占用"
        netstat -tulpn | grep ":$QDRANT_PORT " | while read line; do
            echo "  $line"
        done
        http_port_check=true
    else
        log_error "✗ HTTP端口 $QDRANT_PORT 未被占用"
    fi
    
    # 检查gRPC端口
    if netstat -tulpn 2>/dev/null | grep -q ":$QDRANT_GRPC_PORT "; then
        log_info "✓ gRPC端口 $QDRANT_GRPC_PORT 已被占用"
        netstat -tulpn | grep ":$QDRANT_GRPC_PORT " | while read line; do
            echo "  $line"
        done
        grpc_port_check=true
    else
        log_error "✗ gRPC端口 $QDRANT_GRPC_PORT 未被占用"
    fi
    
    if [[ "$http_port_check" == true && "$grpc_port_check" == true ]]; then
        return 0
    else
        return 1
    fi
}

# 4. 检查API响应
check_api_response() {
    log_step "4. 检查API响应"
    
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "尝试连接API... ($attempt/$max_attempts)"
        
        # 检查健康状态
        if curl -s --connect-timeout 5 "http://localhost:$QDRANT_PORT/health" >/dev/null 2>&1; then
            log_info "✓ 健康检查端点响应正常"
            
            # 获取详细信息
            local health_response=$(curl -s "http://localhost:$QDRANT_PORT/health" 2>/dev/null)
            echo "健康状态: $health_response"
            
            # 检查根端点
            if curl -s --connect-timeout 5 "http://localhost:$QDRANT_PORT/" >/dev/null 2>&1; then
                log_info "✓ 根API端点响应正常"
                
                # 获取版本信息
                local version_info=$(curl -s "http://localhost:$QDRANT_PORT/" 2>/dev/null)
                echo "版本信息:"
                echo "$version_info" | python3 -m json.tool 2>/dev/null || echo "$version_info"
                
                return 0
            else
                log_warn "⚠ 根API端点无响应"
            fi
            
            return 0
        else
            log_warn "⚠ API暂无响应，等待中..."
            sleep 3
            ((attempt++))
        fi
    done
    
    log_error "✗ API连接失败"
    return 1
}

# 5. 检查配置文件
check_configuration() {
    log_step "5. 检查配置文件"
    
    # 检查配置目录
    if [[ -d "$QDRANT_CONFIG_DIR" ]]; then
        log_info "✓ 配置目录存在: $QDRANT_CONFIG_DIR"
        
        # 检查配置文件
        if [[ -f "$QDRANT_CONFIG_DIR/config.yaml" ]]; then
            log_info "✓ 配置文件存在"
            echo "配置文件内容："
            head -20 "$QDRANT_CONFIG_DIR/config.yaml" | sed 's/^/  /'
        else
            log_warn "⚠ 配置文件不存在"
        fi
    else
        log_warn "⚠ 配置目录不存在: $QDRANT_CONFIG_DIR"
    fi
    
    # 检查数据目录
    if [[ -d "$QDRANT_DATA_DIR" ]]; then
        log_info "✓ 数据目录存在: $QDRANT_DATA_DIR"
        
        # 显示数据目录大小
        local data_size=$(du -sh "$QDRANT_DATA_DIR" 2>/dev/null | cut -f1 || echo "未知")
        echo "数据目录大小: $data_size"
        
        # 显示目录权限
        ls -la "$QDRANT_DATA_DIR" | head -5 | sed 's/^/  /'
    else
        log_warn "⚠ 数据目录不存在: $QDRANT_DATA_DIR"
    fi
}

# 6. 检查系统服务状态
check_systemd_service() {
    log_step "6. 检查系统服务状态"
    
    if systemctl list-unit-files | grep -q "qdrant.service"; then
        log_info "✓ 找到systemd服务"
        
        local service_status=$(systemctl is-active qdrant 2>/dev/null || echo "inactive")
        local service_enabled=$(systemctl is-enabled qdrant 2>/dev/null || echo "disabled")
        
        echo "服务状态: $service_status"
        echo "开机启动: $service_enabled"
        
        if [[ "$service_status" == "active" ]]; then
            log_info "✓ 系统服务运行正常"
            return 0
        else
            log_warn "⚠ 系统服务未运行"
            
            # 尝试启动服务
            read -p "是否尝试启动系统服务？(y/N): " start_service
            if [[ "$start_service" == "y" || "$start_service" == "Y" ]]; then
                systemctl start qdrant
                sleep 5
                log_info "已尝试启动系统服务"
            fi
            return 1
        fi
    else
        log_warn "⚠ 未找到systemd服务"
        return 1
    fi
}

# 7. 执行功能测试
perform_functional_test() {
    log_step "7. 执行功能测试"
    
    # 检查集合列表
    if curl -s "http://localhost:$QDRANT_PORT/collections" >/dev/null 2>&1; then
        log_info "✓ 集合API响应正常"
        
        local collections=$(curl -s "http://localhost:$QDRANT_PORT/collections" 2>/dev/null)
        echo "当前集合:"
        echo "$collections" | python3 -m json.tool 2>/dev/null || echo "$collections"
    else
        log_error "✗ 集合API无响应"
        return 1
    fi
    
    # 检查集群信息
    if curl -s "http://localhost:$QDRANT_PORT/cluster" >/dev/null 2>&1; then
        log_info "✓ 集群API响应正常"
        
        local cluster_info=$(curl -s "http://localhost:$QDRANT_PORT/cluster" 2>/dev/null)
        echo "集群信息:"
        echo "$cluster_info" | python3 -m json.tool 2>/dev/null || echo "$cluster_info"
    else
        log_warn "⚠ 集群API无响应"
    fi
    
    return 0
}

# 8. 检查日志
check_logs() {
    log_step "8. 检查日志"
    
    # Docker容器日志
    if command -v docker &> /dev/null && docker ps | grep -q "$QDRANT_CONTAINER_NAME"; then
        log_info "Docker容器日志（最后20行）："
        docker logs "$QDRANT_CONTAINER_NAME" --tail 20 | sed 's/^/  /'
    fi
    
    # 系统服务日志
    if systemctl list-unit-files | grep -q "qdrant.service"; then
        log_info "系统服务日志（最后10行）："
        journalctl -u qdrant --no-pager -n 10 | sed 's/^/  /'
    fi
}

# 生成诊断报告
generate_diagnosis() {
    log_title "=== 诊断报告 ==="
    
    local issues=()
    local suggestions=()
    
    # 检查各项测试结果
    if ! check_docker_container >/dev/null 2>&1 && ! check_systemd_service >/dev/null 2>&1; then
        issues+=("Qdrant服务未运行")
        suggestions+=("尝试启动Docker容器或系统服务")
    fi
    
    if ! check_port_status >/dev/null 2>&1; then
        issues+=("端口未被正确占用")
        suggestions+=("检查服务配置和防火墙设置")
    fi
    
    if ! check_api_response >/dev/null 2>&1; then
        issues+=("API无响应")
        suggestions+=("检查服务启动状态和网络连接")
    fi
    
    # 输出问题和建议
    if [[ ${#issues[@]} -eq 0 ]]; then
        log_info "🎉 Qdrant安装验证成功！所有检查都通过了。"
        echo
        echo "访问方式："
        echo "  HTTP API: http://localhost:$QDRANT_PORT"
        echo "  管理界面: http://localhost:$QDRANT_PORT/dashboard"
        echo "  健康检查: http://localhost:$QDRANT_PORT/health"
    else
        log_error "发现以下问题："
        for issue in "${issues[@]}"; do
            echo "  • $issue"
        done
        
        echo
        log_info "建议解决方案："
        for suggestion in "${suggestions[@]}"; do
            echo "  • $suggestion"
        done
        
        echo
        echo "常用故障排除命令："
        echo "  查看Docker容器: docker ps -a | grep qdrant"
        echo "  启动Docker容器: docker start $QDRANT_CONTAINER_NAME"
        echo "  查看容器日志: docker logs $QDRANT_CONTAINER_NAME"
        echo "  查看系统服务: systemctl status qdrant"
        echo "  启动系统服务: systemctl start qdrant"
        echo "  检查端口占用: netstat -tulpn | grep -E '(6333|6334)'"
    fi
}

# 主函数
main() {
    log_title "=== Qdrant 安装验证工具 ==="
    
    echo "开始全面验证Qdrant安装状态..."
    echo
    
    # 执行所有检查
    check_docker_container
    echo
    
    check_process_status  
    echo
    
    check_port_status
    echo
    
    check_api_response
    echo
    
    check_configuration
    echo
    
    check_systemd_service
    echo
    
    perform_functional_test
    echo
    
    check_logs
    echo
    
    # 生成最终诊断
    generate_diagnosis
}

# 执行主函数
main "$@" 