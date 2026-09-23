// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0
//
// Real-world Chinese address text matching.
//
// The corpus in testdata/data.txt contains ~20k records of messy,
// real-world Chinese address queries paired with candidate POI texts,
// each human-labelled as 完全匹配 (exact), 部分匹配 (partial) or
// 不匹配 (none).  This module provides a dependency-free heuristic
// scorer that reproduces those labels:
//
//   1. normalize: full-width digits/letters -> ASCII, Chinese numerals
//      in tokens -> Arabic digits, drop punctuation/whitespace;
//   2. extract a hierarchy of signal tokens from the text:
//        POI core    村/小区/大厦/广场/市场/公司/宾馆/山 ...  (strong)
//        township    街道/镇/乡/办事处                      (medium)
//        road        大道/路/街/国道/乡道 ... (+门牌号)     (medium)
//        bare name   leftover CJK run >= 4 chars           (strong)
//        admin only  省/市/区/县 ...                        (ignored)
//   3. score with character-bigram Sørensen-Dice plus token recall
//      and bucket into the three match levels.

///|
/// Human-labelled (or predicted) semantic match level of two address
/// texts.
pub(all) enum MatchLevel {
  Exact
  Partial
  None
}

///|
pub impl Show for MatchLevel with fn output(self, logger) {
  logger.write_string(match self {
    Exact => "完全匹配"
    Partial => "部分匹配"
    None => "不匹配"
  })
}

///|
/// Chinese label text used in the JSONL corpus.
pub fn MatchLevel::from_label(label : String) -> MatchLevel {
  match label {
    "完全匹配" => Exact
    "部分匹配" => Partial
    _ => None
  }
}

///|
/// Rank used for sorting: stronger matches first.
pub fn MatchLevel::rank(self : MatchLevel) -> Int {
  match self {
    Exact => 2
    Partial => 1
    None => 0
  }
}

///|
/// Result of comparing a query against one candidate address text.
pub(all) struct MatchResult {
  level : MatchLevel
  score : Double
  dice : Double
  feature_recall : Double
  road_recall : Double
  num_recall : Double
}

// All intermediate features computed during matching, exported so an
// external classifier (sklearn decision tree) can learn a better decision
// surface than the hand-tuned OR-of-rules can capture.
pub(all) struct FeatureBundle {
  dice : Double
  road_b : Double
  feature_recall : Double
  name_recall : Double
  admin_hit : Int
  road_hit : Int
  town_hit : Int
  context_ok : Int
  house_recall : Double
  house_conflict : Int
  veto : Int
  q_structured : Int
  c_structured : Int
  feat_overlap : Int
  weak_core_exact : Int
  fuzzy_poi_overlap : Int
  reverse_poi_overlap : Int
  road_conflict : Int
  main_hit : Int
  house_missing : Int
  foreign_city : Int
  q_roads : Int
  c_roads : Int
  q_feats : Int
  c_feats : Int
  score : Double
}

// ---- Normalization ----

///|
/// Normalize an address text for comparison:
/// full-width digits/latin letters are folded to ASCII, whitespace and
/// common CJK/ASCII punctuation are removed, latin letters are
/// lower-cased.  Chinese numeral runs (三巷 / 二十三号) are converted to
/// Arabic digits so the same number in different scripts compares equal.
pub fn normalize_address_text(input : String) -> String {
  let folded : StringBuilder = StringBuilder()
  for c in input {
    let code = c.to_int()
    // Full-width ASCII variants: ！ U+FF01 .. ～ U+FF5E map to !..~
    if code >= 0xFF01 && code <= 0xFF5E {
      write_norm_char(folded, (code - 0xFEE0).unsafe_to_char())
      continue
    }
    if code == 0x3000 {
      // Full-width space: drop.
      continue
    }
    write_norm_char(folded, c)
  }
  // Convert Chinese numeral runs (both sides get the same treatment, so
  // name identity is preserved while script differences disappear).
  let src = folded.to_string()
  let codes : Array[Int] = []
  for c in src {
    codes.push(c.to_int())
  }
  let out = StringBuilder()
  let mut i = 0
  while i < codes.length() {
    if is_cjk_code(codes[i]) {
      match cn_run(codes, i) {
        // A lone 一 directly before a bare 号 (壹号 / 华一号) is part of
        // a fashionable proper name, not a house number: keep it CJK.
        // Other lone digits (五号 / 三号) are genuine house numbers.
        Some((v, end)) if end - i == 1 && v == 1 &&
          end < codes.length() && codes[end] == ('号').to_int() &&
          (end + 1 >= codes.length() || codes[end + 1] != ('楼').to_int()) =>
          {
            ignore(out.write_char(codes[i].unsafe_to_char()))
            i = i + 1
          }
        Some((v, end)) => {
          ignore(out.write_string(v.to_string()))
          i = end
        }
        None => {
          ignore(out.write_char(codes[i].unsafe_to_char()))
          i = i + 1
        }
      }
    } else {
      ignore(out.write_char(codes[i].unsafe_to_char()))
      i = i + 1
    }
  }
  // Suffix unification: 幢→栋, 层→楼, 弄→号, 座→栋 (except 座号/之座).
  // These are surface-form variants of the same semantic building marker.
  let sbuf = StringBuilder()
  let nchars : Array[Char] = []
  for c in out.to_string() {
    nchars.push(c)
  }
  let mut ci = 0
  while ci < nchars.length() {
    let ch = nchars[ci]
    let ccode = ch.to_int()
    if ch == ('幢') {
      ignore(sbuf.write_string("栋"))
      ci = ci + 1
    } else if ch == ('层') {
      ignore(sbuf.write_string("楼"))
      ci = ci + 1
    } else if ch == ('弄') {
      ignore(sbuf.write_string("号"))
      ci = ci + 1
    } else if ch == ('座') {
      let prev_code = if ci > 0 { nchars[ci - 1].to_int() } else { 0 }
      if prev_code == ('号').to_int() || prev_code == ('之').to_int() {
        ignore(sbuf.write_char(ch))
      } else {
        ignore(sbuf.write_string("栋"))
      }
      ci = ci + 1
    } else if ch == ('圆') {
      // Common CJK typo: 花圆 → 花园, 沁园春圆 → 沁园春园.
      // 圆 (circle) vs 园 (garden) — homophones on Mandarin (yuán).
      ignore(sbuf.write_string("园"))
      ci = ci + 1
    } else if ccode == 0xFF08 || ccode == 0xFF09 ||
      ccode == 0xFF0C || ccode == 0xFF1A ||
      ccode == 0xFF1B || ccode == 0xFF1D || ccode == 0xFF1E {
      // Skip any remaining full-width punctuation that didn't get mapped.
      ci = ci + 1
    } else {
      ignore(sbuf.write_char(ch))
      ci = ci + 1
    }
  }
  sbuf.to_string()
}

fn write_norm_char(out : StringBuilder, c : Char) -> Unit {
  let code = c.to_int()
  if c.is_whitespace() {
    return
  }
  // Keep CJK ideographs.
  if code >= 0x4E00 && code <= 0x9FFF {
    out.write_char(c)
    return
  }
  // Keep ASCII letters (lower-cased) and digits.
  if (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A) {
    let lower = if code >= 0x41 && code <= 0x5A {
      code + 0x20
    } else {
      code
    }
    ignore(out.write_char(lower.unsafe_to_char()))
    return
  }
  if code >= 0x30 && code <= 0x39 {
    out.write_char(c)
    return
  }
  // Everything else (punctuation, symbols) is dropped.
}

// ---- Token extraction ----

fn is_cjk_code(code : Int) -> Bool {
  code >= 0x4E00 && code <= 0x9FFF
}

fn is_digit_code(code : Int) -> Bool {
  code >= 0x30 && code <= 0x39
}

/// Chinese numeral -> Arabic digit (single char).
fn cn_numeral(code : Int) -> Int? {
  let c = code.unsafe_to_char()
  match c {
    '零' => Some(0)
    '一' => Some(1)
    '两' => Some(2)
    '二' => Some(2)
    '三' => Some(3)
    '四' => Some(4)
    '五' => Some(5)
    '六' => Some(6)
    '七' => Some(7)
    '八' => Some(8)
    '九' => Some(9)
    _ => None
  }
}

/// Parse a Chinese numeral run at `start` (一 / 十三 / 二十三 / 一百五),
/// returning (value, end index). A bare 十 means 10.
fn cn_run(codes : Array[Int], start : Int) -> (Int, Int)? {
  let n = codes.length()
  let mut j = start
  let mut section = 0
  let mut digit = -1
  let mut any = false
  while j < n {
    match cn_numeral(codes[j]) {
      Some(d) => {
        digit = d
        any = true
        j = j + 1
      }
      None => {
        if codes[j] == ('十').to_int() {
          let add = if digit < 0 { 10 } else { digit * 10 }
          section = section + add
          digit = -1
          any = true
          j = j + 1
        } else if codes[j] == ('百').to_int() || codes[j] == ('千').to_int() {
          // A multiplier needs a leading digit (一百五 / 两千); a bare
          // 百 as in 百合 is not a numeral run.
          if digit < 0 {
            break
          }
          let mul = if codes[j] == ('百').to_int() { 100 } else { 1000 }
          let add = digit * mul
          section = section + add
          digit = -1
          any = true
          j = j + 1
        } else {
          break
        }
      }
    }
  }
  if any {
    let tail = if digit < 0 { 0 } else { digit }
    Some((section + tail, j))
  } else {
    None
  }
}

// Category of a matched suffix.
let cat_town = 1 // 街道/镇/乡/办事处
let cat_road = 2 // 路/街/道/巷/国道/乡道 ...
let cat_feature = 3 // 村/小区/大厦/广场/公司 ...
let cat_admin = 4 // 省/市/区/县 ... (cut, no token)

// Ordered (longest / highest-priority first) suffix table.
let suffix_table : Array[(String, Int)] = [
  ("步行街", cat_road),
  ("风景区", cat_feature),
  ("办事处", cat_town),
  ("村委会", cat_admin),
  ("居委会", cat_admin),
  ("国道", cat_road),
  ("省道", cat_road),
  ("县道", cat_road),
  ("乡道", cat_road),
  ("大道", cat_road),
  ("大街", cat_road),
  ("街道", cat_town),
  ("社区", cat_town),
  ("小区", cat_feature),
  ("新村", cat_feature),
  ("新区", cat_feature),
  ("大厦", cat_feature),
  ("广场", cat_feature),
  ("市场", cat_feature),
  ("公寓", cat_feature),
  ("家园", cat_feature),
  ("花园", cat_feature),
  ("酒店", cat_feature),
  ("宾馆", cat_feature),
  ("医院", cat_feature),
  ("学校", cat_feature),
  ("学院", cat_feature),
  ("大学", cat_feature),
  ("公司", cat_feature),
  ("银行", cat_feature),
  ("食堂", cat_feature),
  ("饭店", cat_feature),
  ("公园", cat_feature),
  ("基地", cat_feature),
  ("中心", cat_feature),
  ("家居", cat_feature),
  ("省", cat_admin),
  ("市", cat_admin),
  ("区", cat_admin),
  ("县", cat_admin),
  ("旗", cat_admin),
  ("镇", cat_town),
  ("乡", cat_town),
  ("路", cat_road),
  ("街", cat_road),
  ("道", cat_road),
  ("巷", cat_road),
  ("弄", cat_road),
  ("线", cat_road),
  ("村", cat_feature),
  ("苑", cat_feature),
  ("城", cat_feature),
  ("府", cat_feature),
  ("馆", cat_feature),
  ("店", cat_feature),
  ("寺", cat_feature),
  ("园", cat_feature),
  ("山", cat_feature),
  ("大队", cat_feature),
  // Specific admin sub-village units (村民组/生产队 etc.) are matched
  // as admin rather than POI features, but the single-char "队" / "组"
  // are intentionally excluded: they cause too many false positives
  // (东山大队 → core 东山大 gets misclassified as admin).
  ("村民组", cat_admin),
  ("生产队", cat_admin),
  ("村民小组", cat_admin),
  // ("组", cat_admin),
  // ("队", cat_admin),
  ("州", cat_admin),
  ("盟", cat_admin),
]

/// First-char -> suffix table indices, so the hot scan tests only the
/// handful of suffixes that can actually start at a position.
let suffix_by_first : @hashmap.HashMap[Int, Array[Int]] = {
  let m : @hashmap.HashMap[Int, Array[Int]] = @hashmap.HashMap([])
  let mut i = 0
  while i < suffix_table.length() {
    let first = suffix_table[i].0.get_char(0).unwrap().to_int()
    let arr = match m.get(first) {
      Some(a) => a
      None => []
    }
    arr.push(i)
    m.set(first, arr)
    i = i + 1
  }
  m
}

///|
/// Tokens extracted from one normalized address.
priv struct AddrTokens {
  roads : Array[String]
  towns : Array[String]
  admins : Array[String]
  features : Array[String]
  names : Array[String]
  struct_nums : Array[String]
  detail_nums : Array[String]
  bigrams : Array[Int]
}

fn slice_eq(codes : Array[Int], start : Int, suf : String) -> Bool {
  let mut k = 0
  for c in suf {
    if start + k >= codes.length() || codes[start + k] != c.to_int() {
      return false
    }
    k = k + 1
  }
  true
}

fn codes_to_string(codes : Array[Int], start : Int, end : Int) -> String {
  let sb : StringBuilder = StringBuilder()
  let mut i = start
  while i < end {
    let code = codes[i]
    match cn_numeral(code) {
      Some(d) =>
        ignore(sb.write_char((d + 0x30).unsafe_to_char()))
      None => ignore(sb.write_char(code.unsafe_to_char()))
    }
    i = i + 1
  }
  sb.to_string()
}

