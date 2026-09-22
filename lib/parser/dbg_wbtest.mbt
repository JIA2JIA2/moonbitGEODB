// Temporary debug test
test "dbg tokens" {
  let pairs = [
    ("(汉中路180号星汉大厦26楼)江苏东方燃油有限公司", "汉中路180号星汉大厦26层A江苏东方燃油有限公司"),
    ("北京市东四环中路195号,华腾新天地5层", "东四环中路195号华腾新天地大厦"),
  ]
  for (q, c) in pairs {
    let tq = tokenize_address(normalize_address_text(q))
    let tc = tokenize_address(normalize_address_text(c))
    println("Q roads=\{tq.roads} towns=\{tq.towns} adm=\{tq.admins} feat=\{tq.features} names=\{tq.names} nums=\{tq.struct_nums} det=\{tq.detail_nums}")
    println("C roads=\{tc.roads} towns=\{tc.towns} adm=\{tc.admins} feat=\{tc.features} names=\{tc.names} nums=\{tc.struct_nums} det=\{tc.detail_nums}")
    println("---")
  }
}
