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
const videoRoutes = require('./routes/video');
const userSockets = require('./routes/video-sockets');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

app.set('io', io);

app.use(helmet({
  contentSecurityPolicy: false,
}));

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 1000,
  message: '请求过于频繁，请稍后再试'
});
app.use(limiter);

app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

app.use('/uploads', express.static('uploads'));

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/secure_voice';

mongoose.connect(MONGODB_URI, {
  useNewUrlParser: true,
  useUnifiedTopology: true,
  serverSelectionTimeoutMS: 5000,
  socketTimeoutMS: 45000,
  maxPoolSize: 10,
  minPoolSize: 2
})
.then(() => {
  console.log('✅ MongoDB连接成功');
})
.catch((err) => {
  console.error('❌ MongoDB连接失败:', err.message);
  process.exit(1);
});

app.use('/api/auth', authRoutes);
app.use('/api/contacts', contactRoutes);
app.use('/api/calls', callRoutes);
app.use('/api/video', videoRoutes);

app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    timestamp: new Date().toISOString(),
    mongodb: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected'
  });
});

const activeCalls = new Map();

io.on('connection', (socket) => {
  console.log('用户连接:', socket.id);

  socket.on('register', (userId) => {
    if (userId && typeof userId === 'string') {
      userSockets.set(userId, socket.id);
      console.log(`用户 ${userId} 已注册，socket ID: ${socket.id}`);
    } else {
      console.warn('无效的用户ID注册:', userId);
    }
  });

  socket.on('call-request', (data) => {
    const { callerId, calleeId, offer, callType } = data;
    if (calleeId && typeof calleeId === 'string') {
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
    } else {
      console.warn('无效的calleeId:', calleeId);
      socket.emit('call-error', { message: '无效的用户ID' });
    }
  });

  socket.on('call-accept', (data) => {
    const { callerId, answer } = data;
    if (callerId && typeof callerId === 'string') {
      const callerSocketId = userSockets.get(callerId);
      
      if (callerSocketId) {
        io.to(callerSocketId).emit('call-accepted', { answer });
        const call = activeCalls.get(callerSocketId);
        if (call) {
          call.status = 'connected';
        }
      }
    }
  });

  socket.on('call-reject', (data) => {
    const { callerId } = data;
    if (callerId && typeof callerId === 'string') {
      const callerSocketId = userSockets.get(callerId);
      
      if (callerSocketId) {
        io.to(callerSocketId).emit('call-rejected', { reason: '用户拒绝接听' });
        activeCalls.delete(callerSocketId);
      }
    }
  });

  socket.on('call-end', (data) => {
    const { targetId } = data;
    if (targetId && typeof targetId === 'string') {
      const targetSocketId = userSockets.get(targetId);
      
      if (targetSocketId) {
        io.to(targetSocketId).emit('call-ended');
      }
      
      for (const [key, value] of activeCalls.entries()) {
        if (value.callerId === targetId || value.calleeId === targetId) {
          activeCalls.delete(key);
        }
      }
    }
  });

  socket.on('ice-candidate', (data) => {
    const { targetId, candidate } = data;
    if (targetId && typeof targetId === 'string') {
      const targetSocketId = userSockets.get(targetId);
      
      if (targetSocketId) {
        io.to(targetSocketId).emit('ice-candidate', { candidate });
      }
    }
  });

  socket.on('disconnect', () => {
    console.log('用户断开连接:', socket.id);
    
    for (const [userId, socketId] of userSockets.entries()) {
      if (socketId === socket.id) {
        userSockets.delete(userId);
        console.log(`用户 ${userId} 已注销`);
        break;
      }
    }
    
    activeCalls.delete(socket.id);
  });
});

app.use((err, req, res, next) => {
  console.error('服务器错误:', err);
  res.status(500).json({ 
    success: false, 
    message: '服务器内部错误',
    error: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

app.use((req, res) => {
  res.status(404).json({ success: false, message: '接口不存在' });
});

const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';

server.listen(PORT, HOST, () => {
  console.log(`🚀 服务器运行在 http://${HOST}:${PORT}`);
  console.log(`📱 API地址: http://${HOST}:${PORT}/api`);
  console.log(`🔌 WebSocket服务已启动`);
});

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
