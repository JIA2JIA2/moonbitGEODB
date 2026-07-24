// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0
//
// Random Chinese address generator for seed/testing data.
// Produces plausible GeoEntry values with real-world city coordinates
// spread across major provinces/municipalities in China.

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
]

/// District/county names grouped by city.
let district_groups : Array[Array[String]] = [
  ["东城区", "西城区", "朝阳区", "海淀区", "丰台区", "石景山区"],
  ["黄浦区", "徐汇区", "长宁区", "静安区", "普陀区", "虹口区"],
  ["和平区", "河东区", "河西区", "南开区", "河北区", "红桥区"],
  ["渝中区", "江北区", "沙坪坝区", "九龙坡区", "南岸区"],
  ["越秀区", "海珠区", "天河区", "白云区", "黄埔区"],
  ["福田区", "罗湖区", "南山区", "宝安区", "龙岗区"],
]

/// Street / road name patterns.
let street_groups : Array[Array[String]] = [
  ["中山路", "人民路", "建设路", "解放路", "和平路", "文化路"],
  ["中山大道", "人民大道", "建设大道", "解放大道", "光明大道"],
  ["东大街", "西大街", "南大街", "北大街", "中心街", "商业街"],
  ["南京路", "北京路", "上海路", "广州路", "深圳路"],
  ["中山北路", "中山南路", "中山东路", "中山西路"],
  ["人民中路", "人民北路", "人民南路"],
  ["幸福路", "美满路", "和谐路", "平安路", "安康路"],
  ["南京东路", "南京西路", "淮海中路", "四川北路"],
]

/// Building/house number suffixes.
let number_suffixes : Array[String] = [
  "1号", "2号", "3号", "5号", "8号", "10号", "12号", "15号",
  "18号", "20号", "25号", "28号", "30号", "32号", "35号",
  "38号", "40号", "45号", "48号", "50号", "55号", "58号",
  "60号", "66号", "68号", "70号", "75号", "80号", "85号",
  "88号", "90号", "95号", "98号", "100号", "108号", "118号",
  "120号", "128号", "138号", "150号", "168号", "188号", "200号",
]

/// Landmark / POI name patterns.
let landmark_names : Array[String] = [
  "中心医院", "第一人民医院", "第二人民医院", "中医院", "妇幼保健院",
  "第一中学", "第二中学", "实验中学", "外国语学校", "附属中学",
  "实验小学", "育才小学", "阳光小学", "希望小学", "中心小学",
  "人民公园", "中山公园", "文化公园", "森林公园", "植物园",
  "动物园", "博物馆", "美术馆", "图书馆", "文化宫",
  "大剧院", "音乐厅", "体育馆", "体育场", "游泳馆",
  "万达广场", "购物中心", "百货商场", "超市", "便利店",
  "国际贸易中心", "会展中心", "展览中心", "健身中心",
  "火车站", "高铁站", "汽车站", "机场", "港口",
  "邮政局", "电信局", "移动营业厅", "银行", "工商银行",
  "建设银行", "农业银行", "中国银行", "招商银行", "交通银行",
  "大酒店", "宾馆", "旅馆", "招待所", "公寓",
  "写字楼", "办公楼", "商业大厦", "科技大厦", "金融中心",
  "高新技术开发区", "经济开发区", "工业园", "科技园", "软件园",
  "大学", "理工大学", "师范大学", "医科大学", "财经大学",
  "农业大学", "工业大学", "科技大学", "交通大学",
]

/// Park/green space names.
let scenic_names : Array[String] = [
  "颐和园", "天坛公园", "故宫博物院", "天安门广场", "国家博物馆",
  "世纪坛", "奥林匹克公园", "鸟巢", "水立方", "圆明园",
  "北海公园", "景山公园", "香山公园", "玉渊潭公园", "紫竹院公园",
  "上海外滩", "东方明珠塔", "上海博物馆", "豫园", "陆家嘴金融中心",
  "广州塔", "白云山", "越秀公园", "陈家祠", "沙面岛",
  "深圳湾公园", "莲花山公园", "世界之窗", "欢乐谷",
  "西湖", "灵隐寺", "千岛湖", "西溪湿地", "宋城",
  "中山陵", "夫子庙", "玄武湖", "明孝陵", "紫金山",
  "黄鹤楼", "东湖", "湖北省博物馆", "归元寺",
  "大雁塔", "兵马俑博物馆", "华清池", "华山",
  "大熊猫基地", "武侯祠", "杜甫草堂", "锦里古街", "宽窄巷子",
]

