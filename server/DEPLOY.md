# 安全语音通话服务器部署指南

## 系统要求

- **操作系统**: Ubuntu 20.04 LTS 或更高版本
- **Node.js**: v18.0.0 或更高版本
- **MongoDB**: v5.0 或更高版本
- **内存**: 至少 2GB RAM
- **磁盘**: 至少 20GB 可用空间

## 部署步骤

### 1. 连接云服务器

```bash
ssh root@123.56.168.149
```

### 2. 安装Node.js

```bash
# 更新系统包
sudo apt update && sudo apt upgrade -y

# 安装Node.js 18.x
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# 验证安装
node --version  # 应显示 v18.x.x
npm --version   # 应显示 9.x.x
```

### 3. 安装MongoDB

```bash
# 导入MongoDB公钥
wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | sudo apt-key add -

# 添加MongoDB源
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list

# 更新包列表
sudo apt update

# 安装MongoDB
sudo apt install -y mongodb-org

# 启动MongoDB服务
sudo systemctl start mongod
sudo systemctl enable mongod

# 验证MongoDB状态
sudo systemctl status mongod
```

### 4. 创建项目目录

```bash
# 创建项目目录
mkdir -p /opt/secure-voice-server
cd /opt/secure-voice-server

# 创建上传目录
mkdir -p uploads
chmod 755 uploads
```

### 5. 上传服务器代码

将本地 `server` 目录中的所有文件上传到云服务器的 `/opt/secure-voice-server` 目录：

```bash
# 在本地执行（Windows PowerShell）
scp -r d:\Flutter\code\flutter_base\server\* root@123.56.168.149:/opt/secure-voice-server/

# 或者使用压缩包方式
# 1. 在本地压缩 server 目录
# 2. 上传到服务器
scp server.zip root@123.56.168.149:/opt/secure-voice-server/

# 3. 在服务器上解压
ssh root@123.56.168.149 "cd /opt/secure-voice-server && unzip server.zip"
```

### 6. 安装依赖

```bash
cd /opt/secure-voice-server
npm install
```

### 7. 配置环境变量

```bash
# 复制环境变量模板
cp .env.example .env

# 编辑环境变量
nano .env
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
JWT_SECRET=your-super-secret-jwt-key-change-this-in-production
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

### 8. 配置防火墙

```bash
# 安装UFW（如果未安装）
sudo apt install -y ufw

# 允许SSH连接
sudo ufw allow 22/tcp

# 允许HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# 允许应用端口（3000）
sudo ufw allow 3000/tcp

# 启用防火墙
sudo ufw enable

# 查看防火墙状态
sudo ufw status
```

### 9. 使用PM2管理进程

```bash
# 安装PM2
sudo npm install -g pm2

# 启动应用
pm2 start server.js --name secure-voice-server

# 设置开机自启
pm2 startup
pm2 save

# 查看应用状态
pm2 status
pm2 logs secure-voice-server
```

### 10. 配置Nginx反向代理（可选但推荐）

```bash
# 安装Nginx
sudo apt install -y nginx

# 创建Nginx配置文件
sudo nano /etc/nginx/sites-available/secure-voice-server
```

添加以下内容：

```nginx
server {
    listen 80;
    server_name 123.56.168.149;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # WebSocket支持
    location /socket.io/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

启用配置：

```bash
# 创建符号链接
sudo ln -s /etc/nginx/sites-available/secure-voice-server /etc/nginx/sites-enabled/

# 删除默认配置
sudo rm /etc/nginx/sites-enabled/default

# 测试配置
sudo nginx -t

# 重启Nginx
sudo systemctl restart nginx
```

### 11. 配置SSL证书（使用Let's Encrypt）

```bash
# 安装Certbot
sudo apt install -y certbot python3-certbot-nginx

# 获取证书
sudo certbot --nginx -d 123.56.168.149

# 自动续期
sudo certbot renew --dry-run
```

### 12. 测试部署

```bash
# 测试API是否正常运行
curl http://123.56.168.149:3000/health

# 应该返回：
# {"status":"ok","timestamp":"2026-03-08T...","mongodb":"connected"}
```

## 常用命令

### 查看日志

```bash
# 查看应用日志
pm2 logs secure-voice-server

# 查看MongoDB日志
sudo tail -f /var/log/mongodb/mongod.log

# 查看Nginx日志
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### 重启服务

```bash
# 重启应用
pm2 restart secure-voice-server

# 重启MongoDB
sudo systemctl restart mongod

# 重启Nginx
sudo systemctl restart nginx
```

### 备份数据库

```bash
# 创建备份目录
mkdir -p /opt/backups

# 备份MongoDB
mongodump --db secure_voice --out /opt/backups/$(date +%Y%m%d_%H%M%S)

# 恢复MongoDB（如果需要）
# mongorestore --db secure_voice /opt/backups/20260308_120000/secure_voice
```

### 更新应用

```bash
cd /opt/secure-voice-server

# 拉取最新代码（如果使用Git）
# git pull

# 或者重新上传代码
# scp -r local-server/* root@123.56.168.149:/opt/secure-voice-server/

# 安装依赖
npm install

# 重启应用
pm2 restart secure-voice-server
```

## 故障排查

### 应用无法启动

```bash
# 检查Node.js版本
node --version

# 检查端口占用
sudo netstat -tlnp | grep 3000

# 查看详细错误
pm2 logs secure-voice-server --lines 100
```

### MongoDB连接失败

```bash
# 检查MongoDB状态
sudo systemctl status mongod

# 检查MongoDB端口
sudo netstat -tlnp | grep 27017

# 测试MongoDB连接
mongo --eval "db.runCommand({ connectionStatus: 1 })"
```

### 防火墙问题

```bash
# 检查防火墙状态
sudo ufw status

# 临时禁用防火墙（仅用于测试）
sudo ufw disable

# 重新启用
sudo ufw enable
```

## 安全建议

1. **修改默认端口**：不要使用默认的3000端口，修改为不常用的端口
2. **强密码策略**：确保JWT_SECRET和MongoDB密码足够复杂
3. **定期更新**：定期更新系统和依赖包
4. **日志监控**：配置日志监控和告警
5. **访问控制**：限制MongoDB仅允许本地访问
6. **HTTPS**：生产环境务必使用HTTPS

## 联系支持

如果遇到问题，请检查：
1. 服务器日志：`pm2 logs`
2. MongoDB日志：`/var/log/mongodb/mongod.log`
3. Nginx日志：`/var/log/nginx/error.log`
