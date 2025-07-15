

使用PostgreSQL官方仓库（推荐，版本更新）

```bash
# 安装PostgreSQL官方仓库
sudo yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# 安装PostgreSQL 14（您也可以选择其他版本如postgresql15-server）
sudo yum install -y postgresql14-server postgresql14 --nogpgcheck


```

使用系统默认仓库
```bash
sudo yum install -y postgresql-server postgresql
```


初始化数据库
```bash
# 如果使用系统默认版本
sudo postgresql-setup initdb

```


启动和启用PostgreSQL服务
```bash
# 系统默认版本
sudo systemctl start postgresql
sudo systemctl stop postgresql
sudo systemctl enable postgresql

```


验证安装
```bash
# 检查服务状态
sudo systemctl status postgresql

# 检查PostgreSQL版本
sudo -u postgres psql -c "SELECT version();"

```

设置postgres用户密码
```bash
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';"
```

配置远程连接（可选）
```bash
# 找到配置文件位置
sudo find /var/lib/pgsql -name "postgresql.conf"

/var/lib/pgsql/data/postgresql.conf

# 编辑配置文件
sudo vi /var/lib/pgsql/data/postgresql.conf
```

修改访问控制：
```bash
sudo vi /var/lib/pgsql/data/pg_hba.conf
```
添加以下行允许远程连接：
```
host    all             all             0.0.0.0/0               md5
```




在配置文件中修改：
```bash
listen_addresses = '*'
port = 5432
```




配置防火墙
```bash
# 开放PostgreSQL端口
sudo firewall-cmd --permanent --add-port=5432/tcp
sudo firewall-cmd --reload
```

重启服务使配置生效
```bash
sudo systemctl restart postgresql
```


创建数据库
```bash
sudo -u postgres psql -c "CREATE DATABASE document_analysis;"
```

```sql
-- 创建数据库
CREATE DATABASE document_analysis;

-- 查看所有数据库
\l

-- 退出psql
\q
```


使用systemd限制CPU使用率
创建systemd服务配置覆盖文件
```bash
# 创建覆盖目录
sudo mkdir -p /etc/systemd/system/postgresql.service.d

# 创建配置文件
sudo vi /etc/systemd/system/postgresql.service.d/cpu-limit.conf
```

添加以下内容限制CPU使用率
```
[Service]
# 限制CPU使用率为50%（可根据需要调整）
CPUQuota=50%
# 限制内存使用（可选）
MemoryLimit=2G
# 限制任务数量
TasksMax=100
```

重新加载配置并重启服务
```bash
sudo systemctl daemon-reload
sudo systemctl restart postgresql
```








