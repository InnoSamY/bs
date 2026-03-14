/**
 * 用户数据模型
 * 
 * 这个文件定义了用户在MongoDB数据库中的数据结构。
 * 使用Mongoose Schema来定义字段类型、验证规则和索引。
 * 
 * 数据模型作用：
 * 1. 定义用户数据的结构
 * 2. 设置字段验证规则
 * 3. 自动管理时间戳
 * 4. 提供数据转换方法
 * 
 * 示例文档：
 * {
 *   "_id": ObjectId("65a1b2c3d4e5f6789012345"),
 *   "username": "张三",
 *   "password": "$2b$10$...",  // bcrypt哈希后的密码
 *   "avatar": "https://example.com/avatar.jpg",
 *   "bio": "这是我的签名",
 *   "publicKey": "MIIBIjANBgkq...",
 *   "signaturePublicKey": "MIIBIjANBgkq...",
 *   "encryptionPublicKey": "MIIBIjANBgkq...",
 *   "lastLoginAt": ISODate("2024-01-01T00:00:00Z"),
 *   "isActive": true,
 *   "createdAt": ISODate("2024-01-01T00:00:00Z"),
 *   "updatedAt": ISODate("2024-01-01T00:00:00Z")
 * }
 */

// 导入Mongoose库
const mongoose = require('mongoose');

/**
 * 用户Schema定义
 * 
 * Schema是Mongoose中用于定义文档结构的对象。
 * 每个字段可以包含：
 * - type: 数据类型
 * - required: 是否必填
 * - unique: 是否唯一
 * - default: 默认值
 * - minlength/maxlength: 最小/最大长度
 * - trim: 是否去除首尾空格
 */
