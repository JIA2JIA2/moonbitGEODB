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

  let final_level = match_by_ensemble(
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
/// LightGBM (20 est×3cls, max_depth=6, lr=0.3).
/// Full-data: 75.90% vs 75.89% single tree (+0.01%).
fn to_dbl(b: Bool) -> Double { if b { 1.0 } else { 0.0 } }

pub fn match_by_ensemble(
  dice: Double, road_b: Double, feature: Double, name: Double,
  admin_hit: Bool, road_hit: Bool, town_hit: Bool, context_ok: Bool,
  house: Double, house_conflict: Bool, veto: Bool,
  q_structured: Bool, c_structured: Bool, feat_overlap: Bool,
  weak_core_exact: Bool, fuzzy_poi_overlap: Bool, reverse_poi_overlap: Bool,
  road_conflict: Bool, main_hit: Bool, house_missing: Bool, foreign_city: Bool,
  q_roads_d: Double, c_roads_d: Double, q_feats_d: Double, c_feats_d: Double
) -> MatchLevel {
  let mut s0 = 0.0
  let mut s1 = 0.0
  let mut s2 = 0.0


  // LGBM tree 0 (estim 0, class 0)
  s0 += (
    if (dice <= 0.462912087912088) {
      if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
        if (dice <= 0.2572373862696444) {
          if (dice <= 0.16271373414230558) {
            -2.9582318504004816
          } else {
            -2.8911621892869768
          }
        } else {
          if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
            if (dice <= 0.3879928315412187) {
              -2.740536441260283
            } else {
              -2.574432883487001
            }
          } else {
            if (house <= 1.0000000180025095e-35) {
              -2.8576374219863223
            } else {
              if (q_roads_d <= 1.0000000180025095e-35) {
                -2.2787010366607214
              } else {
                -2.732044786364645
              }
            }
          }
        }
      } else {
        if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
          if (feature <= 0.5500000000000002) {
            if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
              if (name <= 0.4166666666666667) {
                -2.820546718940367
              } else {
                -2.0492834482349416
              }
            } else {
              -2.455678118614563
            }
          } else {
            -2.0064668955128924
          }
        } else {
          if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
            if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
              if (feature <= 0.8750000000000001) {
                -2.382953746054489
              } else {
                -1.7730590262273351
              }
            } else {
              -1.4995221305735038
            }
          } else {
            -1.189500015161005
          }
        }
      }
    } else {
      if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
        if (dice <= 0.672316384180791) {
          if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
            if (name <= 0.5833333333333334) {
              -2.30323523345748
            } else {
              if (dice <= 0.5273088381330686) {
                -2.2799237659960454
              } else {
                -1.6487185845910841
              }
            }
          } else {
            if (house <= 0.5833333333333334) {
              -2.739730377773418
            } else {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                -2.0647234029790322
              } else {
                -2.4849017580544923
              }
            }
          }
        } else {
          if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
            if (name <= 0.5833333333333334) {
              -1.7672415648315984
            } else {
              if (feature <= 0.5500000000000002) {
                -1.3650714068998266
              } else {
                -0.27603187795383244
              }
            }
          } else {
            if (house <= 0.8333333333333334) {
              -2.4681806731269855
            } else {
              if (dice <= 0.9009803921568629) {
                -2.051421353904298
              } else {
                -1.4552169333033618
              }
            }
          }
        }
      } else {
        if (dice <= 0.5741758241758242) {
          -1.9704157146128203
        } else {
          if (dice <= 0.8193473193473194) {
            if (name <= 0.4166666666666667) {
              -1.4830544840849302
            } else {
              -0.5164763468288545
            }
          } else {
            -0.4542948122546884
          }
        }
      }
    }
  )

  // LGBM tree 1 (estim 0, class 1)
  s1 += (
    if (road_b <= 0.22500000000000003) {
      if (feature <= 0.2916666666666667) {
        if (dice <= 0.16784037558685447) {
          if (name <= 0.4166666666666667) {
            if (dice <= 0.057983193277310933) {
              -1.3799086951505128
            } else {
              -1.3206216761008407
            }
          } else {
            -1.0335159964181408
          }
        } else {
          if (name <= 1.0000000180025095e-35) {
            if (dice <= 0.31311274509803927) {
              if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
                -1.2618485815478282
              } else {
                -1.153833587686923
              }
            } else {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                -1.2059481333379864
              } else {
                -1.1014327142396365
              }
            }
          } else {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              -1.1629595738059453
            } else {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                -1.0062023334794117
              } else {
                -0.8173284142310071
              }
            }
          }
        }
      } else {
        if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
          if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
            if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                -1.082045610039035
              } else {
                -1.265196085046722
              }
            } else {
              -1.2976501055605825
            }
          } else {
            -0.8941430230994849
          }
        } else {
          if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                -0.9781363523053986
              } else {
                -1.1860930886379577
              }
            } else {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                -0.8367437667241303
              } else {
                -1.048561139807008
              }
            }
          } else {
            if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
              -1.1398164331527845
            } else {
              -0.9008545700571894
            }
          }
        }
      }
    } else {
      if (house <= 0.4166666666666667) {
        if (feature <= 0.45000000000000007) {
          if (q_feats_d <= 1.0000000180025095e-35) {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                -0.972203518574364
              } else {
                -1.22751288615242
              }
            } else {
              if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
                -0.8589008419462554
              } else {
                -1.0519185307485752
              }
            }
          } else {
            if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
              if (dice <= 0.23904761904761906) {
                -1.196078734139955
              } else {
                -1.064777897840571
              }
            } else {
              -0.8910032409212597
            }
          }
        } else {
          if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
            -0.772215061939457
          } else {
            -1.042821232703869
          }
        }
      } else {
        if (dice <= 0.6516683518705765) {
          -0.7133765420866622
        } else {
          -0.8332921783220317
        }
      }
    }
  )

  // LGBM tree 2 (estim 0, class 2)
  s2 += (
    if (road_b <= 0.22500000000000003) {
      if (feature <= 0.2916666666666667) {
        if (dice <= 0.2572373862696444) {
          if (name <= 0.5833333333333334) {
            if (dice <= 0.14415584415584418) {
              if (dice <= 0.057983193277310933) {
                -0.1974240361827186
              } else {
                -0.2522220271232599
              }
            } else {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                -0.3044209215220669
              } else {
                -0.43389959193078315
              }
            }
          } else {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              -0.41015089787779624
            } else {
              if (dice <= 0.11215932914046123) {
                -0.33745344043752407
              } else {
                -0.6896460601234774
              }
            }
          }
        } else {
          if (name <= 1.0000000180025095e-35) {
            if (dice <= 0.46737588652482276) {
              if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
                -0.38341378016418315
              } else {
                -0.4872784467592528
              }
            } else {
              -0.5619433443719621
            }
          } else {
            if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
              if (q_feats_d <= 1.0000000180025095e-35) {
                -0.6389359107514032
              } else {
                -0.45380317214722105
              }
            } else {
              -0.7980728328988111
            }
          }
        }
      } else {
        if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
          if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
            if (feature <= 0.5500000000000002) {
              -0.4071896209891197
            } else {
              -0.5484530083960969
            }
          } else {
            -0.7224072225157893
          }
        } else {
          if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
            if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                -0.6704210412273133
              } else {
                -0.8494263659292375
              }
            } else {
              if (dice <= 0.5045454545454546) {
                -0.3911526903093338
              } else {
                -0.7540958578102669
              }
            }
          } else {
            -0.8154500391309842
          }
        }
      }
    } else {
      if (house <= 0.4166666666666667) {
        if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
          if (q_feats_d <= 1.0000000180025095e-35) {
            if (name <= 1.0000000180025095e-35) {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                -0.6915604105498177
              } else {
                -0.5178255580122084
              }
            } else {
              -0.8977506104954556
            }
          } else {
            if (feature <= 0.5500000000000002) {
              if (dice <= 0.26201372997711675) {
                -0.3965382710544949
              } else {
                -0.563248609905797
              }
            } else {
              -0.785521233828543
            }
          }
        } else {
          if (feature <= 0.45000000000000007) {
            -0.7649481881430644
          } else {
            -0.8981747733784013
          }
        }
      } else {
        if (dice <= 0.37617924528301894) {
          -0.8578788968013643
        } else {
          -0.9330566516631287
        }
      }
    }
  )

  // LGBM tree 3 (estim 1, class 0)
  s0 += (
    if (dice <= 0.34216027874564464) {
      if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
        if (dice <= 0.1719211822660099) {
          -0.1669794444733553
        } else {
          if (house <= 0.8333333333333334) {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              if (name <= 0.5833333333333334) {
                -0.04598735245304325
              } else {
                0.18671656445331442
              }
            } else {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                -0.13388692048183184
              } else {
                -0.06224911741317818
              }
            }
          } else {
            if (c_roads_d <= 1.5000000000000002) {
              if (feature <= 0.8750000000000001) {
                -0.040114326002824066
              } else {
                0.2190827122455252
              }
            } else {
              0.2248833249935471
            }
          }
        }
      } else {
        if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
          if (house <= 0.8333333333333334) {
            if (name <= 0.5833333333333334) {
              if (feature <= 0.2916666666666667) {
                -0.06812357713006495
              } else {
                0.17624352391610382
              }
            } else {
              0.38038037483455844
            }
          } else {
            0.33569192039046025
          }
        } else {
          0.2516015954293094
        }
      }
    } else {
      if (dice <= 0.5472370766488415) {
        if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
          if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
            if (road_b <= 0.45000000000000007) {
              0.09496521244361486
            } else {
              if (c_roads_d <= 1.5000000000000002) {
                0.16787495992222487
              } else {
                0.34069599122447225
              }
            }
          } else {
            if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
              if (c_roads_d <= 1.5000000000000002) {
                -0.10561204996829024
              } else {
                0.02491388794509129
              }
            } else {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                0.09098383393591063
              } else {
                -0.03968329513061869
              }
            }
          }
        } else {
          if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
            if (q_roads_d <= 1.5000000000000002) {
              if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
                0.29528055130152625
              } else {
                0.03861730821263735
              }
            } else {
              0.5082769896509332
            }
          } else {
            -0.037336094356417555
          }
        }
      } else {
        if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
          if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
            if (c_roads_d <= 1.5000000000000002) {
              if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
                0.11965024005236459
              } else {
                0.2954670835315655
              }
            } else {
              0.35122639251567717
            }
          } else {
            -0.04085389345989101
          }
        } else {
          if (dice <= 0.8432748538011697) {
            0.23328044907926535
          } else {
            if (c_roads_d <= 1.5000000000000002) {
              0.32378277961886004
            } else {
              0.7067378326076469
            }
          }
        }
      }
    }
  )

  // LGBM tree 4 (estim 1, class 1)
  s1 += (
    if (road_b <= 1.0000000180025095e-35) {
      if (feature <= 0.18333333333333338) {
        if (dice <= 0.16784037558685447) {
          if (dice <= 0.0650449497620307) {
            -0.223238636713214
          } else {
            if (name <= 0.4166666666666667) {
              if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
                -0.19478759011147248
              } else {
                -0.1473212370989839
              }
            } else {
              if (q_feats_d <= 1.0000000180025095e-35) {
                0.22493342484599824
              } else {
                -0.05446373445321314
              }
            }
          }
        } else {
          if (name <= 1.0000000180025095e-35) {
            if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                -0.11607040051823751
              } else {
                -0.04427274849406653
              }
            } else {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                -0.030145906146614502
              } else {
                0.1318738306880621
              }
            }
          } else {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              -0.05148897314461262
            } else {
              if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
                0.10700272298350856
              } else {
                -0.08253519763292615
              }
            }
          }
        }
      } else {
        if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
          if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
            if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
              if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
                -0.03408163853150363
              } else {
                0.07857459031641088
              }
            } else {
              -0.11266855139084629
            }
          } else {
            if (dice <= 0.30901856763925734) {
              0.23123356270129858
            } else {
              0.10150598971161068
            }
          }
        } else {
          if (c_roads_d <= 1.0000000180025095e-35) {
            if (feature <= 0.5500000000000002) {
              0.13728290254420905
            } else {
              0.2487770012090426
            }
          } else {
            0.09611259006297206
          }
        }
      }
    } else {
      if (house <= 0.4166666666666667) {
        if (feature <= 0.45000000000000007) {
          if (q_feats_d <= 1.0000000180025095e-35) {
            if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
              if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
                0.0397467770272936
              } else {
                0.1687867924986447
              }
            } else {
              if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
                0.174747050459774
              } else {
                0.030464751539332213
              }
            }
          } else {
            if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
              if (dice <= 0.23904761904761906) {
                -0.05145641515338404
              } else {
                0.029235262786571507
              }
            } else {
              0.1935518597813548
            }
          }
        } else {
          0.17177797047611773
        }
      } else {
        if (c_roads_d <= 1.5000000000000002) {
          0.2119423337696676
        } else {
          if (dice <= 0.6214559386973181) {
            0.15621703684512916
          } else {
            -0.02901322690750155
          }
        }
      }
    }
  )

  // LGBM tree 5 (estim 1, class 2)
  s2 += (
    if (dice <= 0.18350168350168353) {
      if (road_b <= 0.2916666666666667) {
        if (feature <= 0.22500000000000003) {
          if (name <= 0.4166666666666667) {
            if (dice <= 0.0650449497620307) {
              0.23934373497881817
            } else {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                0.17902921212320588
              } else {
                0.04748333138595274
              }
            }
          } else {
            if (q_feats_d <= 1.0000000180025095e-35) {
              -0.2065298135877608
            } else {
              0.06065120574743977
            }
          }
        } else {
          if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
            0.05811224577715347
          } else {
            if (to_dbl(veto) <= 1.0000000180025095e-35) {
              -0.16441978480291602
            } else {
              0.0614254137206211
            }
          }
        }
      } else {
        if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
          0.04055992205006076
        } else {
          if (q_feats_d <= 1.0000000180025095e-35) {
            if (dice <= 0.11882352941176472) {
              -0.02442512159403548
            } else {
              -0.21909724001834022
            }
          } else {
            0.01354114225718776
          }
        }
      }
    } else {
      if (road_b <= 0.36666666666666675) {
        if (feature <= 0.36666666666666675) {
          if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
            if (dice <= 0.30901856763925734) {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                0.09035460027700502
              } else {
                0.18912421182528755
              }
            } else {
              if (q_feats_d <= 1.0000000180025095e-35) {
                -0.02766466520081185
              } else {
                0.07224320871590552
              }
            }
          } else {
            if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                -0.03841599583558565
              } else {
                0.18662239409462417
              }
            } else {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                -0.14931839408090813
              } else {
                -0.2947366718612207
              }
            }
          }
        } else {
          if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
            if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                -0.0735121017645931
              } else {
                0.11006952078189068
              }
            } else {
              if (feature <= 0.5500000000000002) {
                -0.11194855305405181
              } else {
                -0.2279327768164279
              }
            }
          } else {
            if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
              -0.2250058832606807
            } else {
              -0.1218996908486489
            }
          }
        }
      } else {
        if (house <= 0.4166666666666667) {
          if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
            if (feature <= 0.8750000000000001) {
              if (dice <= 0.40370370370370373) {
                -0.05364039275521446
              } else {
                -0.1360032753170534
              }
            } else {
              -0.21494464127799667
            }
          } else {
            -0.2584354386353642
          }
        } else {
          -0.24428463309758128
        }
      }
    }
  )

  // LGBM tree 6 (estim 2, class 0)
  s0 += (
    if (dice <= 0.34216027874564464) {
      if (dice <= 0.16784037558685447) {
        if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
          if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
            -0.15615546727247728
          } else {
            -0.06251335515149485
          }
        } else {
          if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
            -0.1301489824638217
          } else {
            0.27778912226383373
          }
        }
      } else {
        if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
          if (house <= 0.8333333333333334) {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              if (name <= 0.5833333333333334) {
                -0.03385550444038278
              } else {
                0.12711134543251007
              }
            } else {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                -0.07582421240334171
              } else {
                -0.14336024596758032
              }
            }
          } else {
            if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
              if (c_roads_d <= 1.5000000000000002) {
                -0.03295435310509738
              } else {
                0.1358483820399052
              }
            } else {
              if (feature <= 0.8750000000000001) {
                0.07209297728763658
              } else {
                0.6853522869956179
              }
            }
          }
        } else {
          if (q_roads_d <= 1.5000000000000002) {
            if (feature <= 0.5500000000000002) {
              if (name <= 0.5833333333333334) {
                0.0021512885077122233
              } else {
                0.27731247494554734
              }
            } else {
              0.15363360071893908
            }
          } else {
            if (road_b <= 0.2916666666666667) {
              0.215925388553473
            } else {
              0.5094849259246865
            }
          }
        }
      }
    } else {
      if (dice <= 0.6167832167832169) {
        if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
          if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
            if (dice <= 0.4558441558441559) {
              0.057470323570521814
            } else {
              0.14059547145871096
            }
          } else {
            if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
              if (name <= 0.4166666666666667) {
                -0.08406588336008507
              } else {
                0.08881435135527378
              }
            } else {
              if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
                0.03900188559150784
              } else {
                0.21107360110279555
              }
            }
          }
        } else {
          if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
            0.1729112105343168
          } else {
            -0.06298272709510075
          }
        }
      } else {
        if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
          if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
            if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
              0.1215826426107079
            } else {
              -0.05192728604636861
            }
          } else {
            if (name <= 0.4166666666666667) {
              0.15986957236425436
            } else {
              0.3176703281663589
            }
          }
        } else {
          if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
            0.15049079836742665
          } else {
            0.4972777289427059
          }
        }
      }
    }
  )

  // LGBM tree 7 (estim 2, class 1)
  s1 += (
    if (dice <= 0.14415584415584418) {
      if (dice <= 0.057983193277310933) {
        -0.1937146715812964
      } else {
        if (road_b <= 0.45000000000000007) {
          if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              -0.17083187312207684
            } else {
              if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
                -0.09358261196364624
              } else {
                -0.18272084757871973
              }
            }
          } else {
            if (feature <= 0.22500000000000003) {
              -0.028898078365282655
            } else {
              if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
                0.1800584304343778
              } else {
                0.0149898474370577
              }
            }
          }
        } else {
          if (house <= 0.8333333333333334) {
            0.005767654248382729
          } else {
            0.14596632595934841
          }
        }
      }
    } else {
      if (road_b <= 0.2916666666666667) {
        if (feature <= 0.36666666666666675) {
          if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
            if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
              if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
                -0.0364845666620631
              } else {
                -0.14021864100511397
              }
            } else {
              if (c_roads_d <= 1.0000000180025095e-35) {
                0.09931513337640642
              } else {
                -0.0063995697310005074
              }
            }
          } else {
            if (c_feats_d <= 1.5000000000000002) {
              if (dice <= 0.5045454545454546) {
                -0.15739546135590401
              } else {
                0.005403353736178449
              }
            } else {
              -0.02671009187252685
            }
          }
        } else {
          if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                0.025025039124974734
              } else {
                -0.07302757705858222
              }
            } else {
              if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
                0.11020732105738845
              } else {
                0.034862966501504965
              }
            }
          } else {
            if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
              -0.14580184783228625
            } else {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                -0.03649229017563487
              } else {
                0.10091248060991417
              }
            }
          }
        }
      } else {
        if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
          if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
            0.031317595263671096
          } else {
            -0.0954245311445864
          }
        } else {
          if (c_roads_d <= 1.5000000000000002) {
            if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                0.1328630177724591
              } else {
                0.044620768471984644
              }
            } else {
              0.026652103570690245
            }
          } else {
            if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                0.10082619293062375
              } else {
                0.011328537645663977
              }
            } else {
              0.029418729455960985
            }
          }
        }
      }
    }
  )

  // LGBM tree 8 (estim 2, class 2)
  s2 += (
    if (dice <= 0.15504807692307696) {
      if (dice <= 0.0650449497620307) {
        0.2000375881932067
      } else {
        if (house <= 0.8333333333333334) {
          if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
            if (road_b <= 0.45000000000000007) {
              if (feature <= 0.2916666666666667) {
                0.15006680989688592
              } else {
                0.06269461175282257
              }
            } else {
              0.022818221484152384
            }
          } else {
            if (feature <= 0.22500000000000003) {
              0.032168546231919115
            } else {
              -0.10080884682837372
            }
          }
        } else {
          if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
            -0.09334394193136376
          } else {
            0.18107017440701625
          }
        }
      }
    } else {
      if (road_b <= 0.2916666666666667) {
        if (feature <= 0.5500000000000002) {
          if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
            if (dice <= 0.40370370370370373) {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                0.05704882691371789
              } else {
                0.14421875105301216
              }
            } else {
              if (house <= 0.8333333333333334) {
                -0.007428313361579881
              } else {
                -0.22130764943161224
              }
            }
          } else {
            if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                -0.036469047279203096
              } else {
                0.14639599384954616
              }
            } else {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                -0.11210211265641558
              } else {
                -0.22755561773785252
              }
            }
          }
        } else {
          if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
            if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
              if (q_feats_d <= 1.5000000000000002) {
                -0.12973045894518717
              } else {
                -0.21428703060898915
              }
            } else {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                0.06537284584229032
              } else {
                -0.20550259586345995
              }
            }
          } else {
            if (q_feats_d <= 1.5000000000000002) {
              if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
                0.02896754242472977
              } else {
                -0.06639805998566366
              }
            } else {
              -0.1722999415892166
            }
          }
        }
      } else {
        if (house <= 0.5833333333333334) {
          if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
            if (name <= 0.5833333333333334) {
              if (q_feats_d <= 1.0000000180025095e-35) {
                -0.07248492824075434
              } else {
                0.003157250826263639
              }
            } else {
              -0.20943784361879844
            }
          } else {
            if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
              if (feature <= 0.45000000000000007) {
                -0.0855108747061668
              } else {
                -0.17249400258228
              }
            } else {
              -0.1997628206957739
            }
          }
        } else {
          if (dice <= 0.37617924528301894) {
            -0.15722814273512645
          } else {
            -0.21172687688664915
          }
        }
      }
    }
  )

  // LGBM tree 9 (estim 3, class 0)
  s0 += (
    if (dice <= 0.26766169154228864) {
      if (dice <= 0.13873295910184444) {
        if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
          -0.14996418430272423
        } else {
          -0.04543040063580874
        }
      } else {
        if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
          if (house <= 0.4166666666666667) {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              -0.03810573218161198
            } else {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                -0.14140428747816788
              } else {
                -0.0725665228864169
              }
            }
          } else {
            if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
              if (feature <= 0.45000000000000007) {
                -0.041246891208640085
              } else {
                0.16719720563512022
              }
            } else {
              0.4223013261499283
            }
          }
        } else {
          if (q_roads_d <= 1.0000000180025095e-35) {
            -0.06428605248446735
          } else {
            if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
              0.10186811375885638
            } else {
              -0.14940677253322576
            }
          }
        }
      }
    } else {
      if (dice <= 0.5173237753882917) {
        if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
          if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
            if (c_roads_d <= 1.5000000000000002) {
              if (name <= 0.5833333333333334) {
                0.018494391500748403
              } else {
                0.15008869088299767
              }
            } else {
              if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
                0.17985118298696165
              } else {
                0.013741389138378335
              }
            }
          } else {
            if (house <= 1.0000000180025095e-35) {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                -0.08057288382024055
              } else {
                0.005410417752731955
              }
            } else {
              if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
                0.035391012731474304
              } else {
                0.29538038891714347
              }
            }
          }
        } else {
          if (house <= 0.8333333333333334) {
            if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                -0.0032916358913525783
              } else {
                0.1363439359512182
              }
            } else {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                0.142029320610335
              } else {
                -0.159990752076198
              }
            }
          } else {
            if (c_feats_d <= 1.0000000180025095e-35) {
              0.4176628750603839
            } else {
              0.13149866845576055
            }
          }
        }
      } else {
        if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
          if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
            if (dice <= 0.6099033816425122) {
              0.033361867320765716
            } else {
              0.15586438550551543
            }
          } else {
            -0.028422393005000123
          }
        } else {
          if (c_roads_d <= 1.5000000000000002) {
            if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
              0.11029343684647763
            } else {
              0.012576992746003993
            }
          } else {
            0.2445618338892968
          }
        }
      }
    }
  )

  // LGBM tree 10 (estim 3, class 1)
  s1 += (
    if (dice <= 0.12632978723404256) {
      if (dice <= 0.04396135265700484) {
        -0.17197966773686416
      } else {
        if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
          -0.1432470850134078
        } else {
          if (feature <= 0.22500000000000003) {
            if (road_b <= 0.45000000000000007) {
              -0.08581044431661572
            } else {
              0.03967633275711873
            }
          } else {
            if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
              0.11705797557654393
            } else {
              -0.09917996695851546
            }
          }
        }
      }
    } else {
      if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
        if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
          if (house <= 0.8333333333333334) {
            if (name <= 1.0000000180025095e-35) {
              if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
                -0.05499280013753323
              } else {
                -0.1452798856307944
              }
            } else {
              if (q_feats_d <= 1.0000000180025095e-35) {
                0.06098032374184498
              } else {
                -0.04766470176329498
              }
            }
          } else {
            if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
              if (c_roads_d <= 1.0000000180025095e-35) {
                0.2739366800625132
              } else {
                0.08192161191096146
              }
            } else {
              -0.15960699967054245
            }
          }
        } else {
          if (dice <= 0.3060200668896322) {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              0.009802563716963883
            } else {
              if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
                0.1125303456942708
              } else {
                0.013867026461005771
              }
            }
          } else {
            if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
              if (dice <= 0.6214559386973181) {
                -0.029486546720511
              } else {
                0.09454582955263308
              }
            } else {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                0.051272418006531366
              } else {
                -0.06618169360984817
              }
            }
          }
        }
      } else {
        if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
          if (dice <= 0.2362911266201396) {
            -0.08614135198102275
          } else {
            if (q_roads_d <= 1.0000000180025095e-35) {
              -0.032783529566930335
            } else {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                0.04019020947242053
              } else {
                -0.07940566099166586
              }
            }
          }
        } else {
          if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
            if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                0.11057207353906182
              } else {
                0.033098678344492996
              }
            } else {
              -0.006908258483020426
            }
          } else {
            if (dice <= 0.2362911266201396) {
              if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
                0.0005143212122591914
              } else {
                -0.1654816280809582
              }
            } else {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                0.034167999903033465
              } else {
                0.1218439133038167
              }
            }
          }
        }
      }
    }
  )

  // LGBM tree 11 (estim 3, class 2)
  s2 += (
    if (dice <= 0.15504807692307696) {
      if (dice <= 0.05064102564102565) {
        0.17844746804601788
      } else {
        if (house <= 0.8333333333333334) {
          if (feature <= 0.22500000000000003) {
            if (road_b <= 0.22500000000000003) {
              if (name <= 1.0000000180025095e-35) {
                0.1197504196429601
              } else {
                -0.005941599581404673
              }
            } else {
              0.01915631704579657
            }
          } else {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              0.10955807978253645
            } else {
              if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
                -0.09498374139159131
              } else {
                0.07771363655853905
              }
            }
          }
        } else {
          if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
            -0.07442217481076552
          } else {
            0.15551929439378256
          }
        }
      }
    } else {
      if (house <= 0.5833333333333334) {
        if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
          if (q_feats_d <= 1.0000000180025095e-35) {
            if (name <= 1.0000000180025095e-35) {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                0.04084840952880694
              } else {
                -0.04244123681836337
              }
            } else {
              if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
                -0.15073345962197737
              } else {
                0.010771937885689887
              }
            }
          } else {
            if (feature <= 0.7083333333333334) {
              if (c_feats_d <= 1.0000000180025095e-35) {
                0.02954115036389859
              } else {
                0.09792929176573366
              }
            } else {
              if (q_feats_d <= 1.5000000000000002) {
                -0.034033072049801
              } else {
                -0.13885067745701157
              }
            }
          }
        } else {
          if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
            if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
              if (c_feats_d <= 1.0000000180025095e-35) {
                -0.30616425843349193
              } else {
                -0.01002961339454683
              }
            } else {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                -0.10332848449301651
              } else {
                0.0026041916014937186
              }
            }
          } else {
            if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                -0.12124610517167977
              } else {
                0.012957990060474284
              }
            } else {
              if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
                -0.16601500552476142
              } else {
                -0.01035717118230066
              }
            }
          }
        }
      } else {
        if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
          if (dice <= 0.41277890466531447) {
            if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
              if (feature <= 0.8750000000000001) {
                -0.10361761583491959
              } else {
                -0.1987780726673585
              }
            } else {
              -0.22195830007659098
            }
          } else {
            -0.1757439906581321
          }
        } else {
          if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
            0.09208869766571737
          } else {
            -0.1219555549483738
          }
        }
      }
    }
  )

  // LGBM tree 12 (estim 4, class 0)
  s0 += (
    if (dice <= 0.24440019910403188) {
      if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
        if (dice <= 0.13873295910184444) {
          if (feature <= 0.45000000000000007) {
            -0.14199414187617979
          } else {
            if (house <= 0.8333333333333334) {
              -0.04784504306067593
            } else {
              0.47350908932272745
            }
          }
        } else {
          if (house <= 0.4166666666666667) {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              -0.03745812941352382
            } else {
              -0.1054094479203994
            }
          } else {
            if (c_roads_d <= 1.5000000000000002) {
              if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
                -0.05011070640276596
              } else {
                0.30867042354945357
              }
            } else {
              0.14037862003708357
            }
          }
        }
      } else {
        if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
          if (house <= 0.8333333333333334) {
            -0.037095826795779475
          } else {
            0.14662659334158246
          }
        } else {
          0.10738673115916735
        }
      }
    } else {
      if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
        if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
          if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
            if (c_roads_d <= 1.5000000000000002) {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                -0.01885669195999153
              } else {
                0.0359154872464367
              }
            } else {
              if (dice <= 0.40370370370370373) {
                0.050394628458895176
              } else {
                0.15615866827721062
              }
            }
          } else {
            -0.07443019577611808
          }
        } else {
          if (house <= 0.4166666666666667) {
            if (name <= 0.4166666666666667) {
              if (c_feats_d <= 1.0000000180025095e-35) {
                -0.14300713659236475
              } else {
                -0.050740069132439454
              }
            } else {
              if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
                0.4962983898218357
              } else {
                -0.10617105769288164
              }
            }
          } else {
            if (c_feats_d <= 1.0000000180025095e-35) {
              0.4056151346115797
            } else {
              0.04984174167315767
            }
          }
        }
      } else {
        if (house <= 1.0000000180025095e-35) {
          if (dice <= 0.8706800445930881) {
            if (c_feats_d <= 3.5000000000000004) {
              if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
                0.044970077939608645
              } else {
                0.10464932380994177
              }
            } else {
              0.31405544567860205
            }
          } else {
            0.1966593666598992
          }
        } else {
          if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
            if (name <= 0.5833333333333334) {
              if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
                0.0670016104437953
              } else {
                0.22291437988849724
              }
            } else {
              if (feature <= 0.45000000000000007) {
                0.15932324951416849
              } else {
                0.3524858707968045
              }
            }
          } else {
            0.44834862647973966
          }
        }
      }
    }
  )

  // LGBM tree 13 (estim 4, class 1)
  s1 += (
    if (dice <= 0.11882352941176472) {
      if (dice <= 0.04396135265700484) {
        -0.14692236906197256
      } else {
        if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
          -0.1190285942539368
        } else {
          if (feature <= 0.22500000000000003) {
            if (house <= 0.4166666666666667) {
              if (c_feats_d <= 1.0000000180025095e-35) {
                -0.024290028396138596
              } else {
                -0.09146565230032343
              }
            } else {
              0.012217872536157906
            }
          } else {
            0.038241508382415974
          }
        }
      }
    } else {
      if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
        if (dice <= 0.26201372997711675) {
          if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
            if (road_b <= 0.22500000000000003) {
              -0.0975163472874205
            } else {
              -0.018920858311382606
            }
          } else {
            -0.011887707412230808
          }
        } else {
          if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
            if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
              -0.02155939788989888
            } else {
              if (c_feats_d <= 1.0000000180025095e-35) {
                -0.17290029886528432
              } else {
                -0.03512977592058909
              }
            }
          } else {
            if (c_roads_d <= 1.0000000180025095e-35) {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                0.05073201150588551
              } else {
                0.20017286481605595
              }
            } else {
              if (road_b <= 0.2916666666666667) {
                -0.02606598996796364
              } else {
                0.040200537741362466
              }
            }
          }
        }
      } else {
        if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
          if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
            if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                0.0733188785957142
              } else {
                -0.01892824610055868
              }
            } else {
              if (c_roads_d <= 1.0000000180025095e-35) {
                0.1760972109670306
              } else {
                -0.010370460655871824
              }
            }
          } else {
            if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
              if (dice <= 0.29340028694404596) {
                -0.03796850717346697
              } else {
                0.024857725532203414
              }
            } else {
              if (dice <= 0.5683229813664598) {
                -0.11360871205364582
              } else {
                0.12825536440189772
              }
            }
          }
        } else {
          if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
            if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
              if (road_b <= 0.45000000000000007) {
                -0.12032921852235798
              } else {
                0.05161738416728997
              }
            } else {
              if (dice <= 0.29340028694404596) {
                0.044221036572510135
              } else {
                -0.06566709002544983
              }
            }
          } else {
            if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
              -0.03193232898069329
            } else {
              if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
                0.16168116658348886
              } else {
                0.003822127550968047
              }
            }
          }
        }
      }
    }
  )

  // LGBM tree 14 (estim 4, class 2)
  s2 += (
    if (dice <= 0.14415584415584418) {
      if (dice <= 0.04396135265700484) {
        0.1540051257521848
      } else {
        if (house <= 0.8333333333333334) {
          if (feature <= 0.22500000000000003) {
            if (q_feats_d <= 1.0000000180025095e-35) {
              if (name <= 0.4166666666666667) {
                0.056577441767943104
              } else {
                -0.19317212890462615
              }
            } else {
              if (c_feats_d <= 1.0000000180025095e-35) {
                0.06669421107500695
              } else {
                0.12264648255973687
              }
            }
          } else {
            -0.0004899769725830159
          }
        } else {
          if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
            -0.05131432028534876
          } else {
            0.14667848093898886
          }
        }
      }
    } else {
      if (feature <= 0.5500000000000002) {
        if (road_b <= 1.0000000180025095e-35) {
          if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
            if (name <= 0.4166666666666667) {
              if (to_dbl(veto) <= 1.0000000180025095e-35) {
                0.03829610242976745
              } else {
                0.12203805068172673
              }
            } else {
              if (q_feats_d <= 1.0000000180025095e-35) {
                -0.08074103574585535
              } else {
                0.01626569749859418
              }
            }
          } else {
            if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                0.04348190530860726
              } else {
                -0.06005533173453163
              }
            } else {
              if (c_roads_d <= 1.0000000180025095e-35) {
                -0.1547296966266116
              } else {
                -0.025911185726238954
              }
            }
          }
        } else {
          if (house <= 0.5833333333333334) {
            if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
              if (name <= 0.5833333333333334) {
                -0.015848929743622953
              } else {
                -0.16183630945126778
              }
            } else {
              -0.13682412731660884
            }
          } else {
            if (dice <= 0.365491651205937) {
              if (q_feats_d <= 1.0000000180025095e-35) {
                -0.10850711666898015
              } else {
                -0.025122249742038045
              }
            } else {
              -0.1380808089954109
            }
          }
        }
      } else {
        if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
          if (q_feats_d <= 1.5000000000000002) {
            if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
              if (q_roads_d <= 1.0000000180025095e-35) {
                -0.07719241747462154
              } else {
                -0.015598584528382127
              }
            } else {
              if (dice <= 0.5524578136463684) {
                0.10614747874050008
              } else {
                -0.0992690752630884
              }
            }
          } else {
            if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
              if (dice <= 0.3306010928961749) {
                -0.15210895219646525
              } else {
                0.008216701129951133
              }
            } else {
              -0.1735510075471354
            }
          }
        } else {
          if (dice <= 0.3504385964912281) {
            -0.07208506377639926
          } else {
            -0.132607166459739
          }
        }
      }
    }
  )

  // LGBM tree 15 (estim 5, class 0)
  s0 += (
    if (dice <= 0.34216027874564464) {
      if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
        if (dice <= 0.16271373414230558) {
          if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              -0.06712826379007655
            } else {
              -0.13347105372518092
            }
          } else {
            0.08305224985299874
          }
        } else {
          if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
            if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
              if (feature <= 0.5500000000000002) {
                -0.030356292678712628
              } else {
                0.03151809047092333
              }
            } else {
              -0.08621921576697861
            }
          } else {
            -0.09482593943184485
          }
        }
      } else {
        if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
          if (name <= 0.5833333333333334) {
            if (q_roads_d <= 2.5000000000000004) {
              if (road_b <= 0.45000000000000007) {
                0.008613664258492275
              } else {
                0.11971602741914208
              }
            } else {
              0.3040422742757733
            }
          } else {
            0.2035246478418137
          }
        } else {
          -0.1440765079820919
        }
      }
    } else {
      if (name <= 0.5833333333333334) {
        if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
          if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
            if (dice <= 0.4577380952380953) {
              -0.004302782741171858
            } else {
              0.06506930839797823
            }
          } else {
            if (c_feats_d <= 1.0000000180025095e-35) {
              -0.11130422144611211
            } else {
              if (road_b <= 0.8750000000000001) {
                -0.03269028104372632
              } else {
                0.07109522053339959
              }
            }
          }
        } else {
          if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
            if (c_roads_d <= 1.5000000000000002) {
              0.04451984417026871
            } else {
              0.12455143763128984
            }
          } else {
            if (q_roads_d <= 1.5000000000000002) {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                -0.094688348239153
              } else {
                0.002290535890736323
              }
            } else {
              0.13277869673638576
            }
          }
        }
      } else {
        if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
          if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
            if (house <= 0.4166666666666667) {
              if (road_b <= 0.45000000000000007) {
                -0.00031253480606823234
              } else {
                0.1136800935697416
              }
            } else {
              if (road_b <= 0.45000000000000007) {
                0.3302289519316815
              } else {
                0.07818441047131307
              }
            }
          } else {
            if (c_feats_d <= 1.0000000180025095e-35) {
              0.10858767792660481
            } else {
              0.4422065303476806
            }
          }
        } else {
          if (dice <= 0.47722567287784684) {
            if (feature <= 0.8750000000000001) {
              0.8728588603139775
            } else {
              0.38634231766096216
            }
          } else {
            0.16473033418478059
          }
        }
      }
    }
  )

  // LGBM tree 16 (estim 5, class 1)
  s1 += (
    if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
      if (dice <= 0.05064102564102565) {
        if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
          -0.15290250552747367
        } else {
          -0.09544561463789751
        }
      } else {
        if (feature <= 0.36666666666666675) {
          if (q_feats_d <= 1.0000000180025095e-35) {
            if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                -0.02575532733376371
              } else {
                -0.10929519494782285
              }
            } else {
              if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
                0.03827518416368269
              } else {
                -0.06873618860213153
              }
            }
          } else {
            if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
              if (c_feats_d <= 1.0000000180025095e-35) {
                -0.02130513102686127
              } else {
                -0.08407553413002479
              }
            } else {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                0.004731967916261564
              } else {
                -0.08378247485550895
              }
            }
          }
        } else {
          if (dice <= 0.3060200668896322) {
            if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                -0.004263097767411956
              } else {
                0.046568640583664646
              }
            } else {
              0.11378603285097665
            }
          } else {
            if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                0.007998691302775902
              } else {
                -0.07332660517665765
              }
            } else {
              if (q_roads_d <= 1.0000000180025095e-35) {
                -0.002998926240151594
              } else {
                -0.11796936111651248
              }
            }
          }
        }
      }
    } else {
      if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
        if (dice <= 0.3207142857142858) {
          if (q_roads_d <= 1.0000000180025095e-35) {
            -0.08679326736698287
          } else {
            -0.02039522523031729
          }
        } else {
          0.012016895277065566
        }
      } else {
        if (q_feats_d <= 1.0000000180025095e-35) {
          if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
            if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                0.08513779776259985
              } else {
                0.03250393909351165
              }
            } else {
              if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
                0.018906502811012152
              } else {
                0.13587635396783385
              }
            }
          } else {
            -0.00905159473974096
          }
        } else {
          if (feature <= 0.2916666666666667) {
            if (c_roads_d <= 1.0000000180025095e-35) {
              if (q_roads_d <= 1.5000000000000002) {
                0.012033764365071958
              } else {
                0.31111711769117717
              }
            } else {
              if (road_b <= 0.45000000000000007) {
                -0.09333006033390594
              } else {
                -0.02404753780888884
              }
            }
          } else {
            if (dice <= 0.7417989417989419) {
              0.06501215806364698
            } else {
              0.012064957036880439
            }
          }
        }
      }
    }
  )

  // LGBM tree 17 (estim 5, class 2)
  s2 += (
    if (dice <= 0.12632978723404256) {
      if (dice <= 0.04396135265700484) {
        if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
          0.16108035882497077
        } else {
          if (road_b <= 0.8750000000000001) {
            if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
              0.11598022941722927
            } else {
              0.013011069641716702
            }
          } else {
            -0.18971025277417142
          }
        }
      } else {
        if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
          if (q_roads_d <= 1.5000000000000002) {
            if (name <= 0.4166666666666667) {
              if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
                0.10967376555229129
              } else {
                0.05655443537902778
              }
            } else {
              -0.13772255810387776
            }
          } else {
            if (q_feats_d <= 1.5000000000000002) {
              if (road_b <= 0.45000000000000007) {
                0.053105724548329236
              } else {
                -0.08993027158668519
              }
            } else {
              if (feature <= 0.45000000000000007) {
                -0.0244297148856989
              } else {
                -0.4324693696363459
              }
            }
          }
        } else {
          -0.07274712551437162
        }
      }
    } else {
      if (dice <= 0.5741758241758242) {
        if (house <= 0.4166666666666667) {
          if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
            if (q_feats_d <= 1.0000000180025095e-35) {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                -0.01962738715277088
              } else {
                0.07104025253290906
              }
            } else {
              if (q_roads_d <= 1.5000000000000002) {
                0.055736604635133025
              } else {
                -0.023961545863992326
              }
            }
          } else {
            if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
              if (dice <= 0.3060200668896322) {
                -0.047830800740698655
              } else {
                0.007138711219352115
              }
            } else {
              if (c_roads_d <= 1.0000000180025095e-35) {
                -0.11343800584059527
              } else {
                -0.05144341360924051
              }
            }
          }
        } else {
          if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
            if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
              if (name <= 0.5833333333333334) {
                -0.059253253783392495
              } else {
                -0.19979712553506196
              }
            } else {
              -0.15751794592177157
            }
          } else {
            if (feature <= 0.5500000000000002) {
              0.09090001733558374
            } else {
              -0.07502538838343904
            }
          }
        }
      } else {
        if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
          if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
            if (name <= 0.5833333333333334) {
              -0.07772952237889617
            } else {
              0.0008320470306287077
            }
          } else {
            -0.1300277233866929
          }
        } else {
          if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
            if (dice <= 0.8248081841432225) {
              0.02935135327387612
            } else {
              -0.12942394497948623
            }
          } else {
            -0.14088885001204482
          }
        }
      }
    }
  )

  // LGBM tree 18 (estim 6, class 0)
  s0 += (
    if (dice <= 0.24440019910403188) {
      if (feature <= 0.2916666666666667) {
        if (dice <= 0.07477288609364081) {
          -0.1291722713661675
        } else {
          if (house <= 0.4166666666666667) {
            -0.06630417101775199
          } else {
            0.008238889026727413
          }
        }
      } else {
        if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
          if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
            0.07053542622253017
          } else {
            -0.10261445503975085
          }
        } else {
          if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
            if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                0.023592027308317488
              } else {
                0.15234707019251917
              }
            } else {
              -0.1529396969009805
            }
          } else {
            -0.09539797082253486
          }
        }
      }
    } else {
      if (dice <= 0.43288288288288296) {
        if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
          if (q_roads_d <= 1.0000000180025095e-35) {
            if (c_roads_d <= 1.0000000180025095e-35) {
              if (q_feats_d <= 1.5000000000000002) {
                -0.001200191578053276
              } else {
                -0.11135630204910353
              }
            } else {
              if (feature <= 0.8750000000000001) {
                0.02296635592611627
              } else {
                0.11899056233733389
              }
            }
          } else {
            if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
              if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
                -0.0014140393709149363
              } else {
                -0.08372756878748426
              }
            } else {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                0.00489465372184593
              } else {
                -0.05858750888684173
              }
            }
          }
        } else {
          if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
            if (q_roads_d <= 1.5000000000000002) {
              0.03627215850369864
            } else {
              0.13880515940038035
            }
          } else {
            -0.1089168133863581
          }
        }
      } else {
        if (c_feats_d <= 1.0000000180025095e-35) {
          if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              if (q_roads_d <= 1.5000000000000002) {
                0.06157771909463005
              } else {
                0.2557183413590179
              }
            } else {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                -0.08508122764488053
              } else {
                0.02348136921928093
              }
            }
          } else {
            -0.06677176197561217
          }
        } else {
          if (name <= 0.4166666666666667) {
            if (road_b <= 0.45000000000000007) {
              if (house <= 0.4166666666666667) {
                0.0132424617569516
              } else {
                0.10939478218888328
              }
            } else {
              if (c_roads_d <= 1.5000000000000002) {
                0.05359181127819501
              } else {
                0.12460726482166559
              }
            }
          } else {
            if (c_roads_d <= 1.5000000000000002) {
              0.114037509704816
            } else {
              0.28999410013130494
            }
          }
        }
      }
    }
  )

  // LGBM tree 19 (estim 6, class 1)
  s1 += (
    if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
      if (dice <= 0.04396135265700484) {
        -0.09974005488615309
      } else {
        if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
          if (dice <= 0.5300120048019209) {
            if (feature <= 0.5500000000000002) {
              if (q_feats_d <= 3.5000000000000004) {
                -0.05779415066898496
              } else {
                0.19025243540477976
              }
            } else {
              if (c_roads_d <= 1.0000000180025095e-35) {
                -0.05261696481340311
              } else {
                0.015297331017077389
              }
            }
          } else {
            0.047685842907459454
          }
        } else {
          if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
            if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                0.03675668795117643
              } else {
                -0.014351597664855368
              }
            } else {
              if (c_feats_d <= 1.5000000000000002) {
                -0.047621575239920465
              } else {
                0.013734233811245562
              }
            }
          } else {
            if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
              if (road_b <= 0.45000000000000007) {
                -0.08615600983773367
              } else {
                0.05071129985372056
              }
            } else {
              0.014513750046176523
            }
          }
        }
      }
    } else {
      if (dice <= 0.3060200668896322) {
        if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
          if (q_roads_d <= 1.0000000180025095e-35) {
            if (c_roads_d <= 1.5000000000000002) {
              -0.06659950833922182
            } else {
              0.057762075985698755
            }
          } else {
            if (q_roads_d <= 1.5000000000000002) {
              if (q_feats_d <= 1.0000000180025095e-35) {
                0.042976256658999845
              } else {
                -0.005974323197129413
              }
            } else {
              if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
                0.2250338006137943
              } else {
                -0.06587505240084662
              }
            }
          }
        } else {
          if (q_feats_d <= 1.0000000180025095e-35) {
            if (dice <= 0.22431865828092246) {
              -0.09510455447346149
            } else {
              if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
                -0.10878845989637405
              } else {
                0.042821029165362685
              }
            }
          } else {
            -0.12577827000459124
          }
        }
      } else {
        if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
          0.00788315914908022
        } else {
          if (c_roads_d <= 1.0000000180025095e-35) {
            if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
              if (dice <= 0.3438423645320198) {
                0.1288111200206511
              } else {
                0.0019027930024706615
              }
            } else {
              if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
                0.14269148683832403
              } else {
                0.026880433601745538
              }
            }
          } else {
            if (c_roads_d <= 1.5000000000000002) {
              if (q_roads_d <= 2.5000000000000004) {
                0.03288384882713985
              } else {
                0.21052314910313882
              }
            } else {
              0.003559946907086423
            }
          }
        }
      }
    }
  )

  // LGBM tree 20 (estim 6, class 2)
  s2 += (
    if (road_b <= 1.0000000180025095e-35) {
      if (feature <= 0.2916666666666667) {
        if (dice <= 0.22431865828092246) {
          if (name <= 0.5833333333333334) {
            if (dice <= 0.04396135265700484) {
              0.10889122519597093
            } else {
              if (q_roads_d <= 1.5000000000000002) {
                0.05833793255544478
              } else {
                -0.0016235953456050893
              }
            }
          } else {
            if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
              0.009435861621806577
            } else {
              -0.12352231196523729
            }
          }
        } else {
          if (q_feats_d <= 1.0000000180025095e-35) {
            if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                -0.0175002270205647
              } else {
                -0.0730591512423428
              }
            } else {
              if (house <= 0.4166666666666667) {
                0.05271960989987208
              } else {
                -0.09494932287121115
              }
            }
          } else {
            if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                0.03759354664342452
              } else {
                -0.0072765498906375
              }
            } else {
              if (c_feats_d <= 1.0000000180025095e-35) {
                -0.10471677719655366
              } else {
                0.15327074161526957
              }
            }
          }
        }
      } else {
        if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
          if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
            if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
              if (dice <= 0.6079192546583853) {
                -0.025279693400110975
              } else {
                -0.13152178537634565
              }
            } else {
              0.048938725084290056
            }
          } else {
            if (dice <= 0.2316636851520573) {
              -0.18676544640388268
            } else {
              if (feature <= 0.8750000000000001) {
                -0.009468626666395762
              } else {
                -0.09043349193138982
              }
            }
          }
        } else {
          if (dice <= 0.3306010928961749) {
            -0.017358199595759294
          } else {
            if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
              if (dice <= 0.6214559386973181) {
                0.09173479658417243
              } else {
                -0.10077303960240058
              }
            } else {
              0.002945188661589266
            }
          }
        }
      }
    } else {
      if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
        if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
          if (feature <= 0.8750000000000001) {
            0.003771145084594665
          } else {
            -0.09362646538767783
          }
        } else {
          if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
            if (q_feats_d <= 1.0000000180025095e-35) {
              if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
                -0.07157388335149499
              } else {
                -0.18151045077782643
              }
            } else {
              if (dice <= 0.23904761904761906) {
                0.021539744289719682
              } else {
                -0.05072395073108559
              }
            }
          } else {
            0.0027209489865180226
          }
        }
      } else {
        -0.10960984233622761
      }
    }
  )

  // LGBM tree 21 (estim 7, class 0)
  s0 += (
    if (dice <= 0.3207142857142858) {
      if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
        if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
          if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
            if (c_roads_d <= 2.5000000000000004) {
              if (name <= 0.5833333333333334) {
                -0.03081109548095003
              } else {
                0.06791576273956859
              }
            } else {
              if (q_roads_d <= 1.5000000000000002) {
                0.22129670606909016
              } else {
                -0.04196500068906365
              }
            }
          } else {
            if (c_feats_d <= 2.5000000000000004) {
              if (q_feats_d <= 1.5000000000000002) {
                0.04611747111785662
              } else {
                -0.017198635797483233
              }
            } else {
              if (dice <= 0.29708431836091415) {
                0.21519283930941582
              } else {
                -0.053481701388174
              }
            }
          }
        } else {
          -0.09635339137969232
        }
      } else {
        if (house <= 1.0000000180025095e-35) {
          -0.09459694671898013
        } else {
          if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
            if (q_roads_d <= 1.0000000180025095e-35) {
              0.06334677145807933
            } else {
              -0.11009567924823366
            }
          } else {
            0.25955377708756294
          }
        }
      }
    } else {
      if (house <= 1.0000000180025095e-35) {
        if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
          if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
            if (feature <= 0.7083333333333334) {
              if (q_roads_d <= 1.5000000000000002) {
                0.013537607262569673
              } else {
                0.09810489849852277
              }
            } else {
              0.045326100733722445
            }
          } else {
            if (c_feats_d <= 2.5000000000000004) {
              if (c_roads_d <= 1.5000000000000002) {
                -0.055398283257654654
              } else {
                0.0749764061298759
              }
            } else {
              0.2426381410886907
            }
          }
        } else {
          if (road_b <= 0.45000000000000007) {
            if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
              -0.0702533558469233
            } else {
              -0.006709945373174826
            }
          } else {
            if (road_b <= 0.5500000000000002) {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                0.049947291196780846
              } else {
                -0.0652332536807712
              }
            } else {
              0.16931284099303248
            }
          }
        }
      } else {
        if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
          if (c_roads_d <= 2.5000000000000004) {
            if (name <= 0.5833333333333334) {
              if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
                0.004014691237975436
              } else {
                0.05431350026231533
              }
            } else {
              0.10632679327739913
            }
          } else {
            0.2774549012341533
          }
        } else {
          if (c_roads_d <= 1.0000000180025095e-35) {
            if (dice <= 0.41763565891472876) {
              0.537167006575924
            } else {
              0.20787336518702532
            }
          } else {
            0.0962008405899788
          }
        }
      }
    }
  )

  // LGBM tree 22 (estim 7, class 1)
  s1 += (
    if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
      if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
        if (dice <= 0.2362911266201396) {
          if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
            if (dice <= 0.09160839160839163) {
              -0.09500469023767036
            } else {
              -0.03761837980231673
            }
          } else {
            -0.13508928295517844
          }
        } else {
          if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
            if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
              if (q_feats_d <= 1.0000000180025095e-35) {
                0.04783528724479562
              } else {
                -0.015111766357542973
              }
            } else {
              if (feature <= 0.5500000000000002) {
                -0.0617285445934782
              } else {
                0.005694422260141271
              }
            }
          } else {
            if (c_roads_d <= 1.5000000000000002) {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                -0.02563380735263902
              } else {
                0.026730383273631364
              }
            } else {
              if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
                0.07718204560869307
              } else {
                -0.07551290152002778
              }
            }
          }
        }
      } else {
        if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
          if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
            if (c_roads_d <= 1.0000000180025095e-35) {
              if (q_roads_d <= 1.5000000000000002) {
                0.05663911223666605
              } else {
                0.19657278948998613
              }
            } else {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                0.02906821827498891
              } else {
                -0.017934959650088
              }
            }
          } else {
            if (house <= 1.0000000180025095e-35) {
              if (dice <= 0.06350806451612905) {
                -0.10648152991918633
              } else {
                -0.000493455681174885
              }
            } else {
              -0.10231883890531941
            }
          }
        } else {
          if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
            if (house <= 0.8333333333333334) {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                -0.06659583997792215
              } else {
                -0.017590789803773148
              }
            } else {
              if (c_roads_d <= 1.5000000000000002) {
                0.05002108184577438
              } else {
                -0.1870681096203691
              }
            }
          } else {
            0.02392419818832231
          }
        }
      }
    } else {
      if (c_feats_d <= 1.0000000180025095e-35) {
        if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
          if (c_roads_d <= 1.5000000000000002) {
            -0.12182035548903587
          } else {
            -0.04464737759416868
          }
        } else {
          -0.027369896479525972
        }
      } else {
        if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
          if (dice <= 0.6167832167832169) {
            if (c_feats_d <= 1.5000000000000002) {
              -0.06584608692387481
            } else {
              if (dice <= 0.2152509652509653) {
                -0.08275226088655936
              } else {
                0.06753386916110149
              }
            }
          } else {
            0.1887191993941448
          }
        } else {
          0.01909465100518013
        }
      }
    }
  )

  // LGBM tree 23 (estim 7, class 2)
  s2 += (
    if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
      if (road_b <= 0.22500000000000003) {
        if (feature <= 0.2916666666666667) {
          if (c_feats_d <= 1.0000000180025095e-35) {
            if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
              if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
                -0.021797396039674708
              } else {
                0.04131110670341259
              }
            } else {
              0.09042983516098084
            }
          } else {
            if (q_feats_d <= 1.0000000180025095e-35) {
              if (dice <= 0.14415584415584418) {
                0.031953160204290655
              } else {
                -0.02119819701237265
              }
            } else {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                0.07265562454754451
              } else {
                0.029968827479684563
              }
            }
          }
        } else {
          if (dice <= 0.6214559386973181) {
            if (c_roads_d <= 1.5000000000000002) {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                0.025593318659995774
              } else {
                -0.015092533155211488
              }
            } else {
              if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
                -0.08208280381598106
              } else {
                -0.0033046801882238882
              }
            }
          } else {
            -0.11113648957382001
          }
        }
      } else {
        if (name <= 0.5833333333333334) {
          if (feature <= 1.0000000180025095e-35) {
            if (q_feats_d <= 1.0000000180025095e-35) {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                0.00466163439290299
              } else {
                -0.04429396512273563
              }
            } else {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                0.011604437146109066
              } else {
                0.08443491945288749
              }
            }
          } else {
            if (house <= 0.4166666666666667) {
              if (dice <= 0.3036890645586298) {
                0.01575448087493071
              } else {
                -0.060620571405848964
              }
            } else {
              -0.12541771442123062
            }
          }
        } else {
          -0.1369032170334154
        }
      }
    } else {
      if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
        if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
          if (feature <= 0.2916666666666667) {
            if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
              0.02445765580924632
            } else {
              0.10977201496661719
            }
          } else {
            -0.04582202767856388
          }
        } else {
          if (dice <= 0.22967032967032971) {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              -0.04358626937958838
            } else {
              -0.16199505772801198
            }
          } else {
            if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
              if (dice <= 0.29708431836091415) {
                -0.10484181480953557
              } else {
                -0.0398060411414475
              }
            } else {
              if (q_roads_d <= 1.5000000000000002) {
                0.045754744936063234
              } else {
                -0.061860404327257326
              }
            }
          }
        }
      } else {
        if (q_roads_d <= 2.5000000000000004) {
          -0.08137893099077799
        } else {
          0.1686164574466746
        }
      }
    }
  )

  // LGBM tree 24 (estim 8, class 0)
  s0 += (
    if (dice <= 0.2572373862696444) {
      if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
        if (house <= 0.8333333333333334) {
          if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
            if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
              if (c_roads_d <= 3.5000000000000004) {
                -0.02943016779975303
              } else {
                0.4593224113440151
              }
            } else {
              0.10385043828065176
            }
          } else {
            if (dice <= 0.1746758199847445) {
              -0.1195622429721019
            } else {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                -0.09257826616958638
              } else {
                0.01390557047654299
              }
            }
          }
        } else {
          if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
            -0.0022360418365578697
          } else {
            if (c_roads_d <= 1.0000000180025095e-35) {
              0.03174457611471423
            } else {
              0.30080768993632084
            }
          }
        }
      } else {
        0.022554842449046836
      }
    } else {
      if (name <= 0.5833333333333334) {
        if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
          if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
            if (c_roads_d <= 2.5000000000000004) {
              0.02037102884597327
            } else {
              if (q_roads_d <= 1.5000000000000002) {
                0.3729216076135514
              } else {
                0.030696487860627848
              }
            }
          } else {
            if (house <= 0.5833333333333334) {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                -0.0712505964474698
              } else {
                -0.022408086154941134
              }
            } else {
              if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
                0.01220915823382569
              } else {
                0.10779082168097535
              }
            }
          }
        } else {
          if (c_feats_d <= 3.5000000000000004) {
            if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
              -0.006051158440279539
            } else {
              if (c_feats_d <= 1.0000000180025095e-35) {
                0.2126050355546911
              } else {
                0.026546274520985444
              }
            }
          } else {
            0.18085706820336522
          }
        }
      } else {
        if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
          if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
            if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
              if (q_roads_d <= 1.0000000180025095e-35) {
                0.06027674482560499
              } else {
                -0.0349319942341712
              }
            } else {
              if (dice <= 0.3712316968130922) {
                0.2127827387884472
              } else {
                0.04951063219501692
              }
            }
          } else {
            -0.08025923178597252
          }
        } else {
          if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
            if (dice <= 0.47722567287784684) {
              if (dice <= 0.38956639566395673) {
                0.18146714553105164
              } else {
                0.5201222571511575
              }
            } else {
              0.09545074643121022
            }
          } else {
            if (dice <= 0.8352713178294575) {
              0.003012245461511439
            } else {
              0.15788684000263406
            }
          }
        }
      }
    }
  )

  // LGBM tree 25 (estim 8, class 1)
  s1 += (
    if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
      if (dice <= 0.2362911266201396) {
        if (dice <= 0.10620300751879701) {
          -0.08051946666008256
        } else {
          if (c_roads_d <= 1.0000000180025095e-35) {
            if (dice <= 0.11215932914046123) {
              0.243900570828547
            } else {
              -0.07777484600081298
            }
          } else {
            if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
              -0.0323477296149096
            } else {
              0.041805256739720784
            }
          }
        }
      } else {
        if (dice <= 0.47722567287784684) {
          if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
            if (feature <= 0.8750000000000001) {
              -0.012327318373602682
            } else {
              0.034250613291608216
            }
          } else {
            if (feature <= 0.18333333333333338) {
              if (c_roads_d <= 1.0000000180025095e-35) {
                -0.014869459509778
              } else {
                -0.10855924087416884
              }
            } else {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                -0.03308304422977072
              } else {
                0.057703194703256494
              }
            }
          }
        } else {
          0.014443586628016218
        }
      }
    } else {
      if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
        if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
          if (c_roads_d <= 1.0000000180025095e-35) {
            if (q_roads_d <= 1.0000000180025095e-35) {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                -0.02451867352548138
              } else {
                0.05462589281495617
              }
            } else {
              if (c_feats_d <= 1.0000000180025095e-35) {
                0.18273705334085233
              } else {
                0.044531248326994254
              }
            }
          } else {
            if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
              if (dice <= 0.06350806451612905) {
                -0.04466614934828535
              } else {
                0.022436200289968008
              }
            } else {
              if (q_feats_d <= 1.0000000180025095e-35) {
                0.008082710067510903
              } else {
                -0.03591661214479086
              }
            }
          }
        } else {
          if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
            if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
              if (dice <= 0.04396135265700484) {
                0.10277461384414405
              } else {
                -0.052092923922256305
              }
            } else {
              if (c_feats_d <= 1.5000000000000002) {
                -0.025979659850069663
              } else {
                0.03961223891985513
              }
            }
          } else {
            0.11220625518719561
          }
        }
      } else {
        if (house <= 1.0000000180025095e-35) {
          if (dice <= 1.0000000180025095e-35) {
            -0.10746502180220287
          } else {
            if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
              if (q_feats_d <= 1.5000000000000002) {
                -0.01913359883860043
              } else {
                0.02291607652527233
              }
            } else {
              if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
                0.015649771123499384
              } else {
                0.13939227322427555
              }
            }
          }
        } else {
          -0.08817893312768973
        }
      }
    }
  )

  // LGBM tree 26 (estim 8, class 2)
  s2 += (
    if (feature <= 0.5500000000000002) {
      if (road_b <= 1.0000000180025095e-35) {
        if (dice <= 0.0650449497620307) {
          if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
            0.07085380279400053
          } else {
            -0.03135547504195676
          }
        } else {
          if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
            if (name <= 1.0000000180025095e-35) {
              if (q_roads_d <= 1.5000000000000002) {
                0.012590098445301243
              } else {
                -0.06646972103003783
              }
            } else {
              if (q_feats_d <= 1.0000000180025095e-35) {
                -0.06642799584670633
              } else {
                0.005735086437854987
              }
            }
          } else {
            if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
              if (q_roads_d <= 1.5000000000000002) {
                0.031532624822901874
              } else {
                -0.016544279982320203
              }
            } else {
              if (dice <= 0.5345238095238096) {
                0.06411431931888317
              } else {
                -0.1326139855556457
              }
            }
          }
        }
      } else {
        if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
          if (q_feats_d <= 1.0000000180025095e-35) {
            if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
              if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
                0.019679692846426858
              } else {
                -0.03685768041880448
              }
            } else {
              if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
                -0.03263309690398802
              } else {
                -0.11343176884701375
              }
            }
          } else {
            if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
              if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
                0.0068183773749179956
              } else {
                -0.08066451859753616
              }
            } else {
              0.05749901966875737
            }
          }
        } else {
          -0.07635606786052203
        }
      }
    } else {
      if (q_feats_d <= 1.5000000000000002) {
        if (road_b <= 0.45000000000000007) {
          if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
            if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
              if (c_roads_d <= 1.0000000180025095e-35) {
                0.0428561905267116
              } else {
                -0.05810221729766784
              }
            } else {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                -0.005221759439302436
              } else {
                -0.06510418150875898
              }
            }
          } else {
            if (dice <= 0.21680376028202117) {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                0.03518840299065408
              } else {
                -0.09588955602630223
              }
            } else {
              if (house <= 1.0000000180025095e-35) {
                0.05135995172935225
              } else {
                -0.04912251733040896
              }
            }
          }
        } else {
          -0.06523026741746014
        }
      } else {
        if (feature <= 0.8750000000000001) {
          if (c_roads_d <= 1.0000000180025095e-35) {
            -0.118300267251726
          } else {
            if (q_roads_d <= 1.0000000180025095e-35) {
              0.13072404513028674
            } else {
              -0.0283364990270072
            }
          }
        } else {
          -0.11746777820814397
        }
      }
    }
  )

  // LGBM tree 27 (estim 9, class 0)
  s0 += (
    if (dice <= 0.40370370370370373) {
      if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
        if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
          if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
            if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
              if (c_roads_d <= 1.5000000000000002) {
                0.0021495266375757467
              } else {
                0.05652154216384807
              }
            } else {
              -0.04769340867521593
            }
          } else {
            if (c_roads_d <= 1.0000000180025095e-35) {
              if (dice <= 0.3819655521783182) {
                -0.12062827218120466
              } else {
                0.022750759867748164
              }
            } else {
              if (q_roads_d <= 1.0000000180025095e-35) {
                0.025077838692333147
              } else {
                -0.0767591021778395
              }
            }
          }
        } else {
          if (to_dbl(veto) <= 1.0000000180025095e-35) {
            if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
              if (q_feats_d <= 1.0000000180025095e-35) {
                0.022412357678773295
              } else {
                -0.018129383601086083
              }
            } else {
              if (dice <= 0.12973352033660593) {
                0.4278752374859392
              } else {
                0.03270121910469078
              }
            }
          } else {
            if (c_feats_d <= 1.5000000000000002) {
              -0.1174576351323135
            } else {
              0.05245037515445693
            }
          }
        }
      } else {
        if (dice <= 0.14724480578139118) {
          if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
            -0.1681235648160626
          } else {
            0.28217553416231583
          }
        } else {
          if (house <= 1.0000000180025095e-35) {
            if (to_dbl(veto) <= 1.0000000180025095e-35) {
              -0.07379144018896416
            } else {
              0.24197108474549625
            }
          } else {
            if (q_roads_d <= 1.5000000000000002) {
              -0.0517665454298621
            } else {
              if (dice <= 0.3306010928961749) {
                0.07914451886128092
              } else {
                0.4748596847344245
              }
            }
          }
        }
      }
    } else {
      if (c_roads_d <= 2.5000000000000004) {
        if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
          if (c_feats_d <= 2.5000000000000004) {
            if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
              0.023195608991942326
            } else {
              -0.018957449648637638
            }
          } else {
            0.07299395224399062
          }
        } else {
          if (c_feats_d <= 1.0000000180025095e-35) {
            if (dice <= 0.4248871695680207) {
              0.13580783586635817
            } else {
              if (q_roads_d <= 2.5000000000000004) {
                -0.08181338351250804
              } else {
                0.0902218884597316
              }
            }
          } else {
            if (name <= 0.5833333333333334) {
              if (q_roads_d <= 1.5000000000000002) {
                -0.03498866879551251
              } else {
                0.034121561551812785
              }
            } else {
              0.15667759756896235
            }
          }
        }
      } else {
        if (house <= 0.4166666666666667) {
          0.08551311191120363
        } else {
          0.32202545285223644
        }
      }
    }
  )

  // LGBM tree 28 (estim 9, class 1)
  s1 += (
    if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
      if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
        if (dice <= 0.27681992337164757) {
          if (q_feats_d <= 1.0000000180025095e-35) {
            if (c_feats_d <= 1.0000000180025095e-35) {
              if (name <= 0.4166666666666667) {
                -0.04204004968303666
              } else {
                0.07916013231426132
              }
            } else {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                0.07058016289345556
              } else {
                -0.005728967125468296
              }
            }
          } else {
            if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
              if (q_roads_d <= 1.5000000000000002) {
                -0.06492889099130737
              } else {
                0.01619932007976964
              }
            } else {
              -0.0044420886626539
            }
          }
        } else {
          -0.00018267652778838122
        }
      } else {
        if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
          if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
            if (c_roads_d <= 1.0000000180025095e-35) {
              if (q_roads_d <= 1.0000000180025095e-35) {
                0.016871418541131753
              } else {
                0.07188837731942646
              }
            } else {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                0.017559639542055947
              } else {
                -0.01295261273281131
              }
            }
          } else {
            if (house <= 1.0000000180025095e-35) {
              if (dice <= 0.2362911266201396) {
                -0.01875914464138869
              } else {
                0.009017441849185522
              }
            } else {
              -0.06581010130960244
            }
          }
        } else {
          if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
            if (house <= 0.8333333333333334) {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                -0.04411151959743098
              } else {
                0.03238959127166979
              }
            } else {
              if (c_roads_d <= 1.5000000000000002) {
                0.0521585677137081
              } else {
                -0.13931633828499432
              }
            }
          } else {
            0.022904344853178493
          }
        }
      }
    } else {
      if (c_feats_d <= 1.0000000180025095e-35) {
        if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
          if (dice <= 0.09160839160839163) {
            if (dice <= 0.04819976771196284) {
              -0.10306012552688129
            } else {
              if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
                0.02755665589112544
              } else {
                0.41826193502961484
              }
            }
          } else {
            if (dice <= 0.6516683518705765) {
              -0.0929249764124463
            } else {
              0.12818318234392603
            }
          }
        } else {
          if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
            -0.027630681523657403
          } else {
            0.15783919100500196
          }
        }
      } else {
        if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
          if (dice <= 0.6167832167832169) {
            -0.03478809231438166
          } else {
            0.13940281812433836
          }
        } else {
          if (dice <= 0.707107843137255) {
            0.017376024791535452
          } else {
            -0.15897719423853982
          }
        }
      }
    }
  )

  // LGBM tree 29 (estim 9, class 2)
  s2 += (
    if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
      if (dice <= 0.560701754385965) {
        if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
          if (q_roads_d <= 1.5000000000000002) {
            if (name <= 1.0000000180025095e-35) {
              if (feature <= 0.5500000000000002) {
                0.01649034640478228
              } else {
                -0.016714393102949365
              }
            } else {
              if (dice <= 0.15047169811320757) {
                -0.17176965419867615
              } else {
                -0.03914221277575309
              }
            }
          } else {
            if (dice <= 1.0000000180025095e-35) {
              0.11217752287474296
            } else {
              if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
                -0.0655295049608771
              } else {
                -0.017007399888375255
              }
            }
          }
        } else {
          if (c_roads_d <= 1.5000000000000002) {
            if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
              if (house <= 0.8333333333333334) {
                0.047071723044848406
              } else {
                -0.05269730615123581
              }
            } else {
              0.09190037129671302
            }
          } else {
            if (q_roads_d <= 2.5000000000000004) {
              if (dice <= 0.25866188769414583) {
                0.000829591105615705
              } else {
                -0.08162118411712127
              }
            } else {
              0.14025661098390266
            }
          }
        }
      } else {
        if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
          if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
            -0.043278830821928946
          } else {
            if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
              -0.030154271305016443
            } else {
              0.14664199658313476
            }
          }
        } else {
          -0.09851295354852664
        }
      }
    } else {
      if (house <= 1.0000000180025095e-35) {
        if (c_roads_d <= 1.5000000000000002) {
          if (dice <= 0.26201372997711675) {
            if (dice <= 0.2572373862696444) {
              if (feature <= 0.22500000000000003) {
                -0.037978930318441864
              } else {
                -0.12649172833448477
              }
            } else {
              -0.2187072266029664
            }
          } else {
            if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
              if (feature <= 0.8750000000000001) {
                0.012906076132330713
              } else {
                -0.03766602340507746
              }
            } else {
              -0.050960803328819845
            }
          }
        } else {
          if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
            if (road_b <= 0.5500000000000002) {
              0.10507132097015796
            } else {
              -0.03407882771948777
            }
          } else {
            if (name <= 0.4166666666666667) {
              if (feature <= 0.8750000000000001) {
                -0.0490889493800912
              } else {
                0.05604926813461196
              }
            } else {
              if (dice <= 0.3169856459330144) {
                0.21732876833778025
              } else {
                -0.022451185619689853
              }
            }
          }
        }
      } else {
        if (dice <= 0.22967032967032971) {
          -0.2109217692748754
        } else {
          -0.07760888764489067
        }
      }
    }
  )

  // LGBM tree 30 (estim 10, class 0)
  s0 += (
    if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
      if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
        if (c_roads_d <= 1.5000000000000002) {
          if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              if (road_b <= 0.8750000000000001) {
                -0.013267738038274603
              } else {
                0.06520167342923625
              }
            } else {
              if (c_feats_d <= 1.0000000180025095e-35) {
                -0.11257821982861195
              } else {
                -0.045150910152081114
              }
            }
          } else {
            if (to_dbl(veto) <= 1.0000000180025095e-35) {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                -0.003875310615632101
              } else {
                0.021645193495558917
              }
            } else {
              -0.09292499149089378
            }
          }
        } else {
          if (c_feats_d <= 1.0000000180025095e-35) {
            if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
              if (dice <= 0.7290209790209791) {
                0.007750258437451868
              } else {
                0.1914266562871898
              }
            } else {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                -0.07025165247933195
              } else {
                0.30742562914312854
              }
            }
          } else {
            if (dice <= 0.16271373414230558) {
              -0.06034124579546386
            } else {
              if (dice <= 0.16784037558685447) {
                0.3484542464043367
              } else {
                0.06062734150416014
              }
            }
          }
        }
      } else {
        if (q_feats_d <= 1.0000000180025095e-35) {
          -0.10287226077692364
        } else {
          if (road_b <= 0.8750000000000001) {
            -0.05182548174636043
          } else {
            0.0490965680849074
          }
        }
      }
    } else {
      if (c_feats_d <= 1.5000000000000002) {
        if (c_roads_d <= 1.5000000000000002) {
          0.008570739874337959
        } else {
          if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
            if (name <= 0.5833333333333334) {
              -0.06146084461302473
            } else {
              if (q_roads_d <= 1.5000000000000002) {
                0.24431431253462244
              } else {
                -0.056972151750171625
              }
            }
          } else {
            if (road_b <= 0.2916666666666667) {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                -0.025819052541517905
              } else {
                0.22255271802820653
              }
            } else {
              0.17541979195496307
            }
          }
        }
      } else {
        if (c_roads_d <= 1.5000000000000002) {
          if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
            if (dice <= 0.7527777777777779) {
              -0.0021122768587186706
            } else {
              0.13494654354530136
            }
          } else {
            if (feature <= 1.0000000180025095e-35) {
              if (road_b <= 0.8750000000000001) {
                0.21498399059953283
              } else {
                0.020290106309447917
              }
            } else {
              if (dice <= 0.26766169154228864) {
                -0.11711415111406379
              } else {
                0.07275996715819015
              }
            }
          }
        } else {
          -0.027711354959650367
        }
      }
    }
  )

  // LGBM tree 31 (estim 10, class 1)
  s1 += (
    if (road_b <= 1.0000000180025095e-35) {
      if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
        if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
          if (c_feats_d <= 1.0000000180025095e-35) {
            if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
              if (q_feats_d <= 1.5000000000000002) {
                -0.0016409040537572058
              } else {
                0.07808787381370559
              }
            } else {
              if (q_roads_d <= 1.0000000180025095e-35) {
                0.04151294977193075
              } else {
                0.2919535545586084
              }
            }
          } else {
            if (q_feats_d <= 1.0000000180025095e-35) {
              if (c_roads_d <= 1.5000000000000002) {
                0.0037320614506084816
              } else {
                0.11400632035510648
              }
            } else {
              if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
                -0.03531195751350122
              } else {
                0.03842479018758829
              }
            }
          }
        } else {
          if (dice <= 0.3060200668896322) {
            if (name <= 0.5833333333333334) {
              0.02901331786827192
            } else {
              0.22852528449075343
            }
          } else {
            if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                -0.006136474193499882
              } else {
                -0.08165922369966605
              }
            } else {
              0.04245573289093676
            }
          }
        }
      } else {
        if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
          if (q_feats_d <= 2.5000000000000004) {
            -0.01502244920947101
          } else {
            0.04779008770482103
          }
        } else {
          if (c_feats_d <= 1.5000000000000002) {
            if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
              -0.06623224038573514
            } else {
              0.09817285267511582
            }
          } else {
            if (dice <= 0.3454907161803714) {
              -0.021359431470205928
            } else {
              0.13664466081676913
            }
          }
        }
      }
    } else {
      if (q_feats_d <= 1.0000000180025095e-35) {
        if (dice <= 0.19433516915814322) {
          0.05228766906964839
        } else {
          if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
            if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                -0.026215482194434096
              } else {
                0.010625513570581759
              }
            } else {
              if (road_b <= 0.5500000000000002) {
                -0.13836795752586972
              } else {
                0.12353301407702892
              }
            }
          } else {
            if (q_roads_d <= 2.5000000000000004) {
              0.02270073658957377
            } else {
              0.13474110368121095
            }
          }
        }
      } else {
        if (feature <= 1.0000000180025095e-35) {
          if (dice <= 0.6167832167832169) {
            -0.008878657728205362
          } else {
            if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
              0.020881267904210528
            } else {
              -0.14443366174374447
            }
          }
        } else {
          if (dice <= 0.43288288288288296) {
            0.04344530279016278
          } else {
            0.005191257564739778
          }
        }
      }
    }
  )

  // LGBM tree 32 (estim 10, class 2)
  s2 += (
    if (road_b <= 1.0000000180025095e-35) {
      if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
        if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
          if (q_feats_d <= 1.0000000180025095e-35) {
            if (c_roads_d <= 1.5000000000000002) {
              if (dice <= 0.26766169154228864) {
                0.015846112898387187
              } else {
                -0.02440694309674107
              }
            } else {
              -0.07995115619749467
            }
          } else {
            if (q_roads_d <= 1.0000000180025095e-35) {
              if (c_feats_d <= 1.0000000180025095e-35) {
                0.0022155665359243717
              } else {
                0.04462830795601013
              }
            } else {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                -0.011865533526128156
              } else {
                -0.18566452973639294
              }
            }
          }
        } else {
          if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
            if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
              if (feature <= 0.8750000000000001) {
                -0.012827610897999109
              } else {
                -0.07163510258053672
              }
            } else {
              if (c_feats_d <= 1.5000000000000002) {
                0.03537399552100734
              } else {
                -0.0592336422897743
              }
            }
          } else {
            if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
              if (c_feats_d <= 1.0000000180025095e-35) {
                -0.16513955248052248
              } else {
                -0.04256260665533809
              }
            } else {
              if (dice <= 0.3819655521783182) {
                -0.029601207649952763
              } else {
                0.11857985924273715
              }
            }
          }
        }
      } else {
        if (q_feats_d <= 1.5000000000000002) {
          if (q_roads_d <= 2.5000000000000004) {
            if (dice <= 0.4144437215354588) {
              if (dice <= 0.41277890466531447) {
                0.022400428104968558
              } else {
                -0.2804647680756388
              }
            } else {
              if (dice <= 0.4299719887955183) {
                0.18531489930384776
              } else {
                0.03886037606166792
              }
            }
          } else {
            0.11498525984274163
          }
        } else {
          if (dice <= 0.20761494252873566) {
            if (dice <= 0.09413067552602437) {
              if (feature <= 0.22500000000000003) {
                0.10524117478459577
              } else {
                -0.09478850786000251
              }
            } else {
              -0.07449803399008453
            }
          } else {
            if (feature <= 0.5500000000000002) {
              0.03769520765100837
            } else {
              if (dice <= 0.29708431836091415) {
                -0.18178006140271524
              } else {
                -0.025579694582564642
              }
            }
          }
        }
      }
    } else {
      if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
        if (name <= 0.5833333333333334) {
          if (dice <= 0.7709790209790212) {
            if (c_feats_d <= 1.0000000180025095e-35) {
              0.001603787730350177
            } else {
              -0.01843178091491788
            }
          } else {
            -0.10309562857016581
          }
        } else {
          -0.07764204500768226
        }
      } else {
        -0.059745442130522304
      }
    }
  )

  // LGBM tree 33 (estim 11, class 0)
  s0 += (
    if (house <= 0.5833333333333334) {
      if (dice <= 0.22967032967032971) {
        if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
          if (dice <= 0.07477288609364081) {
            if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
              if (q_roads_d <= 3.5000000000000004) {
                -0.08791416458116576
              } else {
                0.5066719659656795
              }
            } else {
              0.7739840822044456
            }
          } else {
            if (c_feats_d <= 1.5000000000000002) {
              -0.018954941094308574
            } else {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                0.05279501609789392
              } else {
                -0.12860035208174858
              }
            }
          }
        } else {
          if (c_feats_d <= 1.5000000000000002) {
            -0.10567791994433441
          } else {
            if (dice <= 0.1746758199847445) {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                0.5094260256940067
              } else {
                0.041179427645524506
              }
            } else {
              -0.046950742551604245
            }
          }
        }
      } else {
        if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
          if (name <= 0.4166666666666667) {
            if (dice <= 0.7791327913279135) {
              -0.001373399587800901
            } else {
              0.0566732976324135
            }
          } else {
            if (dice <= 0.2636544190665343) {
              0.15918120898840388
            } else {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                0.017198133873563507
              } else {
                0.10296120658017625
              }
            }
          }
        } else {
          if (q_roads_d <= 1.5000000000000002) {
            if (q_feats_d <= 1.0000000180025095e-35) {
              -0.08197974515282515
            } else {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                -0.030641730454446632
              } else {
                0.14564429759233283
              }
            }
          } else {
            if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
              -0.022784549292753215
            } else {
              if (dice <= 0.5895721925133691) {
                0.17987790251394267
              } else {
                -0.03560651604398882
              }
            }
          }
        }
      }
    } else {
      if (c_roads_d <= 1.5000000000000002) {
        if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
          if (c_feats_d <= 2.5000000000000004) {
            0.004600529021226077
          } else {
            0.10224579253191665
          }
        } else {
          if (q_roads_d <= 1.0000000180025095e-35) {
            if (q_feats_d <= 1.0000000180025095e-35) {
              0.32321946097955795
            } else {
              0.07209585706325529
            }
          } else {
            0.05784709053436636
          }
        }
      } else {
        if (q_roads_d <= 1.5000000000000002) {
          0.10513640233739178
        } else {
          if (c_roads_d <= 2.5000000000000004) {
            if (dice <= 0.7290209790209791) {
              if (road_b <= 0.8750000000000001) {
                0.003709712614954211
              } else {
                -0.18357523089031744
              }
            } else {
              0.09347677204497973
            }
          } else {
            0.2279652311745835
          }
        }
      }
    }
  )

  // LGBM tree 34 (estim 11, class 1)
  s1 += (
    if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
      if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
        if (dice <= 0.30901856763925734) {
          if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
            if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
              -0.03788395624910234
            } else {
              if (dice <= 0.22967032967032971) {
                0.18201336027111942
              } else {
                -0.02959989211136535
              }
            }
          } else {
            if (c_feats_d <= 1.5000000000000002) {
              if (c_roads_d <= 1.0000000180025095e-35) {
                0.08630924627913279
              } else {
                0.007771661179204065
              }
            } else {
              -0.04998887028844468
            }
          }
        } else {
          if (c_roads_d <= 2.5000000000000004) {
            if (c_roads_d <= 1.5000000000000002) {
              if (dice <= 0.6262254901960785) {
                -0.007328402146016615
              } else {
                0.0340193609242004
              }
            } else {
              if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
                0.008199899029642037
              } else {
                0.10526650726294175
              }
            }
          } else {
            if (dice <= 0.4355731225296443) {
              -0.03645467281805649
            } else {
              -0.22980937385675632
            }
          }
        }
      } else {
        if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
          if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
            if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
              if (q_roads_d <= 1.5000000000000002) {
                0.013660650605818368
              } else {
                0.03617080909016262
              }
            } else {
              if (dice <= 0.2343137254901961) {
                0.026596725603722064
              } else {
                -0.02069738661100123
              }
            }
          } else {
            if (q_roads_d <= 1.0000000180025095e-35) {
              if (q_feats_d <= 2.5000000000000004) {
                0.0075149720275499736
              } else {
                0.09725731267171839
              }
            } else {
              if (dice <= 0.07767722473604828) {
                -0.0869319918928293
              } else {
                -0.008117671118012395
              }
            }
          }
        } else {
          if (c_feats_d <= 2.5000000000000004) {
            if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                -0.03388861267049383
              } else {
                0.0030732106284513975
              }
            } else {
              0.09168630465492693
            }
          } else {
            0.06247199898702356
          }
        }
      }
    } else {
      if (c_feats_d <= 1.0000000180025095e-35) {
        if (c_roads_d <= 1.5000000000000002) {
          if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
            if (dice <= 0.14724480578139118) {
              0.005406144567230711
            } else {
              -0.09362529815623548
            }
          } else {
            if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
              if (dice <= 0.3594871794871795) {
                -0.030965891493563
              } else {
                0.07207145703264639
              }
            } else {
              -0.1547050739965009
            }
          }
        } else {
          0.0002687809340632673
        }
      } else {
        -0.00597635724246152
      }
    }
  )

  // LGBM tree 35 (estim 11, class 2)
  s2 += (
    if (house <= 0.4166666666666667) {
      if (to_dbl(veto) <= 1.0000000180025095e-35) {
        if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
          if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
            if (c_feats_d <= 1.5000000000000002) {
              if (dice <= 0.057983193277310933) {
                0.08742612463454728
              } else {
                0.0074402218720690146
              }
            } else {
              if (dice <= 0.335897435897436) {
                -0.0033745977156910186
              } else {
                -0.06293162748114696
              }
            }
          } else {
            if (c_feats_d <= 1.0000000180025095e-35) {
              if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
                -0.049808604048085264
              } else {
                0.014722757119871987
              }
            } else {
              if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
                0.0038252552006222042
              } else {
                -0.03172053254616957
              }
            }
          }
        } else {
          if (dice <= 0.2343137254901961) {
            if (dice <= 0.10300618921308578) {
              if (c_roads_d <= 1.0000000180025095e-35) {
                -0.08837160497521496
              } else {
                0.09044756478306638
              }
            } else {
              if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
                -0.027498157132275387
              } else {
                -0.1771198200397995
              }
            }
          } else {
            if (feature <= 0.5500000000000002) {
              if (c_feats_d <= 1.5000000000000002) {
                0.03724442167425866
              } else {
                0.11665796758765239
              }
            } else {
              if (dice <= 0.4355731225296443) {
                -0.030474007275674512
              } else {
                0.03876667754703007
              }
            }
          }
        }
      } else {
        if (c_feats_d <= 1.5000000000000002) {
          if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
            0.04901558223066688
          } else {
            -0.06996052934124686
          }
        } else {
          if (dice <= 0.08421985815602838) {
            0.15439293466416465
          } else {
            if (q_feats_d <= 1.0000000180025095e-35) {
              -0.20806782869944426
            } else {
              -0.01632918880299274
            }
          }
        }
      }
    } else {
      if (feature <= 0.8750000000000001) {
        if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
          if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
            if (dice <= 0.462912087912088) {
              if (c_roads_d <= 1.0000000180025095e-35) {
                -0.06145402164747452
              } else {
                -0.00410717087669159
              }
            } else {
              if (dice <= 0.48566748566748574) {
                -0.172124910504186
              } else {
                -0.04855153179968417
              }
            }
          } else {
            -0.07046645510457154
          }
        } else {
          if (name <= 0.5833333333333334) {
            if (c_roads_d <= 1.0000000180025095e-35) {
              0.09716791608375144
            } else {
              if (q_feats_d <= 1.5000000000000002) {
                -0.06039441726792037
              } else {
                0.16734823231130477
              }
            }
          } else {
            -0.1990714981689891
          }
        }
      } else {
        -0.06676646853494049
      }
    }
  )

  // LGBM tree 36 (estim 12, class 0)
  s0 += (
    if (house <= 0.5833333333333334) {
      if (dice <= 0.2572373862696444) {
        if (road_b <= 0.2916666666666667) {
          if (dice <= 0.07477288609364081) {
            if (feature <= 0.22500000000000003) {
              if (q_feats_d <= 1.5000000000000002) {
                -0.049875103974556176
              } else {
                -0.20191398752959064
              }
            } else {
              if (c_feats_d <= 1.5000000000000002) {
                0.3057260135582911
              } else {
                -0.20793836521349843
              }
            }
          } else {
            if (c_roads_d <= 3.5000000000000004) {
              if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
                -0.0022900013348439857
              } else {
                -0.04789472177362464
              }
            } else {
              0.3643591115706914
            }
          }
        } else {
          -0.06858979043377605
        }
      } else {
        if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
          if (c_roads_d <= 1.5000000000000002) {
            if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
              if (dice <= 0.8599439775910366) {
                0.004386481603245634
              } else {
                0.062124722725901596
              }
            } else {
              if (feature <= 0.45000000000000007) {
                -0.06627370095253537
              } else {
                0.020598710764607463
              }
            }
          } else {
            if (dice <= 0.8706800445930881) {
              if (q_feats_d <= 1.0000000180025095e-35) {
                0.007097266435532301
              } else {
                0.055299546338744295
              }
            } else {
              -0.13389796970701406
            }
          }
        } else {
          if (q_feats_d <= 1.5000000000000002) {
            if (road_b <= 0.5500000000000002) {
              if (dice <= 0.6434624697336563) {
                -0.020593003520309697
              } else {
                -0.099863302807931
              }
            } else {
              0.08436649325973312
            }
          } else {
            if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
              -0.0010022797546543395
            } else {
              if (dice <= 0.31909090909090915) {
                -0.03272091302598602
              } else {
                0.23268506253163623
              }
            }
          }
        }
      }
    } else {
      if (c_roads_d <= 1.5000000000000002) {
        if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
          if (c_feats_d <= 2.5000000000000004) {
            if (name <= 0.5833333333333334) {
              if (c_roads_d <= 1.0000000180025095e-35) {
                -0.04952443455914199
              } else {
                0.004547807644870196
              }
            } else {
              if (road_b <= 0.45000000000000007) {
                0.11452022030638814
              } else {
                0.016904845462135436
              }
            }
          } else {
            0.07698548080886154
          }
        } else {
          0.059717402125969474
        }
      } else {
        if (name <= 0.5833333333333334) {
          if (q_roads_d <= 1.5000000000000002) {
            0.07625620956185816
          } else {
            if (c_roads_d <= 2.5000000000000004) {
              -0.048545389701799044
            } else {
              0.1628339672040615
            }
          }
        } else {
          0.18479748534272475
        }
      }
    }
  )

  // LGBM tree 37 (estim 12, class 1)
  s1 += (
    if (q_feats_d <= 1.0000000180025095e-35) {
      if (road_b <= 0.5500000000000002) {
        if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
          if (c_feats_d <= 1.0000000180025095e-35) {
            -0.019209271599608176
          } else {
            if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
              if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
                0.042259834219640906
              } else {
                -0.01297021859778656
              }
            } else {
              -0.12756712292516745
            }
          }
        } else {
          0.010479670024380184
        }
      } else {
        if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
          if (road_b <= 0.8750000000000001) {
            0.10466831167691593
          } else {
            0.010772045960718082
          }
        } else {
          if (dice <= 0.5345238095238096) {
            0.1219206239205194
          } else {
            0.019169156650065508
          }
        }
      }
    } else {
      if (feature <= 0.36666666666666675) {
        if (c_feats_d <= 1.0000000180025095e-35) {
          if (c_roads_d <= 1.0000000180025095e-35) {
            if (q_feats_d <= 1.5000000000000002) {
              if (dice <= 0.5843495934959351) {
                0.009335396854802662
              } else {
                -0.14884644629605992
              }
            } else {
              if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
                -0.0020357912297839873
              } else {
                0.14204356205107885
              }
            }
          } else {
            if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
              if (q_feats_d <= 2.5000000000000004) {
                -0.0115580229373845
              } else {
                -0.14573892867883925
              }
            } else {
              if (dice <= 0.41763565891472876) {
                0.16301754295984974
              } else {
                -0.0710463185903778
              }
            }
          }
        } else {
          if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
            if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
              if (road_b <= 0.22500000000000003) {
                -0.025785099431137198
              } else {
                0.000810202955753667
              }
            } else {
              if (dice <= 0.20169491525423733) {
                0.11266856063321405
              } else {
                0.004564511950601735
              }
            }
          } else {
            if (house <= 0.4166666666666667) {
              if (c_roads_d <= 1.0000000180025095e-35) {
                0.016267468161245212
              } else {
                -0.08562766772027117
              }
            } else {
              if (road_b <= 0.2916666666666667) {
                0.2313922254577179
              } else {
                -0.06948798338664672
              }
            }
          }
        }
      } else {
        if (dice <= 0.2343137254901961) {
          if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
            0.019708135478973904
          } else {
            0.0885312486288968
          }
        } else {
          if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
            -0.006539153499317899
          } else {
            if (c_feats_d <= 3.5000000000000004) {
              if (c_roads_d <= 1.0000000180025095e-35) {
                0.041571307166619324
              } else {
                0.007125409098870851
              }
            } else {
              -0.16277392223293377
            }
          }
        }
      }
    }
  )

  // LGBM tree 38 (estim 12, class 2)
  s2 += (
    if (dice <= 0.5812316715542524) {
      if (q_roads_d <= 1.5000000000000002) {
        if (c_roads_d <= 1.5000000000000002) {
          if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
            if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                0.017276940970193985
              } else {
                0.0004814655962756469
              }
            } else {
              if (dice <= 0.3306010928961749) {
                0.018929809640952856
              } else {
                0.06113728593157498
              }
            }
          } else {
            if (dice <= 0.26201372997711675) {
              if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
                -0.02870350370535532
              } else {
                -0.09058031090603623
              }
            } else {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                0.008812000266500883
              } else {
                -0.04017851386523964
              }
            }
          }
        } else {
          if (dice <= 0.09639953542392568) {
            if (q_feats_d <= 1.5000000000000002) {
              0.02980956960295861
            } else {
              0.11053020148351758
            }
          } else {
            if (dice <= 0.10084745762711866) {
              -0.2062656537552153
            } else {
              if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
                -0.022721317061318923
              } else {
                0.03220615368297899
              }
            }
          }
        }
      } else {
        if (road_b <= 0.5500000000000002) {
          if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
            if (q_feats_d <= 1.5000000000000002) {
              if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
                0.03053515904078942
              } else {
                -0.002201484610366547
              }
            } else {
              if (dice <= 0.24068965517241384) {
                -0.11980136411137143
              } else {
                0.013924115477798345
              }
            }
          } else {
            if (dice <= 0.13446327683615822) {
              if (q_roads_d <= 2.5000000000000004) {
                0.0028060591547861297
              } else {
                0.12097265575171212
              }
            } else {
              if (c_roads_d <= 1.5000000000000002) {
                -0.049958535682175266
              } else {
                -0.00855936965262973
              }
            }
          }
        } else {
          if (q_feats_d <= 1.0000000180025095e-35) {
            if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
              if (dice <= 0.5192592592592594) {
                -0.08407766980435598
              } else {
                0.06433100508839652
              }
            } else {
              -0.20950900871473024
            }
          } else {
            if (dice <= 0.3485162180814355) {
              0.21675341353750657
            } else {
              -0.07476564619852895
            }
          }
        }
      }
    } else {
      if (dice <= 0.5843495934959351) {
        -0.12715819343278187
      } else {
        if (dice <= 0.7709790209790212) {
          if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
            -0.023881481654491728
          } else {
            if (name <= 0.4166666666666667) {
              -0.0005636956737892598
            } else {
              0.19450343802343498
            }
          }
        } else {
          -0.054282299290078634
        }
      }
    }
  )

  // LGBM tree 39 (estim 13, class 0)
  s0 += (
    if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
      if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
        if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
          if (c_roads_d <= 3.5000000000000004) {
            if (q_roads_d <= 1.0000000180025095e-35) {
              0.02346740254690494
            } else {
              -0.0014726890719130822
            }
          } else {
            0.2606956320097506
          }
        } else {
          if (c_feats_d <= 1.0000000180025095e-35) {
            if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
              if (c_roads_d <= 1.5000000000000002) {
                -0.10190417052964215
              } else {
                -0.03265007851988211
              }
            } else {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                0.03325116683199989
              } else {
                -0.16383582465673266
              }
            }
          } else {
            if (dice <= 0.25866188769414583) {
              -0.060932363624063596
            } else {
              if (c_roads_d <= 1.0000000180025095e-35) {
                -0.037026626512086304
              } else {
                0.026143368345432277
              }
            }
          }
        }
      } else {
        if (to_dbl(veto) <= 1.0000000180025095e-35) {
          if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
            if (dice <= 0.34216027874564464) {
              if (q_feats_d <= 1.5000000000000002) {
                -0.015480747325284941
              } else {
                -0.09832902325201504
              }
            } else {
              if (q_roads_d <= 1.5000000000000002) {
                0.0018075346224466844
              } else {
                0.09778787054280969
              }
            }
          } else {
            if (name <= 0.5833333333333334) {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                0.0021604030728725435
              } else {
                0.022191343001474084
              }
            } else {
              if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
                0.036757904400505595
              } else {
                0.19001251473074665
              }
            }
          }
        } else {
          -0.05972406623776348
        }
      }
    } else {
      if (q_feats_d <= 1.0000000180025095e-35) {
        if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
          if (c_roads_d <= 1.0000000180025095e-35) {
            if (name <= 0.4166666666666667) {
              if (dice <= 0.3454907161803714) {
                0.04144675188491417
              } else {
                0.849380932144716
              }
            } else {
              -0.20839819633110335
            }
          } else {
            if (dice <= 0.15894736842105264) {
              -0.1802124756593411
            } else {
              if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
                -0.03140894691100035
              } else {
                -0.14673964676441278
              }
            }
          }
        } else {
          -0.16860531148418806
        }
      } else {
        if (dice <= 0.43288288288288296) {
          if (c_roads_d <= 1.5000000000000002) {
            -0.04710503112446856
          } else {
            if (house <= 0.4166666666666667) {
              0.019501754728780605
            } else {
              0.27210104041593275
            }
          }
        } else {
          if (c_feats_d <= 2.5000000000000004) {
            0.010840243112391219
          } else {
            0.20842307491551912
          }
        }
      }
    }
  )

  // LGBM tree 40 (estim 13, class 1)
  s1 += (
    if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
      if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
        if (q_roads_d <= 1.5000000000000002) {
          if (feature <= 0.36666666666666675) {
            if (q_feats_d <= 1.0000000180025095e-35) {
              if (dice <= 0.5045454545454546) {
                0.0001724647371483617
              } else {
                0.032212456466577714
              }
            } else {
              if (c_feats_d <= 1.0000000180025095e-35) {
                0.006613000500619971
              } else {
                -0.02591651383228995
              }
            }
          } else {
            if (dice <= 0.4248871695680207) {
              if (dice <= 0.4220647773279353) {
                0.01162841320253063
              } else {
                0.18890601326758277
              }
            } else {
              if (dice <= 0.5812316715542524) {
                -0.01555333023404786
              } else {
                0.01344455729961875
              }
            }
          }
        } else {
          if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
            if (dice <= 0.05634920634920635) {
              -0.0553225621051809
            } else {
              if (dice <= 0.6414285714285716) {
                0.021601511613962916
              } else {
                -0.05962717668133602
              }
            }
          } else {
            if (dice <= 0.19433516915814322) {
              -0.1514331412674705
            } else {
              if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
                -0.06585621613560017
              } else {
                -0.0026893576670361905
              }
            }
          }
        }
      } else {
        if (name <= 0.5833333333333334) {
          if (c_roads_d <= 1.5000000000000002) {
            if (c_feats_d <= 1.0000000180025095e-35) {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                -0.04187963160881202
              } else {
                -0.21973505274943808
              }
            } else {
              -0.006991874734933671
            }
          } else {
            0.021152655949414553
          }
        } else {
          if (dice <= 0.24068965517241384) {
            0.042760565672182026
          } else {
            -0.1191534338064223
          }
        }
      }
    } else {
      if (q_roads_d <= 2.5000000000000004) {
        if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
          if (dice <= 0.12973352033660593) {
            -0.1610519542860474
          } else {
            if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
              if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
                0.029456300787250055
              } else {
                0.08899219575603415
              }
            } else {
              if (dice <= 0.3504385964912281) {
                -0.12299292418981027
              } else {
                0.004135954006971898
              }
            }
          }
        } else {
          if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
            if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
              -0.09531024787116237
            } else {
              -0.29389812578107133
            }
          } else {
            if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                0.04661930026806336
              } else {
                -0.14432071894406903
              }
            } else {
              0.04849750931125117
            }
          }
        }
      } else {
        -0.19697823096761655
      }
    }
  )

  // LGBM tree 41 (estim 13, class 2)
  s2 += (
    if (feature <= 0.8750000000000001) {
      if (q_feats_d <= 1.0000000180025095e-35) {
        if (c_feats_d <= 1.0000000180025095e-35) {
          if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
            if (name <= 0.5833333333333334) {
              if (dice <= 0.3060200668896322) {
                0.016541138883769724
              } else {
                -0.009497671531140136
              }
            } else {
              if (q_roads_d <= 1.0000000180025095e-35) {
                -0.07225545578380155
              } else {
                -0.00850298668547356
              }
            }
          } else {
            if (c_roads_d <= 1.5000000000000002) {
              0.059719888849129925
            } else {
              -0.018866142738777687
            }
          }
        } else {
          if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
            if (q_roads_d <= 1.0000000180025095e-35) {
              -0.04633649312308488
            } else {
              -0.01671042682892339
            }
          } else {
            0.008892794691719991
          }
        }
      } else {
        if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
          if (q_roads_d <= 1.5000000000000002) {
            if (c_feats_d <= 1.0000000180025095e-35) {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                0.009403876586991267
              } else {
                -0.0737357642975427
              }
            } else {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                0.03352324196461971
              } else {
                -0.010203882269462231
              }
            }
          } else {
            if (feature <= 1.0000000180025095e-35) {
              if (dice <= 0.5227743271221533) {
                -0.003372129890318788
              } else {
                -0.16392192042745876
              }
            } else {
              if (dice <= 0.10620300751879701) {
                -0.30010568756494166
              } else {
                -0.057027442937145414
              }
            }
          }
        } else {
          if (c_feats_d <= 1.0000000180025095e-35) {
            if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
              -0.16837305358437868
            } else {
              if (dice <= 0.2636544190665343) {
                -0.14095350938255685
              } else {
                0.031034561444165273
              }
            }
          } else {
            if (dice <= 0.3712316968130922) {
              if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
                0.021924196147809466
              } else {
                -0.030382990198796957
              }
            } else {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                0.03064467472588943
              } else {
                -0.013467138415692524
              }
            }
          }
        }
      }
    } else {
      if (q_feats_d <= 1.5000000000000002) {
        if (q_roads_d <= 2.5000000000000004) {
          if (dice <= 0.19560019129603065) {
            -0.040842203985138555
          } else {
            if (road_b <= 0.45000000000000007) {
              0.003036121129047859
            } else {
              -0.02710284866145974
            }
          }
        } else {
          if (dice <= 0.34216027874564464) {
            0.18690563329000262
          } else {
            -0.08216775292993216
          }
        }
      } else {
        if (dice <= 0.49561403508771934) {
          -0.10654514687266883
        } else {
          -0.03861459591538418
        }
      }
    }
  )

  // LGBM tree 42 (estim 14, class 0)
  s0 += (
    if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
      if (to_dbl(veto) <= 1.0000000180025095e-35) {
        if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
          if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
            0.009757191078932316
          } else {
            if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
              if (dice <= 0.41763565891472876) {
                -0.03431732873652087
              } else {
                0.02397057747844505
              }
            } else {
              if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
                -0.07678174161247031
              } else {
                0.16767245906854994
              }
            }
          }
        } else {
          if (c_feats_d <= 1.5000000000000002) {
            if (q_roads_d <= 3.5000000000000004) {
              if (c_roads_d <= 1.5000000000000002) {
                0.0019854222774979232
              } else {
                0.028217964379220126
              }
            } else {
              -0.1825384177504636
            }
          } else {
            if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
              if (c_roads_d <= 2.5000000000000004) {
                0.007751476655896719
              } else {
                0.2395194045587148
              }
            } else {
              if (q_feats_d <= 2.5000000000000004) {
                0.07057659715016104
              } else {
                -0.07848479508951278
              }
            }
          }
        }
      } else {
        if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
          if (dice <= 0.07767722473604828) {
            -0.17393647111593696
          } else {
            if (q_feats_d <= 1.0000000180025095e-35) {
              if (q_roads_d <= 2.5000000000000004) {
                -0.08955124377216847
              } else {
                0.22074549199410196
              }
            } else {
              if (dice <= 0.29708431836091415) {
                0.05149400114015791
              } else {
                -0.06254611593086756
              }
            }
          }
        } else {
          -0.1286201776139924
        }
      }
    } else {
      if (dice <= 0.14724480578139118) {
        if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
          -0.14659850997476706
        } else {
          0.1908283571594389
        }
      } else {
        if (q_roads_d <= 1.5000000000000002) {
          if (c_feats_d <= 1.0000000180025095e-35) {
            if (q_feats_d <= 1.0000000180025095e-35) {
              -0.09531154991882995
            } else {
              if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
                0.06196647622138946
              } else {
                -0.21414685647131762
              }
            }
          } else {
            if (dice <= 0.16108108108108113) {
              if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
                -0.05165515983321004
              } else {
                0.7141489931648053
              }
            } else {
              if (dice <= 0.1804613297150611) {
                -0.20994293817384616
              } else {
                -0.014724224608327634
              }
            }
          }
        } else {
          if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
            if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
              if (dice <= 0.365491651205937) {
                0.07975840793959921
              } else {
                -0.06790864157558084
              }
            } else {
              0.11274497354419367
            }
          } else {
            -0.15546967965830819
          }
        }
      }
    }
  )

  // LGBM tree 43 (estim 14, class 1)
  s1 += (
    if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
      if (dice <= 0.18677325581395351) {
        if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
          if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
            -0.035811534137736155
          } else {
            -0.14477308457356947
          }
        } else {
          if (q_roads_d <= 1.5000000000000002) {
            -0.025766322576543498
          } else {
            if (to_dbl(veto) <= 1.0000000180025095e-35) {
              0.0872702849702944
            } else {
              -0.14130454643218518
            }
          }
        }
      } else {
        if (dice <= 0.19433516915814322) {
          if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
            0.10300955019832665
          } else {
            -0.032410783775815175
          }
        } else {
          -0.0026477636398087576
        }
      }
    } else {
      if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
        if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
          if (c_feats_d <= 1.5000000000000002) {
            if (c_roads_d <= 1.0000000180025095e-35) {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                -0.0021836860625183453
              } else {
                0.051195876899341956
              }
            } else {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                0.0038139277226959577
              } else {
                0.019653273594366166
              }
            }
          } else {
            if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
              if (dice <= 0.335897435897436) {
                0.007528993772537498
              } else {
                0.09197347362518415
              }
            } else {
              if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
                -0.010878575271806374
              } else {
                -0.06835391021991757
              }
            }
          }
        } else {
          if (house <= 1.0000000180025095e-35) {
            if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
              if (q_feats_d <= 1.5000000000000002) {
                -0.010866711827929547
              } else {
                0.014726789616730743
              }
            } else {
              if (c_feats_d <= 1.5000000000000002) {
                0.054563877463245376
              } else {
                -0.039660011157193704
              }
            }
          } else {
            if (c_roads_d <= 1.0000000180025095e-35) {
              if (dice <= 0.5192592592592594) {
                -0.10202652746929046
              } else {
                0.06319564695385507
              }
            } else {
              if (c_feats_d <= 1.0000000180025095e-35) {
                -0.11577322977722433
              } else {
                0.034884071054947105
              }
            }
          }
        }
      } else {
        if (c_feats_d <= 2.5000000000000004) {
          if (dice <= 0.04396135265700484) {
            0.12149399558460958
          } else {
            if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
              if (road_b <= 0.45000000000000007) {
                -0.042958102544661154
              } else {
                -0.002354448733031787
              }
            } else {
              if (c_feats_d <= 1.5000000000000002) {
                -0.01757775022471145
              } else {
                0.04093177060756702
              }
            }
          }
        } else {
          if (feature <= 0.8750000000000001) {
            0.1057038973480461
          } else {
            -0.011132001535955614
          }
        }
      }
    }
  )

  // LGBM tree 44 (estim 14, class 2)
  s2 += (
    if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
      if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
        if (c_roads_d <= 1.0000000180025095e-35) {
          if (q_feats_d <= 1.5000000000000002) {
            0.024439223843716017
          } else {
            if (c_feats_d <= 1.0000000180025095e-35) {
              -0.06291176301589481
            } else {
              if (dice <= 0.18808962264150947) {
                0.09250098200330842
              } else {
                -0.0018809780672317266
              }
            }
          }
        } else {
          if (c_feats_d <= 1.0000000180025095e-35) {
            if (dice <= 0.06107226107226108) {
              0.09122159685764018
            } else {
              if (dice <= 0.15047169811320757) {
                -0.03794144763062972
              } else {
                0.01510037111254423
              }
            }
          } else {
            if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
              -0.023412639719119357
            } else {
              if (dice <= 0.04396135265700484) {
                0.14228232169969107
              } else {
                0.0011213505668031382
              }
            }
          }
        }
      } else {
        if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
          if (c_feats_d <= 1.5000000000000002) {
            if (feature <= 0.18333333333333338) {
              if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
                -0.003832308447480001
              } else {
                0.02119584191388231
              }
            } else {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                -0.01651312964812799
              } else {
                -0.07092625627051422
              }
            }
          } else {
            if (house <= 0.4166666666666667) {
              if (q_feats_d <= 1.5000000000000002) {
                0.010024813187997894
              } else {
                0.04519186444099789
              }
            } else {
              if (dice <= 0.335897435897436) {
                -0.050544698074850465
              } else {
                0.030670617184579394
              }
            }
          }
        } else {
          if (dice <= 0.1804613297150611) {
            -0.15412065845166042
          } else {
            if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
              if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
                -0.02478104566388932
              } else {
                -0.09749134309958075
              }
            } else {
              0.016258922119346122
            }
          }
        }
      }
    } else {
      if (q_roads_d <= 2.5000000000000004) {
        if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
          if (dice <= 0.4558441558441559) {
            if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
              if (q_feats_d <= 1.0000000180025095e-35) {
                -0.0029854733168543407
              } else {
                -0.07819412428358966
              }
            } else {
              if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
                0.02656303377482123
              } else {
                -0.11600357478532472
              }
            }
          } else {
            -0.07553511113060167
          }
        } else {
          if (name <= 0.5833333333333334) {
            if (dice <= 0.560701754385965) {
              0.042907402266685
            } else {
              -0.06487215920490537
            }
          } else {
            0.2504492735632921
          }
        }
      } else {
        0.19035578117661708
      }
    }
  )

  // LGBM tree 45 (estim 15, class 0)
  s0 += (
    if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
      if (c_feats_d <= 4.500000000000001) {
        if (name <= 0.5833333333333334) {
          if (feature <= 0.7083333333333334) {
            if (c_roads_d <= 1.0000000180025095e-35) {
              if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
                -0.013810161212934552
              } else {
                -0.05727397968068153
              }
            } else {
              if (feature <= 0.36666666666666675) {
                0.006791260543677332
              } else {
                -0.021305265166655034
              }
            }
          } else {
            if (c_feats_d <= 2.5000000000000004) {
              if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
                -0.012009165812840946
              } else {
                0.015247162146499803
              }
            } else {
              if (dice <= 0.21680376028202117) {
                0.22528160658657292
              } else {
                0.039609865487558175
              }
            }
          }
        } else {
          if (dice <= 0.18350168350168353) {
            if (q_feats_d <= 1.0000000180025095e-35) {
              if (q_roads_d <= 1.0000000180025095e-35) {
                0.0705509877231604
              } else {
                0.4323463945123299
              }
            } else {
              if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
                -0.12919151655406041
              } else {
                0.1300153105388223
              }
            }
          } else {
            if (dice <= 0.22431865828092246) {
              if (dice <= 0.19560019129603065) {
                -0.2250736828027486
              } else {
                -0.08912378185874076
              }
            } else {
              if (dice <= 0.2636544190665343) {
                0.11501529914137353
              } else {
                0.016127773589681586
              }
            }
          }
        }
      } else {
        0.2088233079360212
      }
    } else {
      if (dice <= 0.19433516915814322) {
        if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
          -0.09844698569637689
        } else {
          0.04720557953481451
        }
      } else {
        if (q_roads_d <= 1.5000000000000002) {
          if (dice <= 0.26201372997711675) {
            if (dice <= 0.2572373862696444) {
              if (feature <= 0.22500000000000003) {
                0.03221825689775613
              } else {
                -0.11217655693574442
              }
            } else {
              0.2980272784340317
            }
          } else {
            if (dice <= 0.3454907161803714) {
              if (c_roads_d <= 1.5000000000000002) {
                -0.1040192908868568
              } else {
                0.041313466059992594
              }
            } else {
              if (c_roads_d <= 1.0000000180025095e-35) {
                0.0651329729676393
              } else {
                -0.023375680830288695
              }
            }
          }
        } else {
          if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
            if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
              if (dice <= 0.365491651205937) {
                0.0818728944773524
              } else {
                -0.0581992310583652
              }
            } else {
              if (dice <= 0.5895721925133691) {
                0.12536660183743006
              } else {
                -0.04459172306672242
              }
            }
          } else {
            -0.12488185968489396
          }
        }
      }
    }
  )

  // LGBM tree 46 (estim 15, class 1)
  s1 += (
    if (c_feats_d <= 3.5000000000000004) {
      if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
        if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
          if (q_roads_d <= 1.5000000000000002) {
            if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
              if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
                -0.0016599243542576763
              } else {
                0.008214639238079928
              }
            } else {
              if (q_feats_d <= 2.5000000000000004) {
                -0.010807074301409062
              } else {
                0.03861399881874111
              }
            }
          } else {
            if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
              if (dice <= 0.46737588652482276) {
                0.016935754211705095
              } else {
                -0.013756207514490918
              }
            } else {
              if (dice <= 0.19433516915814322) {
                -0.13776367313197663
              } else {
                -0.011698803911929631
              }
            }
          }
        } else {
          if (name <= 0.5833333333333334) {
            if (dice <= 0.6324561403508773) {
              if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
                -0.005292046854578258
              } else {
                -0.0360977883584511
              }
            } else {
              if (road_b <= 0.8750000000000001) {
                0.15824832299572061
              } else {
                -0.02485855241467012
              }
            }
          } else {
            if (dice <= 0.2343137254901961) {
              0.05477671165990514
            } else {
              if (q_feats_d <= 1.0000000180025095e-35) {
                -0.14608122475538804
              } else {
                -0.014333433483086503
              }
            }
          }
        }
      } else {
        if (dice <= 0.6324561403508773) {
          if (road_b <= 0.5500000000000002) {
            if (road_b <= 0.22500000000000003) {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                0.027464692031500433
              } else {
                -0.05534048290318939
              }
            } else {
              if (dice <= 0.32345248474280736) {
                -0.25290618636388157
              } else {
                -0.008698571057337711
              }
            }
          } else {
            if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
              if (c_roads_d <= 1.5000000000000002) {
                0.14895564377681808
              } else {
                0.0417232670799404
              }
            } else {
              0.0399147368078949
            }
          }
        } else {
          if (q_feats_d <= 1.0000000180025095e-35) {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              -0.0692889439661962
            } else {
              if (house <= 0.8333333333333334) {
                0.08556408767444147
              } else {
                -0.04336977456644466
              }
            }
          } else {
            if (feature <= 0.5500000000000002) {
              -0.18835012843620424
            } else {
              if (dice <= 0.8352713178294575) {
                0.021403689924501805
              } else {
                -0.09039358486209774
              }
            }
          }
        }
      }
    } else {
      if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
        -0.066562193320265
      } else {
        if (dice <= 0.3925070028011205) {
          0.13307833142130857
        } else {
          -0.061086638179628824
        }
      }
    }
  )

  // LGBM tree 47 (estim 15, class 2)
  s2 += (
    if (dice <= 0.672316384180791) {
      if (q_roads_d <= 1.5000000000000002) {
        if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
          if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
            if (c_roads_d <= 1.5000000000000002) {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                0.012883476487595219
              } else {
                -0.003445144517450877
              }
            } else {
              if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
                -0.016243696302301543
              } else {
                0.03225501623303928
              }
            }
          } else {
            if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
              if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
                0.0025816990064336377
              } else {
                -0.058408552297768666
              }
            } else {
              if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
                -0.024295560871310788
              } else {
                0.10130535162763664
              }
            }
          }
        } else {
          if (c_roads_d <= 1.0000000180025095e-35) {
            if (dice <= 0.18808962264150947) {
              if (dice <= 0.15047169811320757) {
                -0.04434805004152677
              } else {
                -0.251758653655205
              }
            } else {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                0.03504376052533503
              } else {
                -0.07614563185433627
              }
            }
          } else {
            if (feature <= 0.36666666666666675) {
              if (q_feats_d <= 3.5000000000000004) {
                0.029911978021457272
              } else {
                0.21297234822726138
              }
            } else {
              if (q_feats_d <= 2.5000000000000004) {
                -0.001735071375332117
              } else {
                -0.15007326321023196
              }
            }
          }
        }
      } else {
        if (dice <= 1.0000000180025095e-35) {
          if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
            0.0936981423996209
          } else {
            -0.36386229863281455
          }
        } else {
          if (road_b <= 0.5500000000000002) {
            if (c_roads_d <= 1.5000000000000002) {
              if (dice <= 0.5439137134052389) {
                -0.02056705691737662
              } else {
                0.05686640974541171
              }
            } else {
              if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
                0.00728047945768975
              } else {
                0.15059563070337362
              }
            }
          } else {
            if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
              -0.08949691405506378
            } else {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                0.1397387835948451
              } else {
                -0.03223099062820838
              }
            }
          }
        }
      }
    } else {
      if (dice <= 0.7008771929824562) {
        if (c_roads_d <= 1.0000000180025095e-35) {
          -0.22834048941482968
        } else {
          -0.06535686564203999
        }
      } else {
        if (name <= 0.5833333333333334) {
          if (dice <= 0.7709790209790212) {
            -0.0043236194005743305
          } else {
            -0.04673344262011737
          }
        } else {
          if (dice <= 0.7211111111111111) {
            0.18102965040799487
          } else {
            0.02202741661946279
          }
        }
      }
    }
  )

  // LGBM tree 48 (estim 16, class 0)
  s0 += (
    if (house <= 1.0000000180025095e-35) {
      if (c_feats_d <= 1.0000000180025095e-35) {
        if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
          if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
            if (dice <= 0.8193473193473194) {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                0.035113036275655554
              } else {
                -0.014373983543038569
              }
            } else {
              -0.13668050172401539
            }
          } else {
            if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
              -0.03996185827347336
            } else {
              0.2741043560829569
            }
          }
        } else {
          if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
            if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
              if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
                -0.035963639662403804
              } else {
                0.0016793153735616016
              }
            } else {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                -0.11580159232387988
              } else {
                0.15051231257738698
              }
            }
          } else {
            if (dice <= 0.6966632962588474) {
              -0.11500480467858828
            } else {
              0.37178304948804036
            }
          }
        }
      } else {
        if (q_feats_d <= 1.0000000180025095e-35) {
          if (q_roads_d <= 1.0000000180025095e-35) {
            if (dice <= 0.6262254901960785) {
              if (dice <= 0.21680376028202117) {
                0.015725247846692835
              } else {
                0.09967386768995957
              }
            } else {
              -0.10913229438191156
            }
          } else {
            if (dice <= 0.18350168350168353) {
              if (dice <= 0.16271373414230558) {
                0.007389943378234015
              } else {
                0.19081248583090335
              }
            } else {
              -0.004951419617265412
            }
          }
        } else {
          if (dice <= 0.7791327913279135) {
            -0.004428018877250557
          } else {
            0.04035011254946772
          }
        }
      }
    } else {
      if (q_roads_d <= 1.0000000180025095e-35) {
        if (q_feats_d <= 1.0000000180025095e-35) {
          if (c_feats_d <= 1.0000000180025095e-35) {
            if (dice <= 0.3925070028011205) {
              if (dice <= 0.21132376395534294) {
                -0.05059508887184827
              } else {
                0.23261935080384227
              }
            } else {
              -0.01934835442848769
            }
          } else {
            if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
              if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
                0.021363833301126674
              } else {
                0.5025160802079621
              }
            } else {
              0.5772130719260534
            }
          }
        } else {
          if (dice <= 0.6516683518705765) {
            if (c_roads_d <= 1.0000000180025095e-35) {
              if (feature <= 0.5500000000000002) {
                -0.13209915630251282
              } else {
                0.06717589284528765
              }
            } else {
              if (dice <= 0.14415584415584418) {
                0.218395498409186
              } else {
                0.027970278098426032
              }
            }
          } else {
            0.1648426924074846
          }
        }
      } else {
        0.004060482684216015
      }
    }
  )

  // LGBM tree 49 (estim 16, class 1)
  s1 += (
    if (q_feats_d <= 1.0000000180025095e-35) {
      if (road_b <= 0.5500000000000002) {
        if (dice <= 0.8765243902439025) {
          if (dice <= 0.81557067271353) {
            if (c_feats_d <= 2.5000000000000004) {
              -0.000992981932399733
            } else {
              if (road_b <= 0.2916666666666667) {
                0.034151202150918644
              } else {
                0.23143346646947657
              }
            }
          } else {
            -0.17872947569747014
          }
        } else {
          0.17345060020339695
        }
      } else {
        if (c_roads_d <= 3.5000000000000004) {
          if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
            if (dice <= 0.19433516915814322) {
              if (dice <= 0.11882352941176472) {
                -0.03729273591128989
              } else {
                0.05216397164686095
              }
            } else {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                0.010904699108871105
              } else {
                -0.023930709424936383
              }
            }
          } else {
            if (dice <= 0.32495285983658084) {
              0.1648267850170878
            } else {
              0.043461588267292184
            }
          }
        } else {
          -0.15204726830961124
        }
      }
    } else {
      if (c_roads_d <= 2.5000000000000004) {
        if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
          if (c_roads_d <= 1.5000000000000002) {
            if (c_feats_d <= 1.0000000180025095e-35) {
              if (name <= 1.0000000180025095e-35) {
                0.013015104796057258
              } else {
                -0.07362830693827266
              }
            } else {
              if (name <= 0.4166666666666667) {
                -0.010393060584635854
              } else {
                0.07475180174707374
              }
            }
          } else {
            if (q_roads_d <= 2.5000000000000004) {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                0.018316972010447068
              } else {
                -0.010560168997475741
              }
            } else {
              -0.09577304553803391
            }
          }
        } else {
          if (dice <= 0.22967032967032971) {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              if (q_roads_d <= 1.0000000180025095e-35) {
                0.08088952332125278
              } else {
                -0.07599188805392666
              }
            } else {
              if (q_feats_d <= 1.5000000000000002) {
                0.05850944709439369
              } else {
                0.1386858796237865
              }
            }
          } else {
            if (c_feats_d <= 1.5000000000000002) {
              if (name <= 0.5833333333333334) {
                0.016261646281721696
              } else {
                -0.03094069287430534
              }
            } else {
              if (c_roads_d <= 1.0000000180025095e-35) {
                0.021553069707914596
              } else {
                -0.0323139833921759
              }
            }
          }
        }
      } else {
        if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
          if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
            -0.00387767704050413
          } else {
            if (c_feats_d <= 1.5000000000000002) {
              -0.05275936186399718
            } else {
              -0.22892183793460014
            }
          }
        } else {
          -0.21335928754613387
        }
      }
    }
  )

  // LGBM tree 50 (estim 16, class 2)
  s2 += (
    if (house <= 0.4166666666666667) {
      if (dice <= 0.560701754385965) {
        if (dice <= 0.44222222222222224) {
          if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
            if (dice <= 0.43288288288288296) {
              if (q_feats_d <= 1.0000000180025095e-35) {
                -0.0022998135531786604
              } else {
                0.009084001245251909
              }
            } else {
              if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
                -0.18318280506164153
              } else {
                -0.03755022612557242
              }
            }
          } else {
            if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
              if (c_feats_d <= 1.5000000000000002) {
                -0.0028575264175109607
              } else {
                0.03697236450252219
              }
            } else {
              if (q_roads_d <= 2.5000000000000004) {
                -0.017843936796464496
              } else {
                0.1277137057226588
              }
            }
          }
        } else {
          if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
            if (dice <= 0.4522215459525259) {
              if (name <= 1.0000000180025095e-35) {
                0.05870576479176983
              } else {
                -0.0483495207786572
              }
            } else {
              if (road_b <= 0.45000000000000007) {
                0.013480402047108032
              } else {
                -0.026529665507200758
              }
            }
          } else {
            if (dice <= 0.48074074074074075) {
              0.009283937310272588
            } else {
              if (q_feats_d <= 1.5000000000000002) {
                0.11194784191057959
              } else {
                -0.018066655913771715
              }
            }
          }
        }
      } else {
        -0.012778639856077747
      }
    } else {
      if (c_feats_d <= 1.0000000180025095e-35) {
        if (dice <= 0.2362911266201396) {
          if (q_roads_d <= 1.0000000180025095e-35) {
            if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
              if (dice <= 0.11215932914046123) {
                -0.2610754360541038
              } else {
                -0.05059009152156981
              }
            } else {
              0.075909325248732
            }
          } else {
            if (dice <= 0.05971479500891266) {
              -0.020421550206645357
            } else {
              if (road_b <= 0.22500000000000003) {
                0.10508783529542595
              } else {
                0.028534931426370494
              }
            }
          }
        } else {
          -0.010468380705510478
        }
      } else {
        if (name <= 0.5833333333333334) {
          if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
            if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
              if (house <= 0.8333333333333334) {
                0.0745799847194905
              } else {
                -0.01178785286576045
              }
            } else {
              -0.08656039881157503
            }
          } else {
            if (dice <= 0.09160839160839163) {
              if (dice <= 0.07207792207792209) {
                0.10518169483520087
              } else {
                -0.8633324399231391
              }
            } else {
              if (feature <= 0.2916666666666667) {
                -0.014252296725266381
              } else {
                -0.11772685169501379
              }
            }
          }
        } else {
          -0.11383047678796089
        }
      }
    }
  )

  // LGBM tree 51 (estim 17, class 0)
  s0 += (
    if (c_roads_d <= 1.5000000000000002) {
      if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
        if (dice <= 0.6167832167832169) {
          if (q_roads_d <= 3.5000000000000004) {
            if (dice <= 0.6079192546583853) {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                -0.020394855027121978
              } else {
                -0.003081848483802882
              }
            } else {
              if (road_b <= 0.8750000000000001) {
                -0.03811753420332626
              } else {
                -0.16399202060260207
              }
            }
          } else {
            if (c_feats_d <= 1.0000000180025095e-35) {
              -0.20903804314879904
            } else {
              0.49508339641329024
            }
          }
        } else {
          if (dice <= 0.6262254901960785) {
            0.1180127814507457
          } else {
            0.009639935370298036
          }
        }
      } else {
        if (c_feats_d <= 1.5000000000000002) {
          if (q_roads_d <= 2.5000000000000004) {
            if (dice <= 0.3036890645586298) {
              if (q_feats_d <= 2.5000000000000004) {
                0.0357542621979888
              } else {
                -0.20391841343907383
              }
            } else {
              if (dice <= 0.38956639566395673) {
                -0.03831683304218699
              } else {
                0.002630022626390875
              }
            }
          } else {
            0.16873232523118023
          }
        } else {
          if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
            if (dice <= 0.20761494252873566) {
              0.17585946830760615
            } else {
              if (q_roads_d <= 1.0000000180025095e-35) {
                0.04178895950103094
              } else {
                -0.0064083763255897925
              }
            }
          } else {
            if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
              if (dice <= 0.3594871794871795) {
                0.152138434916613
              } else {
                -0.02916513653831074
              }
            } else {
              0.30718600731821194
            }
          }
        }
      }
    } else {
      if (dice <= 0.09639953542392568) {
        -0.05692322794775066
      } else {
        if (dice <= 0.1085995085995086) {
          if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
            if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
              if (to_dbl(q_structured) <= 1.0000000180025095e-35) {
                -0.04087081890669008
              } else {
                0.4965030698006242
              }
            } else {
              -0.0830162336845281
            }
          } else {
            0.7486985370042595
          }
        } else {
          if (q_roads_d <= 1.0000000180025095e-35) {
            if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
              0.0476377200845537
            } else {
              if (q_feats_d <= 1.5000000000000002) {
                0.010230793454752573
              } else {
                -0.13633517641238616
              }
            }
          } else {
            if (dice <= 0.3796653796653797) {
              if (house <= 0.4166666666666667) {
                -0.023447339414145254
              } else {
                0.03005118999983781
              }
            } else {
              if (dice <= 0.5683229813664598) {
                0.044136301997648786
              } else {
                -0.010683074846421649
              }
            }
          }
        }
      }
    }
  )

  // LGBM tree 52 (estim 17, class 1)
  s1 += (
    if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
      if (c_feats_d <= 3.5000000000000004) {
        if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
          if (c_feats_d <= 1.5000000000000002) {
            if (dice <= 0.3594871794871795) {
              if (q_feats_d <= 2.5000000000000004) {
                -0.0016912112591868239
              } else {
                0.05433529650808049
              }
            } else {
              if (dice <= 0.365491651205937) {
                -0.06655480577766881
              } else {
                -0.011434370303710388
              }
            }
          } else {
            if (dice <= 0.3207142857142858) {
              if (dice <= 0.3118055555555556) {
                0.0015064858830816797
              } else {
                -0.08884877354170224
              }
            } else {
              if (road_b <= 0.22500000000000003) {
                0.05646672733463548
              } else {
                0.003476995430628427
              }
            }
          }
        } else {
          if (c_roads_d <= 1.0000000180025095e-35) {
            if (c_feats_d <= 1.0000000180025095e-35) {
              if (dice <= 0.1085995085995086) {
                -0.07237779754395729
              } else {
                0.09205154406078303
              }
            } else {
              if (q_feats_d <= 1.0000000180025095e-35) {
                -0.036555310952724414
              } else {
                0.02205019185005439
              }
            }
          } else {
            if (c_feats_d <= 1.5000000000000002) {
              if (q_feats_d <= 2.5000000000000004) {
                0.004647274866123109
              } else {
                -0.04877785552673067
              }
            } else {
              if (house <= 0.4166666666666667) {
                -0.03258573188395156
              } else {
                0.010124466330584374
              }
            }
          }
        }
      } else {
        if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
          -0.0677974218119043
        } else {
          0.024722246658055645
        }
      }
    } else {
      if (c_feats_d <= 2.5000000000000004) {
        if (dice <= 0.04396135265700484) {
          0.08589105237964297
        } else {
          if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
            if (house <= 0.8333333333333334) {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                -0.03526162568454009
              } else {
                0.02019279913177974
              }
            } else {
              if (q_feats_d <= 1.0000000180025095e-35) {
                -0.018542872298994467
              } else {
                0.0842218906003429
              }
            }
          } else {
            if (c_roads_d <= 1.0000000180025095e-35) {
              if (c_feats_d <= 1.5000000000000002) {
                -0.047562661340607
              } else {
                0.07921528261024448
              }
            } else {
              if (q_roads_d <= 1.0000000180025095e-35) {
                0.1286736946395503
              } else {
                0.016394441397619027
              }
            }
          }
        }
      } else {
        if (dice <= 0.31311274509803927) {
          if (c_roads_d <= 1.0000000180025095e-35) {
            0.22236045359578754
          } else {
            0.06075837903072869
          }
        } else {
          if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
            -0.06421680439200994
          } else {
            0.11496657367308288
          }
        }
      }
    }
  )

  // LGBM tree 53 (estim 17, class 2)
  s2 += (
    if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
      if (c_feats_d <= 1.5000000000000002) {
        0.005895550222379711
      } else {
        if (dice <= 0.3207142857142858) {
          if (dice <= 0.3118055555555556) {
            -0.005455883226861805
          } else {
            0.11013131547280929
          }
        } else {
          if (road_b <= 0.22500000000000003) {
            if (feature <= 0.22500000000000003) {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                -0.2224259517659186
              } else {
                -0.0622690291046716
              }
            } else {
              if (feature <= 0.5500000000000002) {
                0.01794046236194942
              } else {
                -0.06312897171550978
              }
            }
          } else {
            if (c_roads_d <= 1.5000000000000002) {
              -0.018283283602320656
            } else {
              0.10170485702301386
            }
          }
        }
      }
    } else {
      if (c_roads_d <= 1.0000000180025095e-35) {
        if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
          if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
            if (dice <= 0.5227743271221533) {
              if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
                -0.018186094395325526
              } else {
                0.03224105438838536
              }
            } else {
              -0.09248212734306714
            }
          } else {
            if (c_feats_d <= 1.5000000000000002) {
              if (dice <= 0.09639953542392568) {
                -0.09647502523417721
              } else {
                0.05325162183968819
              }
            } else {
              if (q_roads_d <= 1.5000000000000002) {
                -0.02282065749897878
              } else {
                -0.20373537713999643
              }
            }
          }
        } else {
          if (q_feats_d <= 2.5000000000000004) {
            if (dice <= 0.35424836601307197) {
              if (c_feats_d <= 1.0000000180025095e-35) {
                -0.07407255299550558
              } else {
                0.00834583709535254
              }
            } else {
              -0.09540050339222504
            }
          } else {
            -0.19281809216289458
          }
        }
      } else {
        if (road_b <= 0.22500000000000003) {
          if (q_feats_d <= 1.5000000000000002) {
            if (q_roads_d <= 2.5000000000000004) {
              if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
                0.003028597181434195
              } else {
                -0.04991366592171146
              }
            } else {
              if (dice <= 0.24316334072431636) {
                0.18400874684590968
              } else {
                -0.022684201785524234
              }
            }
          } else {
            if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
              if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
                0.09113561060998288
              } else {
                0.010330131080370248
              }
            } else {
              0.0013409642731276685
            }
          }
        } else {
          if (road_b <= 0.5500000000000002) {
            if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
              if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
                -0.024544204947208242
              } else {
                0.08514574610384133
              }
            } else {
              -0.08885256928184694
            }
          } else {
            -0.00362282444652822
          }
        }
      }
    }
  )

  // LGBM tree 54 (estim 18, class 0)
  s0 += (
    if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
      if (to_dbl(veto) <= 1.0000000180025095e-35) {
        if (c_feats_d <= 4.500000000000001) {
          if (name <= 0.5833333333333334) {
            if (c_roads_d <= 2.5000000000000004) {
              if (feature <= 0.7083333333333334) {
                -0.0030106873615578056
              } else {
                0.006886669448313925
              }
            } else {
              if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
                0.06152605916426133
              } else {
                -0.010864289172428694
              }
            }
          } else {
            if (to_dbl(foreign_city) <= 1.0000000180025095e-35) {
              if (dice <= 0.16784037558685447) {
                0.10478195429553766
              } else {
                0.008201641508787265
              }
            } else {
              if (c_feats_d <= 1.0000000180025095e-35) {
                -0.0016769955023088732
              } else {
                0.12574626224908536
              }
            }
          }
        } else {
          0.1294492737287961
        }
      } else {
        if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
          if (dice <= 0.07767722473604828) {
            -0.16699837758142244
          } else {
            if (q_feats_d <= 1.0000000180025095e-35) {
              if (name <= 0.5833333333333334) {
                -0.022735447395758526
              } else {
                -0.22344180402786729
              }
            } else {
              if (q_roads_d <= 1.0000000180025095e-35) {
                0.061459828884782776
              } else {
                -0.033598978498255
              }
            }
          }
        } else {
          if (dice <= 0.31311274509803927) {
            if (house <= 0.8333333333333334) {
              -0.15635346340778825
            } else {
              -0.028258842232130113
            }
          } else {
            0.1473427115921847
          }
        }
      }
    } else {
      if (dice <= 0.09639953542392568) {
        if (c_roads_d <= 1.0000000180025095e-35) {
          if (dice <= 0.07207792207792209) {
            -0.20130144918868
          } else {
            0.31362695623455294
          }
        } else {
          -0.17104840711313593
        }
      } else {
        if (q_feats_d <= 1.0000000180025095e-35) {
          if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
            if (dice <= 0.15894736842105264) {
              -0.20211379792795456
            } else {
              if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
                -0.008888838684650449
              } else {
                -0.11765363658361877
              }
            }
          } else {
            -0.13914806661387794
          }
        } else {
          if (dice <= 0.12632978723404256) {
            if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
              0.7444142380317682
            } else {
              if (dice <= 0.11882352941176472) {
                -0.20289194339915514
              } else {
                0.46222457455189025
              }
            }
          } else {
            if (dice <= 0.18808962264150947) {
              if (c_feats_d <= 1.5000000000000002) {
                -0.03349239804790563
              } else {
                -0.21017533041310052
              }
            } else {
              if (dice <= 0.26201372997711675) {
                0.07920481298216411
              } else {
                -0.007591174718092217
              }
            }
          }
        }
      }
    }
  )

  // LGBM tree 55 (estim 18, class 1)
  s1 += (
    if (q_feats_d <= 1.0000000180025095e-35) {
      if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
        0.005098204032329123
      } else {
        -0.007781822583925942
      }
    } else {
      if (dice <= 0.4248871695680207) {
        if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
          if (dice <= 0.37617924528301894) {
            if (c_roads_d <= 1.0000000180025095e-35) {
              if (q_roads_d <= 1.0000000180025095e-35) {
                -0.013138712018123574
              } else {
                0.02892086502758387
              }
            } else {
              if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
                -0.00755147262967565
              } else {
                -0.0863551383314311
              }
            }
          } else {
            if (dice <= 0.38529014844804327) {
              if (road_b <= 0.8750000000000001) {
                0.16269835044312334
              } else {
                -0.015496694767408541
              }
            } else {
              if (feature <= 0.8750000000000001) {
                -0.0007976821054282783
              } else {
                0.077687365961826
              }
            }
          }
        } else {
          if (road_b <= 0.22500000000000003) {
            if (dice <= 0.20601237842617157) {
              if (q_feats_d <= 2.5000000000000004) {
                0.04235132461538437
              } else {
                -0.05868075229805329
              }
            } else {
              if (q_feats_d <= 2.5000000000000004) {
                -0.005360096024637007
              } else {
                0.04496424484132576
              }
            }
          } else {
            if (c_feats_d <= 1.5000000000000002) {
              if (q_feats_d <= 1.5000000000000002) {
                0.05203034279148212
              } else {
                0.10401172409408763
              }
            } else {
              if (road_b <= 0.5500000000000002) {
                0.06513736414935689
              } else {
                -0.019740486981841446
              }
            }
          }
        }
      } else {
        if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
          if (name <= 0.5833333333333334) {
            if (q_roads_d <= 1.0000000180025095e-35) {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                -0.008846569305836598
              } else {
                0.02415824389024252
              }
            } else {
              if (c_roads_d <= 1.0000000180025095e-35) {
                -0.03963993053398441
              } else {
                -0.004352862541096029
              }
            }
          } else {
            if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
              if (to_dbl(context_ok) <= 1.0000000180025095e-35) {
                -0.06413438694460347
              } else {
                0.008551191740720332
              }
            } else {
              -0.13742211731330922
            }
          }
        } else {
          if (q_roads_d <= 1.0000000180025095e-35) {
            if (feature <= 0.2916666666666667) {
              -0.1763376366599047
            } else {
              if (dice <= 0.5472370766488415) {
                -0.01786621696415859
              } else {
                -0.13706483445532086
              }
            }
          } else {
            if (house <= 1.0000000180025095e-35) {
              if (dice <= 0.7161172161172162) {
                -0.02099134409730283
              } else {
                -0.09764651732902875
              }
            } else {
              0.053554684977420206
            }
          }
        }
      }
    }
  )

  // LGBM tree 56 (estim 18, class 2)
  s2 += (
    if (q_feats_d <= 1.0000000180025095e-35) {
      if (c_feats_d <= 1.0000000180025095e-35) {
        if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
          if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
            if (name <= 0.4166666666666667) {
              if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
                0.008453768322839927
              } else {
                -0.11331719443911113
              }
            } else {
              if (dice <= 0.2636544190665343) {
                -0.14639475937925456
              } else {
                -0.009649801113220799
              }
            }
          } else {
            if (c_roads_d <= 1.5000000000000002) {
              0.016638787612678334
            } else {
              if (dice <= 0.31311274509803927) {
                0.20704351797623735
              } else {
                0.0559977945934531
              }
            }
          }
        } else {
          if (q_roads_d <= 1.0000000180025095e-35) {
            if (dice <= 0.16271373414230558) {
              -0.2142250242783412
            } else {
              if (dice <= 0.3207142857142858) {
                0.09069110634333828
              } else {
                0.010351050094845745
              }
            }
          } else {
            if (dice <= 0.25866188769414583) {
              0.0362500593456688
            } else {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                -0.04550213934817826
              } else {
                0.07413856111076597
              }
            }
          }
        }
      } else {
        if (q_roads_d <= 1.0000000180025095e-35) {
          if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
            if (dice <= 0.12632978723404256) {
              if (to_dbl(house_missing) <= 1.0000000180025095e-35) {
                -0.04002169771311687
              } else {
                -0.23003314967089206
              }
            } else {
              if (c_feats_d <= 2.5000000000000004) {
                -0.003085516195785651
              } else {
                -0.18550169949460518
              }
            }
          } else {
            -0.07137013983530309
          }
        } else {
          if (dice <= 0.08759590792838877) {
            0.040720450027456945
          } else {
            if (c_roads_d <= 1.0000000180025095e-35) {
              if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
                0.013909291257856032
              } else {
                0.17890103306564986
              }
            } else {
              if (dice <= 0.1913919413919414) {
                -0.035364517489062594
              } else {
                -0.007042618425703732
              }
            }
          }
        }
      }
    } else {
      if (dice <= 0.04396135265700484) {
        if (q_feats_d <= 1.5000000000000002) {
          if (c_feats_d <= 1.0000000180025095e-35) {
            0.06457650041534602
          } else {
            -0.0200183198839822
          }
        } else {
          0.12381493459897577
        }
      } else {
        if (dice <= 0.09918032786885247) {
          if (c_roads_d <= 2.5000000000000004) {
            -0.027085424380858838
          } else {
            0.13256129240525186
          }
        } else {
          if (dice <= 0.10620300751879701) {
            if (house <= 0.8333333333333334) {
              0.08426790291424525
            } else {
              -0.17860878138948752
            }
          } else {
            0.0012883057886593835
          }
        }
      }
    }
  )

  // LGBM tree 57 (estim 19, class 0)
  s0 += (
    if (house <= 1.0000000180025095e-35) {
      if (to_dbl(house_conflict) <= 1.0000000180025095e-35) {
        if (q_roads_d <= 3.5000000000000004) {
          -0.0004685249268467088
        } else {
          if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
            0.20717772500322873
          } else {
            -0.11465392159411622
          }
        }
      } else {
        if (dice <= 0.19433516915814322) {
          if (c_feats_d <= 1.5000000000000002) {
            if (c_roads_d <= 1.0000000180025095e-35) {
              if (dice <= 0.1719211822660099) {
                0.37175824514576394
              } else {
                -0.2268983639495136
              }
            } else {
              -0.08127883422445732
            }
          } else {
            -0.20575200474442054
          }
        } else {
          if (q_feats_d <= 1.0000000180025095e-35) {
            if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
              if (dice <= 0.5843495934959351) {
                -0.05788069960985164
              } else {
                -0.22397538965972397
              }
            } else {
              if (road_b <= 0.5500000000000002) {
                -0.05049889756661307
              } else {
                0.2748008288698857
              }
            }
          } else {
            if (dice <= 0.5843495934959351) {
              if (dice <= 0.26201372997711675) {
                0.06820154300213346
              } else {
                -0.03038136541938731
              }
            } else {
              if (dice <= 0.6414285714285716) {
                0.12499102170879857
              } else {
                0.008387034801683738
              }
            }
          }
        }
      }
    } else {
      if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
        if (q_feats_d <= 1.5000000000000002) {
          if (c_roads_d <= 1.5000000000000002) {
            if (dice <= 0.49561403508771934) {
              if (q_roads_d <= 1.0000000180025095e-35) {
                0.04170916494532618
              } else {
                -0.016828541323680248
              }
            } else {
              if (dice <= 0.6902821316614421) {
                0.04597924467784339
              } else {
                -0.010870320084009495
              }
            }
          } else {
            if (to_dbl(town_hit) <= 1.0000000180025095e-35) {
              if (dice <= 0.560701754385965) {
                0.05910589724056562
              } else {
                -0.010947483935393059
              }
            } else {
              -0.08786732716294372
            }
          }
        } else {
          -0.02106470991481412
        }
      } else {
        if (c_roads_d <= 1.0000000180025095e-35) {
          if (feature <= 0.45000000000000007) {
            if (q_feats_d <= 1.0000000180025095e-35) {
              if (dice <= 0.36939571150097467) {
                0.00550292069407549
              } else {
                0.2325397874328084
              }
            } else {
              -0.08593456899134749
            }
          } else {
            0.21922875810553186
          }
        } else {
          if (dice <= 0.9905660377358492) {
            if (dice <= 0.81557067271353) {
              if (dice <= 0.6966632962588474) {
                0.006435772062424225
              } else {
                0.12930346218980657
              }
            } else {
              -0.058533264991161287
            }
          } else {
            0.1466732946364627
          }
        }
      }
    }
  )

  // LGBM tree 58 (estim 19, class 1)
  s1 += (
    if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
      if (c_feats_d <= 2.5000000000000004) {
        if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
          -0.0017175811137729005
        } else {
          if (c_roads_d <= 1.0000000180025095e-35) {
            if (c_feats_d <= 1.0000000180025095e-35) {
              if (q_feats_d <= 1.5000000000000002) {
                0.04015783503025127
              } else {
                0.16905232290358965
              }
            } else {
              if (q_feats_d <= 1.0000000180025095e-35) {
                -0.034809276887640746
              } else {
                0.01629955880889904
              }
            }
          } else {
            0.0006360810649256719
          }
        }
      } else {
        if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
          if (dice <= 0.14160401002506268) {
            -0.12084796724834777
          } else {
            if (dice <= 0.6434624697336563) {
              0.04510827199670744
            } else {
              -0.0667843834761242
            }
          }
        } else {
          if (house <= 0.8333333333333334) {
            if (dice <= 0.686607142857143) {
              if (dice <= 0.2343137254901961) {
                -0.009469919292931363
              } else {
                -0.07491512994195673
              }
            } else {
              0.07899011371749307
            }
          } else {
            if (to_dbl(feat_overlap) <= 1.0000000180025095e-35) {
              0.0690698535565058
            } else {
              -0.044108208810971834
            }
          }
        }
      }
    } else {
      if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
        if (house <= 0.8333333333333334) {
          if (dice <= 0.04396135265700484) {
            0.05093802421438053
          } else {
            if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
              -0.028206469444067697
            } else {
              if (dice <= 0.3454907161803714) {
                -0.04397064018741195
              } else {
                0.05979936412286168
              }
            }
          }
        } else {
          if (q_feats_d <= 1.0000000180025095e-35) {
            if (dice <= 0.44222222222222224) {
              if (to_dbl(road_conflict) <= 1.0000000180025095e-35) {
                0.05632584221577181
              } else {
                -0.05168734062276483
              }
            } else {
              -0.12615109247894607
            }
          } else {
            0.08075976942838312
          }
        }
      } else {
        if (c_roads_d <= 1.0000000180025095e-35) {
          if (c_feats_d <= 1.5000000000000002) {
            if (dice <= 0.5300120048019209) {
              -0.05619371051264297
            } else {
              0.03180589273063595
            }
          } else {
            if (dice <= 0.41277890466531447) {
              0.14947432234195016
            } else {
              -0.005895913656441339
            }
          }
        } else {
          if (to_dbl(fuzzy_poi_overlap) <= 1.0000000180025095e-35) {
            if (dice <= 0.4220647773279353) {
              0.03458562764938418
            } else {
              0.18050652185573127
            }
          } else {
            if (q_roads_d <= 1.0000000180025095e-35) {
              0.11708037338506384
            } else {
              if (dice <= 0.6018867924528303) {
                -0.09616237633550967
              } else {
                0.02230999866588373
              }
            }
          }
        }
      }
    }
  )

  // LGBM tree 59 (estim 19, class 2)
  s2 += (
    if (feature <= 0.8750000000000001) {
      if (q_feats_d <= 1.0000000180025095e-35) {
        -0.0025662399149076484
      } else {
        if (c_feats_d <= 1.0000000180025095e-35) {
          if (dice <= 1.0000000180025095e-35) {
            0.07716048344588809
          } else {
            if (to_dbl(admin_hit) <= 1.0000000180025095e-35) {
              if (house <= 0.4166666666666667) {
                -0.024843302715567082
              } else {
                0.025972174220149025
              }
            } else {
              if (to_dbl(c_structured) <= 1.0000000180025095e-35) {
                0.03994914426518038
              } else {
                -0.076896538805618
              }
            }
          }
        } else {
          if (q_roads_d <= 1.5000000000000002) {
            0.009884735219940094
          } else {
            if (dice <= 0.34216027874564464) {
              if (dice <= 0.09413067552602437) {
                -0.07461645634964333
              } else {
                0.015286729194113082
              }
            } else {
              if (q_feats_d <= 2.5000000000000004) {
                -0.06317797567760555
              } else {
                0.1268277840213037
              }
            }
          }
        }
      }
    } else {
      if (q_feats_d <= 1.5000000000000002) {
        if (q_roads_d <= 1.0000000180025095e-35) {
          if (c_roads_d <= 1.5000000000000002) {
            if (c_feats_d <= 2.5000000000000004) {
              if (dice <= 0.3504385964912281) {
                0.005555884560646673
              } else {
                -0.02080087967316888
              }
            } else {
              0.07749114905728567
            }
          } else {
            if (dice <= 0.15504807692307696) {
              -0.1372871692831261
            } else {
              -0.04040529618195676
            }
          }
        } else {
          if (dice <= 0.27842377260981915) {
            if (q_roads_d <= 2.5000000000000004) {
              if (road_b <= 0.45000000000000007) {
                -0.011725219265262493
              } else {
                -0.10596670073238017
              }
            } else {
              0.16418799478535592
            }
          } else {
            if (to_dbl(main_hit) <= 1.0000000180025095e-35) {
              if (dice <= 0.8248081841432225) {
                0.017065513897696057
              } else {
                -0.07086527603218162
              }
            } else {
              if (dice <= 0.40370370370370373) {
                0.026078943037934118
              } else {
                0.1400384811682546
              }
            }
          }
        }
      } else {
        if (dice <= 0.6930926216640504) {
          if (q_feats_d <= 2.5000000000000004) {
            if (dice <= 0.3925070028011205) {
              if (to_dbl(reverse_poi_overlap) <= 1.0000000180025095e-35) {
                -0.08473317101023801
              } else {
                -0.18286065502562904
              }
            } else {
              if (c_roads_d <= 1.5000000000000002) {
                -0.058799780378295745
              } else {
                0.13460824812577535
              }
            }
          } else {
            -0.2290700289427959
          }
        } else {
          if (c_feats_d <= 2.5000000000000004) {
            if (dice <= 0.8765243902439025) {
              0.11681740840344995
            } else {
              -0.035267478024315804
            }
          } else {
            -0.0936945586365488
          }
        }
      }
    }
  )

  let final_level = if s0 >= s1 && s0 >= s2 {
    Exact
  } else if s1 >= s2 {
    Partial
  } else {
    None
  }
  final_level
}
