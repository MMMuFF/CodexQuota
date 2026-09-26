# 新版窄导航栏适配 / Navigation rail layout

目标版本：0.8.6（35）。实际发布和验收状态见对应 Release 说明。

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

仍需本机安装后确认新版 Codex 是否暴露完整的导航栏辅助功能结构，以及真实悬停、缩放、设置页、侧栏收起和跨应用窗口遮挡是否正常。测试通过不等于真实 UI 已验收。

## English

Target version: 0.8.6 (35); see its Release for publication and acceptance status. Legacy footers retain the horizontal chip. A detected narrow navigation rail displays remaining percentage, short reset date, and days remaining in three centered rows above the help button. The detail card opens to the right; the subtle deviation underline stays visible on hover. Placement uses bounded Accessibility-tree inspection and fails closed if controls or free space cannot be established. Real Codex Accessibility compatibility and live interaction still need post-install acceptance. Generated previews use demo data only.
