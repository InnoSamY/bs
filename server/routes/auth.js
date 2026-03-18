/**
 * 认证路由模块
 * 
 * 这个文件处理所有与用户认证相关的API请求，包括：
 * - 用户注册（POST /api/auth/register）
 * - 用户登录（POST /api/auth/login）
 * - 获取当前用户信息（GET /api/auth/me）
 * - 更新用户资料（PUT /api/auth/profile）
 * - 修改密码（PUT /api/auth/password）
 * 
 * 技术栈：
 * - Express.js: Web框架
 * - bcryptjs: 密码哈希
 * - jsonwebtoken: JWT令牌生成和验证
 * - uuid: 生成唯一ID
 * 
 * 安全机制：
 * - 密码使用bcrypt哈希存储
 * - 使用JWT进行身份验证
 * - 中间件验证请求令牌
 * - 输入验证防止注入攻击
 */

// ==================== 导入依赖模块 ====================

const express = require('express');           // Express框架
const bcrypt = require('bcryptjs');         // 密码哈希库
const jwt = require('jsonwebtoken');        // JWT令牌库
const { v4: uuidv4 } = require('uuid');     // UUID生成器（备用）
const { User } = require('../models');      // 用户数据模型

// ==================== 创建路由实例 ====================

const router = express.Router();

// ==================== 配置常量 ====================

/**
 * JWT配置
 * 
 * JWT (JSON Web Token) 用于在用户登录后进行身份验证。
 * 每次API请求都需要携带令牌，服务器验证令牌的有效性。
 */
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key-change-in-production';  // JWT密钥
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '7d';  // 令牌有效期（7天）

/**
 * 生成JWT令牌
 * 
 * 用户登录或注册成功后，生成一个JWT令牌返回给客户端。
 * 客户端后续请求需要携带这个令牌进行身份验证。
 * 
 * 令牌包含的信息：
 * - userId: 用户ID（用于查询用户）
 * 
 * 参数：[userId] - 用户ID
 * 返回：JWT令牌字符串
 * 
 * 示例：'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'
 */
const generateToken = (userId) => {
  // 使用签名JWT_SECRET，过期时间为JWT_EXPIRES_IN
  return jwt.sign({ userId }, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
};

/**
 * JWT验证中间件
 * 
 * 这是一个Express中间件，用于保护需要登录才能访问的API。
 * 
 * 工作流程：
 * 1. 从请求头获取Authorization字段
 * 2. 提取Bearer令牌
 * 3. 验证令牌是否有效
 * 4. 查询用户是否存在
 * 5. 将用户信息添加到req对象
 * 6. 调用next()继续处理请求
 * 
 * 错误处理：
 * - 未提供令牌：返回401状态码
 * - 令牌无效：返回401状态码
 * - 令牌过期：返回401状态码
 * - 用户不存在：返回401状态码
 */
const authMiddleware = async (req, res, next) => {
  try {
    // 从请求头获取令牌（格式：Bearer <token>）
    const token = req.headers.authorization?.replace('Bearer ', '');
    
    // 检查是否提供了令牌
    if (!token) {
      return res.status(401).json({ success: false, message: '未提供认证令牌' });
    }

    // 验证令牌是否有效
    const decoded = jwt.verify(token, JWT_SECRET);
    
    // 根据令牌中的userId查询用户
    const user = await User.findById(decoded.userId);
    
    // 检查用户是否存在且处于激活状态
    if (!user || !user.isActive) {
      return res.status(401).json({ success: false, message: '用户不存在或已被禁用' });
    }

    // 将用户ID和用户对象添加到请求对象，供后续处理使用
    req.userId = user._id.toString();
    req.user = user;
    
    // 继续处理请求
    next();
  } catch (error) {
    // 处理不同的JWT错误
    if (error.name === 'JsonWebTokenError') {
      return res.status(401).json({ success: false, message: '无效的令牌' });
    }
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({ success: false, message: '令牌已过期' });
    }
    return res.status(500).json({ success: false, message: '认证失败', error: error.message });
  }
};

// ==================== API路由处理 ====================

