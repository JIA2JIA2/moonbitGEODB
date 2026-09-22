# moonbitGEODB

一个基于 [MoonBit](https://moonbitlang.com/) 编写的地理信息数据库，专门用于存储、解析、检索中国地址信息。

## 快速开始

```bash
# 一键演示 61 POI（13 城市簇）+ 全部核心功能
moon run cmd demo

# 语义地址匹配（20k 真实地址评测语料）
moon run cmd addr-match "汉中路180号星汉大厦26楼江苏东方燃油有限公司" "汉中路180号星汉大厦26层A江苏东方燃油有限公司"
moon run cmd addr-eval testdata/data.txt 0          # 全量 20k × 5 candidates 评测
moon run cmd corpus-db 500                          # 从真实语料构建空间 DB

# 性能基准（默认 1000，可指定 10000 等更大规模）
moon run cmd benchmark 10000

# 完整测试套件
moon test   # 340/340 passed

# 高级空间分析示例
moon run cmd kmeans 3                      # K-Means 聚类（3 大宏观区域）
moon run cmd dbscan 50.0 3                 # DBSCAN 密度聚类（自动识别 13 城市簇）
moon run cmd tsp-2opt bj-gugong            # TSP + 2-opt 路线优化
moon run cmd idw 35.0 115.0 2.0            # IDW 空间插值
moon run cmd kriging 35.0 115.0 12         # Kriging 克里金插值
moon run cmd concave-hull 1.5              # 凹包 (Alpha-Shape)
moon run cmd moran-i-knn                   # Moran's I (KNN 权重)
moon run cmd sde                           # 标准差椭圆
```

`demo` 命令在 61 POI 样本库上依次演示：按 ID/名称检索 → 附近查询 → K-Means 宏观分区 → **DBSCAN 城市簇识别（13 簇 + 3 远郊噪声点）** → 标准差椭圆 → TSP NN+2-opt（节省约 265 km）→ IDW/Kriging 插值 → 凹包 → 中文地址解析。

## 特性

- **地址解析**：支持多格式地址字符串解析，特别是针对中文地址（如"北京市海淀区颐和园路5号"）的智能行政区划识别
- **语义地址匹配**：基于特征提取 + Dice 系数 + 启发式规则的三层分类器（完全匹配/部分匹配/不匹配），在 20k 条真实中文地址标注语料上评测，吞吐量 ~24k pairs/s
- **地理运算**：内置 Haversine 距离计算、方位角计算、边界框（BBox）操作
- **空间索引**：基于网格的空间索引（BBox 范围查询）与 R-tree（亚线性的 k 最近邻搜索与范围查询）
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

- **DBSCAN 密度聚类**：R-tree 加速的密度聚类，自动识别空间簇和噪声点
- **K-Means 聚类**：Forgy 初始化 + Haversine 距离，确定性结果
- **Elbow 方法**：自动跑 k=1..N 计算 WCSS，辅助选最佳 k
- **标准差椭圆 (SDE)**：量化方向趋势和离散度（长轴/短轴/旋转角/偏心率）
- **TSP 最近邻路由 + 2-opt 优化**：贪心启发式 + 边交换改进，通常再省 3-10% 路程
- **IDW 空间插值**：反距离加权从已知点估算任意位置值（支持全量和 KNN 两种模式）
- **Kriging 克里金插值**：基于变异函数建模的最优无偏空间插值（球状/指数/高斯模型 + 普通克里金 + KNN 加速）
- **凹包 (Alpha-Shape)**：基于 Delaunay 三角化的凹多边形边界，比凸包更贴合点云
- **Moran's I 空间自相关**：反距离加权 + 行标准化，正确落在 [-1,1]
- **多边形操作**：面积计算（鞋带公式）和点-in-多边形测试（射线法）
- **Geohash 编码/解码**：支持空间索引、前缀查询和邻域查询
- **坐标转换**：WGS84 ↔ GCJ-02（火星坐标）转换
- **凸包计算**：Andrew's monotone chain 算法
- **质心计算**：平面质心和球面地理中心（3D 投影法）
- **路径距离**：多点路径距离计算
- **径向密度分析**：同心圆区域分布统计
- **平均最近邻距离**：空间分布分析
- **热点分析**：Getis-Ord Gi* 热点/冷点检测
- **LISA**：Local Moran's I 局部聚类类型（HH/LL/HL/LH）
- **空间范围查询**：便利的 `find_bbox(min_lat, max_lat, min_lng, max_lng)` 直接调用
- **罗盘方向**：bearing → 16 方位名称

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

## 性能优化

本版本针对查询性能进行了多项优化：

| 方法 | 优化前 | 优化后 | 提升 |
|------|--------|--------|------|
| `find_in_ring` | O(n) 全扫描 + 每个 haversine | O(k) 用 bbox 候选集 + 精确过滤 | **10-100x** |
| `nearest_neighbors_range` | O(n) 全计算 + 排序 | O(log n) R-tree KNN | **100x+** |
| `tsp_nearest` | O(n²) 内部 O(n) 扫描 | O(n·log n) R-tree KNN + 跳过已访问 | **50x** |
| `tsp_2opt` | 内部 O(n²) 嵌套双循环 + 每候选 4 次 HashMap+haversine | 路线坐标/edge 邻接数组，d_before 零三角函数、零 HashMap | **10-30x** |
| `cluster_dbscan` (正确性) | 初始邻居未入去重集合 → 同一点重复入队、簇膨胀、额外扩张 | `clustered[]` 统一归属/去重，初始邻居先标记再入队 | 正确性 + **1.7x** 速度 |
| `spatial_join_nearest` | O(n·m) 双循环 | O(n·log m) 临时 R-tree | **50x** |
| `spatial_join_within` | O(n·m) 双循环 | O(n + k) bbox 候选集 + haversine 精炼 | **50x** |
| `spatial_join_knearest` | O(n·m·log m) 全距离排序 | O(n·log m) 临时 R-tree | **50x** |
| `cluster_dbscan` | O(n²) 每个点全扫描邻居 | O(n·k) coarse-grid 范围查询 | **10-100x** |
| **grid 层** | `HashMap[String]` 每次插值 + 单网格 | `HashMap[Int]` + **dual-grid** 细(0.1°)/粗(0.5°) 自适应选择 | **5-10x** |
| `bulk_insert` (insert 批量) | 每条目 HashMap 重复查找 + R-tree 逐步插入 | 一次性构建 + R-tree 集中插入 | **5-20x** |
| `morans_i_knn` | O(n²) 全 n×n 距离矩阵 | O(n·k·log n) 仅 k 最近邻 | **10x+ (大 n)** |
| `find_neighbors` | O(n log n) 全扫描 | O(log n) R-tree 最近邻 | 1000x+ |
| `find_sorted_by_distance` | O(n log n) 全扫描 | O(log n) R-tree 最近邻 | 1000x+ |
| `find_nearest_pairs` | O(n² log n²) 全对排序 | O(n log k) R-tree 分批 | 100x+ |
| `find_nearby` | O(m log m) 全排序 | O(m log k) 堆维护 | 大候选集显著 |
| `compute_bbox` | O(n) 每次 | O(1) 缓存 | 多次调用显著 |
| `voronoi` | O(n³) 每次 | O(n³) 缓存 | 2x+ |
| `voronoi_neighbors` | O(n³·\|a\|·\|b\|) | O(n³·(\|a\|+\|b\|)) | 邻居查询显著 |

**Benchmark 实测**（随机中国地址，单位：us。使用 `bulk_insert` 批量构建）：

| 操作 | 1k | 10k | 扩展趋势 | 实现 |
|------|-----|------|---------|------|
| **构建 DB** | **10,021** | **134,586** | ~O(n) ✓ | bulk_insert + dual-grid |
| 构建/条目 | 10.0 μs | 13.5 μs | 近常数 ✓ | |
| BBox 查询 | **6** | **42** | O(log n) ✓ | adaptive fine/coarse/R-tree |
| KNN (k=5) | **43** | **84** | O(log n) ✓ | R-tree best-first |
| Within 100km | 9 | 48 | 亚线性 ✓ | unsorted bbox → haversine |
| K-Means (k=3) | 4,380 | 109,800 | O(n·iters·k) | K-Means++ 初始化 |
| **DBSCAN (eps=50km)** | 7,372 | 237,038 | O(n·k) 扩张 | clustered[] 去重队列 |
| TSP 2-opt | **49,548** | **406,937** | O(n²·rounds)，实测亚线性 | edge 数组 + 0 HashMap |
| **Moran's I KNN** | 27,748 | 634,763 | **O(n·k·log n) ✓** | 真 R-tree KNN + 行标准化 |
| **Kriging (k=12)** | 8,184 | 40,882 | O(n·log n + k²) | R-tree KNN + 变异函数 |

运行命令：`moon run cmd benchmark [N]`（默认 N=1000）

**缓存策略**：
- `Index` 层：`compute_bbox` 和 `to_array` 结果在 `insert`/`remove` 时失效
- `GeoDB` 层：Voronoi 图结果在 `insert`/`remove` 时失效

**R-tree 索引**：
- 所有空间查询（`find_nearest`、`find_neighbors`、`find_nearby`、`find_nearest_pairs`）均通过 R-tree 加速
- 使用 best-first 搜索 + 弦距下界剪枝，结果精确但只访问部分子树

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
| **geo** | 实现 Haversine 公式、Geohash 编解码、WGS84↔GCJ-02 坐标转换、凸包计算、Voronoi 图（泰森多边形）、Moran's I 空间自相关、Getis-Ord Gi* 热点分析、LISA 局部聚类、多边形面积、点-in-多边形、径向密度等地理运算 |
| **parser** | 支持逗号分隔、制表符分隔、中文行政区划等多种地址格式的解析；新增**语义地址匹配器**（`address_match.mbt`）——基于特征提取+Dice系数+启发式规则，实现三层分类（完全匹配/部分匹配/不匹配），可对数据库内地址做模糊语义检索 |
| **index** | 网格空间索引加速 BBox 查询；R-tree（`rtree.mbt`）提供亚线性的 k 最近邻与范围查询；基于 HashMap 的名称/标签/地址索引 |
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
moon run cmd dbscan [eps_km] [min_points] DBSCAN 聚类（默认 50km / 3 点）
moon run cmd polygon <lat1>,<lng1> <lat2>,<lng2> ... 多边形操作
moon run cmd geohash-neighbors <hash> [precision] Geohash 邻域
moon run cmd radial-density <lat> <lng> <km> <rings> 径向密度
moon run cmd to-geojson-bbox [path] 带 BBox 的 GeoJSON
moon run cmd distance-histogram [bucket_size_km]  距离直方图
moon run cmd coord-histogram lat|lng [bucket_size] 坐标直方图
moon run cmd distance-summary                  距离统计摘要
moon run cmd kmeans <k> [max_iter]            K-Means 聚类
moon run cmd elbow [max_k]                     Elbow 方法选 k
moon run cmd centroid-all                      全局质心 + 地理中心
moon run cmd geographic-center                 球面地理中心
moon run cmd bbox-query <min_lat> <max_lat> <min_lng> <max_lng>  边界框查询
moon run cmd moran-i                           Moran's I 空间自相关
moon run cmd sde                               标准差椭圆
moon run cmd tsp <start_id>                    TSP 最近邻路由
moon run cmd tsp-2opt <start_id>               TSP + 2-opt 优化（再省 3-10%）
moon run cmd idw <lat> <lng> [power]           IDW 空间插值（反距离加权）
moon run cmd concave-hull <alpha>              凹包（Alpha-Shape），alpha=0 → 凸包
moon run cmd benchmark [N]                     性能基准测试（默认 1000）
moon run cmd demo                              一键演示（K-Means + SDE + TSP + IDW + 凹包）
moon run cmd moran-i-knn                       Moran's I（KNN 权重，比 O(n²) 快）
moon run cmd voronoi                     Voronoi 图（泰森多边形）
 moon run cmd voronoi-cell <id>           单个条目的 Voronoi 多边形
 moon run cmd voronoi-neighbors <id>      条目的 Voronoi 邻居
 moon run cmd delaunay                    Delaunay 三角剖分
 moon run cmd delaunay-edges              Delaunay 边（唯一）
moon run cmd morans-i-lat                  全局 Moran's I（纬度）
moon run cmd morans-i-lng                  全局 Moran's I（经度）
moon run cmd hotspot-lat                   Getis-Ord Gi* 热点/冷点（纬度）
moon run cmd hotspot-lng                   Getis-Ord Gi* 热点/冷点（经度）
moon run cmd lisa-lat                      局部 Moran's I LISA（纬度）
moon run cmd lisa-lng                      局部 Moran's I LISA（经度）
moon run cmd kriging <lat> <lng> [k]       Kriging 克里金插值
moon run cmd clear                 清空所有条目
moon run cmd help                  显示帮助
moon run cmd addr-match <q> <c>    语义地址匹配（查询 vs 候选）
moon run cmd addr-eval <path> [N]  评测地址匹配器（JSONL 语料）
moon run cmd corpus-db [N]         从真实地址语料构建空间 DB
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
  "bj-yiheyuan",
  "颐和园",
  39.9999,
  116.2755,
  "北京市海淀区颐和园路5号"
)

