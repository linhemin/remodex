# Connection Path Status Design

## Goal

在 iPhone 的设置页里明确显示“当前实际连接路径”，让用户能直接判断这次连接走的是局域网、私网 overlay，还是远端 relay。

## Scope

只展示当前实际连接路径，不展示未来候选或重连优先级。断开时显示未连接。

## Recommended Approach

把连接路径判断放在 `CodexService` 服务层，复用现有 relay host 分类逻辑，再由设置页读取一个 UI 友好的只读状态。

推荐显示四种状态：

- `局域网直连`
- `私网 Overlay`
- `远端 Relay`
- `未连接`

## Data Flow

1. `CodexService` 从当前 `relayUrl` 读取已连接 relay 基址。
2. 复用 `relayHostCategory(for:)` 判断 host 是 local、overlay 还是 neither。
3. 派生一个设置页可直接消费的标签。
4. `SettingsView` 在现有 `Connection` 卡片中展示 `连接路径` 一行。

## Why This Approach

- 不改连接流程或重连排序，风险最低。
- 状态来源明确，用户看到的是“当前实际连接路径”而不是推测。
- 复用现有 LAN/overlay 判断逻辑，避免重复实现和 UI/服务层分叉。

## Testing

- 新增服务层单测，覆盖 local / overlay / remote / disconnected 四种状态。
- 不新增 UI snapshot 测试；设置页只消费服务层状态，保持最小改动。
