---
name: addr-model-review
description: 审查重新训练后内嵌进 MoonBit 的地址匹配 LightGBM 模型。当用户在重训模型后说"审查新模型""我做了一点优化你看下有没有问题"或要求验证模型移植、准确率、过拟合时使用。不用于与 ensemble 无关的普通代码改动。
---

# 地址模型重训审查

用户在 Python (`tools/addr_model/`) 重训 LightGBM 并把生成的 600 树 `match_by_ensemble` 嵌入 `lib/parser/address_match.mbt` 后，按下面顺序审查。**只审查验证，不改业务代码，不提交**（用户明确要求才提交）。用中文回复。

## 环境约定（每条命令都要带）

- `export PATH="/home/developer/.moon/bin:$PATH"`
- 构建前必须 `rm -rf _build`（增量缓存不可信）
- eval 二进制：`./_build/native/debug/build/cmd/cmd.exe addr-eval testdata/data.txt 0`
- 语料：20,000 记录 / 96,423 对；标签 完全匹配/部分匹配/不匹配

## 审查步骤

1. **定位改动**：`git status`、`git diff --stat`、`git log --oneline -3`（优化可能已提交也可能在工作区）。看 `tools/addr_model/train_final.py` 的 diff，确认本次超参数。
2. **找到树 JSON**：`ls -lat /tmp/addr_trees*.json`。训练脚本支持环境变量 `NUM_LEAVES N_EST MIN_CHILD_SAMPLES REG_ALPHA REG_LAMBDA SKIP_CV TREE_OUT EARLY_STOP`；生成器支持 `TREE_IN`。
3. **确认树前业务逻辑零改动**：`grep -n "^pub fn match_by_ensemble" lib/parser/address_match.mbt` 记为 S；与上一版本比较 `head -n $((S-2))`（通常前 1853/1854 行）。有差异要逐处人工审查并报告。
4. **移植逐字节一致性**（核心）：
   ```bash
   TREE_IN=<对应树json> python3 tools/addr_model/generate_moonbit.py
   head -c $(head -n $((S-1)) lib/parser/address_match.mbt | wc -c) lib/parser/address_match.mbt > /tmp/check_full.mbt
   cat /tmp/match_by_ensemble.mbt >> /tmp/check_full.mbt
   cmp /tmp/check_full.mbt lib/parser/address_match.mbt
   ```
   必须输出逐字节一致。同时 `grep -c "LGBM tree"` 应为 600、三类各 200。
5. **构建与测试**：`rm -rf _build && moon build`（0 错误，警告可接受）；`moon test` 必须 **339/339 通过**。
6. **全量准确率**：跑 `addr-eval`，与 commit message / 用户声称的 Agreement 比对，数值必须精确吻合。记录 Match 耗时用于性能对比。
7. **诚实 5 折 OOF（必做，防被全量拟合数字欺骗）**：用本次参数后台跑
   ```bash
   NUM_LEAVES=<值> MIN_CHILD_SAMPLES=<值> REG_ALPHA=<值> REG_LAMBDA=<值> \
   SKIP_CV=0 TREE_OUT=/tmp/verify_tmp.json python3 tools/addr_model/train_final.py
   ```
   约需 5–10 分钟，用后台任务。OOF 与用户声称值核对，并计算"全量拟合 − OOF"过拟合差距。
8. **清理**：删除自己在 `/tmp` 生成的 check/verify 临时文件（用户原有的树 JSON 和 pkl 不动）。

## 报告要求

- 给出本次参数、四项硬结论：移植一致性 / 构建 / 339 测试 / eval 准确率，全部基于实际命令输出，禁止凭推测宣称通过。
- 列出诚实 OOF 和过拟合差距；与历史模型（31 叶 OOF 76.09%、63 叶+正则 76.59%、127 叶 77.16%）做表格对比，说明准确率/源码体积（7.7万/15.4万/30.7万行）/耗时的工程取舍。
- 已知方法论注意点：`EARLY_STOP` 用单次 80/20 split 选迭代后覆盖 `n_estimators` 再跑 CV，存在轻微数据泄漏；审查时确认嵌入模型是否受影响。
- LightGBM 树→类是交替映射（tree k → class k%3）；生成器若退回连续块映射属回归 bug。
