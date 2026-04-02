/**
 * 服务器主入口文件
 * 
 * 这是整个后端服务器的核心文件，负责：
 * 1. 创建和配置 Express 应用
 * 2. 连接 MongoDB 数据库
 * 3. 设置 WebSocket 服务器（用于实时通信）
 * 4. 配置路由和中间件
 * 5. 处理客户端连接和断开
 * 
 * 技术栈：
 * - Express.js: Web应用框架
 * - Socket.io: 实时双向通信（仅用于用户注册和心跳）
 * - MongoDB: 数据库
 * - Helmet: 安全中间件
 * 
 * 启动方式：
 * node server.js
 * 
 * 或使用 PM2（推荐生产环境）：
 * pm2 start server.js --name secure-voice-server
 */

// ==================== 导入依赖包 ====================

const express = require('express');        // Express框架，用于创建Web服务器
const mongoose = require('mongoose');      // MongoDB对象建模工具
const cors = require('cors');              // 跨域资源共享中间件
const http = require('http');              // Node.js内置HTTP模块
const { Server } = require('socket.io');   // Socket.io服务器类
const helmet = require('helmet');          // 安全HTTP头中间件
const rateLimit = require('express-rate-limit');  // 速率限制中间件
require('dotenv').config();                // 加载环境变量

// ==================== 导入路由模块 ====================

const authRoutes = require('./routes/auth');        // 认证路由（注册、登录）
const contactRoutes = require('./routes/contacts'); // 联系人路由
const callRoutes = require('./routes/calls');       // 通话路由
const audioRoutes = require('./routes/audio');      // 音频通话路由
const userSockets = require('./routes/audio-sockets');  // 用户Socket映射

// ==================== 创建应用实例 ====================

const app = express();                     // 创建Express应用实例
const server = http.createServer(app);     // 创建HTTP服务器

/**
 * 创建Socket.io服务器实例
 * 
 * Socket.io 用于实现实时双向通信，主要功能：
 * - 实时通话信令交换
 * - 在线状态管理
 * - 实时消息推送
 * 
 * 配置说明：
 * - cors.origin: "*" 允许所有来源连接（生产环境应限制）
 * - cors.methods: 允许的HTTP方法
 */
const io = new Server(server, {
  cors: {
    origin: "*",                          // 允许所有来源（开发环境）
    methods: ["GET", "POST"]              // 允许的HTTP方法
  }
});

// 将io实例保存到app中，以便在路由中使用
app.set('io', io);

// ==================== 配置安全中间件 ====================

/**
 * Helmet安全中间件
 * 
 * 设置各种HTTP头以提高安全性：
 * - X-Content-Type-Options: 防止MIME类型嗅探
 * - X-Frame-Options: 防止点击劫持
 * - X-XSS-Protection: XSS过滤器
 * 
 * 注意：contentSecurityPolicy设为false，因为我们的应用需要加载外部资源
 */
app.use(helmet({
  contentSecurityPolicy: false,           // 禁用CSP，避免资源加载问题
}));

/**
 * 速率限制中间件
 * 
 * 防止暴力破解和DDoS攻击：
 * - windowMs: 时间窗口（15分钟）
 * - max: 在时间窗口内最多允许的请求数（1000次）
 * 
 * 超过限制后，客户端会收到"请求过于频繁"的错误
 */
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,               // 15分钟时间窗口
  max: 1000,                              // 最多1000次请求
  message: '请求过于频繁，请稍后再试'      // 超过限制时的错误消息
});
app.use(limiter);

/**
 * CORS跨域配置
 * 
 * 允许前端应用从不同域名访问后端API：
 * - origin: "*" 允许所有来源（生产环境应限制）
 * - methods: 允许的HTTP方法
 * - allowedHeaders: 允许的请求头
 */
app.use(cors({
  origin: '*',                            // 允许所有来源
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],  // 允许的方法
  allowedHeaders: ['Content-Type', 'Authorization']      // 允许的请求头
}));

// ==================== 配置请求解析中间件 ====================

/**
 * JSON解析中间件
 * 
 * 解析请求体中的JSON数据：
 * - limit: '10mb' 限制请求体大小为10MB（支持大文件上传）
 */
app.use(express.json({ limit: '10mb' }));

/**
 * URL编码解析中间件
 * 
 * 解析URL编码的请求体：
 * - extended: true 使用qs库解析（支持嵌套对象）
 * - limit: '10mb' 限制请求体大小
 */
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// ==================== 配置静态文件服务 ====================

/**
 * 静态文件服务
 * 
 * 将uploads目录设置为静态文件目录：
 * - 访问方式：http://服务器地址:端口/uploads/文件名
 * - 用于提供用户上传的头像等文件
 */
app.use('/uploads', express.static('uploads'));

// ==================== 连接MongoDB数据库 ====================

/**
 * MongoDB连接配置
 * 
 * 从环境变量读取连接字符串，如果没有则使用默认值
 */
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/secure_voice';

/**
 * 连接MongoDB
 * 
 * 连接选项说明：
 * - useNewUrlParser: 使用新的URL解析器
 * - useUnifiedTopology: 使用新的拓扑引擎
 * - serverSelectionTimeoutMS: 服务器选择超时（5秒）
 * - socketTimeoutMS: Socket超时（45秒）
 * - maxPoolSize: 最大连接池大小（10个连接）
 * - minPoolSize: 最小连接池大小（2个连接）
 */