// Build a token string from [start, end) but skip positions marked
// consumed (number spans like "25栋" or "2楼"). Without this the POI
// token window swallows numeric suffixes, producing garbage like
// "溢璟庭25栋2楼物业中心" instead of "香溢璟庭".
fn codes_to_string_free(codes : Array[Int], consumed : Array[Bool],
  start : Int, end : Int) -> String {
  let sb : StringBuilder = StringBuilder()
  let mut i = start
  while i < end {
    if not(consumed[i]) {
      let code = codes[i]
      match cn_numeral(code) {
        Some(d) =>
          ignore(sb.write_char((d + 0x30).unsafe_to_char()))
        None => ignore(sb.write_char(code.unsafe_to_char()))
      }
    }
    i = i + 1
  }
  sb.to_string()
}

fn push_unique(arr : Array[String], s : String) -> Unit {
  if s.length() > 0 && not(arr.contains(s)) {
    arr.push(s)
  }
}

fn suffix_at(codes : Array[Int], pos : Int) -> (String, Int)? {
  match suffix_by_first.get(codes[pos]) {
    None => None
    Some(indices) => {
      for idx in indices {
        let (suf, cat) = suffix_table[idx]
        let slen = suf.length()
        if pos + slen <= codes.length() && slice_eq(codes, pos, suf) {
          return Some((suf, cat))
        }
      }
      None
    }
  }
}

/// Count unconsumed CJK code points in [start, end) (positions taken by
/// number spans like 602号楼 are skipped).
fn count_free_cjk(codes : Array[Int], consumed : Array[Bool], start : Int,
    end : Int) -> Int {
  let mut k = start
  let mut count = 0
  while k < end {
    if is_cjk_code(codes[k]) && not(consumed[k]) {
      count = count + 1
    }
    k = k + 1
  }
  count
}

///|
/// Extract road/township/POI tokens, structural & detail numbers and
/// CJK bigrams from a normalized address string.
fn tokenize_address(norm : String) -> AddrTokens {
  let codes : Array[Int] = []
  for c in norm {
    codes.push(c.to_int())
  }
  let n = codes.length()
  let roads : Array[String] = []
  let towns : Array[String] = []
  let admins : Array[String] = []
  let features : Array[String] = []
  let names : Array[String] = []
  let struct_nums : Array[String] = []
  let detail_nums : Array[String] = []
  let bigrams : Array[Int] = []
  // Positions already consumed by a suffix token (digits inside a POI
  // name like 省建5公司 must not become fake house numbers).
  let consumed : Array[Bool] = []
  for _ in 0..<n {
    consumed.push(false)
  }

  // ---- Pass 1: number runs + immediate unit suffix ----
  // Done first so the number spans (232号 / 602号楼 / 2单元 / 3期) are
  // marked consumed and never leak into POI token windows or bare
  // names. Bare digit runs are intentionally NOT tokens. Highway
  // prefixes (801乡道) have no unit suffix and stay unconsumed.
  let struct_suffixes = ["号楼", "单元", "号", "栋", "幢", "座", "组"]
  let detail_suffixes = ["层", "楼", "室", "期"]
  let mut i = 0
  while i < n {
    let mut j = i
    let mut value = ""
    if is_digit_code(codes[i]) {
      while j < n && is_digit_code(codes[j]) {
        value = value + (codes[j].unsafe_to_char().to_string())
        j = j + 1
      }
    } else {
      match cn_run(codes, j) {
        Some((v, end)) => {
          // Lone 一 before a bare 号 stays a proper name (壹号).
          if end - j == 1 && v == 1 && end < n &&
            codes[end] == ('号').to_int() &&
            (end + 1 >= n || codes[end + 1] != ('楼').to_int()) {
            ()
          } else {
            value = v.to_string()
            j = end
          }
        }
        None => ()
      }
    }
    if j > i {
      let mut matched = false
      for suf in struct_suffixes {
        let slen = suf.length()
        if j + slen <= n && slice_eq(codes, j, suf) {
          push_unique(struct_nums, value + suf)
          i = j + slen
          matched = true
          break
        }
      }
      if not(matched) {
        for suf in detail_suffixes {
          let slen = suf.length()
          if j + slen <= n && slice_eq(codes, j, suf) {
            push_unique(detail_nums, value + suf)
            i = j + slen
            matched = true
            break
          }
        }
      }
      if matched {
        // Marked span ends at i; extend left over the number run.
        let span_end = i
        let mut span_start = j
        while span_start > 0 &&
          (is_digit_code(codes[span_start - 1]) ||
            cn_numeral(codes[span_start - 1]) is Some) {
          span_start = span_start - 1
        }
        let mut m = span_start
        while m < span_end {
          consumed[m] = true
          m = m + 1
        }
        i = span_end
      } else {
        i = j
      }
    } else {
      i = i + 1
    }
  }

  // A trailing bare digit run ("松花江路36") is a truncated house
  // number: synthesize a 号 token. Digit runs elsewhere stay bare
  // (highway numbers like 801 in 801乡道, digits inside POI names).
  if n > 0 && is_digit_code(codes[n - 1]) {
    let mut s = n - 1
    while s > 0 && is_digit_code(codes[s - 1]) {
      s = s - 1
    }
    if not(consumed[s]) {
      let val = codes_to_string(codes, s, n)
      push_unique(struct_nums, val + "号")
      let mut m = s
      while m < n {
        consumed[m] = true
        m = m + 1
      }
    }
  }

  // ---- Pass 2: whole-string greedy suffix scan ----
  // Scanning the full string keeps digit-containing names intact
  // (801乡道 / 省建5公司); number spans are skipped via `consumed`.
  // A landmark marker (工商银行"对过" / 超市"对面") means POIs named
  // BEFORE it are orientation references, not the target entity.
  let mut landmark_at = n
  {
    let mut k = 0
    while k + 1 < n {
      let pair = codes_to_string(codes, k, k + 2)
      if pair == "对过" || pair == "对面" || pair == "隔壁" ||
        pair == "旁边" {
        landmark_at = k
        consumed[k] = true
        consumed[k + 1] = true
        break
      }
      k = k + 1
    }
  }
  let mut cut = 0
  let mut p = 0
  while p < n {
    if not(is_cjk_code(codes[p])) {
      p = p + 1
      continue
    }
    match suffix_at(codes, p) {
      Some((suf, cat)) => {
        let slen = suf.length()
        // A weak single-char POI suffix (山/园/村/城 ...) directly
        // followed by a road/admin suffix yields that higher-level
        // token instead: 华山路 is a road, 兰山区 an admin district.
        // One intervening direction char is allowed: 君山西路,
        // 佳苑南街.
        if cat == cat_feature && slen == 1 && p + slen < n &&
          not(consumed[p + slen]) {
          let after = codes[p + slen]
          let after2 = if p + slen + 1 < n {
            codes[p + slen + 1]
          } else {
            0
          }
          let is_dir = after == ('东').to_int() || after == ('西').to_int() ||
            after == ('南').to_int() || after == ('北').to_int() ||
            after == ('中').to_int()
          let hi = after == ('路').to_int() || after == ('街').to_int() ||
            after == ('道').to_int() || after == ('巷').to_int() ||
            after == ('弄').to_int() || after == ('线').to_int() ||
            after == ('区').to_int() || after == ('市').to_int() ||
            after == ('县').to_int() || after == ('旗').to_int() ||
            after == ('省').to_int()
          let hi2 = after2 == ('路').to_int() || after2 == ('街').to_int() ||
            after2 == ('道').to_int() || after2 == ('巷').to_int() ||
            after2 == ('弄').to_int() || after2 == ('区').to_int()
          if hi || (is_dir && hi2) {
            p = p + 1
            continue
          }
        }
        let cap = if cat == cat_feature {
          10
        } else if cat == cat_road {
          5
        } else if cat == cat_town {
          3
        } else {
          2
        }
        let mut tok_start = if p - cut > cap {
          p - cap
        } else {
          cut
        }
        // Clamp the window over number spans / non-CJK fragments so
        // tokens never begin with "232号" or digits inside a name.
        while tok_start < p &&
          (consumed[tok_start] || not(is_cjk_code(codes[tok_start]))) {
          tok_start = tok_start + 1
        }
        let tok = codes_to_string_free(codes, consumed, tok_start, p + slen)
        // Weak single-char suffixes (山/村/园 ...) need a real core
        // character, otherwise province names like 山东/山西 or stray
        // suffix characters produce fake POI tokens.
        let weak_empty = cat == cat_feature && slen == 1 && tok_start >= p
        // POI tokens entirely before a landmark marker are dropped.
        let before_landmark = landmark_at < n && p + slen <= landmark_at
        if not(weak_empty) && not(cat == cat_feature && before_landmark) {
          if cat == cat_road {
            push_unique(roads, tok)
          } else if cat == cat_town {
            push_unique(towns, tok)
          } else if cat == cat_feature {
            push_unique(features, tok)
          } else {
            // Admin division: keep only the core name (strip suffix),
            // so 溧水县 / 溧水区 share the core 溧水. Skip autonomous
            // suffix junk like 自治 / 壮自 and direction-only cores.
            let core = codes_to_string(codes, tok_start, p)
            let head = if core.length() > 0 {
              core.get_char(0).unwrap().to_int()
            } else {
              0
            }
            if core.length() >= 2 && not(core.contains("治")) &&
              not(core.contains("壮")) && not(core.contains("回")) &&
              not(core.contains("维")) && head != ('内').to_int() &&
              head != ('外').to_int() {
              push_unique(admins, core)
            }
          }
          // Bare distinctive name in the preceding gap: needs at least
          // 3 unconsumed CJK chars, so admin prefixes (甘井子) and
          // number tails (602号楼2单元1层) can't form fake names.
          // Gaps before a landmark marker contain only references.
          if count_free_cjk(codes, consumed, cut, tok_start) >= 3 &&
            not(landmark_at < n && tok_start <= landmark_at) {
            push_unique(names, cjk_only_free(codes, consumed, cut, tok_start))
          }
          let mut k = tok_start
          while k < p + slen {
            consumed[k] = true
            k = k + 1
          }
        }
        cut = p + slen
        p = cut
      }
      None => p = p + 1
    }
  }
  // Trailing bare name; if a landmark marker remains in the span, only
  // text after it belongs to the target entity.
  let tail_start = if landmark_at < n && landmark_at >= cut {
    landmark_at + 2
  } else {
    cut
  }
  if count_free_cjk(codes, consumed, tail_start, n) >= 3 {
    push_unique(names, cjk_only_free(codes, consumed, tail_start, n))
  }

  // ---- CJK bigrams ----
  let mut prev = -1
  for c in norm {
    let code = c.to_int()
    if is_cjk_code(code) {
      if prev >= 0 {
        bigrams.push(prev * 41000 + code)
      }
      prev = code
    } else {
      prev = -1
    }
  }

  { roads, towns, admins, features, names, struct_nums, detail_nums, bigrams }
}

/// Rebuild a bare-name token keeping only unconsumed CJK code points.
fn cjk_only_free(codes : Array[Int], consumed : Array[Bool], start : Int,
    end : Int) -> String {
  let sb = StringBuilder()
  let mut i = start
  while i < end {
    if is_cjk_code(codes[i]) && not(consumed[i]) {
      ignore(sb.write_char(codes[i].unsafe_to_char()))
    }
    i = i + 1
  }
  sb.to_string()
}

// ---- Scoring ----

/// Recall of query tokens in the candidate token set. Matching is
/// directional containment: the full query token must appear inside a
/// candidate token ("装饰城" in "鲁南装饰城" counts; "谢岗" alone does
/// NOT satisfy "谢岗村"). An empty query set yields 0.0: "no signal"
/// must never be mistaken for "every signal present".
fn token_recall(query : Array[String], candidate : Array[String]) -> Double {
  if query.length() == 0 {
    return 0.0
  }
  let mut hit = 0
  for t in query {
    let mut found = false
    for c in candidate {
      if c.contains(t) {
        found = true
        break
      }
    }
    if found {
      hit = hit + 1
    }
  }
  hit.to_double() / query.length().to_double()
}

fn dice_bigrams(a : Array[Int], b : Array[Int]) -> Double {
  if a.length() == 0 || b.length() == 0 {
    return 0.0
  }
  let cset : @hashmap.HashMap[Int, Bool] = @hashmap.HashMap([])
  for g in b {
    cset.set(g, true)
  }
  let aset : @hashmap.HashMap[Int, Bool] = @hashmap.HashMap([])
  let mut inter = 0
  for g in a {
    if not(aset.contains(g)) {
      aset.set(g, true)
      if cset.contains(g) {
        inter = inter + 1
      }
    }
  }
  let ua = aset.length()
  let ub = cset.length()
  2.0 * inter.to_double() / (ua + ub).to_double()
}

/// Bidirectional containment: either token appears inside the other
/// (裕华东岗路 vs 东岗路). Single-char tokens never match.
fn token_pair_hit(a : String, b : String) -> Bool {
  (a.contains(b) || b.contains(a)) &&
    (a.length() >= 2 && b.length() >= 2)
}

/// Fraction of query tokens having a bidirectional hit in the candidate
/// token set. Empty query set yields 0.0.
fn token_recall_bidir(query : Array[String], candidate : Array[String])
    -> Double {
  if query.length() == 0 {
    return 0.0
  }
  let mut hit = 0
  for t in query {
    let mut found = false
    for c in candidate {
      if token_pair_hit(t, c) {
        found = true
        break
      }
    }
    if found {
      hit = hit + 1
    }
  }
  hit.to_double() / query.length().to_double()
}

/// Whether at least one query token shares a bidirectional hit.
fn token_any_hit(query : Array[String], candidate : Array[String]) -> Bool {
  for t in query {
    for c in candidate {
      if token_pair_hit(t, c) {
        return true
      }
    }
  }
  false
}

