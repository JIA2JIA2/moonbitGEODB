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
moon test   # 339/339 passed

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
- **语义地址匹配**：基于 **LightGBM 集成**（60 棵决策树，n_estimators=20×3 类，max_depth=6）的三层分类器（完全匹配/部分匹配/不匹配）。手工规则 OR-of-16 → 25 中间特征导出 → LightGBM 投票决策。在 20k 条真实中文地址标注语料上 **Agreement 75.90%**（96,423 query-candidate 对），吞吐量 ~18k pairs/s，比初始 66.98% 手工规则提升 **+8.92%**
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
| **parser** | 支持逗号分隔、制表符分隔、中文行政区划等多种地址格式的解析；核心模块 **`address_match.mbt`** 实现语义地址匹配器 — 25 维中间特征提取 + **LightGBM 集成**（60 棵树投票），在 96,423 对真实中文地址上 Agreement **75.90%**，可对数据库内地址做模糊语义检索 |
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
moon run cmd addr-feat-dump <path> 导出 25 维特征 TSV（用于 sklearn 重训）
moon run cmd corpus-db [N]         从真实地址语料构建空间 DB
```

### CLI 使用示例

#### 基础数据库操作

```bash
# 运行默认演示
moon run cmd

# 解析并存储地址
moon run cmd "北京市海淀区颐和园路5号"

# 搜索关键字
moon run cmd search "颐和园"

# 模糊搜索（最多 2 次编辑距离）
moon run cmd fuzzy "Yuan" 2

# 附近查找（5 公里内）
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

#### 语义地址匹配（真实 CLI 输出示例）

```bash
# Exact — suffix 统一化（幢↔栋、层↔楼 自动折叠）
$ moon run cmd addr-match \
    "北京市海淀区中关村南大街27号中央民族大学2号楼" \
    "北京市海淀区中关村南大街27号中央民族大学2栋"
  level: 完全匹配      score: 0.84  dice: 0.97  road: 1  num: 0.5

# Exact — 完整 POI + 门牌号 完全一致
$ moon run cmd addr-match \
    "陕西省西安市雁塔区小寨路街道长安中路100号赛高国际" \
    "陕西省西安市雁塔区小寨路街道长安中路100号赛高国际"
  level: 完全匹配      score: 0.75  dice: 1.00  road: 1  num: 1

# Partial — 同 POI 但楼层/房间号不同（26楼 vs 26层A）
$ moon run cmd addr-match \
    "汉中路180号星汉大厦26楼江苏东方燃油有限公司" \
    "汉中路180号星汉大厦26层A江苏东方燃油有限公司"
  level: 部分匹配      score: 0.84  dice: 0.97  road: 1  num: 1

# Partial — 同道路 + 同门牌段号，但建筑不同
$ moon run cmd addr-match \
    "上海市浦东新区世纪大道100号环球金融中心" \
    "上海市浦东新区世纪大道88号金茂大厦"
  level: 部分匹配      score: 0.56  dice: 0.67  road: 1  num: 0

# Partial — 同门牌号但跨城市同名 POI（LGBM 判 Partial 而非 None，
# 因为 road_b=1 + feature_recall=1.0 + admin_hit=0，属于典型"地名歧义"）
$ moon run cmd addr-match \
    "浙江省杭州市西湖区文三路90号东部软件园" \
    "江苏省南京市玄武区文三路90号东部软件园"
  level: 部分匹配      score: 0.65  dice: 0.43  road: 1  num: 1

# None — 完全不相关
$ moon run cmd addr-match \
    "北京市朝阳区建国门外大街1号国贸中心" \
    "广州市天河区天河路228号正佳广场"
  level: 不匹配        score: 0.00  dice: 0.00  road: 0  num: 0
```

#### 评测 + 调试

```bash
# 完整评测：混淆矩阵 + 三分类 F1
$ moon run cmd addr-eval testdata/data.txt 0
=== Address matcher evaluation ===
  Records: 20000  pairs: 96423
  Throughput: 18284 pairs/s
  Agreement: 75.90% (73187/96423)
  Confusion matrix (rows = gold, cols = pred):
                 完全匹配  部分匹配  不匹配
  完全匹配       948      2902      2157
  部分匹配       440     21305     10146
  不匹配         253      7338     50934

# 导出 25 维特征 TSV + score + gold，供 sklearn 重训
$ moon run cmd addr-feat-dump testdata/data.txt | head -3
dice  road_b  feat  name  admin_hit  road_hit  ...  score  gold
0.296  0.5    0     0     1          0        ...  0.204  2
0.143  0.5    0     0     0          0        ...  0.125  2
```

## 编程 API

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

### 语义地址匹配 API

