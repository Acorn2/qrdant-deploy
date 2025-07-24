# PostgreSQL 故障排查工具套件

这是一套完整的PostgreSQL数据库故障排查和监控工具，专门用于解决数据表被意外清空的问题。

## 🎯 问题背景

当后端服务运行一段时间后，PostgreSQL数据库中的表会被清空，但后端代码中没有删除表的逻辑。本工具套件提供系统化的排查方案。

## 📁 脚本文件说明

### 核心脚本

- **`10_master_script.sh`** - 主控制脚本，提供交互式菜单
- **`01_immediate_check.sh`** - 立即诊断，快速检查当前状态
- **`07_health_check.sh`** - 综合健康检查，全面分析系统状态

### 监控脚本

- **`02_enable_monitoring.sh`** - 启用详细日志记录
- **`03_table_monitor.sh`** - 实时表监控（后台运行）
- **`04_connection_monitor.sh`** - 数据库连接监控（后台运行）
- **`08_start_all_monitoring.sh`** - 一键启动所有监控

### 配置管理

- **`05_optimize_config.sh`** - PostgreSQL配置优化
- **`09_restore_config.sh`** - 恢复正常配置，移除调试设置

### 专项排查

- **`06_check_cleanup_tasks.sh`** - 检查可疑的清理脚本和定时任务

## 🚀 快速开始

### 1. 上传脚本到服务器

```bash
# 将整个pg目录上传到服务器
scp -r pg/ root@your-server:/root/

# 或者使用其他方式上传
```

### 2. 设置权限

```bash
# 进入脚本目录
cd pg/

# 设置执行权限
chmod +x *.sh
```

### 3. 运行主控制脚本

```bash
# 运行主控制脚本（需要root权限）
sudo ./10_master_script.sh
```

## 📊 使用流程

### 第一阶段：立即诊断

1. **运行立即诊断** (`选项1`)
   - 检查PostgreSQL服务状态
   - 查看当前表状态
   - 检查系统资源

2. **综合健康检查** (`选项2`)
   - 全面系统分析
   - 性能指标检查
   - 配置参数验证

### 第二阶段：启动监控

3. **启用详细日志** (`选项4`)
   - 开启详细的SQL日志记录
   - 记录所有数据库操作

4. **启动实时监控** (`选项5`)
   - 表监控：每分钟检查表状态
   - 连接监控：每5分钟检查连接状态

### 第三阶段：深度排查

5. **检查清理任务** (`选项3`)
   - 搜索可疑的定时任务
   - 检查清理脚本
   - 分析应用程序代码

6. **监控数据分析** (`选项11`)
   - 分析表变化趋势
   - 统计异常事件

### 第四阶段：问题解决

7. **配置优化** (`选项8`)
   - 优化PostgreSQL配置
   - 调整系统资源限制

8. **恢复正常配置** (`选项9`)
   - 移除调试配置
   - 恢复生产环境设置

## 📋 监控说明

### 表监控 (`03_table_monitor.sh`)

- **功能**：实时监控数据表的变化
- **频率**：默认60秒间隔
- **日志**：`/var/log/table_monitor.log`
- **监控内容**：
  - 表的存在性
  - 行数统计（插入/删除/活跃/死行）
  - 数据库连接状态

### 连接监控 (`04_connection_monitor.sh`)

- **功能**：监控数据库连接和查询活动
- **频率**：默认300秒间隔
- **日志**：`/var/log/pg_connections.log`
- **监控内容**：
  - 连接数统计
  - 长时间运行的查询
  - 锁等待情况

### 监控管理

```bash
# 查看监控状态
sudo pg_monitor_manager.sh status

# 停止所有监控
sudo pg_monitor_manager.sh stop

# 查看最新日志
sudo pg_monitor_manager.sh logs

# 实时查看日志
sudo pg_monitor_manager.sh tail
```

## 🔍 常见问题排查

### 1. 表突然清空

**检查步骤**：
1. 查看表监控日志：`tail -f /var/log/table_monitor.log`
2. 检查PostgreSQL错误日志
3. 运行清理任务检查脚本
4. 分析监控数据趋势

### 2. 数据库连接异常

**检查步骤**：
1. 运行立即诊断检查
2. 查看连接监控日志
3. 检查系统资源使用
4. 验证配置参数

### 3. 性能问题

**优化步骤**：
1. 运行综合健康检查
2. 执行配置优化脚本
3. 监控性能改善情况

## 📁 日志文件位置

- **表监控日志**：`/var/log/table_monitor.log`
- **连接监控日志**：`/var/log/pg_connections.log`
- **PostgreSQL日志**：`/var/lib/pgsql/data/log/postgresql-*.log`
- **系统报告**：`/tmp/pg_*_report_*.txt`

## 🔧 配置文件备份

脚本会自动备份配置文件：
- **原始备份**：`postgresql.conf.backup.YYYYMMDD_HHMMSS`
- **优化前备份**：`postgresql.conf.optimize_backup.YYYYMMDD_HHMMSS`
- **恢复前备份**：`postgresql.conf.before_restore.YYYYMMDD_HHMMSS`

## ⚠️ 注意事项

1. **权限要求**：所有脚本都需要root权限运行
2. **日志增长**：详细日志会快速增长，定期清理
3. **监控资源**：监控脚本会消耗一定系统资源
4. **配置恢复**：排查完成后记得恢复正常配置

## 🆘 紧急处理

如果发现表被清空：

1. **立即停止应用程序**
2. **运行立即诊断**：`sudo ./01_immediate_check.sh`
3. **启动全量监控**：`sudo ./08_start_all_monitoring.sh`
4. **检查最近日志**：主菜单选项10
5. **搜索清理脚本**：`sudo ./06_check_cleanup_tasks.sh`

## 📞 技术支持

- 所有脚本都包含详细的错误处理和日志记录
- 使用主控制脚本的选项13生成完整系统报告
- 监控数据可用于问题复现和分析

---

**版本**: 1.0  
**更新**: 2024年  
**兼容**: CentOS/RHEL 7+, PostgreSQL 10+ 