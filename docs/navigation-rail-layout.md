# 新版窄导航栏适配 / Navigation rail layout

目标版本：0.8.6（37）。实际发布和验收状态见对应 Release 说明。

- 旧版账户底栏继续横排；新版窄导航栏在帮助按钮上方空白处显示三行：剩余百分比、短日期、剩余天数。
- 文字不旋转，统一采用原有次级文字色；偏差下划线在悬停时保留。默认日期不加星期，完整日期仍在详情卡显示。
- 竖排详情向右展开。额度面板仍跟随目标窗口，不成为全局置顶窗口。
- 通过辅助功能树的实际栏宽和按钮边界识别；支持 48–88pt 宽的左侧导航栏。扫描不完整、底部按钮缺失、空间不足或其他按钮占用该位置时不显示，避免覆盖按钮。
- 不读取账号名称来定位，不修改 Codex 安装包，不改变额度、重置券或更新器行为。

## 验证

修改文件：`CodexSidebarLocator.swift`（窄栏识别）、`CodexOverlayGeometry.swift`（位置与避让）、`QuotaOverlayPanel.swift`（三行排版）、`StatusItemController.swift`（坐标转换及弹窗方向），以及对应核心/AppKit 测试。原有 CI 文件本地改动未处理。

```sh
./scripts/run-tests.sh
./scripts/run-app-tests.sh
./scripts/build-app.sh
git diff --check
```

合成测试覆盖窄栏定位、负坐标屏幕、按钮避让、三行居中、100% 与最长短日期、横竖切换、偏差线保留及弹窗方向。预览输出于 `.build/manual-app-tests/navigation-rail-preview-zh.png` 和 `navigation-rail-preview-en.png`，使用虚构数据，并非真实 Codex 截图。

构建 37 已由用户确认恢复显示。另有 4 项直接运行真实定位器、仅使用虚构辅助功能节点的回归检查，覆盖搜索优先级、隐藏缓存重新识别、占位按钮避让和权限缺失。所有窗口/多显示器组合仍需持续验证，合成测试不替代真实 UI 验收。

## English

Target version: 0.8.6 (37); see its Release for publication and acceptance status. Legacy footers retain the horizontal chip. A detected narrow navigation rail displays remaining percentage, short reset date, and days remaining in three centered rows above the help button. The detail card opens to the right; the subtle deviation underline stays visible on hover. Placement uses bounded Accessibility-tree inspection and fails closed if controls or free space cannot be established. The user confirmed restored visibility in build 37; four real-locator tests with synthetic nodes cover discovery priority, hidden-cache recovery, occupied slots, and missing permission. Not every window/multi-display combination has been tested. Generated previews use demo data only.