/**
 * 用户注册接口
 * 
 * POST /api/auth/register
 * 
 * 创建新用户账号：
 * 1. 验证必填字段（用户名、密码、公钥）
 * 2. 检查用户名是否已存在
 * 3. 使用bcrypt哈希密码
 * 4. 创建用户记录
 * 5. 生成JWT令牌
 * 6. 返回用户信息和令牌
 * 
 * 请求体参数：
 * - username: 用户名（3-20个字符，唯一）
 * - password: 密码（至少6个字符）
 * - avatar: 头像URL（可选）
 * - bio: 个性签名（可选）
 * - publicKey: 加密公钥（必填）
 * 
 * 成功响应（201）：
 * {
 *   "success": true,
 *   "message": "注册成功",
 *   "data": {
 *     "id": "用户ID",
 *     "username": "用户名",
 *     "avatar": "头像URL",
 *     "bio": "个性签名",
 *     "publicKey": "公钥",
 *     "token": "JWT令牌"
 *   }
 * }
 * 
 * 错误响应：
 * - 400: 参数验证失败
 * - 409: 用户名已存在
 * - 500: 服务器内部错误
 */
router.post('/register', async (req, res) => {
  try {
    // 从请求体获取参数
    const { username, password, avatar, bio, publicKey, kemPublicKey, sigPublicKey } = req.body;

    // 验证必填字段
    if (!username || !password) {
      return res.status(400).json({
        success: false,
        message: '用户名和密码不能为空'
      });
    }

    // 检查用户名是否已存在（查询数据库）
    const existingUser = await User.findOne({ username });
    if (existingUser) {
      return res.status(409).json({
        success: false,
        message: '用户名已存在'
      });
    }

    // 使用bcrypt加密密码
    // bcrypt特点：
    // - 自动生成盐值（salt）
    // - 哈希过程较慢，防止暴力破解
    // - 每次哈希结果不同（因为盐值不同）
    const salt = await bcrypt.genSalt(10);  // 生成盐值（10轮）
    const hashedPassword = await bcrypt.hash(password, salt);  // 哈希密码

    // 创建新用户对象
    // 优先使用新的后量子公钥字段，兼容旧版本
    const user = new User({
      username,                              // 用户名
      password: hashedPassword,             // 哈希后的密码
      avatar: avatar || null,               // 头像（默认null）
      bio: bio || '',                       // 个性签名（默认空字符串）
      publicKey: publicKey || kemPublicKey || '',  // 兼容旧版本
      encryptionPublicKey: kemPublicKey,    // ML-KEM 公钥
      signaturePublicKey: sigPublicKey      // 签名公钥
    });

    // 保存到数据库
    await user.save();

    // 生成JWT令牌
    const token = generateToken(user._id);

    // 返回成功响应（不包含密码）
    res.status(201).json({
      success: true,
      message: '注册成功',
      data: {
        id: user._id.toString(),            // 用户ID
        username: user.username,            // 用户名
        avatar: user.avatar,               // 头像
        bio: user.bio,                     // 个性签名
        publicKey: user.publicKey,         // 公钥（兼容旧版本）
        kemPublicKey: user.encryptionPublicKey,  // ML-KEM 公钥
        sigPublicKey: user.signaturePublicKey,   // 签名公钥
        token                               // JWT令牌
      }
    });
  } catch (error) {
    // 记录错误日志
    console.error('注册错误:', error);
    
    // 返回错误响应
    res.status(500).json({
      success: false,
      message: '注册失败',
      error: error.message
    });
  }
});

/**
 * 用户登录接口
 * 
 * POST /api/auth/login
 * 
 * 用户登录流程：
 * 1. 验证必填字段（用户ID、密码）
 * 2. 通过用户ID查找用户
 * 3. 验证用户是否激活
 * 4. 验证密码是否正确
 * 5. 更新最后登录时间
 * 6. 生成JWT令牌
 * 7. 返回用户信息和令牌
 * 
 * 请求体参数：
 * - userId: 用户ID
 * - password: 密码
 * 
 * 成功响应（200）：
 * {
 *   "success": true,
 *   "message": "登录成功",
 *   "data": {
 *     "id": "用户ID",
 *     "username": "用户名",
 *     "avatar": "头像URL",
 *     "bio": "个性签名",
 *     "publicKey": "公钥",
 *     "token": "JWT令牌"
 *   }
 * }
 * 
 * 错误响应：
 * - 400: 参数验证失败
 * - 401: 用户ID或密码错误
 * - 500: 服务器内部错误
 */
