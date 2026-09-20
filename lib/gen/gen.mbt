// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0
//
// Random Chinese address generator for seed/testing data.
// Produces plausible GeoEntry values with real-world city coordinates
// spread across major provinces/municipalities in China.

///|
/// Major cities with known coordinates: [name, province, lat, lng].
let cities : Array[Array[String]] = [
  ["北京", "北京市", "39.9042", "116.4074"],
  ["上海", "上海市", "31.2304", "121.4737"],
  ["天津", "天津市", "39.0842", "117.2009"],
  ["重庆", "重庆市", "29.4316", "106.9123"],
  ["广州", "广东省", "23.1291", "113.2644"],
  ["深圳", "广东省", "22.5431", "114.0579"],
  ["杭州", "浙江省", "30.2741", "120.1551"],
  ["南京", "江苏省", "32.0603", "118.7969"],
  ["苏州", "江苏省", "31.2989", "120.5853"],
  ["成都", "四川省", "30.5728", "104.0668"],
  ["武汉", "湖北省", "30.5928", "114.3055"],
  ["西安", "陕西省", "34.3416", "108.9398"],
  ["长沙", "湖南省", "28.2282", "112.9388"],
  ["青岛", "山东省", "36.0671", "120.3826"],
  ["济南", "山东省", "36.6512", "117.1201"],
  ["郑州", "河南省", "34.7466", "113.6254"],
  ["合肥", "安徽省", "31.8206", "117.2272"],
  ["福州", "福建省", "26.0745", "119.2965"],
  ["厦门", "福建省", "24.4798", "118.0894"],
  ["大连", "辽宁省", "38.9140", "121.6147"],
  ["沈阳", "辽宁省", "41.8057", "123.4315"],
  ["哈尔滨", "黑龙江省", "45.8038", "126.5349"],
  ["昆明", "云南省", "25.0389", "102.7183"],
  ["贵阳", "贵州省", "26.6470", "106.6302"],
  ["兰州", "甘肃省", "36.0611", "103.8343"],
  ["南宁", "广西壮族自治区", "22.8170", "108.3665"],
  ["海口", "海南省", "20.0442", "110.1999"],
  ["银川", "宁夏回族自治区", "38.4872", "106.2309"],
  ["乌鲁木齐", "新疆维吾尔自治区", "43.8256", "87.6168"],
  ["拉萨", "西藏自治区", "29.6500", "91.1000"],
  ["呼和浩特", "内蒙古自治区", "40.8424", "111.7492"],
  ["南昌", "江西省", "28.6820", "115.8579"],
  ["太原", "山西省", "37.8706", "112.5489"],
  ["石家庄", "河北省", "38.0428", "114.5149"],
  ["宁波", "浙江省", "29.8683", "121.5440"],
  ["温州", "浙江省", "27.9939", "120.6994"],
  ["佛山", "广东省", "23.0218", "113.1219"],
  ["东莞", "广东省", "23.0207", "113.7518"],
  ["珠海", "广东省", "22.2710", "113.5767"],
  ["中山", "广东省", "22.5176", "113.3928"],
  ["无锡", "江苏省", "31.4912", "120.3119"],
  ["常州", "江苏省", "31.8107", "119.9741"],
  ["烟台", "山东省", "37.4638", "121.4479"],
  ["泉州", "福建省", "24.8741", "118.6748"],
  ["洛阳", "河南省", "34.6197", "112.4540"],
  ["唐山", "河北省", "39.6305", "118.1802"],
  ["保定", "河北省", "38.8740", "115.4646"],
  ["西宁", "青海省", "36.6171", "101.7782"],
  ["桂林", "广西壮族自治区", "25.2345", "110.1800"],
  ["三亚", "海南省", "18.2528", "109.5120"],
  ["包头", "内蒙古自治区", "40.6574", "109.8404"],
  ["徐州", "江苏省", "34.2618", "117.1846"],
  ["南通", "江苏省", "31.9806", "120.8943"],
  ["盐城", "江苏省", "33.3474", "120.1636"],
  ["扬州", "江苏省", "32.3912", "119.4129"],
  ["泰州", "江苏省", "32.4840", "119.9229"],
  ["潍坊", "山东省", "36.7068", "119.1619"],
  ["临沂", "山东省", "35.1041", "118.3564"],
  ["济宁", "山东省", "35.4145", "116.5873"],
  ["德州", "山东省", "37.4539", "116.3573"],

]

