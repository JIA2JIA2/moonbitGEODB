"""超参数扫描：找到能复现/超越 75.902% 的 LightGBM 配置。"""
import numpy as np
import lightgbm as lgb
from sklearn.model_selection import StratifiedKFold

FEAT_PATH = "/tmp/feat_dump.tsv"
data = np.loadtxt(FEAT_PATH, delimiter="\t", skiprows=1)
X = data[:, :-1].astype(np.float64)
y = data[:, -1].astype(int)

skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
folds = list(skf.split(X, y))

configs = [
    dict(n_estimators=20, num_leaves=31, max_depth=6, learning_rate=0.1),
    dict(n_estimators=50, num_leaves=31, max_depth=6, learning_rate=0.1),
    dict(n_estimators=100, num_leaves=31, max_depth=6, learning_rate=0.1),
    dict(n_estimators=200, num_leaves=31, max_depth=-1, learning_rate=0.1),
    dict(n_estimators=100, num_leaves=63, max_depth=-1, learning_rate=0.05),
    dict(n_estimators=300, num_leaves=63, max_depth=-1, learning_rate=0.05),
    dict(n_estimators=200, num_leaves=127, max_depth=-1, learning_rate=0.05),
]

for cfg in configs:
    oof = np.zeros(len(y), dtype=int)
    for tr, te in folds:
        clf = lgb.LGBMClassifier(**cfg, random_state=42, verbose=-1)
        clf.fit(X[tr], y[tr])
        oof[te] = clf.predict(X[te])
    oof_acc = (oof == y).mean()
    # 全量训练/全量评估
    clf_all = lgb.LGBMClassifier(**cfg, random_state=42, verbose=-1)
    clf_all.fit(X, y)
    full_acc = (clf_all.predict(X) == y).mean()
    print(f"{cfg} -> OOF={oof_acc:.6f}  full={full_acc:.6f}")