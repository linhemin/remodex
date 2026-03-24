# 后台保持连接设计

**日期：** 2026-03-22

**目标：** 在 Remodex iOS 端引入“实时活动 + 定位后台保活”能力，让 App 在后台、锁屏和切到其他 App 时尽量维持与 relay/server 的连接，并把能力、风险和权限说明明确暴露给用户。

## 背景

现有 iOS 端已经有：

- `CodexService` 负责 websocket/secure transport/重连/sync loop
- 前后台切换时的 sync loop 节流
- 有运行中的 turn 时的有限 `beginBackgroundTask` grace window
- 推送注册和后台完成提醒

但当前没有：

- `ActivityKit` / Live Activity
- 定位后台模式
- 统一的“后台保持连接”用户设置、首次提示和权限编排

仅靠 Live Activity 无法让 iOS 在后台持续保活网络连接，因此本设计把 Live Activity 作为状态显示，把定位后台模式作为后台执行时间来源。

## 用户体验

### 首次使用

当用户第一次进入主功能区且还未对该功能做过选择时，弹出一次说明：

- 功能名称：后台保持连接
- 明确说明会启用实时活动显示连接状态
- 明确说明为了尽量在锁屏、后台和切到其他 App 时持续连接，会请求定位权限并在开启后持续使用定位作为后台保活手段
- 明确说明会增加耗电，且不能承诺 100% 永不掉线

可选操作：

- `启用`
- `暂不启用`

用户选择会被持久化，除非用户主动去设置修改，否则不重复弹窗。

### 设置页

设置页新增“后台保持连接”卡片，展示：

- 总开关
- 当前能力状态：未启用 / 权限不足 / 已启用但受限 / 已启用且保活中
- 简短说明：会使用定位在后台尽量维持连接，增加耗电
- 跳转系统设置入口

### 实时活动

当用户启用了该功能且当前存在活跃连接或后台保活动作时，展示 Live Activity。展示内容只包含泛化状态：

- Connected
- Keeping alive in background
- Permission required
- Connection interrupted

不展示敏感信息，例如 relay `sessionId`、token、完整聊天标题或服务器地址。

## 范围与非目标

### 范围内

- 首次提示与用户选择持久化
- 定位授权链路
- 后台定位保活
- Live Activity 状态展示
- 设置页开关与状态说明
- 和现有 `CodexService` 生命周期联动

### 范围外

- 不修改 relay/bridge 协议
- 不把这套逻辑替换为 VoIP、音频、导航等其它后台模式
- 不承诺 100% 永不掉线
- 不做基于消息内容的 Live Activity 富展示

## 技术设计

### 架构原则

- 连接真相继续由 `CodexService` 持有
- 后台保活逻辑拆为独立 service/coordinator，不塞进视图
- 首次启用、设置开关、前后台切换统一收敛到单一协调层
- 敏感权限和系统框架通过协议封装，便于单元测试

### 组件划分

#### `CodexMobile/CodexMobile/Models/BackgroundConnectionPreference.swift`

持久化：

- 是否已展示首次提示
- 用户是否启用后台保持连接
- 用户是否已经明确拒绝该功能

#### `CodexMobile/CodexMobile/Services/BackgroundLocationKeepaliveService.swift`

职责：

- 持有 `CLLocationManager`
- 请求 `When In Use` 与 `Always` 授权
- 管理 `allowsBackgroundLocationUpdates`
- 管理 `pausesLocationUpdatesAutomatically = false`
- 在需要时启动/停止 `startUpdatingLocation`
- 作为保守兜底可并行启用 significant-change updates

输出：

- 当前授权状态
- 是否正在执行后台定位保活
- 是否具备“完整后台能力”

#### `CodexMobile/CodexMobile/Services/LiveActivityService.swift`

职责：

- 封装 `ActivityKit`
- 创建、更新、结束单个后台连接 Live Activity
- 根据连接状态、权限状态、前后台状态生成 activity content state

说明：

- 该服务不承载业务决策，只做展示映射
- 需要新增一个 Widget Extension 作为 Live Activity UI 宿主

#### `CodexMobile/CodexMobile/Services/BackgroundConnectionCoordinator.swift`

职责：

- 持有用户偏好和首次提示状态
- 接收来自 `CodexService` 的连接摘要
- 接收前后台状态
- 决定何时：
  - 触发首次提示
  - 请求定位权限
  - 启动/停止后台定位
  - 启动/更新/结束 Live Activity

该协调器不直接管理 websocket，只增强现有连接生命周期。

### 与 `CodexService` 的关系

`CodexService` 保持为连接事实来源，新增尽量少量的只读投影供 coordinator 使用，例如：

- `isConnected`
- `hasAnyRunningTurn`
- `connectionPhase`
- `lastErrorMessage`
- 前后台状态更新入口

coordinator 只消费这些状态，不重写当前 reconnect、sync loop、push 或 secure transport 逻辑。

### 前后台行为

- 前台且功能启用时：保持普通连接；根据状态决定是否显示 Live Activity
- 切到后台时：
  - 如果功能启用且定位权限满足，则启动后台定位保活
  - 更新 Live Activity 为“Keeping alive in background”
- 回到前台时：
  - 停止不必要的定位保活
  - 刷新权限与状态
  - 让 `CodexService` 继续沿用既有前台重连/同步策略

### 权限降级

- 用户拒绝定位：功能状态为“权限不足”，不启动后台定位
- 用户只给 `When In Use`：功能状态为“已启用但受限”，说明锁屏后台时可能断开
- 用户后续在系统设置撤销权限：前台恢复时检测并自动降级

## 工程改动

### iOS App

- `CodexMobile/CodexMobile/CodexMobileApp.swift`
- `CodexMobile/CodexMobile/ContentView.swift`
- `CodexMobile/CodexMobile/Views/SettingsView.swift`
- `CodexMobile/CodexMobile/Services/CodexService.swift`
- 新增后台连接相关 model/service

### 配置

- `CodexMobile/BuildSupport/CodexMobile-Info.plist`
  - 增加 `NSSupportsLiveActivities`
  - 增加 `NSLocationWhenInUseUsageDescription`
  - 增加 `NSLocationAlwaysAndWhenInUseUsageDescription`
  - `UIBackgroundModes` 增加 `location`

### Xcode 工程

- `CodexMobile/CodexMobile.xcodeproj/project.pbxproj`
  - 新增 Live Activity Widget Extension target
  - 把新增 Swift 文件和资源接入 target

## 测试策略

以单元测试为主，不默认执行 Xcode build/test。优先增加：

- `BackgroundConnectionCoordinatorTests`
- `BackgroundLocationKeepaliveServiceTests`
- Settings 状态映射测试

`ActivityKit` 与 `CLLocationManager` 通过协议/适配器隔离，使测试可以使用假实现。

## 风险

### 技术风险

- iOS 仍可能因为系统策略、网络切换或 relay 问题中断连接
- Live Activity 不是保活能力本身
- 后台定位会带来明显耗电

### 审核风险

- 该方案本质上是使用定位后台模式维持网络活动，审核风险客观存在
- 文案必须明确说明用途与耗电影响
- 不能伪装成导航或地图用途

## 结论

推荐方案是：

- 使用 Live Activity 展示后台连接状态
- 使用定位后台模式尽量维持后台执行时间
- 通过单独 coordinator 与现有 `CodexService` 集成
- 在首次使用和设置页中对用户做清晰、直接、可关闭的说明