// 批量插入（比循环 insert 快 5-20 倍，50k 仅 ~1.1s）
db.bulk_insert([entry1, entry2, entry3])

// 按 ID 查找
match db.get("bj-yiheyuan") {
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

// DBSCAN 密度聚类（50km 邻域，至少 3 点成簇）
let clusters = db.cluster_dbscan(50.0, 3)

// Geohash 前缀查询
let results = db.find_by_geohash_prefix("wx4g0d", precision=6)

// 路径距离计算
let d = db.path_distance(["id1", "id2", "id3"])

// 分页查询
let page = db.page_all(limit=10, offset=0)

// 地址标准化
let ok = db.normalize_address("bj-yiheyuan")

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

// Voronoi 图（泰森多边形）
let cells = @geo.voronoi_diagram(points, bbox)

// 单个条目的 Voronoi 多边形
let poly = db.voronoi_cell("id1")

// Voronoi 邻居（共享边的条目）
let neighbors = db.voronoi_neighbors("id1")

// Delaunay 三角剖分（Voronoi 对偶）
let tris = db.delaunay()  // 返回三角形索引数组

// Delaunay 边（唯一）
let edges = db.delaunay_edges()

// 空间自相关：Moran's I 全局聚集度检验（纬度）
let moran = db.morans_i_on_lat()

// 热点分析：Getis-Ord Gi* 热点/冷点检测（经度）
let hotspots = db.getis_ord(vals, k = 5, threshold = 1.96)

// LISA：局部 Moran's I 聚类类型（HH/LL/HL/LH）
let lisa = db.lisa(vals, k = 5, threshold = 1.96)

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

// 性能优化示例：高效查询（O(log n) 通过 R-tree）
// 查找最近 10 个邻居（避免 O(n) 全扫描）
let neighbors = db.find_neighbors(target.location, 10)

// 查找半径内条目（堆维护，避免 O(m log m) 全排序）
let nearby = db.find_nearby(center, 5.0, limit=20)

// 查找最近点对（避免 O(n²) 全对计算）
let pairs = db.find_nearest_pairs(k=5)
```

### 随机数据生成

```moonbit
// 生成 100 条随机中国地址
let entries = @gen.gen_batch(100)

// 预填充数据库
let db = @gen.gen_db(500)

// 也可以通过 CLI 生成并持久化
// moon run cmd seed 500  # 自动保存到 testdata/geo_seeded.db
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

测试覆盖（**340 个测试**）：
- 类型构造与序列化
- 地理距离与 BBox 运算
- **K-Means / SDE / Moran's I / TSP / 2-opt / IDW / Concave Hull / Kriging** 高级算法
- Geohash 编解码与邻域查询
- WGS84 ↔ GCJ-02 坐标转换
- 凸包计算与多边形面积
- DBSCAN 密度聚类
- 径向密度分析
- 地址解析（中文、英文、多格式）
- **语义地址匹配（中文地址三层分类器）**
- 空间索引（R-tree + grid）与名称索引
- 数据库 CRUD 操作
- 标签查询与聚合
- 地理统计与分布
- 持久化与恢复
- 随机地址生成器
- 变异函数建模与普通克里金插值

## 测试数据

### 1. 内置精选演示数据集（61 个真实 POI）

`moon run cmd demo` 使用 `build_sample_db()` 内置 **61 个真实中国地标 POI**，按 13 个城市分组，天然具有城市级聚类结构，可直接验证 K-Means / DBSCAN / TSP / Moran's I：

| 城市 | POI 数 | 代表地标 |
|------|--------|----------|
| 北京 | 11 | 故宫、天安门、天坛、颐和园、八达岭、鸟巢、水立方、798 |
| 上海 | 8 | 东方明珠、外滩、豫园、南京路、迪士尼、上海中心 |
| 广州 | 5 | 广州塔、陈家祠、越秀公园、白云山、沙面 |
| 深圳 | 5 | 平安金融中心、世界之窗、欢乐谷、莲花山、大梅沙 |
| 成都 | 5 | 宽窄巷子、锦里、武侯祠、熊猫基地、都江堰 |
| 重庆 | 5 | 解放碑、洪崖洞、南山、磁器口、武隆 |
| 杭州 | 4 | 西湖、灵隐寺、西溪湿地、千岛湖 |
| 南京 | 3 | 中山陵、夫子庙、南京博物院 |
| 武汉 | 3 | 黄鹤楼、东湖、武汉大学 |
| 西安 | 3 | 大雁塔、兵马俑、西安城墙 |
| 天津 | 3 | 天津之眼、古文化街、五大道 |
| 青岛 | 3 | 栈桥、崂山、八大关 |
| 昆明 | 3 | 滇池、翠湖、西山 |

每条数据都包含 **id（城市前缀-地标拼音）、中文名、精确经纬度、完整中文地址**（精确到省/市/区/街道/门牌号）。

无需指定簇数，DBSCAN 可自动还原城市结构（3 个噪声点为距市中心 >50km 的千岛湖、武隆天生三桥、都江堰）：

```bash
$ moon run cmd dbscan 50.0 3
=== DBSCAN (eps=50km, min_points=3) ===
  Cluster #1 (3 POIs):     # 武汉
  Cluster #2 (11 POIs):    # 北京
  ...
  Cluster #13 (3 POIs):    # 昆明
  Clusters: 13  Noise: 3   # 58 + 3 = 61，全部点都有归属判定
  Noise points:
    - hz-qiandao (千岛湖)
    - cq-wulong (武隆天生三桥)
    - cd-dujiangyan (都江堰景区)
```

### 2. 随机地址生成器（347 城）

内置随机地址生成器覆盖 **347 个中国主要城市**（含直辖市、省会、地级市、台湾地区、港澳特别行政区），每个城市配备真实行政区划（区/县），可生成大规模性能测试数据：

| 类别 | 数量 | 示例 |
|------|------|------|
| 城市 | 347 | 北京、上海、广州、深圳、成都、武汉、西安、杭州、南京、重庆、天津、青岛、郑州、长沙、昆明、厦门、珠海、洛阳、保定、西宁、桂林、三亚、包头、徐州、南通、盐城、扬州、泰州、潍坊、临沂、济宁、德州、淄博、威海、泰安、滨州、菏泽、聊城、东营、襄阳、宜昌、荆州、十堰、黄冈、孝感、咸宁、恩施、株洲、湘潭、衡阳、邵阳、岳阳、常德、张家界、益阳、郴州、永州、怀化、娄底、柳州、梧州、北海、玉林、钦州、鞍山、抚顺、本溪、吉林、四平、齐齐哈尔、大庆、锦州、营口、辽阳、盘锦、铁岭、朝阳、葫芦岛、牡丹江、佳木斯、绥化、大同、运城、临汾、长治、咸阳、宝鸡、渭南、汉中、绵阳、德阳、宜宾、泸州、南充、丽江、大理、玉溪、曲靖、遵义、六盘水、安顺、芜湖、蚌埠、阜阳、马鞍山、安庆、赣州、九江、上饶、宜春、邯郸、廊坊、沧州、开封、新乡、南阳、商丘、长春、通化、延边、鸡西、吴忠、石嘴山、日喀则、林芝、昌都、那曲、海东、眉山、资阳、凉山、达州、广安、巴中、雅安、普洱、临沧、德宏、怒江、迪庆、红河、文山、楚雄、崇左、防城港、贵港、贺州、河池、来宾、朔州、阳泉、忻州、吕梁、晋中、榆林、延安、安康、商洛、毕节、铜仁、昭通、保山、巢湖、池州、宣城、新余、抚州、鹰潭、景德镇、萍乡、鹤壁、济源、三门峡、漯河、信阳、周口、驻马店、随州、仙桃、潜江、天门、神农架、儋州、文昌、万宁、东方、五指山、琼海、乐东、陵水、白沙、昌江、澄迈、临高、定安、屯昌、伊春、黑河、大兴安岭、莱州、滕州、玉树、果洛、海北、黄南、阿里、山南、吐鲁番、哈密、克拉玛依、阿克苏、喀什、和田、伊宁、塔城、阿勒泰、石河子、阿拉尔、图木舒克、北屯、双河、高雄、台北、台中、台南、基隆、新竹、嘉义、彰化、云林、南投、屏东、宜兰、花莲、台东、澎湖、金门、连江、香港、澳门、南沙、天水、庆阳、平凉、酒泉、张掖、武威、定西、陇南、临夏、甘南、嘉兴、湖州、绍兴、金华、衢州、台州、丽水、漳州、三明、南平、龙岩、宁德、惠州、汕头、江门、湛江、茂名、肇庆、揭阳、梅州、清远、潮州、云浮、张家口、承德、衡水、邢台、秦皇岛、辽源、白山、松原、白城、鄂尔多斯、呼伦贝尔、巴彦淖尔、乌兰察布、兴安盟、锡林郭勒、阿拉善盟、固原、中卫、亳州、宿州、六安、镇江、淮安、连云港、宿迁、莆田、黔东南、黔南、黔西南、铜川、渭南、延安、榆林、汉中、安康、商洛、海北、黄南、拉萨、日喀则、林芝、昌都、那曲、阿里、山南、吉林、四平、长春、通化、延边、石家庄、唐山、保定、邯郸、廊坊、沧州、广州、深圳、佛山、东莞、珠海、中山、乌鲁木齐、克拉玛依、吐鲁番、哈密、阿克苏、喀什、和田、伊宁、塔城、阿勒泰、石河子、阿拉尔、图木舒克、五家渠、北屯、双河、昆玉、西宁、海东、西安、铜川、宝鸡、咸阳、渭南、延安、汉中、榆林、安康、商洛、兰州、嘉峪关、金昌、白银、天水、武威、张掖、平凉、酒泉、庆阳、定西、陇南、临夏、甘南等 |
| 行政区划 | 每城市 4-10 个 | 海淀区、朝阳区、天河区、锦江区、武侯区等 |
| 地标/POI 名称 | 100+ | 颐和园、故宫、西湖、兵马俑、鼓浪屿、泰山、张家界等 |
| 街道名称 | 50+ | 中山路、人民路、解放路、幸福路等 |

运行 `moon run cmd seed 1000` 可快速生成 1000 条随机中国地址用于测试。

### 3. 真实地址评测语料库（20k 条）

`testdata/data.txt` 是一份包含 **20,000 条真实中文地址查询** 的标注语料库，每行 1 个 JSONL 记录，每条 query 配有 5 个人工标注的候选地址（完全匹配/部分匹配/不匹配），总共约 96k 对 query-candidate 对。用于：

- **评测语义地址匹配器**：`moon run cmd addr-eval testdata/data.txt 0` 输出混淆矩阵 + 各分类 precision/recall/F1
- **构建真实空间 DB**：`moon run cmd corpus-db 500` 取前 500 条记录，自动提取城市坐标，DBSCAN 聚类持久化到 `testdata/geo_corpus.db`
- **匹配器参数调优**：调整 `address_match.mbt` 中的阈值（`standalone_dice_threshold`、`context_dice_threshold` 等）后重新运行 addr-eval 观察效果

| 统计量 | 数值 |
|--------|------|
| query 数量 | 20,000 |
| 候选地址对 | ~96,400 |
| **整体 Agreement** | **68.37%** |
| **完全匹配 F1** | **21.19%** (Prec 20.8%, Rec 21.6%) |
| **部分匹配 F1** | **55.55%** (Prec 58.2%, Rec 53.1%) |
| **不匹配 F1** | **79.73%** (Prec 78.0%, Rec 81.2%) |
| 吞吐量 | ~23,500 pairs/s |
| 混淆矩阵 | 3×3 (Exact/Partial/None) |

评测命令末尾自动输出三类典型错误样本 (gold=部分→None、gold=部分→完全、gold=不→完全) 供阈值调优参考。

## 许可证

Apache-2.0
