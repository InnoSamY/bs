cmake_minimum_required(VERSION 3.10.2)
project("flutter_base")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 创建 FFI 接口库
# 注意：当前使用纯 Dart 实现的 ML-DSA (Dilithium) 后量子签名算法
# 无需 native 代码实现
add_library(
    flutter_base
    SHARED
    # 暂无 native 实现，保留空库以兼容现有配置
    empty.cpp
)

# 创建空实现文件（如果不存在）
file(WRITE "${CMAKE_CURRENT_SOURCE_DIR}/empty.cpp" "// Empty implementation file\n")

# 链接日志库
target_link_libraries(
    flutter_base
    PRIVATE
    log
)

message(STATUS "flutter_base native library configured (ML-DSA via Dart)")