```moonbit
// 基础用法 — 直接拿 MatchResult
let q = "汉中路180号星汉大厦26楼江苏东方燃油有限公司"
let c = "汉中路180号星汉大厦26层A江苏东方燃油有限公司"
let result = @parser.match_address(q, c)

match result.level {
  Exact   => println("完全匹配，score=" + result.score.to_string())
  Partial => println("部分匹配，dice="  + result.dice.to_string())
  None    => println("不匹配")
}
// result.dice        — 标准化字符串的 Dice 系数
// result.feature_recall, road_recall, num_recall — 三个手工核心指标

// 带特征导出 — 拿 MatchResult + FeatureBundle (25 维中间特征)
let (result2, feats) = @parser.match_address_ex(q, c)

// feats.dice, feats.road_b, feats.feature_recall, feats.admin_hit,
// feats.road_hit, feats.foreign_city, feats.feat_overlap,
// feats.house_missing, feats.veto, feats.main_hit ... 全部可读

// 地址文本标准化（公开 API）
let norm = @parser.normalize_address_text("北京市 海淀区 颐和园路5号 ")
// → "北京市海淀区颐和园路5号"（全角→半角、去标点、trim）

// MatchLevel 枚举工具
Exact.rank()    // 2
Partial.rank()  // 1
None.rank()     // 0
MatchLevel::from_label("完全匹配")  // → Exact
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

测试覆盖（**339 个测试**）：
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
- **匹配器特征调优**：调整 `address_match.mbt` 中 FeatureBundle 内的中间特征（如 `standalone_dice_threshold`、`context_dice_threshold` 等规则引擎阈值），dump 新特征后重训 LightGBM → 观察 addr-eval 效果

| 统计量 | 数值 |
|--------|------|
| query 数量 | 20,000 |
| 候选地址对 | **96,423** |
| **整体 Agreement** | **75.90%** (73,187/96,423) |
| **完全匹配 F1** | **24.79%** (Prec 57.8%, Rec 15.8%) |
| **部分匹配 F1** | **67.17%** (Prec 67.5%, Rec 66.8%) |
| **不匹配 F1** | **83.66%** (Prec 80.5%, Rec 87.0%) |
| 吞吐量 | ~18,280 pairs/s |
| 混淆矩阵 | 3×3 (Exact 948 / Partial 21,305 / None 50,934 正确) |

评测命令末尾自动输出三类典型错误样本 (gold=部分→None、gold=部分→完全、gold=不→完全) 供阈值调优参考。

### FeatureBundle 25 维中间特征

手工规则 OR-of-16 无法捕捉非线性特征交互（如 `road_b(0.23-0.50) + feat(≥0.30)` 应判 Partial 但规则漏判）。FeatureBundle 把所有中间计算结果导出给 sklearn/LightGBM：

| # | 字段 | 类型 | 含义 | LGBM 重要性 |
|---|------|------|------|------------|
| 0 | `dice` | Double | 标准化字符串 Dice 系数（2|A∩B|/(\|A\|+\|B\|)） | **0.12** |
| 1 | `road_b` | Double | 道路 token B 分数（匹配 + 加权） | **0.36**（最重要） |
| 2 | `feature_recall` | Double | POI/建筑名召回率 | **0.24** |
| 3 | `name_recall` | Double | 公司/机构名召回率 | 0.04 |
| 4 | `admin_hit` | Int | 行政区划 hit 数（省/市/区/街道） | — |
| 5 | `road_hit` | Int | 道路是否命中（0/1） | — |
| 6 | `town_hit` | Int | 乡镇/街道是否命中 | — |
| 7 | `context_ok` | Int | 上下文门控（admin + road 联合 OK） | — |
| 8 | `house_recall` | Double | 门牌号召回率 | 0.04 |
| 9 | `house_conflict` | Int | 门牌号冲突（同 road 不同 num → 1） | — |
| 10 | `veto` | Int | 硬 veto（道路冲突 + POI 不重叠 → 必 None） | — |
| 11 | `q_structured` | Int | query 是否含完整结构（省市区） | — |
| 12 | `c_structured` | Int | candidate 是否含完整结构 | — |
| 13 | `feat_overlap` | Int | POI 子串重叠（3+ chars 跨 token） | **0.04** |
| 14 | `weak_core_exact` | Int | 弱核心词精确匹配 | — |
| 15 | `fuzzy_poi_overlap` | Int | 模糊 POI 重叠（Dice ≥ 0.6） | — |
| 16 | `reverse_poi_overlap` | Int | 反向 POI 子串（candidate→query） | — |
| 17 | `road_conflict` | Int | 道路显式冲突（不同道路名同时存在） | — |
| 18 | `main_hit` | Int | 主干道 + 门牌号 + POI 三项核心全命中 | — |
| 19 | `house_missing` | Int | 一方有门牌号另一方没有 | — |
| 20 | `foreign_city` | Int | 双方属于不同城市（跨城标志） | — |
| 21 | `q_roads` | Int | query 中道路 token 数 | — |
| 22 | `c_roads` | Int | candidate 中道路 token 数 | — |
| 23 | `q_feats` | Int | query 中 POI token 数 | — |
| 24 | `c_feats` | Int | candidate 中 POI token 数 | — |
| 25 | `score` | Double | 手工规则输出的加权总分（仅作为调试参考） | — |

> **特征重要性 Top 3**：`road_b` (36%) → `feature_recall` (24%) → `dice` (12%)。这三个特征占 LightGBM 决策的 **72%**，而手工规则几乎不使用 `road_b` 的中间分数——这是 ML 能提升 7%+ 的核心原因。

### LightGBM 集成架构

```
                 25 维 FeatureBundle [Double/Int]
                          │
                          ▼
               ┌──────────────────────────────┐
               │  60 棵决策树（纯 MoonBit if-else）│
               │  n_estimators=20 × 3 classes  │
               │  max_depth=6, min_child_samples=50  │
               │  tree_idx → class: tree_idx % 3  │
               └──────────────────────────────┘
                │     │     │     │            │
                ▼     ▼     ▼     ▼            ▼
              tree0  tree1  tree2  tree3  ...  tree59
                │     │     │     │            │
              s0+L  s1+L  s2+L  s0+L       s2+L
                │     │     │     │            │
                └─────┴─────┴─────┴────────────┘
                              │
                              ▼
               ┌──────────────────────────────┐
               │  s0, s1, s2 (累加 raw score)  │
               │  argmax(s0, s1, s2)          │
               └──────────────────────────────┘
                     │       │       │
                   class0  class1  class2
                     │       │       │
                  Exact   Partial   None
