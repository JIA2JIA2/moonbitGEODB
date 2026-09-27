"""训练最终模型：模糊匹配特征 + 组合特征，导出用于 MoonBit 移植。"""
import json
import numpy as np
from sklearn.model_selection import StratifiedKFold
from Levenshtein import distance as lev_distance
from jellyfish import jaro_winkler_similarity
import lightgbm as lgb
import pickle

DATA_PATH = "/home/developer/moonbitGEODB/testdata/data.txt"
FEAT_PATH = "/tmp/feat_dump.tsv"

def jaccard_sim(a, b):
    set_a, set_b = set(a), set(b)
    if not set_a and not set_b:
        return 1.0
    return len(set_a & set_b) / len(set_a | set_b)

def lcs_len(a, b):
    m, n = len(a), len(b)
    dp = [[0] * (n + 1) for _ in range(m + 1)]
    for i in range(1, m + 1):
        for j in range(1, n + 1):
            if a[i-1] == b[j-1]:
                dp[i][j] = dp[i-1][j-1] + 1
            else:
                dp[i][j] = max(dp[i-1][j], dp[i][j-1])
    return dp[m][n]

def tokenize(text):
    import re
    return re.findall(r'[\w]+', text.lower())

def compute_all_features(query, candidate, old_features_dict):
    """计算所有新特征（模糊匹配 + 组合特征）。"""
    q_tokens = tokenize(query)
    c_tokens = tokenize(candidate)
    
    # 模糊匹配特征
    edit_dist = lev_distance(query.lower(), candidate.lower())
    max_len = max(len(query), len(candidate), 1)
    edit_dist_norm = edit_dist / max_len
    jw_sim = jaro_winkler_similarity(query.lower(), candidate.lower())
    jaccard_tok = jaccard_sim(q_tokens, c_tokens)
    lcs = lcs_len(query.lower(), candidate.lower())
    lcs_ratio = lcs / max_len
    q_set, c_set = set(q_tokens), set(c_tokens)
    tok_overlap = len(q_set & c_set) / max(len(q_set | c_set), 1)
    
    # 组合特征
    dice = old_features_dict.get("dice", 0)
    house_recall = old_features_dict.get("house_recall", 0)
    feat = old_features_dict.get("feat", 0)
    road_b = old_features_dict.get("road_b", 0)
    name = old_features_dict.get("name", 0)
    admin_hit = old_features_dict.get("admin_hit", 0)
    road_hit = old_features_dict.get("road_hit", 0)
    town_hit = old_features_dict.get("town_hit", 0)
    context_ok = old_features_dict.get("context_ok", 0)
    
    comb_features = [
        dice * house_recall,
        dice * feat,
        dice * road_b,
        dice * name,
        house_recall * feat,
        house_recall * road_b,
        feat * road_b,
        dice * admin_hit,
        dice * road_hit,
        dice * town_hit,
        house_recall * context_ok,
        edit_dist_norm * dice,
        jw_sim * dice,
        jaccard_tok * dice,
    ]
    
    return [edit_dist_norm, jw_sim, jaccard_tok, lcs_ratio, tok_overlap] + comb_features

# 加载原始文本
print("加载原始文本...")
text_pairs = []
with open(DATA_PATH) as f:
    for line in f:
        record = json.loads(line)
        query = record["query"]
        for cand in record["candidate"]:
            text = cand["text"]
            label = cand["label"]
            text_pairs.append((query, text, label))

print(f"加载了 {len(text_pairs)} 个 query-candidate 对")

# 加载现有特征
print("加载现有特征...")
with open(FEAT_PATH) as f:
    header = f.readline().rstrip("\n").split("\t")
feat_cols = [c for c in header if c != "gold"]
data = np.loadtxt(FEAT_PATH, delimiter="\t", skiprows=1)
X_old = data[:, :-1].astype(np.float64)
y = data[:, -1].astype(int)

# 创建特征字典
old_features_dict = {}
for i, col in enumerate(feat_cols):
    old_features_dict[col] = X_old[:, i]

# 计算新特征
print("计算新特征...")
new_features = []
for i, (q, c, label) in enumerate(text_pairs):
    if i % 10000 == 0:
        print(f"  处理 {i}/{len(text_pairs)}")
    feats = compute_all_features(q, c, {col: old_features_dict[col][i] for col in feat_cols})
    new_features.append(feats)

X_new = np.array(new_features)
print(f"新特征形状: {X_new.shape}")

# 合并特征
X_combined = np.hstack([X_old, X_new])
print(f"合并后特征形状: {X_combined.shape}")

# 5-fold CV
params = dict(
    n_estimators=200,
    num_leaves=31,
    max_depth=-1,
    learning_rate=0.05,
    random_state=42,
    verbose=-1,
)

skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
folds = list(skf.split(X_combined, y))

oof = np.zeros(len(y), dtype=int)
for fold, (tr, te) in enumerate(folds):
    clf = lgb.LGBMClassifier(**params)
    clf.fit(X_combined[tr], y[tr])
    oof[te] = clf.predict(X_combined[te])
    acc = (oof[te] == y[te]).mean()
    print(f"fold {fold}: {acc:.6f}")

oof_acc = (oof == y).mean()
print(f"\nOOF Agreement (with all new features): {oof_acc:.6f}")

# 全量训练
print("\n全量训练...")
clf_all = lgb.LGBMClassifier(**params)
clf_all.fit(X_combined, y)
pred_all = clf_all.predict(X_combined)
full_acc = (pred_all == y).mean()
print(f"Full Agreement: {full_acc:.6f}")

# 导出模型
print("\n导出模型...")
model_data = {
    "feature_names": feat_cols + [
        "edit_dist_norm", "jw_sim", "jaccard_tok", "lcs_ratio", "tok_overlap",
        "dice*house_recall", "dice*feat", "dice*road_b", "dice*name",
        "house_recall*feat", "house_recall*road_b", "feat*road_b",
        "dice*admin_hit", "dice*road_hit", "dice*town_hit",
        "house_recall*context_ok", "edit_dist_norm*dice", "jw_sim*dice",
        "jaccard_tok*dice",
    ],
    "params": params,
    "model": clf_all,
}

with open("/tmp/addr_model_final.pkl", "wb") as f:
    pickle.dump(model_data, f)

print("模型已导出到 /tmp/addr_model_final.pkl")

# 导出决策树用于 MoonBit 移植
print("\n导出决策树...")
trees = clf_all.booster_.dump_model()["tree_info"]
print(f"共 {len(trees)} 棵树")

# 保存树结构
tree_data = {
    "n_estimators": len(trees),
    "trees": trees,
    "feature_names": feat_cols + [
        "edit_dist_norm", "jw_sim", "jaccard_tok", "lcs_ratio", "tok_overlap",
        "dice*house_recall", "dice*feat", "dice*road_b", "dice*name",
        "house_recall*feat", "house_recall*road_b", "feat*road_b",
        "dice*admin_hit", "dice*road_hit", "dice*town_hit",
        "house_recall*context_ok", "edit_dist_norm*dice", "jw_sim*dice",
        "jaccard_tok*dice",
    ],
}

with open("/tmp/addr_trees.json", "w") as f:
    import json
    json.dump(tree_data, f, indent=2)

print("决策树已导出到 /tmp/addr_trees.json")