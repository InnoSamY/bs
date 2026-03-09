# CentOS 7 部署指南

## 系统要求

- **操作系统**: CentOS 7.x
- **Node.js**: v18.0.0 或更高版本
- **MongoDB**: v5.0 或更高版本
- **内存**: 至少 2GB RAM
- **磁盘**: 至少 20GB 可用空间

⚠️ **重要提示**: CentOS 7将于2024年6月停止维护，建议尽快升级到CentOS 8或更新的版本。

## 部署步骤

### 1. 连接云服务器

```bash
ssh root@123.56.168.149
```

### 2. 更新系统

```bash
# 更新所有已安装的包
sudo yum update -y

# 安装必要的工具
sudo yum install -y wget curl vim git
```

### 3. 安装Node.js 18.x

```bash
# 使用NodeSource安装Node.js 18.x
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -

# 安装Node.js
sudo yum install -y nodejs

# 验证安装
node --version  # 应显示 v18.x.x
npm --version   # 应显示 9.x.x

# 如果版本不对，手动设置
sudo ln -sf /usr/bin/node /usr/local/bin/node
sudo ln -sf /usr/bin/npm /usr/local/bin/npm
```

### 4. 安装MongoDB 6.0

CentOS 7需要使用MongoDB 6.0（MongoDB 7.0不支持CentOS 7）

```bash
# 创建MongoDB仓库配置文件
sudo tee /etc/yum.repos.d/mongodb-org-6.0.repo <<EOF
[mongodb-org-6.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/7/mongodb-org/6.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-6.0.asc
EOF

# 导入GPG密钥
sudo rpm --import https://www.mongodb.org/static/pgp/server-6.0.asc

# 安装MongoDB
sudo yum install -y mongodb-org

# 创建数据目录（如果不存在）
sudo mkdir -p /var/lib/mongo
sudo chown -R mongod:mongod /var/lib/mongo

# 创建日志目录
sudo mkdir -p /var/log/mongodb
sudo chown -R mongod:mongod /var/log/mongodb

# 启动MongoDB服务
sudo systemctl start mongod

# 设置开机自启
sudo systemctl enable mongod

# 验证MongoDB状态
sudo systemctl status mongod

# 查看MongoDB日志（如果有问题）
sudo tail -f /var/log/mongodb/mongod.log
```

### 5. 创建项目目录

```bash
# 创建项目目录
sudo mkdir -p /opt/secure-voice-server

# 创建上传目录
sudo mkdir -p /opt/secure-voice-server/uploads

# 设置权限
sudo chmod -R 755 /opt/secure-voice-server
sudo chown -R $USER:$USER /opt/secure-voice-server
```

### 6. 上传服务器代码

**方法1：使用SCP上传（推荐）**

在本地Windows PowerShell中执行：

```powershell
# 进入server目录
cd d:\Flutter\code\flutter_base\server

# 上传所有文件
scp -r . root@123.56.168.149:/opt/secure-voice-server/
```

**方法2：使用压缩包上传**

```powershell
# 在本地压缩server目录
Compress-Archive -Path server -DestinationPath server.zip -Force

# 上传压缩包
scp server.zip root@123.56.168.149:/opt/

# 在服务器上解压
ssh root@123.56.168.149 "cd /opt/secure-voice-server && unzip -o /opt/server.zip"
```

### 7. 安装项目依赖

```bash
# 进入项目目录
cd /opt/secure-voice-server

# 安装依赖
npm install

# 如果遇到权限问题
sudo chown -R $USER:$USER node_modules/
```

### 8. 配置环境变量

```bash
# 复制环境变量模板
cp .env.example .env

# 编辑环境变量
vim .env
```

编辑以下内容：

```env
# 服务器配置
PORT=3000
HOST=0.0.0.0
NODE_ENV=production

# MongoDB配置
MONGODB_URI=mongodb://localhost:27017/secure_voice

# JWT配置（请修改为一个强密码）
JWT_SECRET=your-super-secret-jwt-key-change-this-in-production-$(openssl rand -hex 32)
JWT_EXPIRES_IN=7d

# 文件上传配置
UPLOAD_DIR=uploads
MAX_FILE_SIZE=10485760

# CORS配置
CORS_ORIGIN=*

# 速率限制配置
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100
```

生成安全的JWT密钥：

```bash
# 生成随机密钥
openssl rand -hex 32
```

将生成的密钥复制到.env文件的JWT_SECRET字段。

### 9. 配置防火墙（firewalld）

CentOS 7使用firewalld而不是UFW：

```bash
# 检查firewalld状态
sudo systemctl status firewalld

# 允许SSH连接
sudo firewall-cmd --permanent --add-service=ssh

# 允许HTTP/HTTPS
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https

# 允许应用端口（3000）
sudo firewall-cmd --permanent --add-port=3000/tcp

# 重新加载防火墙规则
sudo firewall-cmd --reload

# 查看防火墙规则
sudo firewall-cmd --list-all
```

### 10. 使用PM2管理进程