router.post('/login', async (req, res) => {
  try {
    // 从请求体获取参数
    const { userId, password } = req.body;

    // 验证必填字段
    if (!userId || !password) {
      return res.status(400).json({
        success: false,
        message: '用户ID和密码不能为空'
      });
    }

    // 查找用户并更新登录时间
    // 使用findOneAndUpdate实现原子操作
    // 参数：
    // - 查询条件：用户ID且处于激活状态
    // - 更新内容：设置最后登录时间
    // - new: true 返回更新后的文档
    const user = await User.findOneAndUpdate(
      { _id: userId, isActive: true },     // 查询条件
      { $set: { lastLoginAt: new Date() } }, // 更新内容
      { new: true }                         // 返回更新后的文档
    );
    
    // 用户不存在
    if (!user) {
      return res.status(401).json({
        success: false,
        message: '用户ID或密码错误'
      });
    }

    // 验证密码
    // bcrypt.compare() 会自动处理盐值，直接比较明文和哈希
    const isValidPassword = await bcrypt.compare(password, user.password);
    
    // 密码错误
    if (!isValidPassword) {
      return res.status(401).json({
        success: false,
        message: '用户名或密码错误'
      });
    }

    // 生成JWT令牌
    const token = generateToken(user._id);

    // 返回成功响应
    res.json({
      success: true,
      message: '登录成功',
      data: {
        id: user._id.toString(),            // 用户ID
        username: user.username,            // 用户名
        avatar: user.avatar,               // 头像
        bio: user.bio,                     // 个性签名
        publicKey: user.publicKey,         // 公钥（兼容旧版本）
        kemPublicKey: user.encryptionPublicKey,  // ML-KEM 公钥
        sigPublicKey: user.signaturePublicKey,   // 签名公钥
        token                               // JWT令牌
      }
    });
  } catch (error) {
    // 记录详细错误日志（包含请求信息）
    console.error('登录错误:', {
      userId: userId,                      // 注意：不要记录密码
      error: error.message,
      stack: error.stack,
      timestamp: new Date().toISOString()
    });
    
    // 返回错误响应（开发环境返回详细错误）
    res.status(500).json({
      success: false,
      message: '登录失败',
      error: process.env.NODE_ENV === 'development' ? error.message : '服务器内部错误'
    });
  }
});

/**
 * 获取当前用户信息接口
 * 
 * GET /api/auth/me
 * 
 * 需要认证：使用authMiddleware中间件验证令牌
 * 
 * 此接口返回当前登录用户的完整信息（除了密码）。
 * 客户端可以使用此接口来刷新用户数据。
 * 
 * 请求头：
 * - Authorization: Bearer <token>
 * 
 * 成功响应（200）：
 * {
 *   "success": true,
 *   "data": {
 *     "id": "用户ID",
 *     "username": "用户名",
 *     "avatar": "头像URL",
 *     "bio": "个性签名",
 *     "publicKey": "公钥",
 *     "createdAt": "注册时间"
 *   }
 * }
 * 
 * 错误响应：
 * - 401: 未授权（令牌无效或过期）
 * - 500: 服务器内部错误
 */