const userSchema = new mongoose.Schema({
  /**
   * 用户名字段
   * 
   * 用户注册时填写的名称，要求：
   * - 必填字段
   * - 在整个系统中唯一（不能重复）
   * - 长度限制：3-20个字符
   * - 自动去除首尾空格
   * 
   * 示例：'张三'、'alice123'
   */
  username: {
    type: String,                         // 字符串类型
    required: [true, '用户名不能为空'],    // 必填，错误消息
    unique: true,                         // 唯一索引，不能重复
    trim: true,                           // 自动去除首尾空格
    minlength: [3, '用户名至少3个字符'],   // 最小长度
    maxlength: [20, '用户名最多20个字符']  // 最大长度
  },
  
  /**
   * 密码字段
   * 
   * 存储用户的登录密码（已哈希处理）：
   * - 必填字段
   * - 最小长度6个字符
   * - 存储前会使用bcrypt进行哈希处理
   * - 返回JSON时自动删除此字段（安全考虑）
   * 
   * 安全说明：
   * - 不存储明文密码
   * - 使用bcrypt算法哈希
   * - 哈希后的密码长度约60个字符
   */
  password: {
    type: String,                         // 字符串类型
    required: [true, '密码不能为空'],      // 必填
    minlength: [6, '密码至少6个字符']      // 最小长度
  },
  
  /**
   * 头像URL字段
   * 
   * 用户头像的网络地址：
   * - 可选字段
   * - 默认值为null（表示使用默认头像）
   * - 可以是服务器上传的头像URL
   * - 也可以是第三方头像服务的URL
   * 
   * 示例：'https://example.com/avatars/user123.jpg'
   */
  avatar: {
    type: String,                         // 字符串类型
    default: null                         // 默认值为null
  },
  
  /**
   * 个性签名字段
   * 
   * 用户设置的个性签名：
   * - 可选字段
   * - 默认值为空字符串
   * - 最大长度200个字符
   * 
   * 示例：'今天天气真好！'
   */
  bio: {
    type: String,                         // 字符串类型
    default: '',                          // 默认值为空字符串
    maxlength: [200, '个性签名最多200个字符']  // 最大长度
  },
  
  /**
   * RSA公钥字段（兼容旧版本）
   * 
   * 用户的RSA公钥，用于加密通信：
   * - 必填字段
   * - 注册时由客户端生成
   * - 用于加密消息和验证签名
   * 
   * 注意：这是Base64编码的公钥字符串
   */
  publicKey: {
    type: String,                         // 字符串类型
    required: [true, '公钥不能为空']       // 必填
  },
  
  /**
   * ML-DSA签名公钥字段
   * 
   * 后量子数字签名公钥（ML-DSA/Dilithium）：
   * - 可选字段（向后兼容）
   * - 用于验证用户身份和消息签名
   * - 抗量子计算攻击
   * 
   * 工作原理：
   * 1. 用户注册时生成ML-DSA密钥对
   * 2. 公钥存储在服务器
   * 3. 发起通话时，用户用私钥签名
   * 4. 接收方用公钥验证签名
   */
  signaturePublicKey: {
    type: String,                         // 字符串类型
    default: null                         // 默认值为null
  },
  
  /**
   * ML-KEM加密公钥字段
   * 
   * 后量子密钥封装公钥（ML-KEM/Kyber）：
   * - 可选字段（向后兼容）
   * - 用于密钥交换和消息加密
   * - 抗量子计算攻击
   * 
   * 工作原理：
   * 1. 用户注册时生成ML-KEM密钥对
   * 2. 公钥存储在服务器
   * 3. 其他用户可以用公钥封装密钥
   * 4. 用户用私钥解封装获得共享密钥
   */
  encryptionPublicKey: {
    type: String,                         // 字符串类型
    default: null                         // 默认值为null
  },
  
  /**
   * 最后登录时间字段
   * 
   * 记录用户最后一次登录的时间：
   * - 可选字段
   * - 每次登录时更新
   * - 用于统计用户活跃度
   */
  lastLoginAt: {
    type: Date,                           // 日期类型
    default: null                         // 默认值为null
  },
  
  /**
   * 账户激活状态字段
   * 
   * 标记账户是否激活：
   * - 默认为true（激活状态）
   * - 可以用于禁用账户
   * - 禁用后用户无法登录
   */
  isActive: {
    type: Boolean,                        // 布尔类型
    default: true                         // 默认为true
  }
}, {
  /**
   * Schema选项
   */
  timestamps: true,                       // 自动添加createdAt和updatedAt字段
  
  /**
   * toJSON转换选项
   * 
   * 当文档转换为JSON时，自动：
   * 1. 删除password字段（安全考虑）
   * 2. 删除__v字段（版本号，不需要暴露）
   * 
   * 这样返回给客户端的数据不会包含敏感信息
   */
  toJSON: {
    transform: function(doc, ret) {
      delete ret.password;                // 删除密码字段
      delete ret.__v;                     // 删除版本号字段
      return ret;
    }
  }
});

/**
 * 创建索引
 * 
 * 索引用于提高查询性能：
 * - username索引：快速查找用户名
 * - createdAt索引：按注册时间排序
 * 
 * 注意：unique字段会自动创建索引
 */
userSchema.index({ username: 1 });        // 用户名升序索引
userSchema.index({ createdAt: -1 });      // 创建时间降序索引

/**
 * 导出User模型
 * 
 * 模型是操作数据库的接口：
 * - User.create(): 创建用户
 * - User.find(): 查找用户
 * - User.findById(): 根据ID查找
 * - User.findOne(): 查找单个用户
 * - User.findByIdAndUpdate(): 更新用户
 * - User.findByIdAndDelete(): 删除用户
 * 
 * 使用示例：
 * ```javascript
 * // 创建用户
 * const user = await User.create({
 *   username: '张三',
 *   password: 'hashedPassword',
 *   publicKey: '...'
 * });
 * 
 * // 查找用户
 * const user = await User.findOne({ username: '张三' });
 * 
 * // 更新用户
 * await User.findByIdAndUpdate(userId, { bio: '新签名' });
 * ```
 */
module.exports = mongoose.model('User', userSchema);