/// 2-3 CJK-char cores of explicit city/county-level regions that appear
/// as X市 / X县 in `text` (上海市 / 泰兴市 / 浚县), guarding against
/// 超市 / 城市 / 自治县 false positives. District-level 区 is excluded
/// on purpose: a bare district often legitimately contains the query.
fn city_cores(text : String) -> Array[String] {
  let codes : Array[Int] = []
  for c in text {
    codes.push(c.to_int())
  }
  let res : Array[String] = []
  let mut i = 0
  while i < codes.length() {
    if (codes[i] == ('市').to_int() || codes[i] == ('县').to_int()) &&
      i >= 2 {
      // "市/县" followed by a road suffix (街/路/道/巷/弄/线) is a
      // street-name fragment (西梆子市街, 建设路县巷), not an admin
      // district marker — skip it.
      if i + 1 < codes.length() {
        let next = codes[i + 1]
        if next == ('街').to_int() || next == ('路').to_int() ||
          next == ('道').to_int() || next == ('巷').to_int() ||
          next == ('弄').to_int() || next == ('线').to_int() {
          i = i + 1
          continue
        }
      }
      let mut s = i - 1
      while s > i - 4 && s > 0 && is_cjk_code(codes[s - 1]) {
        s = s - 1
      }
      let before = if s > 0 {
        codes[s - 1]
      } else {
        0
      }
      if before != ('超').to_int() && before != ('城').to_int() &&
        before != ('省').to_int() {
        let core = codes_to_string(codes, s, i)
        if not(core.contains("治")) && not(core.contains("壮")) &&
          not(core.contains("回")) && not(core.contains("维")) &&
          not(core.contains("彝")) && not(core.contains("苗")) &&
          not(core.contains("侗")) && not(core.contains("瑶")) &&
          core.length() >= 2 {
          push_unique(res, core)
        }
      }
    }
    i = i + 1
  }
  res
}

/// Thresholds calibrated against the 20k-record labelled corpus; run
/// `moon run cmd addr-eval` for the confusion matrix.
let standalone_dice_threshold : Double = 0.40
let admin_dice_threshold : Double = 0.40
let context_dice_threshold : Double = 0.40
let overlap_dice_threshold : Double = 0.25

/// Two-character POI suffixes strong enough that a 6+ char token with
/// such a suffix identifies a unique place (近铁城市广场 / 百家湖东花园).
let strong_feat_suffixes = [
  "大厦", "广场", "市场", "公寓", "花园", "家园", "酒店", "宾馆",
  "医院", "学校", "学院", "大学", "公司", "银行", "饭店", "公园",
  "基地", "中心", "新村", "新区", "小区", "步行街", "风景区",
]

/// A feature token that can identify a place on its own (without an
/// agreeing road/number).
fn is_standalone_feat(tok : String) -> Bool {
  if tok.length() >= 7 {
    return true
  }
  if tok.length() >= 6 {
    for s in strong_feat_suffixes {
      if tok.ends_with(s) {
        return true
      }
    }
  }
  false
}

/// A structural number is a "house number" when it ends with 号;
/// 栋/幢/座/号楼/单元 identify buildings/units.
fn is_house_num(tok : String) -> Bool {
  tok.ends_with("号")
}

fn is_building_num(tok : String) -> Bool {
  tok.contains("号楼") || tok.ends_with("栋") || tok.ends_with("幢") ||
    tok.ends_with("座") || tok.ends_with("单元")
}

fn is_unit_num(tok : String) -> Bool {
  tok.ends_with("单元")
}

fn is_main_building_num(tok : String) -> Bool {
  tok.contains("号楼") || tok.ends_with("栋") || tok.ends_with("幢") ||
    tok.ends_with("座")
}

fn is_phase_num(tok : String) -> Bool {
  tok.ends_with("期")
}

/// Floor / room suffixes (2层, 5楼, 1室, A厅...)
fn is_floor_num(tok : String) -> Bool {
  tok.ends_with("层") || tok.ends_with("楼") || tok.ends_with("室") ||
    tok.ends_with("厅") || tok.ends_with("排")
}

/// Recall of building tokens (栋/幢/座/号楼/单元): a missing building on
/// the candidate side means the address is less detailed (partial).
fn building_recall(query : Array[String], candidate : Array[String]) -> Double {
  recall_filtered(query, candidate, is_building_num)
}

/// Recall of detail numbers (层/楼/室/期) compared by numeric value, so
/// 26楼 and 26层 agree. Only phase numbers (期) are required for an
/// exact match; floor/room omissions are tolerated.
fn detail_value_recall(query : Array[String], candidate : Array[String],
    pred : (String) -> Bool) -> Double {
  let cval : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([])
  for t in candidate {
    cval.set(house_digit_prefix(t), true)
  }
  let mut total = 0
  let mut hit = 0
  for t in query {
    if pred(t) {
      total = total + 1
      if cval.contains(house_digit_prefix(t)) {
        hit = hit + 1
      }
    }
  }
  if total == 0 {
    1.0
  } else {
    hit.to_double() / total.to_double()
  }
}

fn recall_filtered(query : Array[String], candidate : Array[String],
    pred : (String) -> Bool) -> Double {
  let mut total = 0
  let mut hit = 0
  for t in query {
    if pred(t) {
      total = total + 1
      for c in candidate {
        if c.contains(t) {
          hit = hit + 1
          break
        }
      }
    }
  }
  if total == 0 {
    0.0
  } else {
    hit.to_double() / total.to_double()
  }
}

/// Weak, generic single-character POI suffixes (village / garden / hill):
/// a short token with one of these is only a partial signal.
let weak_feat_ends = ["村", "苑", "城", "府", "馆", "店", "寺", "园", "山"]

/// Residential-community suffixes: two different communities of this
/// kind sharing an address are distinct entities (百家湖东花园 vs
/// 百家湖国际花园), whereas a community vs a facility (神兴小区 vs
/// 神兴小学) is a partial.
let residential_suffixes = [
  "小区", "新村", "新区", "花园", "家园", "公寓", "别墅", "社区", "苑", "府",
]

fn is_weak_feat(tok : String) -> Bool {
  if tok.length() <= 4 {
    for e in weak_feat_ends {
      if tok.ends_with(e) {
        return true
      }
    }
  }
  false
}

/// Distinctive core of a POI token: strip the known category suffix
/// (花园/小区/公司/城 ...) so shared generic tails don't count as
/// name overlap (东花园 vs 国际花园 -> cores share 百家湖, a conflict).
fn core_of_poi(tok : String) -> String {
  for s in strong_feat_suffixes {
    if tok.ends_with(s) {
      return tok[:tok.length() - s.length()].to_string()
    }
  }
  for e in weak_feat_ends {
    if tok.ends_with(e) {
      return tok[:tok.length() - 1].to_string()
    }
  }
  tok
}

/// Length of the longest common substring (code points).
fn lcs_len(a : String, b : String) -> Int {
  let ca : Array[Int] = []
  for c in a {
    ca.push(c.to_int())
  }
  let cb : Array[Int] = []
  for c in b {
    cb.push(c.to_int())
  }
  let la = ca.length()
  let lb = cb.length()
  if la == 0 || lb == 0 {
    return 0
  }
  let prev : Array[Int] = []
  let cur : Array[Int] = []
  for _ in 0..<lb {
    prev.push(0)
    cur.push(0)
  }
  let mut best = 0
  for i in 0..<la {
    for j in 0..<lb {
      if ca[i] == cb[j] {
        cur[j] = if j == 0 { 1 } else { prev[j - 1] + 1 }
        if cur[j] > best {
          best = cur[j]
        }
      } else {
        cur[j] = 0
      }
    }
    for j in 0..<lb {
      prev[j] = cur[j]
    }
  }
  best
}

/// Character-bigram Jaccard similarity between two strings. Catches
/// typo / abbreviation / suffix variants that exact token matching
/// misses (花园 vs 花圆, 大鸿城壹号 vs 大鸿城). Single-char strings
/// fall back to equality.
fn bigram_jaccard(a : String, b : String) -> Double {
  let ca : Array[Int] = []
  for c in a {
    ca.push(c.to_int())
  }
  let cb : Array[Int] = []
  for c in b {
    cb.push(c.to_int())
  }
  let la = ca.length()
  let lb = cb.length()
  if la == 0 || lb == 0 {
    return 0.0
  }
  // Single-char: compare directly.
  if la == 1 || lb == 1 {
    return if a == b { 1.0 } else { 0.0 }
  }
  let n_bigrams_a = la - 1
  let n_bigrams_b = lb - 1
  // Collect bigrams as packed Int keys.
  let ba : @hashmap.HashMap[Int, Bool] = @hashmap.HashMap([])
  let bb : @hashmap.HashMap[Int, Bool] = @hashmap.HashMap([])
  for i in 0..<n_bigrams_a {
    let key = ca[i] * 65537 + ca[i + 1]
    ba.set(key, true)
  }
  for i in 0..<n_bigrams_b {
    let key = cb[i] * 65537 + cb[i + 1]
    bb.set(key, true)
  }
  let mut inter = 0
  for (k, _) in ba.iter() {
    if bb.contains(k) {
      inter = inter + 1
    }
  }
  let union = ba.length() + bb.length() - inter
  if union == 0 {
    0.0
  } else {
    inter.to_double() / union.to_double()
  }
}
/// "99"). A prefix relation (9号 vs 9-1号) means the same entrance with
/// a sub-number, which is a partial (not none) signal.
fn house_digit_prefix(tok : String) -> String {
  let sb = StringBuilder()
  for c in tok {
    if ('0').to_int() <= c.to_int() && c.to_int() <= ('9').to_int() {
      ignore(sb.write_char(c))
    } else {
      break
    }
  }
  sb.to_string()
}

fn house_prefix_related(qnums : Array[String], cnums : Array[String]) -> Bool {
  for qt in qnums {
    if is_house_num(qt) {
      let qp = house_digit_prefix(qt)
      if qp.length() > 0 {
        for ct in cnums {
          if is_house_num(ct) {
            let cp = house_digit_prefix(ct)
            // Equal leading number with different suffix token
            // (99号 vs 99-3号) or a strict prefix relation (9 vs 9-1).
            if cp.length() > 0 && cp.starts_with(qp) && not(ct == qt) {
              return true
            }
          }
        }
      }
    }
  }
  false
}