///|
/// District/county names for each city, one array per city (aligned with
/// `cities` by index). This keeps generated districts consistent with the
/// randomly chosen city.
let city_districts : Array[Array[String]] = [
  ["东城区", "西城区", "朝阳区", "海淀区", "丰台区", "石景山区", "通州区", "昌平区", "大兴区", "顺义区"],
  ["黄浦区", "徐汇区", "长宁区", "静安区", "普陀区", "虹口区", "杨浦区", "浦东新区", "闵行区", "宝山区"],
  ["和平区", "河东区", "河西区", "南开区", "河北区", "红桥区", "滨海新区", "西青区", "津南区"],
  ["渝中区", "江北区", "沙坪坝区", "九龙坡区", "南岸区", "渝北区", "巴南区", "北碚区"],
  ["越秀区", "海珠区", "天河区", "白云区", "黄埔区", "番禺区", "花都区", "荔湾区"],
  ["福田区", "罗湖区", "南山区", "宝安区", "龙岗区", "龙华区", "盐田区", "坪山区"],
  ["西湖区", "上城区", "拱墅区", "滨江区", "萧山区", "余杭区", "临平区", "钱塘区"],
  ["玄武区", "秦淮区", "建邺区", "鼓楼区", "栖霞区", "雨花台区", "江宁区", "浦口区"],
  ["姑苏区", "虎丘区", "吴中区", "相城区", "吴江区", "工业园区", "高新区"],
  ["锦江区", "青羊区", "金牛区", "武侯区", "成华区", "龙泉驿区", "双流区", "温江区"],
  ["江岸区", "江汉区", "硚口区", "汉阳区", "武昌区", "青山区", "洪山区", "东西湖区"],
  ["新城区", "碑林区", "莲湖区", "灞桥区", "未央区", "雁塔区", "长安区", "临潼区"],
  ["芙蓉区", "天心区", "岳麓区", "开福区", "雨花区", "望城区", "长沙县"],
  ["市南区", "市北区", "黄岛区", "崂山区", "李沧区", "城阳区", "即墨区"],
  ["历下区", "市中区", "槐荫区", "天桥区", "历城区", "长清区", "章丘区"],
  ["中原区", "二七区", "管城回族区", "金水区", "上街区", "惠济区", "郑东新区"],
  ["庐阳区", "蜀山区", "包河区", "瑶海区", "滨湖新区", "经开区"],
  ["鼓楼区", "台江区", "仓山区", "马尾区", "晋安区", "长乐区"],
  ["思明区", "湖里区", "集美区", "海沧区", "同安区", "翔安区"],
  ["中山区", "西岗区", "沙河口区", "甘井子区", "旅顺口区", "金州区"],
  ["和平区", "沈河区", "大东区", "皇姑区", "铁西区", "浑南区", "于洪区"],
  ["道里区", "道外区", "南岗区", "香坊区", "平房区", "松北区"],
  ["五华区", "盘龙区", "官渡区", "西山区", "呈贡区", "晋宁区"],
  ["南明区", "云岩区", "花溪区", "乌当区", "白云区", "观山湖区"],
  ["城关区", "七里河区", "西固区", "安宁区", "红古区"],
  ["青秀区", "兴宁区", "江南区", "西乡塘区", "良庆区", "邕宁区"],
  ["秀英区", "龙华区", "琼山区", "美兰区"],
  ["兴庆区", "西夏区", "金凤区", "永宁县"],
  ["天山区", "沙依巴克区", "新市区", "水磨沟区", "头屯河区"],
  ["城关区", "堆龙德庆区", "达孜区"],
  ["新城区", "回民区", "玉泉区", "赛罕区"],
  ["东湖区", "西湖区", "青云谱区", "青山湖区", "新建区", "红谷滩区"],
  ["小店区", "迎泽区", "杏花岭区", "尖草坪区", "万柏林区", "晋源区"],
  ["长安区", "桥西区", "新华区", "裕华区", "藁城区", "鹿泉区"],
  ["海曙区", "江北区", "北仑区", "镇海区", "鄞州区", "奉化区"],
  ["鹿城区", "龙湾区", "瓯海区", "洞头区"],
  ["禅城区", "南海区", "顺德区", "高明区", "三水区"],
  ["莞城街道", "南城街道", "东城街道", "万江街道", "松山湖"],
  ["香洲区", "斗门区", "金湾区"],
  ["石岐街道", "东区街道", "西区街道", "南区街道"],
  ["梁溪区", "锡山区", "惠山区", "滨湖区", "新吴区"],
  ["天宁区", "钟楼区", "新北区", "武进区", "金坛区"],
  ["芝罘区", "福山区", "牟平区", "莱山区", "蓬莱区"],
  ["鲤城区", "丰泽区", "洛江区", "泉港区"],
  ["老城区", "西工区", "瀍河区", "涧西区", "洛龙区"],
  ["路南区", "路北区", "古冶区", "开平区", "丰南区"],
  ["竞秀区", "莲池区", "满城区", "清苑区", "徐水区"],
  ["城东区", "城中区", "城西区", "城北区", "湟中区"],
  ["秀峰区", "叠彩区", "象山区", "七星区", "雁山区", "临桂区"],
  ["海棠区", "吉阳区", "天涯区", "崖州区"],
  ["昆都仑区", "东河区", "青山区", "石拐区", "九原区", "白云鄂博矿区"],
  ["鼓楼区", "云龙区", "贾汪区", "泉山区", "铜山区"],
  ["崇川区", "通州区", "海门区", "如皋区", "启东区"],
  ["亭湖区", "盐都区", "大丰区", "响水县", "滨海县"],
  ["广陵区", "邗江区", "江都区", "仪征市", "高邮市"],
  ["海陵区", "高港区", "姜堰区", "兴化市", "靖江市"],
  ["潍城区", "寒亭区", "坊子区", "奎文区", "青州市"],
  ["兰山区", "罗庄区", "河东区", "沂南县", "郯城县"],
  ["任城区", "兖州区", "曲阜市", "邹城市", "微山县"],
  ["德城区", "陵城区", "乐陵市", "禹城市", "宁津县"],
]

