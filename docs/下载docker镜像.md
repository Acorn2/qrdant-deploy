
使用Skopeo工具（无需Docker）
Skopeo是一个可以在没有Docker的情况下操作容器镜像的工具：

```bash
# 在Mac上安装skopeo
brew install skopeo

brew uninstall skopeo

# 强制下载Linux amd64版本（适用于大多数云服务器），成功了
skopeo copy --override-os linux --override-arch amd64 \
    docker://qdrant/qdrant:latest \
    docker-archive:qdrant.tar

# 直接下载镜像为tar格式
skopeo copy docker://qdrant/qdrant:latest docker-archive:qdrant-latest.tar

# 下载特定版本
skopeo copy docker://qdrant/qdrant:v1.14.1 docker-archive:qdrant-v1.14.1.tar

skopeo copy --arch amd64 docker://qdrant/qdrant:v1.14.1 docker-archive:qdrant-v1.14.1.tar

# 下载Linux amd64版本（适用于大多数云服务器）
skopeo copy --arch amd64 docker://qdrant/qdrant:v1.14.1 docker-archive:qdrant-v1.14.1.tar

# 检查文件是否创建成功
ls -lh qdrant-v1.14.1.tar

# 压缩以减少传输时间
gzip qdrant-v1.14.1.tar

# 检查下载的文件
ls -lh qdrant-*.tar
```

下面这个方式成功了

```
# 1. 先安装crane（更稳定的工具）
brew install crane

brew uninstall crane

# 2. 检查镜像支持的平台
crane manifest qdrant/qdrant:v1.14.1

# 3. 导出Linux/amd64版本的镜像
CRANE_PLATFORM=linux/amd64 crane export qdrant/qdrant:v1.14.1 qdrant-v1.14.1.tar

# 4. 验证文件
ls -lh qdrant-v1.14.1.tar

# 5. 压缩并上传
gzip qdrant-v1.14.1.tar
scp qdrant-v1.14.1.tar.gz 
```