///|
/// Compare two raw address texts and return a predicted match level
/// with the component scores used for ranking.
pub fn match_address_ex(query : String, candidate : String) -> (MatchResult, FeatureBundle) {
  let nq = normalize_address_text(query)
  let nc = normalize_address_text(candidate)
  let tq = tokenize_address(nq)
  let tc = tokenize_address(nc)

  let dice = dice_bigrams(tq.bigrams, tc.bigrams)
  let road = token_recall(tq.roads, tc.roads)
  let town = token_recall(tq.towns, tc.towns)
  let admin = token_recall(tq.admins, tc.admins)
  // Combined POI pool: suffixed features and bare distinctive names
  // satisfy each other bidirectionally (华腾新天地 vs 华腾新天地大厦).
  let q_poi : Array[String] = []
  for t in tq.features {
    q_poi.push(t)
  }
  for t in tq.names {
    q_poi.push(t)
  }
  let c_poi : Array[String] = []
  for t in tc.features {
    c_poi.push(t)
  }
  for t in tc.names {
    c_poi.push(t)
  }
  // Concatenated POI blobs (query and candidate) — allows fuzzy cross-
  // token bigram matching and substring containment that the greedy
  // tokenizer may have missed.
  let poi_blob = {
    let sb = StringBuilder()
    for pf in c_poi {
      ignore(sb.write_string(pf))
    }
    sb.to_string()
  }
  let q_blob = {
    let sb = StringBuilder()
    for pf in q_poi {
      ignore(sb.write_string(pf))
    }
    sb.to_string()
  }
  // Fuzzy POI overlap via bigram similarity: any q_poi token (≥3 chars)
  // shares ≥50% bigrams with the candidate POI blob. Using the raw
  // token (not the stripped core) because weak suffixes (城/园/村) often
  // leave the core too short (大鸿 → 2 chars) to trigger the overlap.
  let fuzzy_poi_overlap = {
    let mut found = false
    for qp in q_poi {
      if qp.length() >= 3 && bigram_jaccard(qp, poi_blob) >= 0.50 {
        found = true
        break
      }
    }
    found
  }
  // Reverse fuzzy POI match: tokenizer may fail on the query side
  // (香溢璟庭 → 溢璟庭25栋2楼物业中心) while extracting the POI cleanly
  // from the candidate (附近香溢璟庭). For each clean c_poi ≥3 chars,
  // strip the full noisy prefix strings (附近/新城· etc.) then check if
  // the POI core appears as a substring in nq. This is an exact substring
  // check — no char-by-char stripping — so precision stays high.
  let noisy_prefixes = ["附近", "新城·", "新城", "交叉口东北"]
  let reverse_poi_overlap = {
    let mut found = false
    for cp in c_poi {
      let mut stripped = cp
      for np in noisy_prefixes {
        if stripped.starts_with(np) && stripped.length() > np.length() {
          stripped = stripped[np.length():].to_string()
        }
      }
      let cc = core_of_poi(stripped)
      let n = cc.length()
      if n >= 3 {
        if nq.contains(cc) {
          found = true
          break
        }
        if n >= 4 {
          if nq.contains(cc[1:].to_string()) ||
            nq.contains(cc[0:n - 1].to_string()) {
            found = true
            break
          }
        }
      }
    }
    found
  }
  let feature = token_recall(tq.features, c_poi)
  let name = token_recall(tq.names, c_poi)
  let snum = token_recall(tq.struct_nums, tc.struct_nums)
  let house = recall_filtered(tq.struct_nums, tc.struct_nums, is_house_num)
  let main_rec =
    recall_filtered(tq.struct_nums, tc.struct_nums, is_main_building_num)
  let unit_rec = recall_filtered(tq.struct_nums, tc.struct_nums, is_unit_num)
  let phase_ok =
    detail_value_recall(tq.detail_nums, tc.detail_nums, is_phase_num) >= 1.0
  // If query mentions specific floors/rooms (2楼/5层/A厅) that the
  // candidate drops, they describe different levels of detail → Partial.
  // The floor_ok escape valve (dice≥0.85 && main_hit && house≥1.0) is
  // evaluated later — dice/main_hit/house are defined below.
  let floor_hard_ok =
    detail_value_recall(tq.detail_nums, tc.detail_nums, is_floor_num) >= 1.0

  let q_has_house = {
    let mut found = false
    for t in tq.struct_nums {
      if is_house_num(t) {
        found = true
      }
    }
    found
  }
  let q_has_main = {
    let mut found = false
    for t in tq.struct_nums {
      if is_main_building_num(t) {
        found = true
      }
    }
    found
  }
  let q_has_unit = {
    let mut found = false
    for t in tq.struct_nums {
      if is_unit_num(t) {
        found = true
      }
    }
    found
  }
  let c_has_house = {
    let mut found = false
    for t in tc.struct_nums {
      if is_house_num(t) {
        found = true
      }
    }
    found
  }
  // At least one main building (号楼/栋/幢/座) of the query appears in
  // the candidate: then a missing 单元 is tolerated (神兴小区11号楼2单元
  // vs 神兴小区11栋11号楼 is exact).
  let main_hit = {
    let mut hit = false
    for t in tq.struct_nums {
      if is_main_building_num(t) {
        for c in tc.struct_nums {
          if c.contains(t) {
            hit = true
          }
        }
      }
    }
    hit
  }
  let building_ok = (not(q_has_main) || main_rec >= 1.0 || main_hit) &&
    (not(q_has_unit) || unit_rec >= 1.0 || (q_has_main && main_hit))
  // Candidate names no main building at all: it is a less detailed
  // description of the same POI, not a conflicting building.
  let c_main_absent = {
    let mut found = false
    for t in tc.struct_nums {
      if is_main_building_num(t) {
        found = true
      }
    }
    not(found)
  }
  let building_complete = (not(q_has_main) || main_rec >= 1.0 || main_hit ||
    c_main_absent) &&
    (not(q_has_unit) || unit_rec >= 1.0 || (q_has_main && main_hit))
  // Floor check evaluated here (all variables now available).
  // Escape valve: when dice ≥ 0.85 AND both the main building and house
  // numbers match exactly, tolerate a missing floor — both describe
  // the same unique building with almost complete text overlap.
  let floor_ok = floor_hard_ok ||
    (dice >= 0.75 && main_hit && house >= 1.0)
  let detail_complete = building_complete && phase_ok && floor_ok
  // Query names a house number that the candidate lacks, and the query
  // has no main building to anchor identity on: suspicious cross-region
  // name coincidence (藤桥永宁村124号 vs 海宁市永宁村).
  let house_missing = q_has_house && not(c_has_house) && not(q_has_main)

  let q_has_roads = tq.roads.length() > 0
  let c_has_roads = tc.roads.length() > 0
  let q_has_feat = tq.features.length() > 0
  let c_has_poi = c_poi.length() > 0
  let q_has_target = q_poi.length() > 0

  let feat_all = q_has_feat && feature >= 1.0

  // Bidirectional road recall: a query road also matches when the
  // candidate road is a substring of it (裕华东岗路 vs 东岗路).
  let road_b = token_recall_bidir(tq.roads, tc.roads)
  let road_hit = road_b >= 1.0
  let town_hit = token_any_hit(tq.towns, tc.towns)
  let admin_hit = token_any_hit(tq.admins, tc.admins)
  let context_ok = road_hit || town_hit || admin_hit

  // Every query feature matches a candidate POI token in either
  // direction (江南建华新村 vs 建华新村).
  let feat_bidir_all = {
    let mut ok = q_has_feat
    if ok {
      for qf in tq.features {
        let mut found = false
        for cf in c_poi {
          if token_pair_hit(qf, cf) {
            found = true
            break
          }
        }
        if not(found) {
          ok = false
          break
        }
      }
    }
    ok
  }

  // Any bare query name appears inside a candidate POI/name token.
  let name_any_hit = token_any_hit(tq.names, c_poi)
  let name_all = tq.names.length() > 0 && name >= 1.0
  // Every bare query name appears verbatim in the raw candidate text
  // (华腾新天地5层 vs ...华腾新天地(大郊亭南街)).
  let name_raw_all = {
    let mut ok = tq.names.length() > 0
    if ok {
      for qn in tq.names {
        if not(nc.contains(qn)) {
          ok = false
          break
        }
      }
    }
    ok
  }

  // Standalone-distinctive suffixed POI token present in the candidate.
  let mut standalone_fwd = false
  for qf in tq.features {
    if is_standalone_feat(qf) {
      for cf in c_poi {
        if cf.contains(qf) {
          standalone_fwd = true
          break
        }
      }
    }
  }
  // Adjacent multi-suffix POIs split into several features
  // (铁成佳园 + 农贸大市场): their in-order compound is the real unique
  // name when it appears verbatim on both sides.
  let compound = {
    let sb = StringBuilder()
    for qf in tq.features {
      ignore(sb.write_string(qf))
    }
    sb.to_string()
  }
  let compound_fwd = compound.length() >= 7 && nq.contains(compound) &&
    nc.contains(compound)
  if compound_fwd {
    standalone_fwd = true
  }

  // Strong containment: a 4+ char query POI token appears verbatim
  // inside a candidate POI token (candidate is a superset of the name).
  let mut strong_embed = false
  for qf in tq.features {
    if qf.length() >= 4 {
      for cf in c_poi {
        if cf.contains(qf) {
          strong_embed = true
          break
        }
      }
    }
  }
  if compound_fwd {
    strong_embed = true
  }

  // Raw-text anchor: the distinctive tail of a query feature appears
  // verbatim in the candidate text, even when greedy scan windows
  // absorbed different prefixes (交汇处装饰城 vs 汇处鲁南装饰城).
  // The fragment is built from the CORE (category suffix stripped,
  // plus 有限/股份 company-filler stripped), so generic tails such as
  // 限公司 / 花园 never anchor. Weak single-char suffixes use 2 core
  // chars, strong suffixes use 3.
  let mut anchor_strong = false
  let mut anchor_weak = false
  for qf in tq.features {
    let weak = is_weak_feat(qf)
    let mut core = core_of_poi(qf)
    for _ in 0..<2 {
      for filler in ["有限责任", "股份有限", "有限", "股份"] {
        if core.ends_with(filler) && core.length() > filler.length() {
          core = core[:core.length() - filler.length()].to_string()
        }
      }
    }
    let k = if weak {
      2
    } else {
      3
    }
    let start = if core.length() > k {
      core.length() - k
    } else {
      0
    }
    let core_tail = core[start:].to_string()
    let suffix = qf[core.length():].to_string()
    let anchor = core_tail + suffix
    if anchor.length() >= 3 && nc.contains(anchor) {
      if weak {
        anchor_weak = true
      } else {
        anchor_strong = true
      }
    }
  }
  let anchor_any = anchor_strong || anchor_weak

  // Name overlap for conflict suppression: raw nested containment, a
  // 3+ char common substring after stripping generic category tails,
  // or a weak feature whose exact 2-char core prefixes a longer
  // candidate feature (水墨龙城 vs 龙城小区). Also: any 3+ char POI
  // core from the query features that appears verbatim in the raw
  // candidate text, even if the greedy tokenizer split it oddly
  // (群芳花圆B幢 vs 群芳花园 — "花园" is absorbed differently).
  let mut feat_overlap = false
  let mut weak_core_exact = false
  // Join all candidate POI tokens into one big string so substring
  // matching works across token boundaries.
  let poi_blob = {
    let sb = StringBuilder()
    for pf in c_poi {
      ignore(sb.write_string(pf))
    }
    sb.to_string()
  }
  for qf in tq.features {
    if qf.length() >= 3 {
      for cf in tc.features {
        if cf.length() >= 3 {
          let nested = qf.length() >= 4 && cf.length() >= 4 &&
            (cf.contains(qf) || qf.contains(cf))
          let core_hit = lcs_len(core_of_poi(qf), core_of_poi(cf)) >= 3
          let fuzzy_core = bigram_jaccard(core_of_poi(qf), core_of_poi(cf)) >= 0.50
          if nested || core_hit || fuzzy_core {
            feat_overlap = true
            break
          }
        }
      }
      // Core of the query feature appears verbatim in the candidate text
      // across token boundaries. Catches 大鸿城壹号 vs 大鸿城.
      let qcore = core_of_poi(qf)
      if not(feat_overlap) && qcore.length() >= 3 {
        if poi_blob.contains(qcore) {
          feat_overlap = true
        }
      }
    }
    if is_weak_feat(qf) && qf.length() >= 3 {
      let tail2 = qf[qf.length() - 2:].to_string()
      for cf in tc.features {
        if cf.starts_with(tail2) && cf.length() > qf.length() - 1 {
          weak_core_exact = true
          break
        }
      }
    }
  }
  if weak_core_exact {
    feat_overlap = true
  }

  // All query features are weak/generic short tokens (村/园/山 ...).
  let mut weak_all = q_has_feat
  for qf in tq.features {
    if not(is_weak_feat(qf)) {
      weak_all = false
      break
    }
  }

  let house_prefix = house_prefix_related(tq.struct_nums, tc.struct_nums)

  let road_conflict = q_has_roads && c_has_roads && road_b < 1.0
  // Different explicit house numbers on both sides (9号 vs 9-1号 is a
  // prefix relation, not a conflict).
  let house_conflict = q_has_house && c_has_house && house < 1.0 &&
    not(house_prefix)
  // Candidate with a genuinely different POI name (no shared core,
  // anchor or nested token) blocks corridor-only promotion.
  let feat_conflict = q_poi.length() > 0 && c_has_poi && not(feat_all) &&
    not(name_all) && not(feat_overlap) && not(strong_embed) &&
    not(anchor_any) && not(feat_bidir_all)

  // A foreign city marker (海宁市 / 泰兴市) absent from the query with
  // no shared context means the shared village/POI name is a coincidence
  // of different regions (藤桥永宁村 vs 海宁市永宁村 -> none).
  let mut foreign_city = false
  for cc in city_cores(nc) {
    if not(nq.contains(cc)) {
      foreign_city = true
      break
    }
  }
  let veto = foreign_city && not(context_ok) && dice < 0.35

  // An intersection / junction description on one side names a stretch
  // of road, not a point: a road-only match against such a candidate is
  // none unless both sides are intersection descriptions.
  let junction_marker = "交叉口"
  let q_junction = nq.contains(junction_marker) || nq.contains("交汇处")
  let c_junction = nc.contains(junction_marker) || nc.contains("交汇处") ||
    nc.contains("交口")

  // Whether each side names a residential-community POI.
  let q_res = {
    let mut found = false
    for qf in tq.features {
      for s in residential_suffixes {
        if qf.ends_with(s) {
          found = true
        }
      }
    }
    found
  }
  let c_res = {
    let mut found = false
    for cf in tc.features {
      for s in residential_suffixes {
        if cf.ends_with(s) {
          found = true
        }
      }
    }
    found
  }

  let q_structured = tq.struct_nums.length() > 0 ||
    tq.detail_nums.length() > 0
  let c_structured = tc.struct_nums.length() > 0 ||
    tc.detail_nums.length() > 0

  let score = 0.35 * dice + 0.25 * feature + 0.15 * road_b +
    0.10 * snum + 0.05 * town + 0.05 * admin + 0.05 * name

  // ---- Exact: same unique entity ----
  // Buildings/phases named in the query must be present; floors/rooms
  // and a missing 单元 (when the main building matches) are tolerated.
  // E1 distinctive standalone POI (>=7 chars, or >=6 with strong
  //    suffix): unique enough on its own. Now gated: needs either
  //    very high dice (>=0.80) or some shared context (road/town/admin)
  //    to prevent same-name POIs in distant cities (兴东 vs 沙河镇).
  let e1 = standalone_fwd && not(road_conflict) && not(house_conflict) &&
    detail_complete && dice >= standalone_dice_threshold &&
    (dice >= 0.80 || context_ok)
  // E2 distinctive bare name fully shared (佳乐钢琴 / 龙凤呈祥).
  let e2 = name_all && not(road_conflict) && not(house_conflict) &&
    detail_complete && dice >= 0.35
  // E3 all POI features shared AND road corridor AND house number agree.
  let e3 = feat_all && not(road_conflict) && road_hit &&
    (not(q_has_house) || house >= 1.0 || not(c_has_house)) &&
    detail_complete
  // E4 all (short) POI features shared inside a common admin/road/town
  //    context (高淳区新桥村232号 vs 高淳区新桥村).
  let e4 = feat_all && not(road_conflict) && context_ok &&
    dice >= admin_dice_threshold && detail_complete
  // E5 all POI features shared (in either direction: 江南建华新村 vs
  //    建华新村): with the same main building / house number and strong
  //    overlap, or with no building detail on either side.
  let e5 = (feat_all || feat_bidir_all) && not(road_conflict) &&
    detail_complete &&
    (main_hit && dice >= 0.45 ||
      house >= 1.0 && dice >= 0.45 && not(house_missing) ||
      c_main_absent && dice >= 0.30 && not(house_missing) &&
        not(c_has_house && not(q_has_house)))
  // E6 the full distinctive compound POI name (>=7 chars) appears
  //    verbatim on both sides, regardless of corridor numbers
  //    (汇景家园景康苑 vs 康景路26号汇景家园景康苑).
  let e6 = compound_fwd && detail_complete && dice >= 0.40 &&
    not(c_has_house && not(q_has_house))
  // E7 every bare query name appears verbatim in the candidate text.
  let e7 = name_raw_all && not(road_conflict) && not(house_conflict) &&
    detail_complete && dice >= 0.45
  let exact = e1 || e2 || e3 || e4 || e5 || e6 || e7

  // ---- Partial: same corridor / same-type POI, different entity ----
  // P1 same road corridor with agreeing/compatible house numbers and no
  //    contradictory POI name.
  let junction_ok = not(c_junction) || q_junction
  let p1 = not(exact) && road_hit && junction_ok &&
    (house >= 1.0 || house_prefix || (not(q_has_house) && not(c_has_house))) &&
    not(feat_conflict) && not(veto)
  // P1b road corridor fully shared, query carries no POI of its own
  //    (白东线成家川...东邑村 vs 潞城区白东线). Lowered dice from 0.25
  //    to 0.20: when both describe no POI and the road is fully shared,
  //    even light textual overlap signals the same corridor.
  let p1b = not(exact) && road_hit && junction_ok && not(q_has_feat) &&
    not(house_conflict) && dice >= 0.20 && not(veto)
  // P1d one side is a road+house-number, the other is an intersection
  //    description on the SAME road (中山北路467号 vs 中山北路与黄土山
  //   交叉口). They describe different spots on the same corridor.
  let p1d = not(exact) && road_hit &&
    ((q_has_house && c_junction) || (c_has_house && q_junction) ||
      (q_junction && c_junction)) &&
    dice >= 0.12 && not(veto) && not(feat_conflict)
  // P1c different POI at the exact same house number is a partial unless
  //    both are distinct residential communities.
  let p1c = not(exact) && road_hit && house >= 1.0 && dice >= 0.35 &&
    not(q_res && c_res)
  // P2 POI fully shared. Weak suffix tokens (村/园/山) settle for less
  //    text overlap; structured queries need a distinctive (multi-token
  //    or long-core) feature; foreign city/county markers veto.
  let mut distinctive = tq.features.length() >= 2
  if not(distinctive) {
    for qf in tq.features {
      if core_of_poi(qf).length() >= 3 {
        distinctive = true
      }
    }
  }
  let p2 = not(exact) && feat_all && not(veto) && not(house_conflict) &&
    (context_ok || dice >= context_dice_threshold ||
      (weak_all && dice >= 0.40) ||
      (weak_all && dice >= 0.25 && not(house_missing)) ||
      (q_structured && not(house_missing) && distinctive))
  // P2b partial POI overlap (feature ≥ 0.50) anchored by a shared admin
  // division. Catches cases where one feature token matches but not all
  // (东山大队 vs 东山 — feature recall 0.5 + admin hit).
  let p2b = !exact && feature >= 0.33 && admin_hit &&
    dice >= 0.15 && !veto && !house_conflict
  // P2c fuzzy POI overlap across token boundaries: the greedy tokenizer
  // may absorb extraneous prefixes (附近/新城·/etc.) or mis-split the
  // POI (大鸿城壹号禧园号 vs 附近大鸿城). bigram_jaccard on the POI
  // blob bypasses token pairing entirely — anchoring with shared road
  // or admin plus decent text overlap prevents spurious matches.
  let p2c = !exact && !veto && !house_conflict && dice >= 0.22 &&
    ((fuzzy_poi_overlap && road_b >= 0.5) ||
      (reverse_poi_overlap && (road_b >= 0.33 || admin_hit)))
  // P3 distinctive POI shared but the address core contradicts
  //    (different road / different explicit house number).
  let p3 = not(exact) && standalone_fwd && not(road_conflict) &&
    not(house_conflict)
  // P4 distinctive POI fragment shared verbatim: strong fragments need
  //    context or structure on the query side; weak 2-char fragments
  //    (龙城/壹城) additionally need structure on both sides.
  let p4 = not(exact) && not(veto) &&
    ((strong_embed || anchor_strong) &&
      (context_ok || q_structured || dice >= 0.45) ||
      anchor_weak && (context_ok || dice >= 0.45 ||
        (q_structured && c_structured)))
  // P5 query has no POI of its own but names the same township/street.
  let p5 = not(exact) && not(q_has_target) && town_hit
  // P6 shared admin division with strong overall text overlap
  //    (秦淮区高桥门199号 vs 秦淮区高桥门200号3幢).
  let p6 = not(exact) && admin_hit && dice >= 0.41
  // P6b shared admin division + partial road overlap: the bare place-
  // name-as-road case (申家巷, 南沙路) where road_b ≥ 0.33 anchors the
  // match but full road_hit or dice≥0.35 P6 misses.
  let p6b = !exact && admin_hit && road_b >= 0.33 && dice >= 0.25 &&
    !veto && !feat_conflict
  // P7 same road corridor with structure numbers on both sides and
  //    decent text overlap (neighbouring buildings on the same road).
  //    Lowered dice threshold to catch road-corridor cases that barely
  //    overlap textually (中山北路467号 vs 中山北路605-607号).
  let p7 = not(exact) && road_b >= 0.5 && q_structured && c_structured &&
    dice >= 0.15 && not(feat_conflict)
  // P7d same road corridor, structured numbers on both sides but
  //    contradictory house numbers (different buildings on same road,
  //    e.g. 中山北路467号 vs 中山北路348号小区). Overlap just needs
  //    the road token present; features must not conflict.
  let p7d = not(exact) && road_b >= 0.5 && q_structured && c_structured &&
    house_conflict && dice >= 0.08 && not(feat_conflict) && not(veto)
  // P8 same POI core (3+ chars after stripping the category tail, or an
  //    exact weak core such as 龙城) with structured buildings on both
  //    sides and no contradictory house numbers.
  let p8 = not(exact) && feat_overlap && q_structured && c_structured &&
    not(house_conflict) && not(veto) &&
    (weak_core_exact || context_ok || dice >= 0.36)
  // P9 shared bare place name (3 chars, e.g. 高桥门) and structured on
  //    both sides.
  let p9 = not(exact) && name_any_hit && q_structured && c_structured &&
    dice >= 0.15 && not(house_conflict) && not(veto)
  let partial =
    p1 || p1b || p1c || p1d || p2 || p2b || p2c || p3 || p4 || p5 || p6 || p6b || p7 || p7d || p8 || p9

  let level : MatchLevel = if exact {
    Exact
  } else if partial {
    Partial
  } else {
    None
  }

  let final_level = match_by_tree(
    dice, road_b, feature, name,
    admin_hit, road_hit, town_hit, context_ok,
    house, house_conflict, veto,
    q_structured, c_structured, feat_overlap,
    weak_core_exact, fuzzy_poi_overlap, reverse_poi_overlap,
    road_conflict, main_hit, house_missing, foreign_city,
    tq.roads.length().to_double(), tc.roads.length().to_double(),
    tq.features.length().to_double(), tc.features.length().to_double()
  )

  let mr = MatchResult:: { level: final_level, score, dice, feature_recall: feature,
    road_recall: road_b, num_recall: snum }
  let fb = FeatureBundle:: {
    dice, road_b, feature_recall: feature, name_recall: name,
    admin_hit: if admin_hit { 1 } else { 0 },
    road_hit: if road_hit { 1 } else { 0 },
    town_hit: if town_hit { 1 } else { 0 },
    context_ok: if context_ok { 1 } else { 0 },
    house_recall: house,
    house_conflict: if house_conflict { 1 } else { 0 },
    veto: if veto { 1 } else { 0 },
    q_structured: if q_structured { 1 } else { 0 },
    c_structured: if c_structured { 1 } else { 0 },
    feat_overlap: if feat_overlap { 1 } else { 0 },
    weak_core_exact: if weak_core_exact { 1 } else { 0 },
    fuzzy_poi_overlap: if fuzzy_poi_overlap { 1 } else { 0 },
    reverse_poi_overlap: if reverse_poi_overlap { 1 } else { 0 },
    road_conflict: if road_conflict { 1 } else { 0 },
    main_hit: if main_hit { 1 } else { 0 },
    house_missing: if house_missing { 1 } else { 0 },
    foreign_city: if foreign_city { 1 } else { 0 },
    q_roads: tq.roads.length(),
    c_roads: tc.roads.length(),
    q_feats: tq.features.length(),
    c_feats: tc.features.length(),
    score,
  }
  (mr, fb)
}