///|
/// Street / road name patterns.
let street_groups : Array[Array[String]] = [
  ["中山路", "人民路", "建设路", "解放路", "和平路", "文化路"],
  [
    "中山大道", "人民大道", "建设大道", "解放大道", "光明大道",
  ],
  ["东大街", "西大街", "南大街", "北大街", "中心街", "商业街"],
  ["南京路", "北京路", "上海路", "广州路", "深圳路"],
  ["中山北路", "中山南路", "中山东路", "中山西路"],
  ["人民中路", "人民北路", "人民南路"],
  ["幸福路", "美满路", "和谐路", "平安路", "安康路"],
  ["南京东路", "南京西路", "淮海中路", "四川北路"],
]

///|
/// Building/house number suffixes.
let number_suffixes : Array[String] = [
  "1号", "2号", "3号", "5号", "8号", "10号", "12号", "15号", "18号", "20号",
  "25号", "28号", "30号", "32号", "35号", "38号", "40号", "45号", "48号",
  "50号", "55号", "58号", "60号", "66号", "68号", "70号", "75号", "80号",
  "85号", "88号", "90号", "95号", "98号", "100号", "108号", "118号", "120号",
  "128号", "138号", "150号", "168号", "188号", "200号",
]

///|
/// Landmark / POI name patterns.
let landmark_names : Array[String] = [
  "中心医院", "第一人民医院", "第二人民医院", "中医院", "妇幼保健院",
  "第一中学", "第二中学", "实验中学", "外国语学校", "附属中学",
  "实验小学", "育才小学", "阳光小学", "希望小学", "中心小学",
  "人民公园", "中山公园", "文化公园", "森林公园", "植物园", "动物园",
  "博物馆", "美术馆", "图书馆", "文化宫", "大剧院", "音乐厅", "体育馆",
  "体育场", "游泳馆", "万达广场", "购物中心", "百货商场", "超市",
  "便利店", "国际贸易中心", "会展中心", "展览中心", "健身中心",
  "火车站", "高铁站", "汽车站", "机场", "港口", "邮政局", "电信局",
  "移动营业厅", "银行", "工商银行", "建设银行", "农业银行", "中国银行",
  "招商银行", "交通银行", "大酒店", "宾馆", "旅馆", "招待所", "公寓",
  "写字楼", "办公楼", "商业大厦", "科技大厦", "金融中心", "高新技术开发区",
  "经济开发区", "工业园", "科技园", "软件园", "大学", "理工大学",
  "师范大学", "医科大学", "财经大学", "农业大学", "工业大学",
  "科技大学", "交通大学",
]

