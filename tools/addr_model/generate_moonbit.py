"""从训练好的 LightGBM 模型生成 MoonBit match_by_ensemble 函数。"""
import json

# 加载树结构
with open("/tmp/addr_trees.json") as f:
    data = json.load(f)

feature_names = data["feature_names"]
trees = data["trees"]

# 特征名到参数名的映射
param_names = [
    "dice", "road_b", "feature", "name",
    "admin_hit", "road_hit", "town_hit", "context_ok",
    "house", "house_conflict", "veto",
    "q_struct", "c_struct", "feat_overlap",
    "weak_core_exact", "fuzzy_poi_overlap", "reverse_poi_overlap",
    "road_conflict", "main_hit", "house_missing", "foreign_city",
    "q_roads_d", "c_roads_d", "q_feats_d", "c_feats_d",
    "score",
    # 新特征
    "edit_dist_norm", "jw_sim", "jaccard_tok", "lcs_ratio", "tok_overlap",
    "dice_house_recall", "dice_feat", "dice_road_b", "dice_name",
    "house_recall_feat", "house_recall_road_b", "feat_road_b",
    "dice_admin_hit", "dice_road_hit", "dice_town_hit",
    "house_recall_context_ok", "edit_dist_norm_dice", "jw_sim_dice",
    "jaccard_tok_dice",
]

# 简化的参数名（用于代码生成）
short_names = {
    "dice": "dice",
    "road_b": "road_b",
    "feat": "feat",
    "name": "name",
    "admin_hit": "admin_hit",
    "road_hit": "road_hit",
    "town_hit": "town_hit",
    "context_ok": "context_ok",
    "house_recall": "house",
    "house_conflict": "house_conflict",
    "veto": "veto",
    "q_struct": "q_structured",
    "c_struct": "c_structured",
    "feat_overlap": "feat_overlap",
    "weak_core": "weak_core_exact",
    "fuzzy_poi": "fuzzy_poi_overlap",
    "reverse_poi": "reverse_poi_overlap",
    "road_conflict": "road_conflict",
    "main_hit": "main_hit",
    "house_missing": "house_missing",
    "foreign_city": "foreign_city",
    "q_roads": "q_roads_d",
    "c_roads": "c_roads_d",
    "q_feats": "q_feats_d",
    "c_feats": "c_feats_d",
    "score": "score",
    "edit_dist_norm": "edit_dist_norm",
    "jw_sim": "jw_sim",
    "jaccard_tok": "jaccard_tok",
    "lcs_ratio": "lcs_ratio",
    "tok_overlap": "tok_overlap",
    "dice*house_recall": "dice_house_recall",
    "dice*feat": "dice_feat",
    "dice*road_b": "dice_road_b",
    "dice*name": "dice_name",
    "house_recall*feat": "house_recall_feat",
    "house_recall*road_b": "house_recall_road_b",
    "feat*road_b": "feat_road_b",
    "dice*admin_hit": "dice_admin_hit",
    "dice*road_hit": "dice_road_hit",
    "dice*town_hit": "dice_town_hit",
    "house_recall*context_ok": "house_recall_context_ok",
    "edit_dist_norm*dice": "edit_dist_norm_dice",
    "jw_sim*dice": "jw_sim_dice",
    "jaccard_tok*dice": "jaccard_tok_dice",
}

def get_param_name(feat_idx):
    """获取特征索引对应的参数名。"""
    feat_name = feature_names[feat_idx]
    return short_names.get(feat_name, feat_name)

