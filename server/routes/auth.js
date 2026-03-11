const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const { User } = require('../models');

const router = express.Router();

// JWT密钥
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key-change-in-production';
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '7d';

// 生成JWT令牌
const generateToken = (userId) => {
  return jwt.sign({ userId }, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
};

// 验证JWT令牌中间件
const authMiddleware = async (req, res, next) => {
  try {
    const token = req.headers.authorization?.replace('Bearer ', '');
    
    if (!token) {
      return res.status(401).json({ success: false, message: '未提供认证令牌' });
    }

    const decoded = jwt.verify(token, JWT_SECRET);
    const user = await User.findById(decoded.userId);
    
    if (!user || !user.isActive) {
      return res.status(401).json({ success: false, message: '用户不存在或已被禁用' });
    }

    req.userId = user._id.toString();
    req.user = user;
    next();
  } catch (error) {
    if (error.name === 'JsonWebTokenError') {
      return res.status(401).json({ success: false, message: '无效的令牌' });
    }
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({ success: false, message: '令牌已过期' });
    }
    return res.status(500).json({ success: false, message: '认证失败', error: error.message });
  }
};

// 用户注册
router.post('/register', async (req, res) => {
  try {
    const { username, password, avatar, bio, publicKey } = req.body;

    // 验证必填字段
    if (!username || !password || !publicKey) {
      return res.status(400).json({
        success: false,
        message: '用户名、密码和公钥不能为空'
      });
    }

    // 检查用户名是否已存在
    const existingUser = await User.findOne({ username });
    if (existingUser) {
      return res.status(409).json({
        success: false,
        message: '用户名已存在'
      });
    }

    // 加密密码
    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash(password, salt);

    // 创建新用户
    const user = new User({
      username,
      password: hashedPassword,
      avatar: avatar || null,
      bio: bio || '',
      publicKey
    });

    await user.save();

    // 生成令牌
    const token = generateToken(user._id);

    res.status(201).json({
      success: true,
      message: '注册成功',
      data: {
        id: user._id.toString(),
        username: user.username,
        avatar: user.avatar,
        bio: user.bio,
        publicKey: user.publicKey,
        token
      }
    });
  } catch (error) {
    console.error('注册错误:', error);
    res.status(500).json({
      success: false,
      message: '注册失败',
      error: error.message
    });
  }
});

// 用户登录
router.post('/login', async (req, res) => {
  try {
    const { userId, password } = req.body;

    // 验证必填字段
    if (!userId || !password) {
      return res.status(400).json({
        success: false,
        message: '用户ID和密码不能为空'
      });
    }

    // 查找用户（通过ID）并更新登录时间（原子操作）
    const user = await User.findOneAndUpdate(
      { _id: userId, isActive: true },
      { $set: { lastLoginAt: new Date() } },
      { new: true }
    );
    
    if (!user) {
      return res.status(401).json({
        success: false,
        message: '用户ID或密码错误'
      });
    }

    // 验证密码
    const isValidPassword = await bcrypt.compare(password, user.password);
    if (!isValidPassword) {
      return res.status(401).json({
        success: false,
        message: '用户名或密码错误'
      });
    }

    // 生成令牌
    const token = generateToken(user._id);

    res.json({
      success: true,
      message: '登录成功',
      data: {
        id: user._id.toString(),
        username: user.username,
        avatar: user.avatar,
        bio: user.bio,
        publicKey: user.publicKey,
        token
      }
    });
  } catch (error) {
    console.error('登录错误:', {
      userId: userId,
      error: error.message,
      stack: error.stack,
      timestamp: new Date().toISOString()
    });
    res.status(500).json({
      success: false,
      message: '登录失败',
      error: process.env.NODE_ENV === 'development' ? error.message : '服务器内部错误'
    });
  }
});

// 获取当前用户信息
router.get('/me', authMiddleware, async (req, res) => {
  try {
    res.json({
      success: true,
      data: {
        id: req.user._id.toString(),
        username: req.user.username,
        avatar: req.user.avatar,
        bio: req.user.bio,
        publicKey: req.user.publicKey,
        createdAt: req.user.createdAt
      }
    });
  } catch (error) {
    console.error('获取用户信息错误:', error);
    res.status(500).json({
      success: false,
      message: '获取用户信息失败',
      error: error.message
    });
  }
});

// 更新用户信息
router.put('/profile', authMiddleware, async (req, res) => {
  try {
    const { avatar, bio } = req.body;
    const updates = {};

    if (avatar !== undefined) updates.avatar = avatar;
    if (bio !== undefined) updates.bio = bio;

    const user = await User.findByIdAndUpdate(
      req.userId,
      updates,
      { new: true, runValidators: true }
    );

    res.json({
      success: true,
      message: '更新成功',
      data: {
        id: user._id.toString(),
        username: user.username,
        avatar: user.avatar,
        bio: user.bio,
        publicKey: user.publicKey
      }
    });
  } catch (error) {
    console.error('更新用户信息错误:', error);
    res.status(500).json({
      success: false,
      message: '更新失败',
      error: error.message
    });
  }
});

// 修改密码
router.put('/password', authMiddleware, async (req, res) => {
  try {
    const { oldPassword, newPassword } = req.body;

    if (!oldPassword || !newPassword) {
      return res.status(400).json({
        success: false,
        message: '旧密码和新密码不能为空'
      });
    }

    if (newPassword.length < 6) {
      return res.status(400).json({
        success: false,
        message: '新密码至少6个字符'
      });
    }

    // 验证旧密码
    const user = await User.findById(req.userId);
    const isValidPassword = await bcrypt.compare(oldPassword, user.password);
    
    if (!isValidPassword) {
      return res.status(401).json({
        success: false,
        message: '旧密码错误'
      });
    }

    // 加密新密码
    const salt = await bcrypt.genSalt(10);
    user.password = await bcrypt.hash(newPassword, salt);
    await user.save();

    res.json({
      success: true,
      message: '密码修改成功'
    });
  } catch (error) {
    console.error('修改密码错误:', error);
    res.status(500).json({
      success: false,
      message: '修改密码失败',
      error: error.message
    });
  }
});

module.exports = router;
module.exports.authMiddleware = authMiddleware;
