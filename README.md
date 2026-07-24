# moonbitGEODB

一个基于 [MoonBit](https://moonbitlang.com/) 编写的地理信息数据库，专门用于存储、解析、检索中国地址信息。

## 特性

- **地址解析**：支持多格式地址字符串解析，特别是针对中文地址（如"北京市海淀区颐和园路5号"）的智能行政区划识别
- **地理运算**：内置 Haversine 距离计算、方位角计算、边界框（BBox）操作
- **空间索引**：基于网格的空间索引，高效进行范围查询和最近邻搜索
- **名称索引**：支持精确匹配、前缀匹配、子串匹配的名称查找
- **持久化存储**：
  - 原子写入（先写 `.tmp` 再重命名），防止数据损坏
  - JSON 快照格式（含元数据、版本号、时间戳）
  - 自动备份与恢复机制
  - 数据库完整性检查
- **随机数据生成**：内置中国地址生成器，可快速填充测试数据
- **原生文件 IO**：通过 C FFI 实现高性能的文件读写

## 模块架构

```
moonbitGEODB/
├── lib/
│   ├── types/        # 核心类型定义 (GeoPoint, Address, GeoEntry, BBox)
│   ├── geo/          # 地理数学运算 (Haversine 距离, BBox)
│   ├── parser/       # 地址解析器 (多格式解析, 中文行政区划识别)
│   ├── index/        # 空间索引 (网格索引, 名称索引)
│   ├── persist/      # 持久化 (JSON 序列化, 原子保存, 备份)
│   ├── gen/          # 随机中国地址生成器
│   └── db/           # 主数据库 API (GeoDB)
└── cmd/              # 命令行接口
```

### 核心模块说明

| 模块 | 说明 |
|------|------|
| **types** | 定义 `GeoPoint`（地理坐标点）、`Address`（结构化地址）、`GeoEntry`（数据库条目）、`BBox`（边界框）等核心数据类型 |
| **geo** | 实现 Haversine 公式计算两点间球面距离、BBox 构造与查询等地理运算 |
| **parser** | 支持逗号分隔、制表符分隔、中文行政区划等多种地址格式的解析 |
| **index** | 基于网格的空间索引加速 BBox 查询；基于 HashMap 的名称索引支持多种查找方式 |
| **persist** | 通过 C FFI 实现跨平台文件 IO；JSON 序列化/反序列化；原子写入确保数据安全 |
| **gen** | 包含 37 个主要中国城市（含真实坐标）、街道名、门牌号的随机地址生成器 |
| **db** | 提供完整的数据库操作 API：增删改查、空间查询、持久化、备份恢复 |

## 构建与运行

### 环境要求

- MoonBit 编译器
- GCC 编译器（用于 C FFI 链接）
- Linux/Unix 环境（用于文件系统操作）

### 构建

```bash
# 设置链接器路径（解决 pthread 和 libc 找不到的问题）
export LIBRARY_PATH=/usr/lib64

# 强制使用 GCC 而非 tcc（推荐）
export MOON_CC=gcc

# 构建项目
moon build

# 运行测试
moon test
```

### 运行 CLI

```bash
# 运行默认演示
moon run cmd

# 解析并存储地址
moon run cmd "北京市海淀区颐和园路5号"

# 搜索关键字
moon run cmd search "颐和园"

# 附近查找
moon run cmd nearby 39.9 116.4 5

# 生成随机地址（默认 100 条）
moon run cmd seed

# 生成 500 条随机地址
moon run cmd seed 500

# 保存数据库到文件
moon run cmd save geo.db

# 从文件加载数据库
moon run cmd load geo.db

# 创建备份
moon run cmd backup geo.db

# 完整性检查
moon run cmd check geo.db

# 查看数据库信息
moon run cmd info geo.db
```

## 快速开始

### CLI 示例：存储、解析、检索北京地址

```bash
# 解析并存储"北京市海淀区颐和园路5号"
moon run cmd "北京市海淀区颐和园路5号"

# 输出示例：
# [STORED] id=e0, name=颐和园路5号
#          location: (39.9999, 116.2755)
#          address:  中国,北京市,北京市,海淀区,颐和园路,5号
```

### 编程 API 使用

```moonbit
// 创建内存数据库
let db = @db.GeoDB::in_memory()

// 插入条目（自动解析地址字符串）
let entry = db.insert_raw(
  "yhy001",
  "颐和园",
  39.9999,
  116.2755,
  "北京市海淀区颐和园路5号"
)

// 按 ID 查找
match db.get("yhy001") {
  Some(e) => println(e.name)
  None => println("not found")
}

// 按名称查找
let results = db.find_by_name("颐和园")

// 按关键字模糊搜索
let results = db.find_name_contains("海淀")

// 附近查找（5 公里内）
let nearby = db.find_nearby(
  @types.GeoPoint::make(39.9999, 116.2755),
  radius_km=5.0,
  limit=10
)

// 保存到文件
ignore(db.save_to("geo.db"))

// 从文件加载
let loaded = @db.GeoDB::open("geo.db")
```

### 随机数据生成

```moonbit
// 生成 100 条随机中国地址
let entries = @gen.gen_batch(100)

// 预填充数据库
let db = @gen.gen_db(500)

// 也可以通过 CLI 生成并持久化
// moon run cmd seed 500  # 自动保存到 geo_seeded.db
```

## 持久化设计

### 文件格式

数据库以 JSON 格式存储，包含元数据快照：

```json
{
  "meta": {
    "version": 1,
    "created_at": 0,
    "updated_at": 0,
    "entry_count": 20
  },
  "entries": [
    {
      "id": "addr12345",
      "name": "颐和园",
      "address": {
        "country": "中国",
        "province": "北京市",
        "city": "北京市",
        "district": "海淀区",
        "street": "颐和园路5号",
        "postal_code": "100091",
        "detail": ""
      },
      "location": { "lat": 39.9999, "lng": 116.2755 },
      "tags": ["poi", "attraction"]
    }
  ]
}
```

### 数据安全策略

1. **原子写入**：保存时先写入 `.tmp` 临时文件，成功后再重命名为目标文件，避免中途崩溃导致数据损坏
2. **自动备份**：通过 `backup()` 方法创建 `.bak` 备份文件
3. **版本兼容**：支持从旧版格式（纯 JSON 数组）升级到新版格式（带元数据快照）
4. **完整性检查**：`check()` 方法验证 JSON 格式、必填字段、版本号

## 测试

```bash
# 运行所有测试（82 个测试用例）
moon test
```

测试覆盖：
- 类型构造与序列化
- 地理距离与 BBox 运算
- 地址解析（中文、英文、多格式）
- 空间索引与名称索引
- 数据库 CRUD 操作
- 持久化与恢复
- 随机地址生成器

## 许可证

Apache-2.0
