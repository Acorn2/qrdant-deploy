# 腾讯云 OpenCloudOS Docker 安装工具

本项目提供了一套完整的脚本工具，用于在腾讯云服务器的 OpenCloudOS 系统上安装和配置 Docker。

## 目录结构

```
qrdant-deploy/
├── install.sh                          # 一键安装主脚本
├── scripts/
│   ├── install-docker.sh              # Docker CE 安装脚本
│   ├── install-docker-compose.sh      # Docker Compose 安装脚本
│   ├── configure-docker.sh            # Docker 配置优化脚本
│   └── uninstall-docker.sh           # Docker 卸载脚本
└── README.md                          # 使用说明
```

## 快速开始

### 1. 克隆项目
```bash
git clone <repository-url>
cd qrdant-deploy
```

### 2. 一键安装
```bash
# 给主脚本执行权限
chmod +x install.sh

# 运行一键安装脚本
sudo ./install.sh
```

### 3. 选择安装选项
- 选项 1：仅安装 Docker CE
- 选项 2：仅安装 Docker Compose
- 选项 3：仅配置 Docker 优化
- 选项 4：完整安装（推荐）
- 选项 5：卸载 Docker
- 选项 6：退出

## 单独使用脚本

### 安装 Docker CE
```bash
sudo bash scripts/install-docker.sh
```

### 安装 Docker Compose
```bash
sudo bash scripts/install-docker-compose.sh
```

### 配置 Docker 优化
```bash
sudo bash scripts/configure-docker.sh
```

### 卸载 Docker
```bash
sudo bash scripts/uninstall-docker.sh
```

## 功能特性

### Docker CE 安装
- 自动检测 OpenCloudOS 系统版本
- 清理旧版本 Docker
- 安装必要依赖包
- 添加官方 Docker 仓库
- 安装最新版 Docker CE
- 配置用户组权限
- 安装验证测试

### Docker Compose 安装
- 自动获取最新版本
- 从官方 GitHub 下载
- 创建系统软链接
- 安装验证测试

### Docker 配置优化
- 配置国内镜像源加速
- 优化日志配置
- 配置系统内核参数
- 防火墙规则配置
- 性能参数调优

### 安全特性
- Root 权限检查
- 系统兼容性检查
- 安装前确认提示
- 详细的日志记录
- 错误处理和回滚

## 系统要求

- 操作系统：腾讯云 OpenCloudOS 或兼容系统
- 权限：需要 root 或 sudo 权限
- 网络：需要访问外网下载软件包
- 硬件：最低 2GB RAM，10GB 可用磁盘空间

## 镜像源配置

脚本自动配置了以下国内镜像源：
- 中科大镜像源：`https://docker.mirrors.ustc.edu.cn`
- 网易镜像源：`https://hub-mirror.c.163.com`
- 百度镜像源：`https://mirror.baidubce.com`

## 日志文件

安装过程的详细日志保存在：
- Docker 安装日志：`/var/log/docker-install.log`

## 常见问题

### 1. 网络连接问题
如果下载速度慢，可以：
- 使用腾讯云内网镜像源
- 配置代理服务器
- 手动下载安装包

### 2. 权限问题
确保使用 root 权限运行脚本：
```bash
sudo ./install.sh
```

### 3. 系统兼容性
如果系统检测失败，但确认是兼容系统，可以：
- 手动修改 `/etc/os-release` 文件
- 强制指定系统版本

### 4. 服务启动失败
检查系统日志：
```bash
journalctl -u docker.service
```

## 卸载说明

使用卸载脚本会：
- 停止所有 Docker 容器
- 删除所有 Docker 镜像和卷
- 卸载 Docker 软件包
- 清理配置文件和数据目录
- 删除用户组

**注意：卸载操作不可逆，请谨慎操作**

## 技术支持

如遇问题，请：
1. 查看日志文件排查错误
2. 检查网络连接和权限
3. 参考官方 Docker 文档
4. 提交 Issue 反馈问题

## 版本信息

- 当前版本：1.0
- 支持系统：OpenCloudOS 8.x
- Docker 版本：Latest CE
- Docker Compose：Latest v2.x

## 许可证

本项目遵循 MIT 许可证。 