```bash
# 全局安装PM2
sudo npm install -g pm2

# 创建PM2配置文件
cat > ecosystem.config.js <<EOF
module.exports = {
  apps: [{
    name: 'secure-voice-server',
    script: './server.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    merge_logs: true
  }]
};
EOF

# 启动应用
pm2 start ecosystem.config.js

# 设置开机自启
pm2 startup
pm2 save

# 查看应用状态
pm2 status

# 查看应用日志
pm2 logs secure-voice-server

# 查看实时日志
pm2 logs secure-voice-server --lines 100
```

### 11. 配置SELinux（如果启用）

```bash
# 检查SELinux状态
getenforce

# 如果是Enforcing，需要配置MongoDB
sudo setsebool -P mongod_can_network_connect_db 1

# 配置Node.js访问
sudo semanage fcontext -a -t httpd_sys_content_t /opt/secure-voice-server/uploads
sudo restorecon -R -v /opt/secure-voice-server/uploads

# 查看SELinux上下文
ls -Z /opt/secure-voice-server/uploads
```

### 12. 测试部署

```bash
# 测试API是否正常运行
curl http://localhost:3000/health

# 应该返回：
# {"status":"ok","timestamp":"2026-03-08T...","mongodb":"connected"}

# 测试外部访问（在本地电脑执行）
curl http://123.56.168.149:3000/health
```

### 13. 配置Nginx反向代理（可选但推荐）

```bash
# 安装EPEL仓库（CentOS 7需要）
sudo yum install -y epel-release

# 安装Nginx
sudo yum install -y nginx

# 启动Nginx
sudo systemctl start nginx
sudo systemctl enable nginx

# 创建Nginx配置文件
sudo tee /etc/nginx/conf.d/secure-voice-server.conf <<EOF
server {
    listen 80;
    server_name 123.56.168.149;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }

    # WebSocket支持
    location /socket.io/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# 测试Nginx配置
sudo nginx -t

# 重启Nginx
sudo systemctl restart nginx
```

## 常用命令

### 查看日志

```bash
# 查看应用日志
pm2 logs secure-voice-server

# 查看MongoDB日志
sudo tail -f /var/log/mongodb/mongod.log

# 查看Nginx日志
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log

# 查看系统日志
sudo journalctl -u mongod -f
sudo journalctl -u nginx -f
```

### 重启服务

```bash
# 重启应用
pm2 restart secure-voice-server

# 重启MongoDB
sudo systemctl restart mongod

# 重启Nginx
sudo systemctl restart nginx

# 重启防火墙
sudo systemctl restart firewalld
```

### 查看服务状态

```bash
# 查看应用状态
pm2 status

# 查看MongoDB状态
sudo systemctl status mongod

# 查看Nginx状态
sudo systemctl status nginx

# 查看防火墙状态
sudo firewall-cmd --list-all
```

### 备份数据库

```bash
# 创建备份目录
sudo mkdir -p /opt/backups

# 备份MongoDB
sudo mongodump --db secure_voice --out /opt/backups/\$(date +%Y%m%d_%H%M%S)

# 恢复MongoDB（如果需要）
sudo mongorestore --db secure_voice /opt/backups/20260308_120000/secure_voice

# 设置自动备份（添加到crontab）
crontab -e

# 添加以下行（每天凌晨2点备份）
0 2 * * * /usr/bin/mongodump --db secure_voice --out /opt/backups/\$(date +\%Y\%m\%d_\%H\%M\%S)
```

## 故障排查

### 应用无法启动

```bash
# 检查Node.js版本
node --version

# 检查端口占用
sudo netstat -tlnp | grep 3000

# 查看详细错误
pm2 logs secure-voice-server --lines 100 --err

# 检查MongoDB连接
mongo --eval "db.runCommand({ connectionStatus: 1 })"
```

### MongoDB连接失败

```bash
# 检查MongoDB状态
sudo systemctl status mongod

# 检查MongoDB端口
sudo netstat -tlnp | grep 27017

# 测试MongoDB连接
mongo --eval "db.runCommand({ connectionStatus: 1 })"

# 查看MongoDB日志
sudo tail -100 /var/log/mongodb/mongod.log

# 重启MongoDB
sudo systemctl restart mongod
```

### 防火墙问题

```bash
# 检查防火墙状态
sudo firewall-cmd --list-all

# 临时禁用防火墙（仅用于测试）
sudo systemctl stop firewalld

# 重新启用
sudo systemctl start firewalld

# 添加特定IP访问
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="YOUR_IP_ADDRESS" port protocol="tcp" port="3000" accept'
sudo firewall-cmd --reload
```

### SELinux问题

```bash
# 检查SELinux状态
getenforce

# 临时禁用SELinux（仅用于测试）
sudo setenforce 0

# 重新启用
sudo setenforce 1

# 查看SELinux拒绝日志
sudo ausearch -m avc -ts recent | tail
```

### 权限问题

```bash
# 检查文件权限
ls -la /opt/secure-voice-server

# 修复权限
sudo chown -R $USER:$USER /opt/secure-voice-server
sudo chmod -R 755 /opt/secure-voice-server

# 检查MongoDB数据目录权限
ls -la /var/lib/mongo
sudo chown -R mongod:mongod /var/lib/mongo
```

