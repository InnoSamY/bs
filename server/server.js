const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const http = require('http');
const { Server } = require('socket.io');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
require('dotenv').config();

const authRoutes = require('./routes/auth');
const contactRoutes = require('./routes/contacts');
const callRoutes = require('./routes/calls');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

// 安全中间件
app.use(helmet({
  contentSecurityPolicy: false,
}));

// 速率限制
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15分钟
  max: 100, // 限制每个IP 100个请求
  message: '请求过于频繁，请稍后再试'
});
app.use(limiter);

// CORS配置
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

// 解析JSON请求体
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// 静态文件服务（用于头像）
app.use('/uploads', express.static('uploads'));

// MongoDB连接
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/secure_voice';

mongoose.connect(MONGODB_URI, {
  useNewUrlParser: true,
  useUnifiedTopology: true,
})
.then(() => {
  console.log('✅ MongoDB连接成功');
})
.catch((err) => {
  console.error('❌ MongoDB连接失败:', err.message);
  process.exit(1);
});

// API路由
app.use('/api/auth', authRoutes);
app.use('/api/contacts', contactRoutes);
app.use('/api/calls', callRoutes);

// 健康检查端点
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    timestamp: new Date().toISOString(),
    mongodb: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected'
  });
});

// WebRTC信令服务
const activeCalls = new Map();
const userSockets = new Map();

io.on('connection', (socket) => {
  console.log('用户连接:', socket.id);

  // 用户注册
  socket.on('register', (userId) => {
    userSockets.set(userId, socket.id);
    console.log(`用户 ${userId} 已注册，socket ID: ${socket.id}`);
  });

  // 发起通话请求
  socket.on('call-request', (data) => {
    const { callerId, calleeId, offer, callType } = data;
    const calleeSocketId = userSockets.get(calleeId);
    
    if (calleeSocketId) {
      io.to(calleeSocketId).emit('incoming-call', {
        callerId,
        offer,
        callType,
        callId: socket.id
      });
      activeCalls.set(socket.id, { callerId, calleeId, status: 'calling' });
    } else {
      socket.emit('call-error', { message: '用户不在线' });
    }
  });

  // 接受通话
  socket.on('call-accept', (data) => {
    const { callerId, answer } = data;
    const callerSocketId = userSockets.get(callerId);
    
    if (callerSocketId) {
      io.to(callerSocketId).emit('call-accepted', { answer });
      const call = activeCalls.get(callerSocketId);
      if (call) {
        call.status = 'connected';
      }
    }
  });

  // 拒绝通话
  socket.on('call-reject', (data) => {
    const { callerId } = data;
    const callerSocketId = userSockets.get(callerId);
    
    if (callerSocketId) {
      io.to(callerSocketId).emit('call-rejected', { reason: '用户拒绝接听' });
      activeCalls.delete(callerSocketId);
    }
  });

  // 挂断通话
  socket.on('call-end', (data) => {
    const { targetId } = data;
    const targetSocketId = userSockets.get(targetId);
    
    if (targetSocketId) {
      io.to(targetSocketId).emit('call-ended');
    }
    
    // 清理通话记录
    for (const [key, value] of activeCalls.entries()) {
      if (value.callerId === targetId || value.calleeId === targetId) {
        activeCalls.delete(key);
      }
    }
  });

  // ICE候选者交换
  socket.on('ice-candidate', (data) => {
    const { targetId, candidate } = data;
    const targetSocketId = userSockets.get(targetId);
    
    if (targetSocketId) {
      io.to(targetSocketId).emit('ice-candidate', { candidate });
    }
  });

  // 断开连接
  socket.on('disconnect', () => {
    console.log('用户断开连接:', socket.id);
    
    // 从用户映射中移除
    for (const [userId, socketId] of userSockets.entries()) {
      if (socketId === socket.id) {
        userSockets.delete(userId);
        break;
      }
    }
    
    // 清理相关通话
    activeCalls.delete(socket.id);
  });
});

// 错误处理中间件
app.use((err, req, res, next) => {
  console.error('服务器错误:', err);
  res.status(500).json({ 
    success: false, 
    message: '服务器内部错误',
    error: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

// 404处理
app.use((req, res) => {
  res.status(404).json({ success: false, message: '接口不存在' });
});

// 启动服务器
const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';

server.listen(PORT, HOST, () => {
  console.log(`🚀 服务器运行在 http://${HOST}:${PORT}`);
  console.log(`📱 API地址: http://${HOST}:${PORT}/api`);
  console.log(`🔌 WebSocket服务已启动`);
});

// 优雅关闭
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  server.close(() => {
    console.log('Server closed');
    mongoose.connection.close(false, () => {
      console.log('MongoDB connection closed');
      process.exit(0);
    });
  });
});

module.exports = { app, server, io };