///|
/// Park/green space names.
let scenic_names : Array[String] = [
  "颐和园", "天坛公园", "故宫博物院", "天安门广场", "国家博物馆",
  "世纪坛", "奥林匹克公园", "鸟巢", "水立方", "圆明园", "北海公园",
  "景山公园", "香山公园", "玉渊潭公园", "紫竹院公园", "上海外滩",
  "东方明珠塔", "上海博物馆", "豫园", "陆家嘴金融中心", "广州塔",
  "白云山", "越秀公园", "陈家祠", "沙面岛", "深圳湾公园", "莲花山公园",
  "世界之窗", "欢乐谷", "西湖", "灵隐寺", "千岛湖", "西溪湿地",
  "宋城", "中山陵", "夫子庙", "玄武湖", "明孝陵", "紫金山", "黄鹤楼",
  "东湖", "湖北省博物馆", "归元寺", "大雁塔", "兵马俑博物馆",
  "华清池", "华山", "大熊猫基地", "武侯祠", "杜甫草堂", "锦里古街",
  "宽窄巷子", "鼓浪屿", "泰山", "崂山", "龙门石窟", "少林寺", "普陀山",
  "莫高窟", "长白山天池", "石林", "丽江古城", "张家界", "桂林山水",
  "阳朔西街", "呼伦贝尔草原", "天山天池", "布达拉宫", "羊卓雍错",
]

///|
/// Airport / station names.
let transport_names : Array[String] = [
  "首都国际机场", "大兴国际机场", "北京南站", "北京西站", "北京站",
  "浦东国际机场", "虹桥国际机场", "上海站", "上海南站", "白云国际机场",
  "深圳宝安国际机场", "广州南站", "深圳北站", "萧山国际机场",
  "杭州站", "杭州东站", "禄口国际机场", "南京站", "南京南站",
  "天府国际机场", "双流国际机场", "成都站", "成都东站", "新郑国际机场",
  "郑州站", "郑州东站", "天河国际机场", "武汉站", "武昌站", "咸阳国际机场",
  "西安站", "西安北站",
]

// ---- helpers ----

///|
fn pick_int(rand : @random.Rand, len : Int) -> Int {
  if len <= 0 {
    return 0
  }
  rand.int(limit=len)
}

///|
fn pick_str(rand : @random.Rand, arr : Array[String]) -> String {
  let i = pick_int(rand, arr.length())
  arr.get(i).unwrap_or("")
}

///|
fn pick_city_idx(rand : @random.Rand) -> Int {
  pick_int(rand, cities.length())
}

///|
fn gen_postal(rand : @random.Rand) -> String {
  let area = pick_int(rand, 9) + 1
  let rest = pick_int(rand, 100000)
  let n = rest + 100000
  "\{area}\{n.to_string().get_view(end=5).unwrap_or("00000")}"
}