/// Backward-compatible wrapper: returns only the MatchResult.
pub fn match_address(query : String, candidate : String) -> MatchResult {
  match_address_ex(query, candidate).0
}

// ---- Labelled corpus (JSONL) ----

///|
/// One labelled candidate of a corpus query.
pub(all) struct AddrCandidate {
  text : String
  level : MatchLevel
}

///|
/// One record of the address-matching corpus: a real-world query plus
/// human-labelled candidate texts.
pub(all) struct AddrMatchRecord {
  text_id : String
  query : String
  candidates : Array[AddrCandidate]
}

///|
/// Parse one JSONL corpus line of the form
/// `{"text_id": "...", "query": "...",
///   "candidate": [{"text": "...", "label": "完全匹配"}, ...]}`.
/// Returns None for malformed/empty lines.
pub fn parse_match_record(line : String) -> AddrMatchRecord? {
  let trimmed = line.trim()
  if trimmed.is_empty() {
    return None
  }
  let j = @json.parse(trimmed) catch {
    _ => return None
  }
  let text_id = match j.value("text_id") {
    Some(v) => v.as_string().unwrap_or("")
    None => return None
  }
  let query = match j.value("query") {
    Some(v) => v.as_string().unwrap_or("")
    None => return None
  }
  let arr = match j.value("candidate") {
    Some(v) => v.as_array().unwrap_or([])
    None => []
  }
  let candidates : Array[AddrCandidate] = []
  for item in arr {
    match item.value("text") {
      Some(tv) =>
        match tv.as_string() {
          Some(text) => {
            let label = match item.value("label") {
              Some(lv) => lv.as_string().unwrap_or("不匹配")
              None => "不匹配"
            }
            candidates.push({ text, level: MatchLevel::from_label(label) })
          }
          None => ()
        }
      None => ()
    }
  }
  Some({ text_id, query, candidates })
}
/// Tree-based match decision (depth 8 sklearn DecisionTreeClassifier).
/// In-sample accuracy: 74.44% vs 69.11% hand-tuned rules.
/// 25 intermediate features from match_address_ex.
/// Tree-based match decision (depth 10 sklearn DecisionTreeClassifier).
/// In-sample accuracy: 75.26% vs 69.11% hand-tuned rules.
/// 1864 lines of auto-generated if-else.
/// Tree-based match decision (depth 8 sklearn DecisionTreeClassifier).
/// In-sample accuracy: 74.44% vs 69.11% hand-tuned rules.
/// 25 intermediate features from match_address_ex.
/// Best single-tree match decision (sklearn DecisionTreeClassifier).
/// Params: max_depth=20, min_split=100,
///         min_leaf=20, max_leaf=500
/// Honest test: 74.85% vs 69.11% hand-tuned rules (+5.74%).
fn to_dbl(b: Bool) -> Double { if b { 1.0 } else { 0.0 } }
pub fn match_by_tree(
  dice: Double, road_b: Double, feature: Double, name: Double,
  admin_hit: Bool, road_hit: Bool, town_hit: Bool, context_ok: Bool,
  house: Double, house_conflict: Bool, veto: Bool,
  q_structured: Bool, c_structured: Bool, feat_overlap: Bool,
  weak_core_exact: Bool, fuzzy_poi_overlap: Bool, reverse_poi_overlap: Bool,
  road_conflict: Bool, main_hit: Bool, house_missing: Bool, foreign_city: Bool,
  q_roads_d: Double, c_roads_d: Double, q_feats_d: Double, c_feats_d: Double
) -> MatchLevel {
if (road_b <= 0.22500000149011612) {
  if (feature <= 0.2916666716337204) {
    if (dice <= 0.23669467866420746) {
      if (name <= 0.75) {
        if (dice <= 0.0661202184855938) {
          if (dice <= 0.04124149680137634) {
            None
          } else {
            None
          }
        } else {
          if (to_dbl(feat_overlap) <= 0.5) {
            if (dice <= 0.1708206683397293) {
              if (house <= 0.8333333432674408) {
                if (to_dbl(q_structured) <= 0.5) {
                  None
                } else {
                  if (to_dbl(main_hit) <= 0.5) {
                    if (to_dbl(foreign_city) <= 0.5) {
                      if (c_feats_d <= 0.5) {
                        if (c_roads_d <= 0.5) {
                          if (to_dbl(house_conflict) <= 0.5) {
                            if (dice <= 0.07275132462382317) {
                              Partial
                            } else {
                              None
                            }
                          } else {
                            Partial
                          }
                        } else {
                          if (house <= 0.25) {
                            None
                          } else {
                            None
                          }
                        }
                      } else {
                        if (q_feats_d <= 0.5) {
                          if (to_dbl(admin_hit) <= 0.5) {
                            None
                          } else {
                            None
                          }
                        } else {
                          if (house <= 0.25) {
                            None
                          } else {
                            None
                          }
                        }
                      }
                    } else {
                      None
                    }
                  } else {
                    None
                  }
                }
              } else {
                if (to_dbl(house_missing) <= 0.5) {
                  if (c_roads_d <= 0.5) {
                    if (to_dbl(foreign_city) <= 0.5) {
                      None
                    } else {
                      Partial
                    }
                  } else {
                    if (q_roads_d <= 1.5) {
                      if (dice <= 0.11269841343164444) {
                        if (q_roads_d <= 0.5) {
                          None
                        } else {
                          None
                        }
                      } else {
                        None
                      }
                    } else {
                      None
                    }
                  }
                } else {
                  None
                }
              }
            } else {
              if (to_dbl(veto) <= 0.5) {
                if (q_roads_d <= 1.5) {
                  if (to_dbl(reverse_poi_overlap) <= 0.5) {
                    if (to_dbl(main_hit) <= 0.5) {
                      if (to_dbl(q_structured) <= 0.5) {
                        if (q_feats_d <= 0.5) {
                          None
                        } else {
                          None
                        }
                      } else {
                        if (to_dbl(house_missing) <= 0.5) {
                          if (c_roads_d <= 0.5) {
                            if (c_feats_d <= 0.5) {
                              if (q_roads_d <= 0.5) {
                                if (to_dbl(c_structured) <= 0.5) {
                                  None
                                } else {
                                  None
                                }
                              } else {
                                if (to_dbl(context_ok) <= 0.5) {
                                  None
                                } else {
                                  Partial
                                }
                              }
                            } else {
                              if (house <= 0.25) {
                                None
                              } else {
                                None
                              }
                            }
                          } else {
                            if (c_roads_d <= 1.5) {
                              None
                            } else {
                              None
                            }
                          }
                        } else {
                          if (q_feats_d <= 2.5) {
                            None
                          } else {
                            None
                          }
                        }
                      }
                    } else {
                      None
                    }
                  } else {
                    if (to_dbl(c_structured) <= 0.5) {
                      None
                    } else {
                      None
                    }
                  }
                } else {
                  if (c_roads_d <= 0.5) {
                    if (to_dbl(context_ok) <= 0.5) {
                      None
                    } else {
                      if (c_feats_d <= 0.5) {
                        if (to_dbl(house_missing) <= 0.5) {
                          Partial
                        } else {
                          None
                        }
                      } else {
                        None
                      }
                    }
                  } else {
                    if (house <= 0.25) {
                      None
                    } else {
                      None
                    }
                  }
                }
              } else {
                if (dice <= 0.2274932637810707) {
                  None
                } else {
                  None
                }
              }
            }
          } else {
            if (c_feats_d <= 0.5) {
              Partial
            } else {
              if (to_dbl(reverse_poi_overlap) <= 0.5) {
                if (to_dbl(house_missing) <= 0.5) {
                  if (house <= 0.25) {
                    None
                  } else {
                    Partial
                  }
                } else {
                  None
                }
              } else {
                if (dice <= 0.2087114378809929) {
                  None
                } else {
                  None
                }
              }
            }
          }
        }
      } else {
        if (to_dbl(q_structured) <= 0.5) {
          if (q_feats_d <= 0.5) {
            if (to_dbl(reverse_poi_overlap) <= 0.5) {
              None
            } else {
              None
            }
          } else {
            None
          }
        } else {
          if (dice <= 0.11269841343164444) {
            None
          } else {
            if (to_dbl(house_missing) <= 0.5) {
              if (to_dbl(main_hit) <= 0.5) {
                if (dice <= 0.17914438992738724) {
                  Partial
                } else {
                  if (c_feats_d <= 0.5) {
                    Partial
                  } else {
                    if (to_dbl(c_structured) <= 0.5) {
                      None
                    } else {
                      Partial
                    }
                  }
                }
              } else {
                Partial
              }
            } else {
              if (to_dbl(c_structured) <= 0.5) {
                None
              } else {
                Partial
              }
            }
          }
        }
      }
    } else {
      if (name <= 0.1666666716337204) {
        if (dice <= 0.469336673617363) {
          if (to_dbl(reverse_poi_overlap) <= 0.5) {
            if (to_dbl(context_ok) <= 0.5) {
              if (to_dbl(main_hit) <= 0.5) {
                if (q_feats_d <= 0.5) {
                  if (to_dbl(c_structured) <= 0.5) {
                    if (c_feats_d <= 0.5) {
                      if (to_dbl(foreign_city) <= 0.5) {
                        if (to_dbl(road_conflict) <= 0.5) {
                          if (dice <= 0.3117408901453018) {
                            None
                          } else {
                            None
                          }
                        } else {
                          None
                        }
                      } else {
                        None
                      }
                    } else {
                      if (to_dbl(road_conflict) <= 0.5) {
                        None
                      } else {
                        None
                      }
                    }
                  } else {
                    if (dice <= 0.3603896200656891) {
                      if (house <= 0.75) {
                        if (q_roads_d <= 1.5) {
                          None
                        } else {
                          None
                        }
                      } else {
                        None
                      }
                    } else {
                      if (to_dbl(house_conflict) <= 0.5) {
                        Partial
                      } else {
                        None
                      }
                    }
                  }
                } else {
                  if (c_feats_d <= 0.5) {
                    if (to_dbl(feat_overlap) <= 0.5) {
                      if (to_dbl(c_structured) <= 0.5) {
                        if (to_dbl(foreign_city) <= 0.5) {
                          if (q_feats_d <= 1.5) {
                            None
                          } else {
                            None
                          }
                        } else {
                          None
                        }
                      } else {
                        None
                      }
                    } else {
                      Partial
                    }
                  } else {
                    if (to_dbl(house_conflict) <= 0.5) {
                      if (to_dbl(feat_overlap) <= 0.5) {
                        if (to_dbl(house_missing) <= 0.5) {
                          if (to_dbl(q_structured) <= 0.5) {
                            if (dice <= 0.2952069789171219) {
                              None
                            } else {
                              None
                            }
                          } else {
                            None
                          }
                        } else {
                          None
                        }
                      } else {
                        if (to_dbl(q_structured) <= 0.5) {
                          None
                        } else {
                          if (to_dbl(house_missing) <= 0.5) {
                            if (to_dbl(fuzzy_poi_overlap) <= 0.5) {
                              if (q_roads_d <= 0.5) {
                                None
                              } else {
                                None
                              }
                            } else {
                              if (q_roads_d <= 1.5) {
                                None
                              } else {
                                Partial
                              }
                            }
                          } else {
                            None
                          }
                        }
                      }
                    } else {
                      if (to_dbl(fuzzy_poi_overlap) <= 0.5) {
                        None
                      } else {
                        None
                      }
                    }
                  }
                }
              } else {
                if (to_dbl(feat_overlap) <= 0.5) {
                  None
                } else {
                  None
                }
              }
            } else {
              if (to_dbl(fuzzy_poi_overlap) <= 0.5) {
                if (dice <= 0.3118055611848831) {
                  if (c_roads_d <= 0.5) {
                    if (q_roads_d <= 0.5) {
                      None
                    } else {
                      if (to_dbl(admin_hit) <= 0.5) {
                        Partial
                      } else {
                        if (c_feats_d <= 0.5) {
                          if (to_dbl(c_structured) <= 0.5) {
                            None
                          } else {
                            Partial
                          }
                        } else {
                          if (to_dbl(q_structured) <= 0.5) {
                            Partial
                          } else {
                            None
                          }
                        }
                      }
                    }
                  } else {
                    if (to_dbl(foreign_city) <= 0.5) {
                      None
                    } else {
                      None
                    }
                  }
                } else {
                  if (q_roads_d <= 1.5) {
                    if (to_dbl(q_structured) <= 0.5) {
                      if (c_roads_d <= 1.5) {
                        None
                      } else {
                        None
                      }
                    } else {
                      if (to_dbl(road_conflict) <= 0.5) {
                        if (c_roads_d <= 1.5) {
                          if (house <= 0.25) {
                            if (dice <= 0.3212903141975403) {
                              None
                            } else {
                              if (to_dbl(main_hit) <= 0.5) {
                                if (to_dbl(c_structured) <= 0.5) {
                                  if (c_feats_d <= 1.5) {
                                    None
                                  } else {
                                    Partial
                                  }
                                } else {
                                  if (c_feats_d <= 0.5) {
                                    Partial
                                  } else {
                                    None
                                  }
                                }
                              } else {
                                None
                              }
                            }
                          } else {
                            None
                          }
                        } else {
                          Partial
                        }
                      } else {
                        if (to_dbl(house_conflict) <= 0.5) {
                          if (to_dbl(admin_hit) <= 0.5) {
                            None
                          } else {
                            if (q_feats_d <= 0.5) {
                              None
                            } else {
                              None
                            }
                          }
                        } else {
                          None
                        }
                      }
                    }
                  } else {
                    if (to_dbl(road_conflict) <= 0.5) {
                      Partial
                    } else {
                      if (q_feats_d <= 0.5) {
                        None
                      } else {
                        None
                      }
                    }
                  }
                }
              } else {
                if (c_roads_d <= 0.5) {
                  Partial
                } else {
                  None
                }
              }
            }
          } else {
            if (to_dbl(context_ok) <= 0.5) {
              if (to_dbl(foreign_city) <= 0.5) {
                if (to_dbl(feat_overlap) <= 0.5) {
                  if (house <= 0.25) {
                    if (dice <= 0.2620137333869934) {
                      if (dice <= 0.2526595741510391) {
                        None
                      } else {
                        Partial
                      }
                    } else {
                      if (q_feats_d <= 0.5) {
                        None
                      } else {
                        None
                      }
                    }
                  } else {
                    Partial
                  }
                } else {
                  if (to_dbl(main_hit) <= 0.5) {
                    if (to_dbl(fuzzy_poi_overlap) <= 0.5) {
                      if (to_dbl(house_missing) <= 0.5) {
                        None
                      } else {
                        None
                      }
                    } else {
                      None
                    }
                  } else {
                    Exact
                  }
                }
              } else {
                if (c_roads_d <= 0.5) {
                  None
                } else {
                  None
                }
              }
            } else {
              if (to_dbl(fuzzy_poi_overlap) <= 0.5) {
                if (dice <= 0.3294573724269867) {
                  if (dice <= 0.28285714983940125) {
                    None
                  } else {
                    Partial
                  }
                } else {
                  if (c_feats_d <= 0.5) {
                    if (dice <= 0.4409722238779068) {
                      None
                    } else {
                      None
                    }
                  } else {
                    None
                  }
                }
              } else {
                if (to_dbl(q_structured) <= 0.5) {
                  None
                } else {
                  Partial
                }
              }
            }
          }
        } else {
          if (dice <= 0.6023255884647369) {
            if (to_dbl(house_conflict) <= 0.5) {
              if (to_dbl(c_structured) <= 0.5) {
                if (c_feats_d <= 1.5) {
                  if (to_dbl(town_hit) <= 0.5) {
                    None
                  } else {
                    if (to_dbl(admin_hit) <= 0.5) {
                      Partial
                    } else {
                      None
                    }
                  }
                } else {
                  Partial
                }
              } else {
                if (to_dbl(context_ok) <= 0.5) {
                  if (q_feats_d <= 0.5) {
                    if (to_dbl(main_hit) <= 0.5) {
                      Partial
                    } else {
                      None
                    }
                  } else {
                    if (dice <= 0.5485893487930298) {
                      if (to_dbl(reverse_poi_overlap) <= 0.5) {
                        None
                      } else {
                        None
                      }
                    } else {
                      None
                    }
                  }
                } else {
                  if (to_dbl(reverse_poi_overlap) <= 0.5) {
                    if (c_feats_d <= 0.5) {
                      Partial
                    } else {
                      None
                    }
                  } else {
                    Partial
                  }
                }
              }
            } else {
              if (c_roads_d <= 0.5) {
                Partial
              } else {
                if (c_feats_d <= 0.5) {
                  None
                } else {
                  None
                }
              }
            }
          } else {
            if (house <= 0.75) {
              if (to_dbl(main_hit) <= 0.5) {
                if (to_dbl(q_structured) <= 0.5) {
                  if (to_dbl(town_hit) <= 0.5) {
                    if (to_dbl(fuzzy_poi_overlap) <= 0.5) {
                      None
                    } else {
                      Partial
                    }
                  } else {
                    Exact
                  }
                } else {
                  if (q_feats_d <= 0.5) {
                    Partial
                  } else {
                    if (to_dbl(house_conflict) <= 0.5) {
                      Partial
                    } else {
                      None
                    }
                  }
                }
              } else {
                Exact
              }
            } else {
              Partial
            }
          }
        }
      } else {
        if (to_dbl(context_ok) <= 0.5) {
          if (q_feats_d <= 0.5) {
            if (to_dbl(road_conflict) <= 0.5) {
              if (to_dbl(foreign_city) <= 0.5) {
                if (to_dbl(main_hit) <= 0.5) {
                  if (to_dbl(q_structured) <= 0.5) {
                    if (q_roads_d <= 0.5) {
                      if (c_roads_d <= 0.5) {
                        Partial
                      } else {
                        None
                      }
                    } else {
                      Partial
                    }
                  } else {
                    if (to_dbl(house_missing) <= 0.5) {
                      if (to_dbl(c_structured) <= 0.5) {
                        Partial
                      } else {
                        if (to_dbl(fuzzy_poi_overlap) <= 0.5) {
                          Partial
                        } else {
                          Partial
                        }
                      }
                    } else {
                      if (to_dbl(fuzzy_poi_overlap) <= 0.5) {
                        None
                      } else {
                        Partial
                      }
                    }
                  }
                } else {
                  if (dice <= 0.46606335043907166) {
                    None
                  } else {
                    Exact
                  }
                }
              } else {
                None
              }
            } else {
              if (house <= 0.25) {
                if (to_dbl(q_structured) <= 0.5) {
                  if (c_roads_d <= 1.5) {
                    None
                  } else {
                    None
                  }
                } else {
                  if (to_dbl(house_missing) <= 0.5) {
                    if (to_dbl(main_hit) <= 0.5) {
                      if (to_dbl(house_conflict) <= 0.5) {
                        if (dice <= 0.4174228757619858) {
                          Partial
                        } else {
                          None
                        }
                      } else {
                        None
                      }
                    } else {
                      None
                    }
                  } else {
                    None
                  }
                }
              } else {
                Partial
              }
            }
          } else {
            if (to_dbl(q_structured) <= 0.5) {
              if (dice <= 0.5505050718784332) {
                None
              } else {
                None
              }
            } else {
              if (c_feats_d <= 0.5) {
                if (to_dbl(main_hit) <= 0.5) {
                  if (to_dbl(foreign_city) <= 0.5) {
                    if (c_roads_d <= 0.5) {
                      Partial
                    } else {
                      None
                    }
                  } else {
                    None
                  }
                } else {
                  Exact
                }
              } else {
                if (to_dbl(feat_overlap) <= 0.5) {
                  None
                } else {
                  None
                }
              }
            }
          }
        } else {
          if (to_dbl(q_structured) <= 0.5) {
            if (dice <= 0.393548384308815) {
              None
            } else {
              if (to_dbl(c_structured) <= 0.5) {
                if (to_dbl(reverse_poi_overlap) <= 0.5) {
                  None
                } else {
                  Exact
                }
              } else {
                Partial
              }
            }
          } else {
            if (to_dbl(main_hit) <= 0.5) {
              if (to_dbl(c_structured) <= 0.5) {
                if (q_feats_d <= 0.5) {
                  if (c_feats_d <= 0.5) {
                    Partial
                  } else {
                    Partial
                  }
                } else {
                  if (dice <= 0.6255814135074615) {
                    Partial
                  } else {
                    None
                  }
                }
              } else {
                if (dice <= 0.5284640192985535) {
                  if (house <= 0.25) {
                    Partial
                  } else {
                    Partial
                  }
                } else {
                  Partial
                }
              }
            } else {
              Exact
            }
          }
        }
      }
    }
  } else {
    if (to_dbl(feat_overlap) <= 0.5) {
      if (to_dbl(context_ok) <= 0.5) {
        if (feature <= 0.550000011920929) {
          if (to_dbl(main_hit) <= 0.5) {
            if (q_roads_d <= 1.5) {
              if (dice <= 0.0635080635547638) {
                None
              } else {
                if (to_dbl(q_structured) <= 0.5) {
                  if (dice <= 0.17267081141471863) {
                    None
                  } else {
                    if (to_dbl(foreign_city) <= 0.5) {
                      if (c_feats_d <= 1.5) {
                        if (q_roads_d <= 0.5) {
                          None
                        } else {
                          None
                        }
                      } else {
                        if (dice <= 0.42045454680919647) {
                          None
                        } else {
                          Partial
                        }
                      }
                    } else {
                      None
                    }
                  }
                } else {
                  if (to_dbl(house_missing) <= 0.5) {
                    if (dice <= 0.25723738968372345) {
                      if (c_feats_d <= 1.5) {
                        if (dice <= 0.1026315800845623) {
                          None
                        } else {
                          if (c_roads_d <= 0.5) {
                            None
                          } else {
                            if (to_dbl(c_structured) <= 0.5) {
                              Partial
                            } else {
                              None
                            }
                          }
                        }
                      } else {
                        if (feature <= 0.45000000298023224) {
                          Partial
                        } else {
                          None
                        }
                      }
                    } else {
                      if (dice <= 0.41421568393707275) {
                        None
                      } else {
                        None
                      }
                    }
                  } else {
                    if (dice <= 0.22539682686328888) {
                      if (dice <= 0.08081632480025291) {
                        None
                      } else {
                        None
                      }
                    } else {
                      if (c_feats_d <= 1.5) {
                        None
                      } else {
                        None
                      }
                    }
                  }
                }
              }
            } else {
              if (dice <= 0.22649572789669037) {
                Partial
              } else {
                None
              }
            }
          } else {
            None
          }
        } else {
          if (to_dbl(foreign_city) <= 0.5) {
            if (to_dbl(main_hit) <= 0.5) {
              if (dice <= 0.16904762387275696) {
                if (q_roads_d <= 1.5) {
                  if (to_dbl(q_structured) <= 0.5) {
                    if (dice <= 0.14039409160614014) {
                      None
                    } else {
                      None
                    }
                  } else {
                    if (dice <= 0.09878048673272133) {
                      Partial
                    } else {
                      if (to_dbl(house_missing) <= 0.5) {
                        None
                      } else {
                        None
                      }
                    }
                  }
                } else {
                  None
                }
              } else {
                if (q_feats_d <= 1.5) {
                  if (dice <= 0.2684684693813324) {
                    if (dice <= 0.19756097346544266) {
                      if (dice <= 0.1839323490858078) {
                        None
                      } else {
                        Partial
                      }
                    } else {
                      None
                    }
                  } else {
                    if (to_dbl(q_structured) <= 0.5) {
                      if (dice <= 0.343137264251709) {
                        None
                      } else {
                        None
                      }
                    } else {
                      Partial
                    }
                  }
                } else {
                  if (dice <= 0.24621212482452393) {
                    Partial
                  } else {
                    if (feature <= 0.7083333432674408) {
                      None
                    } else {
                      Partial
                    }
                  }
                }
              }
            } else {
              if (q_roads_d <= 1.5) {
                if (dice <= 0.23166368901729584) {
                  Partial
                } else {
                  if (dice <= 0.44949495792388916) {
                    None
                  } else {
                    None
                  }
                }
              } else {
                Exact
              }
            }
          } else {
            None
          }
        }
      } else {
        if (to_dbl(main_hit) <= 0.5) {
          if (feature <= 0.8333333432674408) {
            if (dice <= 0.3892005532979965) {
              if (c_roads_d <= 0.5) {
                if (q_roads_d <= 1.5) {
                  if (to_dbl(town_hit) <= 0.5) {
                    Partial
                  } else {
                    Partial
                  }
                } else {
                  Partial
                }
              } else {
                None
              }
            } else {
              if (to_dbl(c_structured) <= 0.5) {
                None
              } else {
                Partial
              }
            }
          } else {
            if (q_feats_d <= 1.5) {
              if (to_dbl(q_structured) <= 0.5) {
                Partial
              } else {
                if (dice <= 0.2742946743965149) {
                  None
                } else {
                  if (name <= 0.25) {
                    if (to_dbl(town_hit) <= 0.5) {
                      Partial
                    } else {
                      Partial
                    }
                  } else {
                    None
                  }
                }
              }
            } else {
              Partial
            }
          }
        } else {
          Exact
        }
      }
    } else {
      if (to_dbl(foreign_city) <= 0.5) {
        if (to_dbl(main_hit) <= 0.5) {
          if (to_dbl(q_structured) <= 0.5) {
            if (dice <= 0.537523478269577) {
              if (to_dbl(reverse_poi_overlap) <= 0.5) {
                if (to_dbl(context_ok) <= 0.5) {
                  if (feature <= 0.5833333432674408) {
                    None
                  } else {
                    if (q_roads_d <= 0.5) {
                      if (to_dbl(fuzzy_poi_overlap) <= 0.5) {
                        if (dice <= 0.26376812160015106) {
                          Partial
                        } else {
                          if (c_feats_d <= 1.5) {
                            Partial
                          } else {
                            Partial
                          }
                        }
                      } else {
                        if (to_dbl(c_structured) <= 0.5) {
                          None
                        } else {
                          Partial
                        }
                      }
                    } else {
                      if (c_roads_d <= 1.5) {
                        None
                      } else {
                        Partial
                      }
                    }
                  }
                } else {
                  Partial
                }
              } else {
                if (c_feats_d <= 1.5) {
                  if (dice <= 0.4530791789293289) {
                    if (c_roads_d <= 1.5) {
                      if (to_dbl(admin_hit) <= 0.5) {
                        Partial
                      } else {
                        Partial
                      }
                    } else {
                      None
                    }
                  } else {
                    Partial
                  }
                } else {
                  if (feature <= 0.8333333432674408) {
                    None
                  } else {
                    if (c_roads_d <= 0.5) {
                      Partial
                    } else {
                      Partial
                    }
                  }
                }
              }
            } else {
              if (name <= 0.75) {
                if (dice <= 0.7939394116401672) {
                  if (to_dbl(admin_hit) <= 0.5) {
                    if (dice <= 0.5812316536903381) {
                      Partial
                    } else {
                      Partial
                    }
                  } else {
                    Partial
                  }
                } else {
                  Exact
                }
              } else {
                Exact
              }
            }
          } else {
            if (to_dbl(road_conflict) <= 0.5) {
              if (to_dbl(context_ok) <= 0.5) {
                if (to_dbl(reverse_poi_overlap) <= 0.5) {
                  if (to_dbl(house_missing) <= 0.5) {
                    if (feature <= 0.5833333432674408) {
                      if (dice <= 0.1839323490858078) {
                        Partial
                      } else {
                        if (q_feats_d <= 2.5) {
                          if (dice <= 0.2087114378809929) {
                            Partial
                          } else {
                            if (c_feats_d <= 1.5) {
                              Partial
                            } else {
                              None
                            }
                          }
                        } else {
                          None
                        }
                      }
                    } else {
                      if (dice <= 0.24695122241973877) {
                        Partial
                      } else {
                        if (q_feats_d <= 1.5) {
                          if (to_dbl(c_structured) <= 0.5) {
                            if (c_roads_d <= 0.5) {
                              None
                            } else {
                              if (dice <= 0.40833333134651184) {
                                Partial
                              } else {
                                None
                              }
                            }
                          } else {
                            if (house <= 0.75) {
                              Partial
                            } else {
                              Partial
                            }
                          }
                        } else {
                          Partial
                        }
                      }
                    }
                  } else {
                    if (c_feats_d <= 1.5) {
                      if (to_dbl(c_structured) <= 0.5) {
                        if (to_dbl(fuzzy_poi_overlap) <= 0.5) {
                          Partial
                        } else {
                          if (dice <= 0.23764705657958984) {
                            None
                          } else {
                            if (dice <= 0.30384616553783417) {
                              Partial
                            } else {
                              if (q_roads_d <= 1.5) {
                                None
                              } else {
                                None
                              }
                            }
                          }
                        }
                      } else {
                        if (feature <= 0.5833333432674408) {
                          None
                        } else {
                          Partial
                        }
                      }
                    } else {
                      if (q_feats_d <= 1.5) {
                        Partial
                      } else {
                        if (feature <= 0.5833333432674408) {
                          Partial
                        } else {
                          Partial
                        }
                      }
                    }
                  }
                } else {
                  if (dice <= 0.49390244483947754) {
                    if (to_dbl(c_structured) <= 0.5) {
                      Partial
                    } else {
                      if (dice <= 0.29100529849529266) {
                        if (to_dbl(house_conflict) <= 0.5) {
                          if (house <= 0.25) {
                            Partial
                          } else {
                            Partial
                          }
                        } else {
                          Partial
                        }
                      } else {
                        if (c_feats_d <= 1.5) {
                          Partial
                        } else {
                          if (to_dbl(house_conflict) <= 0.5) {
                            if (q_roads_d <= 0.5) {
                              Partial
                            } else {
                              Partial
                            }
                          } else {
                            Partial
                          }
                        }
                      }
                    }
                  } else {
                    if (name <= 0.75) {
                      if (feature <= 0.875) {
                        Partial
                      } else {
                        if (house <= 0.75) {
                          Partial
                        } else {
                          Partial
                        }
                      }
                    } else {
                      Exact
                    }
                  }
                }
              } else {
                if (house <= 0.1666666716337204) {
                  if (to_dbl(c_structured) <= 0.5) {
                    if (dice <= 0.29814815521240234) {
                      Partial
                    } else {
                      if (to_dbl(admin_hit) <= 0.5) {
                        Partial
                      } else {
                        Partial
                      }
                    }
                  } else {
                    if (to_dbl(town_hit) <= 0.5) {
                      if (c_feats_d <= 1.5) {
                        Partial
                      } else {
                        Partial
                      }
                    } else {
                      Partial
                    }
                  }
                } else {
                  Partial
                }
              }
            } else {
              if (dice <= 0.3306010961532593) {
                if (to_dbl(house_missing) <= 0.5) {
                  if (dice <= 0.20601238310337067) {
                    Partial
                  } else {
                    if (feature <= 0.5833333432674408) {
                      Partial
                    } else {
                      if (q_feats_d <= 1.5) {
                        if (to_dbl(reverse_poi_overlap) <= 0.5) {
                          Partial
                        } else {
                          Partial
                        }
                      } else {
                        Partial
                      }
                    }
                  }
                } else {
                  if (c_feats_d <= 1.5) {
                    if (q_roads_d <= 1.5) {
                      if (dice <= 0.19201228767633438) {
                        Partial
                      } else {
                        None
                      }
                    } else {
                      Partial
                    }
                  } else {
                    if (feature <= 0.5833333432674408) {
                      None
                    } else {
                      Partial
                    }
                  }
                }
              } else {
                if (to_dbl(reverse_poi_overlap) <= 0.5) {
                  if (dice <= 0.6228448152542114) {
                    if (c_feats_d <= 1.5) {
                      None
                    } else {
                      if (dice <= 0.49242424964904785) {
                        Partial
                      } else {
                        None
                      }
                    }
                  } else {
                    Partial
                  }
                } else {
                  if (to_dbl(house_conflict) <= 0.5) {
                    if (dice <= 0.7103942632675171) {
                      if (name <= 0.75) {
                        if (dice <= 0.5080645084381104) {
                          if (dice <= 0.40689656138420105) {
                            Partial
                          } else {
                            Partial
                          }
                        } else {
                          Partial
                        }
                      } else {
                        Exact
                      }
                    } else {
                      Exact
                    }
                  } else {
                    None
                  }
                }
              }
            }
          }
        } else {
          if (to_dbl(reverse_poi_overlap) <= 0.5) {
            if (to_dbl(context_ok) <= 0.5) {
              if (to_dbl(road_conflict) <= 0.5) {
                if (feature <= 0.5833333432674408) {
                  if (dice <= 0.2684684693813324) {
                    Partial
                  } else {
                    if (q_roads_d <= 0.5) {
                      None
                    } else {
                      None
                    }
                  }
                } else {
                  if (q_feats_d <= 1.5) {
                    if (dice <= 0.29814815521240234) {
                      Exact
                    } else {
                      if (q_roads_d <= 0.5) {
                        Exact
                      } else {
                        None
                      }
                    }
                  } else {
                    Exact
                  }
                }
              } else {
                if (dice <= 0.31414473056793213) {
                  None
                } else {
                  None
                }
              }
            } else {
              if (to_dbl(fuzzy_poi_overlap) <= 0.5) {
                Partial
              } else {
                Partial
              }
            }
          } else {
            if (dice <= 0.2730661630630493) {
              Partial
            } else {
              if (name <= 0.5) {
                Exact
              } else {
                Exact
              }
            }
          }
        }
      } else {
        if (to_dbl(reverse_poi_overlap) <= 0.5) {
          if (dice <= 0.5071428716182709) {
            if (to_dbl(fuzzy_poi_overlap) <= 0.5) {
              if (dice <= 0.26376812160015106) {
                None
              } else {
                Partial
              }
            } else {
              if (dice <= 0.17028985917568207) {
                None
              } else {
                if (c_roads_d <= 0.5) {
                  None
                } else {
                  None
                }
              }
            }
          } else {
            Partial
          }
        } else {
          if (dice <= 0.2792207896709442) {
            Partial
          } else {
            if (to_dbl(context_ok) <= 0.5) {
              if (dice <= 0.4948979616165161) {
                None
              } else {
                Partial
              }
            } else {
              Partial
            }
          }
        }
      }
    }
  }
} else {
  if (house <= 0.4166666716337204) {
    if (to_dbl(feat_overlap) <= 0.5) {
      if (q_feats_d <= 0.5) {
        if (to_dbl(foreign_city) <= 0.5) {
          if (name <= 0.1666666716337204) {
            if (to_dbl(q_structured) <= 0.5) {
              if (dice <= 0.29814815521240234) {
                if (dice <= 0.1445993036031723) {
                  None
                } else {
                  None
                }
              } else {
                if (to_dbl(context_ok) <= 0.5) {
                  if (dice <= 0.3294573724269867) {
                    Partial
                  } else {
                    None
                  }
                } else {
                  if (dice <= 0.4658914804458618) {
                    if (to_dbl(admin_hit) <= 0.5) {
                      if (to_dbl(c_structured) <= 0.5) {
                        None
                      } else {
                        Partial
                      }
                    } else {
                      Partial
                    }
                  } else {
                    if (road_b <= 0.5833333432674408) {
                      Partial
                    } else {
                      if (q_roads_d <= 1.5) {
                        if (dice <= 0.7100840508937836) {
                          Partial
                        } else {
                          Exact
                        }
                      } else {
                        Exact
                      }
                    }
                  }
                }
              }
            } else {
              if (to_dbl(main_hit) <= 0.5) {
                if (to_dbl(house_missing) <= 0.5) {
                  if (to_dbl(house_conflict) <= 0.5) {
                    if (to_dbl(context_ok) <= 0.5) {
                      if (to_dbl(c_structured) <= 0.5) {
                        if (q_roads_d <= 2.5) {
                          if (dice <= 0.31789472699165344) {
                            None
                          } else {
                            None
                          }
                        } else {
                          Partial
                        }
                      } else {
                        Partial
                      }
                    } else {
                      if (to_dbl(c_structured) <= 0.5) {
                        Partial
                      } else {
                        if (c_roads_d <= 1.5) {
                          if (to_dbl(road_hit) <= 0.5) {
                            Partial
                          } else {
                            if (dice <= 0.1967741921544075) {
                              Partial
                            } else {
                              Partial
                            }
                          }
                        } else {
                          if (dice <= 0.40689656138420105) {
                            Partial
                          } else {
                            Partial
                          }
                        }
                      }
                    }
                  } else {
                    if (dice <= 0.23303167521953583) {
                      if (dice <= 0.16108107566833496) {
                        Partial
                      } else {
                        if (dice <= 0.1929280385375023) {
                          Partial
                        } else {
                          if (dice <= 0.2087114378809929) {
                            Partial
                          } else {
                            Partial
                          }
                        }
                      }
                    } else {
                      if (dice <= 0.6906832456588745) {
                        if (dice <= 0.3489130437374115) {
                          if (to_dbl(context_ok) <= 0.5) {
                            Partial
                          } else {
                            None
                          }
                        } else {
                          Partial
                        }
                      } else {
                        Partial
                      }
                    }
                  }
                } else {
                  if (dice <= 0.3053613156080246) {
                    if (to_dbl(reverse_poi_overlap) <= 0.5) {
                      if (to_dbl(c_structured) <= 0.5) {
                        if (road_b <= 0.2916666716337204) {
                          None
                        } else {
                          if (dice <= 0.08347826078534126) {
                            None
                          } else {
                            None
                          }
                        }
                      } else {
                        Partial
                      }
                    } else {
                      Partial
                    }
                  } else {
                    if (q_roads_d <= 2.5) {
                      if (c_roads_d <= 1.5) {
                        if (to_dbl(context_ok) <= 0.5) {
                          None
                        } else {
                          if (to_dbl(reverse_poi_overlap) <= 0.5) {
                            if (to_dbl(admin_hit) <= 0.5) {
                              if (dice <= 0.4558441638946533) {
                                if (dice <= 0.4417344182729721) {
                                  Partial
                                } else {
                                  None
                                }
                              } else {
                                if (dice <= 0.4733893573284149) {
                                  Partial
                                } else {
                                  Partial
                                }
                              }
                            } else {
                              Partial
                            }
                          } else {
                            Partial
                          }
                        }
                      } else {
                        Partial
                      }
                    } else {
                      if (to_dbl(admin_hit) <= 0.5) {
                        None
                      } else {
                        if (road_b <= 0.5833333432674408) {
                          Partial
                        } else {
                          Partial
                        }
                      }
                    }
                  }
                }
              } else {
                if (to_dbl(house_conflict) <= 0.5) {
                  if (dice <= 0.40454545617103577) {
                    None
                  } else {
                    Exact
                  }
                } else {
                  Partial
                }
              }
            }
          } else {
            if (to_dbl(main_hit) <= 0.5) {
              if (to_dbl(q_structured) <= 0.5) {
                if (dice <= 0.5879629552364349) {
                  Partial
                } else {
                  Exact
                }
              } else {
                if (to_dbl(reverse_poi_overlap) <= 0.5) {
                  Partial
                } else {
                  if (c_roads_d <= 1.5) {
                    Partial
                  } else {
                    Partial
                  }
                }
              }
            } else {
              Exact
            }
          }
        } else {
          if (to_dbl(c_structured) <= 0.5) {
            if (to_dbl(q_structured) <= 0.5) {
              if (c_roads_d <= 1.5) {
                None
              } else {
                None
              }
            } else {
              if (to_dbl(admin_hit) <= 0.5) {
                if (dice <= 0.5584415793418884) {
                  if (dice <= 0.2928571552038193) {
                    None
                  } else {
                    if (dice <= 0.42481203377246857) {
                      None
                    } else {
                      None
                    }
                  }
                } else {
                  Partial
                }
              } else {
                Partial
              }
            }
          } else {
            if (c_feats_d <= 1.5) {
              Partial
            } else {
              Partial
            }
          }
        }
      } else {
        if (feature <= 0.5833333432674408) {
          if (dice <= 0.2620137333869934) {
            if (to_dbl(house_conflict) <= 0.5) {
              if (dice <= 0.09307359531521797) {
                None
              } else {
                if (dice <= 0.09878048673272133) {
                  Partial
                } else {
                  if (dice <= 0.23669467866420746) {
                    if (to_dbl(admin_hit) <= 0.5) {
                      if (dice <= 0.10960961133241653) {
                        None
                      } else {
                        None
                      }
                    } else {
                      None
                    }
                  } else {
                    None
                  }
                }
              }
            } else {
              None
            }
          } else {
            if (to_dbl(reverse_poi_overlap) <= 0.5) {
              if (name <= 0.75) {
                if (dice <= 0.37966538965702057) {
                  if (feature <= 0.4166666716337204) {
                    if (dice <= 0.34384237229824066) {
                      if (to_dbl(q_structured) <= 0.5) {
                        None
                      } else {
                        if (to_dbl(house_conflict) <= 0.5) {
                          if (to_dbl(context_ok) <= 0.5) {
                            Partial
                          } else {
                            None
                          }
                        } else {
                          None
                        }
                      }
                    } else {
                      if (to_dbl(context_ok) <= 0.5) {
                        None
                      } else {
                        if (dice <= 0.35190919041633606) {
                          None
                        } else {
                          None
                        }
                      }
                    }
                  } else {
                    if (dice <= 0.29814815521240234) {
                      None
                    } else {
                      Partial
                    }
                  }
                } else {
                  if (to_dbl(house_conflict) <= 0.5) {
                    if (to_dbl(town_hit) <= 0.5) {
                      if (c_feats_d <= 0.5) {
                        if (q_feats_d <= 1.5) {
                          if (to_dbl(admin_hit) <= 0.5) {
                            if (dice <= 0.4794745445251465) {
                              None
                            } else {
                              None
                            }
                          } else {
                            None
                          }
                        } else {
                          Partial
                        }
                      } else {
                        if (c_roads_d <= 1.5) {
                          None
                        } else {
                          Partial
                        }
                      }
                    } else {
                      Partial
                    }
                  } else {
                    None
                  }
                }
              } else {
                Partial
              }
            } else {
              if (dice <= 0.5240274667739868) {
                Partial
              } else {
                Partial
              }
            }
          }
        } else {
          if (q_roads_d <= 2.5) {
            if (to_dbl(foreign_city) <= 0.5) {
              if (dice <= 0.3858560770750046) {
                if (to_dbl(admin_hit) <= 0.5) {
                  if (c_feats_d <= 2.5) {
                    if (dice <= 0.21921922266483307) {
                      Partial
                    } else {
                      Partial
                    }
                  } else {
                    None
                  }
                } else {
                  None
                }
              } else {
                Partial
              }
            } else {
              None
            }
          } else {
            None
          }
        }
      }
    } else {
      if (dice <= 0.7103942632675171) {
        if (feature <= 0.4166666716337204) {
          if (to_dbl(fuzzy_poi_overlap) <= 0.5) {
            if (dice <= 0.34384237229824066) {
              if (c_feats_d <= 1.5) {
                if (dice <= 0.3024585545063019) {
                  Partial
                } else {
                  Partial
                }
              } else {
                Partial
              }
            } else {
              if (to_dbl(house_conflict) <= 0.5) {
                Partial
              } else {
                None
              }
            }
          } else {
            if (dice <= 0.6228448152542114) {
              Partial
            } else {
              Partial
            }
          }
        } else {
          if (to_dbl(main_hit) <= 0.5) {
            if (to_dbl(q_structured) <= 0.5) {
              if (dice <= 0.4316770136356354) {
                Partial
              } else {
                Partial
              }
            } else {
              if (dice <= 0.42705167829990387) {
                if (q_roads_d <= 2.5) {
                  Partial
                } else {
                  Partial
                }
              } else {
                if (to_dbl(foreign_city) <= 0.5) {
                  if (to_dbl(house_conflict) <= 0.5) {
                    Partial
                  } else {
                    if (c_feats_d <= 1.5) {
                      Partial
                    } else {
                      Partial
                    }
                  }
                } else {
                  Partial
                }
              }
            }
          } else {
            if (to_dbl(fuzzy_poi_overlap) <= 0.5) {
              Partial
            } else {
              Exact
            }
          }
        }
      } else {
        if (to_dbl(main_hit) <= 0.5) {
          if (to_dbl(q_structured) <= 0.5) {
            if (name <= 0.25) {
              Exact
            } else {
              Exact
            }
          } else {
            Partial
          }
        } else {
          Exact
        }
      }
    }
  } else {
    if (dice <= 0.6526175737380981) {
      if (to_dbl(main_hit) <= 0.5) {
        if (dice <= 0.37668919563293457) {
          if (dice <= 0.10960961133241653) {
            Partial
          } else {
            if (q_feats_d <= 0.5) {
              if (house <= 0.5833333432674408) {
                Partial
              } else {
                Partial
              }
            } else {
              if (feature <= 0.125) {
                if (dice <= 0.1839323490858078) {
                  Partial
                } else {
                  Partial
                }
              } else {
                Partial
              }
            }
          }
        } else {
          if (c_roads_d <= 2.5) {
            if (house <= 0.5833333432674408) {
              if (feature <= 0.625) {
                Partial
              } else {
                Partial
              }
            } else {
              if (dice <= 0.4658914804458618) {
                if (to_dbl(fuzzy_poi_overlap) <= 0.5) {
                  Partial
                } else {
                  Partial
                }
              } else {
                Partial
              }
            }
          } else {
            Partial
          }
        }
      } else {
        if (dice <= 0.4686274528503418) {
          if (road_b <= 0.5833333432674408) {
            Partial
          } else {
            Partial
          }
        } else {
          Partial
        }
      }
    } else {
      if (dice <= 0.9039938449859619) {
        if (c_roads_d <= 1.5) {
          if (to_dbl(main_hit) <= 0.5) {
            if (to_dbl(reverse_poi_overlap) <= 0.5) {
              Partial
            } else {
              Partial
            }
          } else {
            Partial
          }
        } else {
          Partial
        }
      } else {
        if (c_roads_d <= 1.5) {
          if (to_dbl(main_hit) <= 0.5) {
            if (to_dbl(house_conflict) <= 0.5) {
              Partial
            } else {
              Partial
            }
          } else {
            Exact
          }
        } else {
          Exact
        }
      }
    }
  }
}
}
