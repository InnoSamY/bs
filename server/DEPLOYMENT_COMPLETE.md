# 服务器部署完成指南

## ✅ 已完成的工作

### 服务器端
- ✅ 安装Node.js 16.x
- ✅ 安装MongoDB 7.0
- ✅ 上传服务器代码
- ✅ 安装依赖
- ✅ 启动服务器

### 客户端
- ✅ 修改API地址指向云服务器
- ✅ 添加JWT token支持
- ✅ 更新用户模型
- ✅ 修改登录/注册接口
- ✅ 更新联系人服务

## 📋 接下来的步骤

### 1. 测试服务器API

在本地Windows PowerShell中执行：

```powershell
# 测试健康检查接口
curl http://123.56.168.149:3000/health

# 应该返回：
# {"status":"ok","timestamp":"2026-03-08T...","mongodb":"connected"}
```

### 2. 测试用户注册

使用Postman或curl测试注册接口：

```powershell
# 注册新用户
curl -X POST http://123.56.168.149:3000/api/auth/register `
  -H "Content-Type: application/json" `
  -d '{
    "username": "testuser",
    "password": "123456",
    "avatar": "",
    "bio": "测试用户",
    "publicKey": "test-public-key"
  }'

# 应该返回：
# {
#   "success": true,
#   "message": "注册成功",
#   "data": {
#     "id": "...",
#     "username": "testuser",
#     "avatar": "",
#     "bio": "测试用户",
#     "publicKey": "test-public-key",
#     "token": "..."
#   }
# }
```

### 3. 运行Flutter应用

```bash
# 在Flutter项目根目录
cd d:\Flutter\code\flutter_base

# 运行应用
flutter run
```

### 4. 测试注册功能

1. 打开应用
2. 点击"还没有账号？立即注册"
3. 填写注册信息：
   - 用户名：testuser
   - 密码：123456
   - 头像：可选
   - 个性签名：测试用户
4. 点击"注册"

### 5. 测试登录功能

1. 返回登录页面
2. 输入用户名：testuser
3. 输入密码：123456
4. 点击"登录"

### 6. 测试联系人功能

登录成功后：
1. 查看联系人列表（初始为空）
2. 点击"添加联系人"
3. 输入另一个用户的用户名或ID
4. 发送好友请求

## 🔧 服务器管理命令

### 查看服务器状态

```bash
# 在服务器上执行
cd /opt/secure-voice-server

# 查看Node.js进程
ps aux | grep node

# 查看MongoDB状态
sudo systemctl status mongod

# 查看服务器日志
tail -f /opt/secure-voice-server/logs/out.log
tail -f /opt/secure-voice-server/logs/err.log
```

### 重启服务器

```bash
# 方法1：如果使用node直接运行
# 先找到进程ID
ps aux | grep node

# 杀死进程
kill <进程ID>

# 重新启动
cd /opt/secure-voice-server
node server.js

# 方法2：如果使用PM2
pm2 restart secure-voice-server
pm2 logs secure-voice-server
```

### 查看MongoDB数据

```bash
# 连接到MongoDB
mongo

# 切换到数据库
use secure_voice

# 查看用户集合
db.users.find()

# 查看联系人集合
db.contacts.find()

# 退出
exit
```

## 📊 API接口文档

### 认证接口

#### 1. 注册用户
```
POST /api/auth/register
Content-Type: application/json

{
  "username": "string",
  "password": "string",
  "avatar": "string (optional)",
  "bio": "string (optional)",
  "publicKey": "string"
}

Response:
{
  "success": true,
  "message": "注册成功",
  "data": {
    "id": "string",
    "username": "string",
    "avatar": "string",
    "bio": "string",
    "publicKey": "string",
    "token": "string"
  }
}
```

#### 2. 用户登录
```
POST /api/auth/login
Content-Type: application/json

{
  "username": "string",
  "password": "string"
}

Response:
{
  "success": true,
  "message": "登录成功",
  "data": {
    "id": "string",
    "username": "string",
    "avatar": "string",
    "bio": "string",
    "publicKey": "string",
    "token": "string"
  }
}
```

#### 3. 获取当前用户
```
GET /api/auth/me
Authorization: Bearer <token>

Response:
{
  "success": true,
  "data": {
    "id": "string",
    "username": "string",
    "avatar": "string",
    "bio": "string",
    "publicKey": "string",
    "createdAt": "string"
  }
}
```

### 联系人接口