## 性能优化

### MongoDB优化

```bash
# 编辑MongoDB配置文件
sudo vim /etc/mongod.conf

# 添加以下配置
storage:
  wiredTiger:
    engineConfig:
      cacheSizeGB: 2
systemLog:
  destination: file
  logAppend: true
  logRotate: reopen
  path: /var/log/mongodb/mongod.log
net:
  port: 27017
  bindIp: 127.0.0.1
operationProfiling:
  mode: slowOp
  slowOpThresholdMs: 100

# 重启MongoDB
sudo systemctl restart mongod
```

### Node.js优化

```bash
# 设置Node.js内存限制
echo "NODE_OPTIONS=--max-old-space-size=4096" | sudo tee -a /etc/environment

# 启用Node.js集群模式（如果需要）
pm2 scale secure-voice-server 2
```

## 安全加固

### 1. 修改默认端口

```bash
# 修改.env文件中的端口
vim .env

# 将PORT改为不常用的端口
PORT=8443
```

### 2. 配置SSH安全

```bash
# 禁用root远程登录
sudo vim /etc/ssh/sshd_config

# 添加或修改以下行
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes

# 重启SSH服务
sudo systemctl restart sshd
```

### 3. 配置fail2ban

```bash
# 安装fail2ban
sudo yum install -y epel-release
sudo yum install -y fail2ban

# 启动fail2ban
sudo systemctl start fail2ban
sudo systemctl enable fail2ban

# 查看fail2ban状态
sudo fail2ban-client status
```

### 4. 配置SSL证书（使用Let's Encrypt）

```bash
# 安装Certbot
sudo yum install -y certbot python2-certbot-nginx

# 获取证书
sudo certbot --nginx -d 123.56.168.149

# 自动续期
sudo certbot renew --dry-run

# 添加自动续期到crontab
echo "0 0,12 * * * /usr/bin/certbot renew --quiet" | sudo crontab -
```

## 监控和告警

### 安装监控工具

```bash
# 安装htop（系统监控）
sudo yum install -y htop

# 安装iotop（磁盘IO监控）
sudo yum install -y iotop

# 安装nethogs（网络监控）
sudo yum install -y nethogs
```

### 配置日志轮转

```bash
# 创建日志轮转配置
sudo tee /etc/logrotate.d/secure-voice-server <<EOF
/opt/secure-voice-server/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    sharedscripts
        postrotate
            pm2 restart secure-voice-server > /dev/null 2>&1 || true
        endscript
}
EOF

# 测试日志轮转
sudo logrotate -d /etc/logrotate.d/secure-voice-server
```

## 升级建议

由于CentOS 7即将停止维护，建议尽快升级：

### 升级到CentOS 8 Stream

```bash
# 备份重要数据
sudo mongodump --db secure_voice --out /opt/backups/pre-upgrade-backup

# 升级系统（需要重新安装）
# 注意：这需要重新安装所有软件
# 建议在测试环境先测试
```

### 或者迁移到AlmaLinux/Rocky Linux

这些是CentOS的社区替代品，提供更好的长期支持。

## 联系支持

如果遇到问题，请检查：

1. **应用日志**: `pm2 logs secure-voice-server`
2. **MongoDB日志**: `/var/log/mongodb/mongod.log`
3. **Nginx日志**: `/var/log/nginx/error.log`
4. **系统日志**: `sudo journalctl -xe`

## 快速参考

### 一键部署脚本

```bash
#!/bin/bash
# 快速部署脚本
set -e

echo "🚀 开始部署安全语音通话服务器..."

# 更新系统
echo "📦 更新系统..."
sudo yum update -y

# 安装Node.js
echo "📦 安装Node.js..."
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo yum install -y nodejs

# 安装MongoDB
echo "📦 安装MongoDB..."
sudo tee /etc/yum.repos.d/mongodb-org-6.0.repo <<EOF
[mongodb-org-6.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/7/mongodb-org/6.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-6.0.asc
EOF
sudo rpm --import https://www.mongodb.org/static/pgp/server-6.0.asc
sudo yum install -y mongodb-org
sudo systemctl start mongod
sudo systemctl enable mongod

# 创建项目目录
echo "📁 创建项目目录..."
sudo mkdir -p /opt/secure-voice-server
sudo mkdir -p /opt/secure-voice-server/uploads
sudo chown -R $USER:$USER /opt/secure-voice-server

# 配置防火墙
echo "🔥 配置防火墙..."
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --reload

# 安装PM2
echo "📦 安装PM2..."
sudo npm install -g pm2

echo "✅ 部署完成！"
echo ""
echo "📝 下一步："
echo "1. 上传代码到 /opt/secure-voice-server"
echo "2. cd /opt/secure-voice-server"
echo "3. npm install"
echo "4. cp .env.example .env && vim .env"
echo "5. pm2 start server.js"
```

保存为 `deploy.sh`，然后执行：

```bash
chmod +x deploy.sh
./deploy.sh
```
