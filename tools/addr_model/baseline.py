"""基线验证：用导出的 26 维特征训练 LightGBM，复现当前 Agreement 75.902%。

标签编码：0=完全匹配(Exact), 1=部分匹配(Partial), 2=不匹配(None)
Agreement = 准确率 (预测 == gold)
"""
import numpy as np
import lightgbm as lgb
from sklearn.model_selection import StratifiedKFold

FEAT_PATH = "/tmp/feat_dump.tsv"

with open(FEAT_PATH) as f:
    header = f.readline().rstrip("\n").split("\t")
feat_cols = [c for c in header if c != "gold"]
data = np.loadtxt(FEAT_PATH, delimiter="\t", skiprows=1)
X = data[:, :-1].astype(np.float64)
y = data[:, -1].astype(int)

print(f"features ({len(feat_cols)}): {feat_cols}")
print(f"samples: {len(y)}")
print(f"label dist: {np.bincount(y)}  (0=Exact,1=Partial,2=None)")

params = dict(
    n_estimators=20,
    max_depth=6,
    num_leaves=31,
    learning_rate=0.1,
    random_state=42,
    verbose=-1,
)

skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
accs = []
oof = np.zeros(len(y), dtype=int)
for fold, (tr, te) in enumerate(skf.split(X, y)):
    clf = lgb.LGBMClassifier(**params)
    clf.fit(X[tr], y[tr])
    pred = clf.predict(X[te])
    oof[te] = pred
    acc = (pred == y[te]).mean()
    accs.append(acc)
    print(f"fold {fold}: {acc:.6f}  ({int((pred == y[te]).sum())}/{len(te)})")
print(f"CV mean Agreement: {np.mean(accs):.6f}")

# 全量训练 + 全量评估（看当前模型是否在此语料上训练）
clf_all = lgb.LGBMClassifier(**params)
clf_all.fit(X, y)
pred_all = clf_all.predict(X)
print(f"full-train/full-eval Agreement: {(pred_all == y).mean():.6f}")

# out-of-fold 预测（衡量泛化能力）
print(f"OOF Agreement: {(oof == y).mean():.6f}")