```

每棵树遍历 root → leaf，leaf 保存一个 raw score（LightGBM 的 leaf value）。同一类的 20 棵树的 leaf value 累加到 `s0`/`s1`/`s2`，最终 argmax 决定 MatchLevel。

**关键设计**：
- **tree_idx % 3 映射**：LightGBM 原生用 "交替并行树"（num_parallel_tree=3），第 i 棵树专属于第 `i % 3` 个类。实测 Python MoonBit 逐行一致（diff=0.0）
- **纯 MoonBit if-else**：每棵树被展开为嵌套 if-else 比较，无运行时依赖。60 棵树 / 1860 个 leaf → 7527 行代码
- **吞吐**：~18,266 pairs/s（规则单用 ~24k，LGBM 慢 ~24%，换 +6.79% 准确性）

### 优化历程

三轮优化将 Agreement 从 66.98% 提升到 **75.90%**（**+8.92%，多判对 6,553 对**）：

**第一轮（阈值调优）**：加强 E1 上下文门控、E2 dice 0.15→0.35、P7 新增 house_conflict 分支、降低 P1b/P6/P7 dice 阈值。消除了 1,018 个 P→Exact 误报。Agreement → **68.37% (+1.39%)**。

**第二轮（结构改进 + Tokenizer 修复）**：
- `normalize_address_text` 新增 suffix 统一化：幢→栋、层→楼、弄→号、座→栋
- `floor_ok` 严格化：query 有楼层/房间号而 candidate 没有时不再判 Exact
- POI 子串匹配增强 `feat_overlap`：跨 token 边界的 3+ chars core 匹配
- Tokenizer greedy scan via `codes_to_string_free` 修复：跳过已消费的数字 span，不再把 "25栋2楼" 吞进 POI 长 token
- Partial TP 从 14,485 升至 **17,022**（+17%）
- Grid search 调优：P6→0.41, P8→0.36。Agreement → **69.11% (+2.13%)**。

**第三轮（ML 集成，最大跃升 +6.79%）**：
- **FeatureBundle**：25 维中间特征导出给外部分类器（dice, road_b, feature, name, admin_hit, road_hit, town_hit, context_ok, house, house_conflict, veto, q_structured, c_structured, feat_overlap, weak_core_exact, fuzzy_poi_overlap, reverse_poi_overlap, road_conflict, main_hit, house_missing, foreign_city, q/c_roads, q/c_feats 等）
- **sklearn Decision Tree 基线**：depth=20, 999 节点，full-data **75.89%**。手工规则 OR-of-16 完全无法捕捉 `road_b(0.23-0.50) + feat(≥0.30)` 这种非线性特征交互（road_b 特征重要性 34%，手工规则几乎不使用）
- **LightGBM 最终方案**：n_estimators=20, max_depth=6, lr=0.3, min_child_samples=50, 60 棵树，7527 行 MoonBit if-else 代码。5-split honest test **75.21% ± 0.41%**，比单树稳定 +0.79%
- Full-data 最终 Agreement **75.90%**（LGBM 75.90 vs 单树 75.89 微涨，但泛化更好）

**Honest train/test split 对比**：

| 模型 | Holdout Accuracy | 实现复杂度 |
|------|-----------------|-----------|
| 手工 OR-of-16-rules | ~69% | 2000 行启发式 |
| 最佳单 Decision Tree (depth 20) | **74.41% ± 0.29%** | 1996 行 if-else |
| **LightGBM (20×3, d=6, lr=0.3)** | **75.21% ± 0.41%** | 7527 行 if-else |
| Random Forest (500, d=15) | 76.23% | 500+ 棵树，不可嵌入 |
| XGBoost / LightGBM (大集成) | 76.6% | 1000+ 棵树，不可嵌入 |

## 许可证

Apache-2.0
