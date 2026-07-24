# moonbitGEODB

一个基于 [MoonBit](https://moonbitlang.com/) 编写的地理信息数据库，专门用于存储、解析、检索中国地址信息。

## 特性

- **地址解析**：支持多格式地址字符串解析，特别是针对中文地址（如"北京市海淀区颐和园路5号"）的智能行政区划识别
- **地理运算**：内置 Haversine 距离计算、方位角计算、边界框（BBox）操作
- **空间索引**：基于网格的空间索引，高效进行范围查询和最近邻搜索
- **名称索引**：支持精确匹配、前缀匹配、子串匹配、通配符匹配的名称查找
- **模糊搜索**：基于 Levenshtein 编辑距离的名称模糊匹配
- **持久化存储**：
  - 纯二进制格式（大端字节序 + CRC32 校验）
  - 原子写入（先写 `.tmp` 再重命名），防止数据损坏
  - 自动备份与恢复机制
  - 数据库完整性检查
- **随机数据生成**：内置中国地址生成器，可快速填充测试数据
- **原生文件 IO**：通过 C FFI 实现高性能的文件读写

### 高级空间分析

- **DBSCAN 密度聚类**：自动识别空间簇和噪声点
- **多边形操作**：面积计算（鞋带公式）和点-in-多边形测试（射线法）
- **Geohash 编码/解码**：支持空间索引、前缀查询和邻域查询
- **坐标转换**：WGS84 ↔ GCJ-02（火星坐标）转换
- **凸包计算**：Andrew's monotone chain 算法
- **路径距离**：多点路径距离计算
- **径向密度分析**：同心圆区域分布统计
- **平均最近邻距离**：空间分布分析
- **分页支持**：大数据集的分页查询

### 数据导入/导出

- **CSV 导入/导出**：支持从 CSV 字符串导入数据
- **GeoJSON 导入/导出**：支持 GeoJSON 格式的导入导出
- **带 BBox 的 GeoJSON**：导出包含每个点的边界框信息
- **JSON 导出**：支持 JSON 格式导出

### 标签与聚合

- **标签查询**：单标签、多标签 AND/OR 逻辑查询
- **标签管理**：添加、删除标签
- **标签共现分析**：标签对分布统计
- **地理聚合**：区县分布、标签计数、省份直方图

### 其他功能

- **反向地理编码**：根据坐标查找最近条目
- **重复数据检测**：基于地理距离+名称相似度识别重复条目
- **空间网格聚类**：按网格单元聚合地理数据
- **距离矩阵**：计算多个地点间的两两距离
- **地址标准化**：自动去除行政区划名称后缀
- **地理围栏查询**：边界框内、距离范围内查询
- **空间范围查询**：半径范围内查询

## 模块架构

```
moonbitGEODB/
├── lib/
│   ├── types/        # 核心类型定义 (GeoPoint, Address, GeoEntry, BBox)
│   ├── geo/          # 地理数学运算 (Haversine, Geohash, 坐标转换, 凸包, 多边形)
│   ├── parser/       # 地址解析器 (多格式解析, 中文行政区划识别)
│   ├── index/        # 空间索引 (网格索引, 名称索引)
│   ├── persist/      # 持久化 (二进制编解码, 原子保存, 备份, FFI IO)
│   ├── gen/          # 随机中国地址生成器
│   └── db/           # 主数据库 API (GeoDB)
└── cmd/              # 命令行接口
```

### 核心模块说明

| 模块 | 说明 |
|------|------|
| **types** | 定义 `GeoPoint`（地理坐标点）、`Address`（结构化地址）、`GeoEntry`（数据库条目）、`BBox`（边界框）等核心数据类型 |
| **geo** | 实现 Haversine 公式、Geohash 编解码、WGS84↔GCJ-02 坐标转换、凸包计算、多边形面积、点-in-多边形、径向密度等地理运算 |
| **parser** | 支持逗号分隔、制表符分隔、中文行政区划等多种地址格式的解析 |
| **index** | 基于网格的空间索引加速 BBox 查询；基于 HashMap 的名称索引支持多种查找方式 |
| **persist** | 二进制编解码（codec.mbt）、GeoEntry 序列化（binary.mbt）、C FFI IO（persist_native.mbt）、原子写入与备份 |
| **gen** | 包含 37 个主要中国城市（含真实坐标）、街道名、门牌号的随机地址生成器 |
| **db** | 提供完整的数据库操作 API：增删改查、空间查询、标签聚合、持久化、备份恢复、高级分析 |

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

### CLI 命令参考

```
moon run cmd <address>              解析并存储地址
moon run cmd search <keyword>       按名称关键词搜索
moon run cmd fuzzy <kw> [max_dist]  模糊搜索（Levenshtein 距离）
moon run cmd nearby <lat> <lng> [km] 附近查找
moon run cmd within <lat> <lng> <km> 地理围栏查询
moon run cmd tag <tag>              按标签查找
moon run cmd tags                   列出所有标签
moon run cmd tag-all <t1> [t2 ...]  多标签 AND 查询
moon run cmd tag-any <t1> [t2 ...]  多标签 OR 查询
moon run cmd province <province>    按省份查找
moon run cmd city <city>            按城市查找
moon run cmd district <district>    按区县查找
moon run cmd stats                 地理统计
moon run cmd export [path]          导出 CSV
moon run cmd to-json [path]         导出 JSON
moon run cmd to-geojson [path]      导出 GeoJSON
moon run cmd add-tag <id> <tag>     添加标签
moon run cmd remove-tag <id> <tag>  删除标签
moon run cmd rename <id> <name>    重命名
moon run cmd update-coords <id> <lat> <lng>  更新坐标
moon run cmd seed [n]               生成随机地址（默认 100 条）
moon run cmd save <path>            保存数据库
moon run cmd load <path>            加载数据库
moon run cmd backup <path>          创建备份
moon run cmd check <path>           完整性检查
moon run cmd info <path>            查看数据库信息
moon run cmd pattern <pattern>      通配符搜索
moon run cmd distance <id1> <id2>   两点距离
moon run cmd neighbors <id> [k]    k 个最近邻
moon run cmd nearest-pairs [k]      k 对最近点
moon run cmd districts [province]   区县分布
moon run cmd tag-count <tag>       标签计数
moon run cmd tag-pairs              标签共现对
moon run cmd centroid <tag>        加权质心
moon run cmd import-csv <csv_str>  CSV 导入
moon run cmd import-geojson <gj_str> GeoJSON 导入
moon run cmd duplicates [dist] [edit] 重复检测
moon run cmd cluster [cell_size_km] 网格聚类
moon run cmd matrix <id1> [id2 ...] 距离矩阵
moon run cmd reverse-geocode <lat> <lng> 反向地理编码
moon run cmd dbscan <eps_km> <min_points> DBSCAN 聚类
moon run cmd polygon <lat1>,<lng1> <lat2>,<lng2> ... 多边形操作
moon run cmd geohash-neighbors <hash> [precision] Geohash 邻域
moon run cmd radial-density <lat> <lng> <km> <rings> 径向密度
moon run cmd to-geojson-bbox [path] 带 BBox 的 GeoJSON
moon run cmd clear                 清空所有条目
moon run cmd help                  显示帮助
```

### CLI 使用示例

```bash
# 运行默认演示
moon run cmd

# 解析并存储地址
moon run cmd "北京市海淀区颐和园路5号"

# 搜索关键字
moon run cmd search "颐和园"

# 模糊搜索（最多 2 次编辑距离）
moon run cmd fuzzy "Yuan" 2

# 附近查找
moon run cmd nearby 39.9 116.4 5

# 地理围栏查询
moon run cmd within 39.9 116.4 10

# 多标签 AND 查询
moon run cmd tag-all "poi" "attraction"

# 按省份查找
moon run cmd province "北京市"

# 生成 500 条随机地址
moon run cmd seed 500

# DBSCAN 聚类（1km 半径，最少 2 点成簇）
moon run cmd dbscan 1.0 2

# 多边形查询
moon run cmd polygon 0,0 0,1 1,1 1,0

# Geohash 邻域查询
moon run cmd geohash-neighbors wx4g0d 6

# 径向密度分析
moon run cmd radial-density 39.9 116.4 1.0 10

# 保存/加载数据库
moon run cmd save geo.db
moon run cmd load geo.db

# 完整性检查
moon run cmd check geo.db

# 数据导出
moon run cmd export output.csv
moon run cmd to-geojson output.json
```

## 快速开始

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

// DBSCAN 密度聚类
let clusters = db.cluster_dbscan(1.0, 2)

// Geohash 前缀查询
let results = db.find_by_geohash_prefix("wx4g0d", precision=6)

// 路径距离计算
let d = db.path_distance(["id1", "id2", "id3"])

// 分页查询
let page = db.page_all(limit=10, offset=0)

// 地址标准化
let ok = db.normalize_address("yhy001")

// 保存到文件
ignore(db.save_to("geo.db"))

// 从文件加载
let loaded = @db.GeoDB::open("geo.db")
```

### 高级 API 使用

```moonbit
// Geohash 编码/解码
let gh = @geo.geohash_encode(39.9087, 116.3975, 6)
let pt = @geo.geohash_decode(gh)

// Geohash 邻域（3×3 网格）
let neighbors = @geo.geohash_neighbors(gh)

// 坐标转换（WGS84 → GCJ-02）
let (gcj_lng, gcj_lat) = @geo.wgs84_to_gcj02(116.4, 39.9)

// 凸包计算
let hull = @geo.convex_hull(points)

// 多边形面积（km²）
let area = @geo.polygon_area(polygon_points)

// 点在多边形内测试
let inside = @geo.point_in_polygon(point, polygon)

// 平均最近邻距离
let avg_nn = @geo.average_nn_distance(points)

// 重复数据检测
let groups = db.find_duplicates(max_distance_km=0.1, max_edit_dist=2)

// 空间网格聚类
let clusters = db.cluster_by_grid(cell_size_km=1.0)

// 距离矩阵
let matrix = db.distance_matrix(["id1", "id2", "id3"])

// 径向密度分析
let rings = db.radial_density(center, ring_width_km=1.0, num_rings=10)

// 反向地理编码
match db.reverse_geocode(39.9, 116.4) {
  Some((entry, dist)) => println("Nearest: " + entry.name)
  None => println("Not found")
}
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

### 二进制文件格式

数据库采用纯二进制格式存储，由以下部分组成：

```
+------------------+
| File Header      |  魔数 ("GEO1") + 版本号 + 条目数 + 创建/更新时间戳
+------------------+
| Entry Block 0    |  条目长度 + CRC32 + 序列化数据
| Entry Block 1    |  ...
+------------------+
| ...              |
+------------------+
```

## 测试

```bash
# 运行所有测试
moon test
```

测试覆盖：
- 类型构造与序列化
- 地理距离与 BBox 运算
- Geohash 编解码与邻域查询
- WGS84 ↔ GCJ-02 坐标转换
- 凸包计算与多边形面积
- DBSCAN 密度聚类
- 径向密度分析
- 地址解析（中文、英文、多格式）
- 空间索引与名称索引
- 数据库 CRUD 操作
- 标签查询与聚合
- 地理统计与分布
- 持久化与恢复
- 随机地址生成器

## 许可证

Apache-2.0
