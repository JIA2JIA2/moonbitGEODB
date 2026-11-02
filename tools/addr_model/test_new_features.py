"""测试新特征：编辑距离、Jaccard、LCS 等模糊匹配特征。"""
import json
import numpy as np
from sklearn.model_selection import StratifiedKFold
from Levenshtein import distance as lev_distance
from jellyfish import jaro_winkler_similarity

def jaccard_sim(a, b):
    set_a, set_b = set(a), set(b)
    if not set_a and not set_b:
        return 1.0
    return len(set_a & set_b) / len(set_a | set_b)

def lcs_len(a, b):
    """计算最长公共子序列长度。"""
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
    """简单分词：按空格和标点分割。"""
    import re
    return re.findall(r'[\w]+', text.lower())

def compute_fuzzy_features(query, candidate):
    """计算模糊匹配特征。"""
    q_tokens = tokenize(query)
    c_tokens = tokenize(candidate)
    
    # 编辑距离（字符级）
    edit_dist = lev_distance(query.lower(), candidate.lower())
    max_len = max(len(query), len(candidate), 1)
    edit_dist_norm = edit_dist / max_len
    
    # Jaro-Winkler 相似度
    jw_sim = jaro_winkler_similarity(query.lower(), candidate.lower())
    
    # Jaccard 相似度（token 级）
    jaccard_tok = jaccard_sim(q_tokens, c_tokens)
    
    # LCS 长度和比率
    lcs = lcs_len(query.lower(), candidate.lower())
    lcs_ratio = lcs / max_len
    
    # Token 级编辑距离
    q_set, c_set = set(q_tokens), set(c_tokens)
    tok_edit = lev_distance(' '.join(sorted(q_tokens)), ' '.join(sorted(c_tokens)))
    tok_edit_norm = tok_edit / max(len(q_tokens), len(c_tokens), 1)
    
    # Token 重叠率
    tok_overlap = len(q_set & c_set) / max(len(q_set | c_set), 1)
    
    return [
        edit_dist_norm,
        jw_sim,
        jaccard_tok,
        lcs_ratio,
        tok_edit_norm,
        tok_overlap,
    ]

# 加载数据
DATA_PATH = "/home/developer/moonbitGEODB/testdata/data.txt"
FEAT_PATH = "/tmp/feat_dump.tsv"

# 加载原始文本
print("加载原始文本...")
text_pairs = []  # (query, candidate, label)
with open(DATA_PATH) as f:
    for line in f:
        record = json.loads(line)
        text_id = record["text_id"]
        query = record["query"]
        for cand in record["candidate"]:
            text = cand["text"]
            label = cand["label"]
            text_pairs.append((query, text, label))

print(f"加载了 {len(text_pairs)} 个 query-candidate 对")

# 加载现有特征
print("加载现有特征...")
data = np.loadtxt(FEAT_PATH, delimiter="\t", skiprows=1)
X_old = data[:, :-1].astype(np.float64)
y = data[:, -1].astype(int)

# 计算新特征（只计算前 N 个以节省时间）
N = min(20000, len(text_pairs))  # 限制数量
print(f"计算前 {N} 个样本的新特征...")

new_features = []
for i, (q, c, label) in enumerate(text_pairs[:N]):
    if i % 1000 == 0:
        print(f"  处理 {i}/{N}")
    feats = compute_fuzzy_features(q, c)
    new_features.append(feats)

X_new = np.array(new_features)
print(f"新特征形状: {X_new.shape}")

# 合并特征
X_combined = np.hstack([X_old[:N], X_new])
y_subset = y[:N]

print(f"合并后特征形状: {X_combined.shape}")
print(f"标签分布: {np.bincount(y_subset)}")

# 训练模型
import lightgbm as lgb

params = dict(
    n_estimators=200,
    num_leaves=31,
    max_depth=-1,
    learning_rate=0.05,
    random_state=42,
    verbose=-1,
)

skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
folds = list(skf.split(X_combined, y_subset))

oof = np.zeros(len(y_subset), dtype=int)
for fold, (tr, te) in enumerate(folds):
    clf = lgb.LGBMClassifier(**params)
    clf.fit(X_combined[tr], y_subset[tr])
    oof[te] = clf.predict(X_combined[te])
    acc = (oof[te] == y_subset[te]).mean()
    print(f"fold {fold}: {acc:.6f}")

oof_acc = (oof == y_subset).mean()
print(f"\nOOF Agreement (with new features): {oof_acc:.6f}")

# 对比：只用旧特征
print("\n--- 对比：只用旧特征 ---")
oof_old = np.zeros(len(y_subset), dtype=int)
for fold, (tr, te) in enumerate(folds):
    clf = lgb.LGBMClassifier(**params)
    clf.fit(X_old[:N][tr], y_subset[tr])
    oof_old[te] = clf.predict(X_old[:N][te])
oof_old_acc = (oof_old == y_subset).mean()
print(f"OOF Agreement (old features only): {oof_old_acc:.6f}")
print(f"Improvement: {oof_acc - oof_old_acc:.6f}")