mongoose.connect(MONGODB_URI, {
  useNewUrlParser: true,
  useUnifiedTopology: true,
  serverSelectionTimeoutMS: 5000,         // 5秒超时
  socketTimeoutMS: 45000,                 // 45秒超时
  maxPoolSize: 10,                        // 最大连接数
  minPoolSize: 2                          // 最小连接数
})
.then(() => {
  console.log('✅ MongoDB连接成功');
})
.catch((err) => {
  console.error('❌ MongoDB连接失败:', err.message);
  process.exit(1);                        // 连接失败，退出进程
});

// ==================== 配置API路由 ====================

/**
 * 挂载路由中间件
 * 
 * 将不同的路由模块挂载到对应的路径：
 * - /api/auth: 认证相关接口（注册、登录）
 * - /api/contacts: 联系人相关接口
 * - /api/calls: 通话相关接口
 * - /api/audio: 音频通话相关接口
 */
app.use('/api/auth', authRoutes);         // 认证路由
app.use('/api/contacts', contactRoutes);  // 联系人路由
app.use('/api/calls', callRoutes);        // 通话路由
app.use('/api/audio', audioRoutes);       // 音频通话路由

// ==================== 健康检查接口 ====================

/**
 * 健康检查接口
 * 
 * GET /health
 * 
 * 用于监控服务器状态：
 * - status: 服务器状态（ok表示正常）
 * - timestamp: 当前时间戳
 * - mongodb: MongoDB连接状态
 * 
 * 示例响应：
 * {
 *   "status": "ok",
 *   "timestamp": "2024-01-01T00:00:00.000Z",
 *   "mongodb": "connected"
 * }
 */
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok',                         // 服务器状态
    timestamp: new Date().toISOString(),  // 当前时间
    mongodb: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected'  // 数据库状态
  });
});

// ==================== WebSocket事件处理 ====================

/**
 * WebSocket连接事件处理
 * 
 * 当客户端连接到服务器时触发：
 * 1. 记录连接日志
 * 2. 设置各种事件监听器
 */
io.on('connection', (socket) => {
  console.log('用户连接:', socket.id);

  /**
   * 用户注册事件
   * 
   * 将用户ID与socket.id关联，用于后续消息路由
   * 
   * 数据格式：{ userId: string }
   * 
   * 流程：
   * 1. 客户端连接后，发送register事件
   * 2. 服务器将userId和socket.id保存到userSockets映射
   * 3. 其他用户可以通过userId找到对应的socket
   */
  socket.on('register', (userId) => {
    // 验证userId是否有效
    if (userId && typeof userId === 'string') {
      userSockets.set(userId, socket.id);  // 保存映射关系
      console.log(`用户 ${userId} 已注册，socket ID: ${socket.id}`);
    } else {
      console.warn('无效的用户ID注册:', userId);
    }
  });

  /**
   * 断开连接事件
   * 
   * 当客户端断开连接时触发
   * 
   * 处理：
   * 1. 从userSockets中删除用户映射
   * 2. 清理相关的通话记录
   */
  socket.on('disconnect', () => {
    console.log('用户断开连接:', socket.id);
    
    // 查找并删除用户映射
    for (const [userId, socketId] of userSockets.entries()) {
      if (socketId === socket.id) {
        userSockets.delete(userId);
        console.log(`用户 ${userId} 已注销`);
        break;
      }
    }
  });
});

// ==================== 错误处理中间件 ====================

/**
 * 全局错误处理中间件
 * 
 * 捕获所有未处理的错误：
 * - 记录错误日志
 * - 返回统一的错误响应
 * 
 * 注意：这个中间件必须放在所有路由之后
 */
app.use((err, req, res, next) => {
  console.error('服务器错误:', err);
  
  res.status(500).json({ 
    success: false, 
    message: '服务器内部错误',
    // 开发环境返回详细错误信息，生产环境不返回
    error: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

/**
 * 404处理中间件
 * 
 * 处理所有未匹配的路由
 */
app.use((req, res) => {
  res.status(404).json({ success: false, message: '接口不存在' });
});

// ==================== 启动服务器 ====================

/**
 * 服务器端口和主机配置
 * 
 * 从环境变量读取，如果没有则使用默认值：
 * - PORT: 3000
 * - HOST: 0.0.0.0（监听所有网络接口）
 */
const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';

/**
 * 启动HTTP服务器
 * 
 * 服务器启动后会监听指定的端口和主机
 */
server.listen(PORT, HOST, () => {
  console.log(`🚀 服务器运行在 http://${HOST}:${PORT}`);
  console.log(`📱 API地址: http://${HOST}:${PORT}/api`);
  console.log(`🔌 WebSocket服务已启动`);
});

// ==================== 优雅关闭处理 ====================

/**
 * SIGTERM信号处理
 * 
 * 当收到终止信号时（如PM2重启、Docker停止）：
 * 1. 停止接受新连接
 * 2. 关闭现有连接
 * 3. 关闭数据库连接
 * 4. 退出进程
 * 
 * 这样可以确保：
 * - 正在处理的请求能够完成
 * - 数据库连接正确关闭
 * - 不丢失数据
 */
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  
  server.close(() => {
    console.log('Server closed');
    
    mongoose.connection.close(false, () => {
      console.log('MongoDB connection closed');
      process.exit(0);                    // 正常退出
    });
  });
});

// ==================== 导出模块 ====================

/**
 * 导出应用实例
 * 
 * 用于：
 * - 单元测试
 * - 其他模块引用
 */
module.exports = { app, server, io };
