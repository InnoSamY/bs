const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
  username: {
    type: String,
    required: [true, '用户名不能为空'],
    unique: true,
    trim: true,
    minlength: [3, '用户名至少3个字符'],
    maxlength: [20, '用户名最多20个字符']
  },
  password: {
    type: String,
    required: [true, '密码不能为空'],
    minlength: [6, '密码至少6个字符']
  },
  avatar: {
    type: String,
    default: null
  },
  bio: {
    type: String,
    default: '',
    maxlength: [200, '个性签名最多200个字符']
  },
  publicKey: {
    type: String,
    required: [true, '公钥不能为空']
  },
  lastLoginAt: {
    type: Date,
    default: null
  },
  isActive: {
    type: Boolean,
    default: true
  }
}, {
  timestamps: true, // 自动添加 createdAt 和 updatedAt
  toJSON: {
    transform: function(doc, ret) {
      delete ret.password; // 返回JSON时不包含密码
      delete ret.__v;
      return ret;
    }
  }
});

// 索引优化
userSchema.index({ username: 1 });
userSchema.index({ createdAt: -1 });

module.exports = mongoose.model('User', userSchema);