router.get('/me', authMiddleware, async (req, res) => {
  try {
    // 通过中间件设置的req.user获取用户信息
    // 注意：由于User Schema的toJSON配置，password已被自动排除
    res.json({
      success: true,
      data: {
        id: req.user._id.toString(),       // 用户ID
        username: req.user.username,       // 用户名
        avatar: req.user.avatar,          // 头像
        bio: req.user.bio,                // 个性签名
        publicKey: req.user.publicKey,    // 公钥
        createdAt: req.user.createdAt     // 注册时间
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

/**
 * 更新用户资料接口
 * 
 * PUT /api/auth/profile
 * 
 * 需要认证：使用authMiddleware中间件验证令牌
 * 
 * 更新当前登录用户的个人资料：
 * - 头像URL
 * - 个性签名
 * 
 * 请求头：
 * - Authorization: Bearer <token>
 * 
 * 请求体参数：
 * - avatar: 头像URL（可选）
 * - bio: 个性签名（可选）
 * 
 * 成功响应（200）：
 * {
 *   "success": true,
 *   "message": "更新成功",
 *   "data": {
 *     "id": "用户ID",
 *     "username": "用户名",
 *     "avatar": "头像URL",
 *     "bio": "个性签名",
 *     "publicKey": "公钥"
 *   }
 * }
 * 
 * 错误响应：
 * - 401: 未授权
 * - 500: 服务器内部错误
 */
router.put('/profile', authMiddleware, async (req, res) => {
  try {
    // 从请求体获取要更新的字段
    const { avatar, bio } = req.body;
    
    // 构建更新对象（只包含提供的字段）
    const updates = {};
    if (avatar !== undefined) updates.avatar = avatar;  // 如果提供了avatar，更新它
    if (bio !== undefined) updates.bio = bio;          // 如果提供了bio，更新它

    // 更新用户记录
    // 参数：
    // - 用户ID
    // - 更新内容
    // - new: true 返回更新后的文档
    // - runValidators: true 运行验证器
    const user = await User.findByIdAndUpdate(
      req.userId,                       // 用户ID（从中间件获取）
      updates,                          // 更新内容
      { new: true, runValidators: true } // 选项
    );

    // 返回更新后的用户信息
    res.json({
      success: true,
      message: '更新成功',
      data: {
        id: user._id.toString(),       // 用户ID
        username: user.username,       // 用户名（不变）
        avatar: user.avatar,           // 新头像
        bio: user.bio,                 // 新签名
        publicKey: user.publicKey      // 公钥（不变）
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

/**
 * 修改密码接口
 * 
 * PUT /api/auth/password
 * 
 * 需要认证：使用authMiddleware中间件验证令牌
 * 
 * 修改当前登录用户的密码：
 * 1. 验证旧密码
 * 2. 加密新密码
 * 3. 保存到数据库
 * 
 * 请求头：
 * - Authorization: Bearer <token>
 * 
 * 请求体参数：
 * - oldPassword: 旧密码（必填）
 * - newPassword: 新密码（必填，至少6个字符）
 * 
 * 成功响应（200）：
 * {
 *   "success": true,
 *   "message": "密码修改成功"
 * }
 * 
 * 错误响应：
 * - 400: 参数验证失败
 * - 401: 旧密码错误
 * - 500: 服务器内部错误
 */
router.put('/password', authMiddleware, async (req, res) => {
  try {
    // 从请求体获取参数
    const { oldPassword, newPassword } = req.body;

    // 验证必填字段
    if (!oldPassword || !newPassword) {
      return res.status(400).json({
        success: false,
        message: '旧密码和新密码不能为空'
      });
    }

    // 验证新密码长度
    if (newPassword.length < 6) {
      return res.status(400).json({
        success: false,
        message: '新密码至少6个字符'
      });
    }

    // 从数据库获取用户（需要完整的密码字段）
    const user = await User.findById(req.userId);
    
    // 验证旧密码
    const isValidPassword = await bcrypt.compare(oldPassword, user.password);
    
    // 旧密码错误
    if (!isValidPassword) {
      return res.status(401).json({
        success: false,
        message: '旧密码错误'
      });
    }

    // 加密新密码
    const salt = await bcrypt.genSalt(10);
    user.password = await bcrypt.hash(newPassword, salt);
    
    // 保存到数据库
    await user.save();

    // 返回成功响应
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

// ==================== 导出模块 ====================

/**
 * 导出路由模块
 * 
 * 在server.js中使用：
 * ```javascript
 * const authRoutes = require('./routes/auth');
 * app.use('/api/auth', authRoutes);
 * ```
 * 
 * 导出authMiddleware中间件供其他模块使用：
 * ```javascript
 * const { authMiddleware } = require('./routes/auth');
 * ```
 */
module.exports = router;
// 同时导出authMiddleware中间件，供其他路由使用（如video.js）
module.exports.authMiddleware = authMiddleware;