/// Airport / station names.
let transport_names : Array[String] = [
  "首都国际机场", "大兴国际机场", "北京南站", "北京西站", "北京站",
  "浦东国际机场", "虹桥国际机场", "上海站", "上海南站",
  "白云国际机场", "深圳宝安国际机场", "广州南站", "深圳北站",
  "萧山国际机场", "杭州站", "杭州东站",
  "禄口国际机场", "南京站", "南京南站",
  "天府国际机场", "双流国际机场", "成都站", "成都东站",
  "新郑国际机场", "郑州站", "郑州东站",
  "天河国际机场", "武汉站", "武昌站",
  "咸阳国际机场", "西安站", "西安北站",
]

// ---- helpers ----

fn pick_int(rand : @random.Rand, len : Int) -> Int {
  if len <= 0 { return 0 }
  rand.int(limit=len)
}

fn pick_str(rand : @random.Rand, arr : Array[String]) -> String {
  let i = pick_int(rand, arr.length())
  arr.get(i).unwrap_or("")
}

fn pick_city_entry(rand : @random.Rand) -> Array[String] {
  let i = pick_int(rand, cities.length())
  cities.get(i).unwrap_or(["北京", "北京市", "39.9042", "116.4074"])
}

fn gen_postal(rand : @random.Rand) -> String {
  let area = pick_int(rand, 9) + 1
  let rest = pick_int(rand, 100000)
  let n = rest + 100000
  "\{area}\{n.to_string().get_view(end=5).unwrap_or("00000")}"
}

/// Generate a random GeoEntry with a Chinese address using a shared RNG.
fn gen_entry_with(rand : @random.Rand, id_prefix~ : String = "addr") -> @types.GeoEntry {
  let city_info = pick_city_entry(rand)
  let city_name = city_info.get(0).unwrap_or("北京")
  let province = city_info.get(1).unwrap_or("北京市")
  let base_lat = try { @string.parse_double(city_info.get(2).unwrap_or("39.9")) } catch {
    _ => 39.9
  }
  let base_lng = try { @string.parse_double(city_info.get(3).unwrap_or("116.4")) } catch {
    _ => 116.4
  }

  let r1 = rand.double() - 0.5
  let r2 = rand.double() - 0.5
  let lat = base_lat + r1 * 0.2
  let lng = base_lng + r2 * 0.2

  let dist_group = pick_int(rand, district_groups.length())
  let district = pick_str(rand, district_groups.get(dist_group).unwrap_or(district_groups[0]))

  let st_group = pick_int(rand, street_groups.length())
  let street = pick_str(rand, street_groups.get(st_group).unwrap_or(street_groups[0]))

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

  let type_tags = ["poi", "landmark", "transport", "medical", "education", "commercial", "residential"]
  let cat_tags = ["attraction", "institution", "transport", "facility", "development"]
  let tags = [pick_str(rand, type_tags), pick_str(rand, cat_tags)]
  entry.tags = tags

  entry
}

/// Generate a random GeoEntry with a Chinese address (convenience, standalone RNG).
pub fn gen_entry(id_prefix~ : String = "addr") -> @types.GeoEntry {
  let rand = @random.Rand::new()
  gen_entry_with(rand, id_prefix=id_prefix)
}

/// Number of cities available in the generator.
pub fn city_count() -> Int {
  cities.length()
}

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

/// Generate an array of N random Chinese address entries (shared RNG for diversity).
pub fn gen_batch(n : Int) -> Array[@types.GeoEntry] {
  let rand = @random.Rand::new()
  let out : Array[@types.GeoEntry] = []
  for _ in 0..<n {
    out.push(gen_entry_with(rand, id_prefix="addr"))
  }
  out
}

/// Build a DB pre-seeded with N random Chinese addresses.
pub fn gen_db(n : Int) -> @db.GeoDB {
  let db = @db.GeoDB::in_memory()
  for e in gen_batch(n) {
    db.insert(e)
  }
  db
}

// ---- tests ----

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

test "gen_batch produces N entries" {
  let entries = gen_batch(10)
  @test.assert_eq(entries.length(), 10)
  for e in entries {
    @test.assert_eq(e.id.length() > 0, true)
  }
}

test "gen_db creates in-memory DB with entries" {
  let db = gen_db(5)
  @test.assert_eq(db.size(), 5)
}

test "gen_entry addresses are diverse" {
  let rand = @random.Rand::new()
  let seen_provinces : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([], capacity=32)
  for _ in 0..<20 {
    let e = gen_entry_with(rand)
    seen_provinces[e.address.province] = true
  }
  @test.assert_eq(seen_provinces.length() >= 3, true)
}
