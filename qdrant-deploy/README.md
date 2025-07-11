 # Qdrant 向量数据库部署工具

本目录包含在腾讯云 OpenCloudOS 服务器上部署 Qdrant 向量数据库的完整脚本工具。

## 文件说明

### 核心部署脚本
- `deploy-qdrant.sh` - 使用 Docker 命令部署 Qdrant
- `deploy-compose.sh` - 使用 Docker Compose 部署 Qdrant
- `docker-compose.yml` - Docker Compose 配置文件
- `config.yaml` - Qdrant 服务配置文件

### 管理脚本
- `qdrant-manage.sh` - Docker 方式的服务管理工具（自动生成）
- `manage-compose.sh` - Docker Compose 方式的服务管理工具（自动生成）

## 前置要求

在部署 Qdrant 之前，确保已安装 Docker：

```bash
# 返回上级目录运行Docker安装脚本
cd ..
sudo bash scripts/install-docker.sh

# 如需使用 Docker Compose 方式，还需安装 Docker Compose
sudo bash scripts/install-docker-compose.sh
```

## 部署方式

### 方式一：使用 Docker 命令部署（推荐）

```bash
# 进入部署目录
cd qdrant-deploy

# 执行部署脚本
sudo bash deploy-qdrant.sh

sudo bash deploy-qdrant-enhanced.sh

# 该脚本成功
sudo bash deploy-qdrant-enhanced-fixed.sh

/my/tool/qdrant-v1.14.1.tar

# 这是正确的tar包
/my/tool/qdrant.tar
```

**特点：**
- 配置灵活，便于调试
- 资源使用透明
- 适合生产环境

### 方式二：使用 Docker Compose 部署

```bash
# 进入部署目录
cd qdrant-deploy

# 执行部署脚本
sudo bash deploy-compose.sh
```

**特点：**
- 配置文件化管理
- 便于多服务编排
- 适合开发和测试环境

## 服务配置

### 默认配置
- **HTTP API 端口**: 6333
- **gRPC API 端口**: 6334
- **数据目录**: `/opt/qdrant/data`
- **配置目录**: `/opt/qdrant/config`
- **内存限制**: 2GB
- **CPU 限制**: 1.0 核心

### 自定义配置

编辑 `config.yaml` 文件来调整 Qdrant 配置：

```yaml
# 修改端口
service:
  http_port: 6333
  grpc_port: 6334

# 调整性能参数
hnsw_config:
  m: 16
  ef_construct: 100

# 启用API密钥（生产环境推荐）
api_key: "your-secure-api-key"
```

## 服务管理

### Docker 方式管理

```bash
# 使用管理脚本（推荐）
./qdrant-manage.sh

# 或直接使用 Docker 命令
docker ps | grep qdrant              # 查看状态
docker logs qdrant-server            # 查看日志
docker stop qdrant-server            # 停止服务
docker start qdrant-server           # 启动服务
docker restart qdrant-server         # 重启服务
```

### Docker Compose 方式管理

```bash
# 使用管理脚本（推荐）
./manage-compose.sh

# 或直接使用 Docker Compose 命令
docker-compose ps                    # 查看状态
docker-compose logs -f               # 查看日志
docker-compose down                  # 停止服务
docker-compose up -d                 # 启动服务
docker-compose restart               # 重启服务
```

## API 使用示例

### 基础 API 测试

```bash
# 检查服务状态
curl http://localhost:6333/

# 健康检查
curl http://localhost:6333/health

# 查看集合列表
curl http://localhost:6333/collections

Qdrant提供了Web管理界面，可以通过以下地址访问：
本地访问: http://localhost:6333/dashboard
外部访问: http://您的公网IP:6333/dashboard（需要配置安全组）

```

### 创建集合示例

```bash
# 创建一个向量集合
curl -X PUT http://localhost:6333/collections/test_collection \
  -H 'Content-Type: application/json' \
  -d '{
    "vectors": {
      "size": 4,
      "distance": "Dot"
    }
  }'
```

### 插入向量示例

```bash
# 插入向量数据
curl -X PUT http://localhost:6333/collections/test_collection/points \
  -H 'Content-Type: application/json' \
  -d '{
    "points": [
      {
        "id": 1,
        "vector": [0.05, 0.61, 0.76, 0.74],
        "payload": {"city": "北京"}
      },
      {
        "id": 2,
        "vector": [0.19, 0.81, 0.75, 0.11],
        "payload": {"city": "上海"}
      }
    ]
  }'
```

### 搜索向量示例

```bash
# 搜索相似向量
curl -X POST http://localhost:6333/collections/test_collection/points/search \
  -H 'Content-Type: application/json' \
  -d '{
    "vector": [0.2, 0.1, 0.9, 0.7],
    "limit": 3
  }'
```

## 监控和维护

### 性能监控

```bash
# 查看容器资源使用
docker stats qdrant-server

# 查看系统指标
curl http://localhost:6333/metrics

# 查看集群信息
curl http://localhost:6333/cluster
```

### 数据备份

```bash
# 手动备份（Docker方式）
sudo tar -czf /opt/qdrant/backup-$(date +%Y%m%d).tar.gz -C /opt/qdrant data

# 使用管理脚本备份
./qdrant-manage.sh  # 选择备份选项
```

### 数据恢复

```bash
# 停止服务
docker stop qdrant-server

# 恢复数据
sudo tar -xzf /opt/qdrant/backup-20240101.tar.gz -C /opt/qdrant

# 启动服务
docker start qdrant-server
```

## 常见问题

### 1. 端口被占用
```bash
# 检查端口占用
netstat -tulpn | grep 6333

# 杀死占用进程
sudo kill -9 <PID>
```

### 2. 容器启动失败
```bash
# 查看详细日志
docker logs qdrant-server

# 检查配置文件
cat /opt/qdrant/config/config.yaml
```

### 3. API 无法访问
```bash
# 检查防火墙
sudo firewall-cmd --list-ports

# 检查服务状态
curl http://localhost:6333/health
```

### 4. 数据丢失
```bash
# 检查数据目录权限
ls -la /opt/qdrant/data

# 修复权限
sudo chown -R 1000:1000 /opt/qdrant
```

## 安全建议

### 生产环境配置

1. **启用API密钥认证**
   ```yaml
   api_key: "your-very-secure-api-key"
   ```

2. **配置防火墙规则**
   ```bash
   # 仅允许特定IP访问
   sudo firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='192.168.1.0/24' port protocol='tcp' port='6333' accept"
   ```

3. **使用HTTPS代理**
   ```bash
   # 配置Nginx反向代理（可选）
   sudo yum install nginx
   ```

4. **定期备份数据**
   ```bash
   # 设置定时备份任务
   crontab -e
   # 添加：0 2 * * * /path/to/backup-script.sh
   ```

## 版本信息

- **Qdrant 版本**: latest（自动获取最新版本）
- **支持系统**: OpenCloudOS 8.x / CentOS 8.x
- **Docker 要求**: 20.10+
- **内存要求**: 最少 512MB，推荐 2GB+
- **磁盘空间**: 根据数据量确定，建议预留充足空间

## 技术支持

如遇问题，请：
1. 查看服务日志排查错误
2. 检查配置文件和权限
3. 参考 [Qdrant 官方文档](https://qdrant.tech/documentation/)
4. 提交 Issue 反馈问题

## 许可证

本项目遵循 MIT 许可证。