#### 1. 获取联系人列表
```
GET /api/contacts
Authorization: Bearer <token>

Response:
{
  "success": true,
  "data": [
    {
      "id": "string",
      "username": "string",
      "avatar": "string",
      "bio": "string",
      "addedAt": "string"
    }
  ]
}
```

#### 2. 添加联系人
```
POST /api/contacts/add
Authorization: Bearer <token>
Content-Type: application/json

{
  "contactId": "string",
  "verificationMessage": "string (optional)"
}

Response:
{
  "success": true,
  "message": "添加请求已发送",
  "data": {
    "id": "string",
    "contactId": "string",
    "status": "pending",
    "verificationMessage": "string",
    "requestedAt": "string"
  }
}
```

#### 3. 删除联系人
```
DELETE /api/contacts/:contactId
Authorization: Bearer <token>

Response:
{
  "success": true,
  "message": "联系人已删除"
}
```

## 🚀 使用PM2管理进程（推荐）

### 安装PM2

```bash
# 在服务器上执行
npm install -g pm2
```

### 使用PM2启动服务器

```bash
# 进入项目目录
cd /opt/secure-voice-server

# 启动应用
pm2 start server.js --name secure-voice-server

# 查看应用状态
pm2 status

# 查看日志
pm2 logs secure-voice-server

# 重启应用
pm2 restart secure-voice-server

# 停止应用
pm2 stop secure-voice-server

# 删除应用
pm2 delete secure-voice-server
```

### 设置开机自启

```bash
# 生成启动脚本
pm2 startup

# 保存当前进程列表
pm2 save
```

## 🔒 安全建议

### 1. 修改默认端口

编辑 `/opt/secure-voice-server/.env`：

```env
PORT=8443
```

### 2. 配置防火墙

```bash
# 删除旧的3000端口
sudo firewall-cmd --permanent --remove-port=3000/tcp

# 添加新端口
sudo firewall-cmd --permanent --add-port=8443/tcp
sudo firewall-cmd --reload
```

### 3. 配置Nginx反向代理

```bash
# 安装Nginx
sudo yum install -y nginx

# 创建配置文件
sudo tee /etc/nginx/conf.d/secure-voice-server.conf <<EOF
server {
    listen 80;
    server_name 123.56.168.149;

    location / {
        proxy_pass http://localhost:8443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }

    location /socket.io/ {
        proxy_pass http://localhost:8443;
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

# 测试配置
sudo nginx -t

# 启动Nginx
sudo systemctl start nginx
sudo systemctl enable nginx
```

### 4. 配置SSL证书

```bash
# 安装Certbot
sudo yum install -y certbot python2-certbot-nginx

# 获取证书
sudo certbot --nginx -d 123.56.168.149

# 自动续期
sudo certbot renew --dry-run
```

## 📱 Flutter应用测试

### 测试流程

1. **注册测试用户**
   - 用户名：user1
   - 密码：123456

2. **登录用户1**
   - 使用user1登录

3. **注册第二个用户**
   - 退出登录
   - 注册用户2
   - 用户名：user2
   - 密码：123456

4. **添加联系人**
   - 使用user1登录
   - 添加user2为联系人
   - 使用user2登录
   - 接受好友请求

5. **测试通话功能**
   - 使用user1登录
   - 选择user2
   - 发起语音通话

## 🐛 常见问题

### 1. 服务器无法启动

```bash
# 检查端口占用
sudo netstat -tlnp | grep 3000

# 查看错误日志
tail -f /opt/secure-voice-server/logs/err.log
```

### 2. MongoDB连接失败

```bash
# 检查MongoDB状态
sudo systemctl status mongod

# 重启MongoDB
sudo systemctl restart mongod

# 查看MongoDB日志
sudo tail -f /var/log/mongodb/mongod.log
```

### 3. Flutter应用无法连接服务器

```bash
# 检查防火墙
sudo firewall-cmd --list-all

# 确保端口已开放
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --reload

# 测试服务器连接
curl http://123.56.168.149:3000/health
```

### 4. 注册/登录失败

```bash
# 查看服务器日志
pm2 logs secure-voice-server

# 检查MongoDB数据
mongo
use secure_voice
db.users.find()
```

## 📞 技术支持

如果遇到问题，请提供以下信息：

1. 错误信息截图
2. 服务器日志：`pm2 logs secure-voice-server --lines 100`
3. MongoDB日志：`sudo tail -50 /var/log/mongodb/mongod.log`
4. Flutter应用日志

## 🎉 恭喜！

你的安全语音通话服务器已经部署完成！现在可以开始测试和使用应用了。

记得：
- 定期备份数据库
- 监控服务器性能
- 及时更新依赖包
- 保持安全配置