///|
/// Generate a random GeoEntry with a Chinese address using a shared RNG.
fn gen_entry_with(
  rand : @random.Rand,
  id_prefix? : String = "addr",
) -> @types.GeoEntry {
  let city_idx = pick_city_idx(rand)
  let city_info = cities.get(city_idx).unwrap_or(["北京", "北京市", "39.9042", "116.4074"])
  let city_name = city_info.get(0).unwrap_or("北京")
  let province = city_info.get(1).unwrap_or("北京市")
  let base_lat = @string.parse_double(city_info.get(2).unwrap_or("39.9")) catch {
    _ => 39.9
  }
  let base_lng = @string.parse_double(city_info.get(3).unwrap_or("116.4")) catch {
    _ => 116.4
  }

  let r1 = rand.double() - 0.5
  let r2 = rand.double() - 0.5
  let lat = base_lat + r1 * 0.2
  let lng = base_lng + r2 * 0.2

  let district = pick_str(
    rand,
    city_districts.get(city_idx).unwrap_or(city_districts[0]),
  )

  let st_group = pick_int(rand, street_groups.length())
  let street = pick_str(
    rand,
    street_groups.get(st_group).unwrap_or(street_groups[0]),
  )

  let number = pick_str(rand, number_suffixes)
  let postal = gen_postal(rand)

  let all_names = landmark_names + scenic_names + transport_names
  let name = pick_str(rand, all_names)

  let address : @types.Address = {
    country: "中国",
    province,
    city: city_name,
    district,
    street: "\{street}\{number}",
    postal_code: postal,
    detail: "",
  }

  let id = "\{id_prefix}\{rand.int(limit=100000)}"

  let entry = @types.GeoEntry::make(
    id,
    name,
    address,
    @types.GeoPoint::make(lat, lng),
  )

  let type_tags = [
    "poi", "landmark", "transport", "medical", "education", "commercial", "residential",
  ]
  let cat_tags = [
    "attraction", "institution", "transport", "facility", "development",
  ]
  let tags = [pick_str(rand, type_tags), pick_str(rand, cat_tags)]
  entry.tags = tags

  entry
}

///|
/// Generate a random GeoEntry with a Chinese address (convenience, standalone RNG).
pub fn gen_entry(id_prefix? : String = "addr") -> @types.GeoEntry {
  let rand = @random.Rand::new()
  gen_entry_with(rand, id_prefix~)
}

///|
/// Number of cities available in the generator.
pub fn city_count() -> Int {
  cities.length()
}

///|
/// List of all province names available in the generator.
pub fn all_province_names() -> Array[String] {
  let out : Array[String] = []
  for c in cities {
    let prov = c.get(1).unwrap_or("")
    if prov.length() > 0 {
      out.push(prov)
    }
  }
  out
}

///|
/// Generate an array of N random Chinese address entries (shared RNG for diversity).
pub fn gen_batch(n : Int) -> Array[@types.GeoEntry] {
  let rand = @random.Rand::new()
  let out : Array[@types.GeoEntry] = []
  for _ in 0..<n {
    out.push(gen_entry_with(rand, id_prefix="addr"))
  }
  out
}

///|
/// Build a DB pre-seeded with N random Chinese addresses.
pub fn gen_db(n : Int) -> @db.GeoDB {
  let db = @db.GeoDB::in_memory()
  db.bulk_insert(gen_batch(n))
  db
}

// ---- tests ----

///|
test "gen_entry produces valid entry" {
  let e = gen_entry()
  @test.assert_eq(e.id.length() > 0, true)
  @test.assert_eq(e.name.length() > 0, true)
  @test.assert_eq(e.address.country, "中国")
  @test.assert_eq(e.address.province.length() > 0, true)
  @test.assert_eq(e.address.city.length() > 0, true)
  @test.assert_eq(e.location.lat > 10.0, true)
  @test.assert_eq(e.location.lat < 55.0, true)
  @test.assert_eq(e.location.lng > 70.0, true)
  @test.assert_eq(e.location.lng < 140.0, true)
  @test.assert_eq(e.tags.length() >= 2, true)
}

///|
test "gen_batch produces N entries" {
  let entries = gen_batch(10)
  @test.assert_eq(entries.length(), 10)
  for e in entries {
    @test.assert_eq(e.id.length() > 0, true)
  }
}

///|
test "gen_db creates in-memory DB with entries" {
  let db = gen_db(5)
  @test.assert_eq(db.size(), 5)
}

///|
test "gen_entry addresses are diverse" {
  let rand = @random.Rand::new()
  let seen_provinces : @hashmap.HashMap[String, Bool] = @hashmap.HashMap(
    [],
    capacity=32,
  )
  for _ in 0..<20 {
    let e = gen_entry_with(rand)
    seen_provinces[e.address.province] = true
  }
  @test.assert_eq(seen_provinces.length() >= 3, true)
}
///|
test "city_districts aligned with cities" {
  @test.assert_eq(city_districts.length(), cities.length())
  for ds in city_districts {
    @test.assert_eq(ds.length() > 0, true)
  }
}

///|
test "city_count matches cities array" {
  @test.assert_eq(city_count(), cities.length())
  @test.assert_eq(city_count() >= 40, true)
}