def generate_tree_code(tree, class_idx):
    """生成单棵树的代码。"""
    def gen_node(node, depth=0):
        indent = "  " * depth
        if "leaf_index" in node:
            return f"{node['leaf_value']}"
        
        feat_idx = node["split_feature"]
        threshold = node["threshold"]
        param_name = get_param_name(feat_idx)
        
        # 处理布尔特征
        if param_name in ["admin_hit", "road_hit", "town_hit", "context_ok",
                          "house_conflict", "veto", "q_structured", "c_structured",
                          "feat_overlap", "weak_core_exact", "fuzzy_poi_overlap",
                          "reverse_poi_overlap", "road_conflict", "main_hit",
                          "house_missing", "foreign_city"]:
            condition = f"to_dbl({param_name}) <= 1.0000000180025095e-35"
        else:
            condition = f"({param_name} <= {threshold})"
        
        left = gen_node(node["left_child"], depth + 1)
        right = gen_node(node["right_child"], depth + 1)
        
        return f"if ({condition}) {{\n{indent}  {left}\n{indent}}} else {{\n{indent}  {right}\n{indent}}}"
    
    return gen_node(tree["tree_structure"])

# 生成函数代码
lines = []
lines.append("pub fn match_by_ensemble(")
lines.append("  dice: Double, road_b: Double, feat: Double, name: Double,")
lines.append("  admin_hit: Bool, road_hit: Bool, town_hit: Bool, context_ok: Bool,")
lines.append("  house: Double, house_conflict: Bool, veto: Bool,")
lines.append("  q_structured: Bool, c_structured: Bool, feat_overlap: Bool,")
lines.append("  weak_core_exact: Bool, fuzzy_poi_overlap: Bool, reverse_poi_overlap: Bool,")
lines.append("  road_conflict: Bool, main_hit: Bool, house_missing: Bool, foreign_city: Bool,")
lines.append("  q_roads_d: Double, c_roads_d: Double, q_feats_d: Double, c_feats_d: Double,")
lines.append("  score: Double,")
lines.append("  // 新特征")
lines.append("  edit_dist_norm: Double, jw_sim: Double, jaccard_tok: Double,")
lines.append("  lcs_ratio: Double, tok_overlap: Double,")
lines.append("  dice_house_recall: Double, dice_feat: Double, dice_road_b: Double, dice_name: Double,")
lines.append("  house_recall_feat: Double, house_recall_road_b: Double, feat_road_b: Double,")
lines.append("  dice_admin_hit: Double, dice_road_hit: Double, dice_town_hit: Double,")
lines.append("  house_recall_context_ok: Double, edit_dist_norm_dice: Double,")
lines.append("  jw_sim_dice: Double, jaccard_tok_dice: Double,")
lines.append(") -> MatchLevel {")
lines.append("  let mut s0 = 0.0")
lines.append("  let mut s1 = 0.0")
lines.append("  let mut s2 = 0.0")
lines.append("")

# 每 3 棵树为一组（对应一个类别）
n_classes = 3
n_estimators = len(trees) // n_classes

for class_idx in range(n_classes):
    class_name = ["Exact", "Partial", "None"][class_idx]
    lines.append(f"  // Class {class_name} ({n_estimators} trees)")

    for i in range(n_estimators):
        # LightGBM interleaves trees across classes: tree k belongs to
        # class k % 3 (verified against booster raw_margin, diff = 0).
        tree_idx = class_idx + i * n_classes
        tree = trees[tree_idx]
        lines.append(f"  // LGBM tree {tree_idx} (estim {i}, class {class_idx})")
        tree_code = generate_tree_code(tree, class_idx)
        # 缩进并添加到分数
        lines.append(f"  s{class_idx} += (")
        for line in tree_code.split("\n"):
            lines.append(f"    {line}")
        lines.append(f"  )")
        lines.append("")

# 最终决策
lines.append("  // 最终决策")
lines.append("  if (s0 >= s1 && s0 >= s2) {")
lines.append("    MatchLevel::Exact")
lines.append("  } else if (s1 >= s0 && s1 >= s2) {")
lines.append("    MatchLevel::Partial")
lines.append("  } else {")
lines.append("    MatchLevel::None")
lines.append("  }")
lines.append("}")

# 写入文件
output_path = "/tmp/match_by_ensemble.mbt"
with open(output_path, "w") as f:
    f.write("\n".join(lines))

print(f"生成了 {len(lines)} 行代码")
print(f"输出文件: {output_path}")

# 统计
tree_count = len(trees)
print(f"共 {tree_count} 棵树")
print(f"每类 {n_estimators} 棵树")