# LAN Promotion Design

## Goal

让 iPhone 在首次通过远端 relay 连上之后，只要后续发现同一台已配对 Mac 的局域网 relay 可达，就自动迁移到局域网连接，而不是一直停留在远端 relay。

## Scope

- 保留现有 relay 协议、secure handshake、trusted reconnect
- 不引入常驻 Bonjour 监听
- 只在当前连接路径是 `Remote relay` 时尝试自动迁移
- 只迁移到 `macDeviceId` 匹配当前已配对 Mac 的 Bonjour 候选

## Recommended Approach

新增一个轻量的 `LAN promotion` 编排流程：

1. 当前连接成功后，如果仍是 `Remote relay`，后台短时执行一次 Bonjour 发现。
2. App 回到前台时，如果当前仍是 `Remote relay`，再次短时执行一次 Bonjour 发现。
3. 命中同一台 Mac 的局域网候选后，主动断开当前远端连接，并立即通过该局域网 relay 走现有 secure reconnect 重新连上。

这个方案比“只在重连时优先 LAN”更符合 local-first 目标，也比“常驻监听、随时切换”更稳，复杂度可控。

## Data Flow

1. `ContentViewModel` 在连接成功后或前台恢复时触发 `attemptLANPromotionIfNeeded`。
2. 该流程先检查：
   - 当前必须已连接
   - 当前路径必须是 `Remote relay`
   - 当前没有其他 promotion 在跑
   - 没有命中冷却窗口
3. 触发 Bonjour 短时发现，得到本轮局域网候选。
4. 只保留 `macDeviceId` 与当前 trusted Mac 匹配的候选。
5. 如果候选 URL 与当前 `relayUrl` 不同，则断开当前连接，并用该候选构造 reconnect URL。
6. 通过现有 `connectWithAutoRecovery` / secure reconnect 连回去。
7. 成功后，设置页自然显示 `LAN direct`。

## Failure Handling

- Bonjour 发现为空：静默跳过
- 候选不匹配当前 Mac：静默跳过
- LAN reconnect 失败：恢复到现有 saved relay / trusted reconnect 路径
- 不清 pairing，不进入 re-pair，除非现有 secure reconnect 本身判定必须重配
- 失败后进入短冷却，避免反复抖动

## Testing

- 新增 ViewModel 单测，覆盖 `Remote relay -> Bonjour LAN candidate -> 自动切换`
- 覆盖当前已是 `LAN direct` / `Private overlay` 时不会 promotion
- 覆盖发现到其他 Mac 时不会切换
- 覆盖 promotion 失败时会回退到原有远端 reconnect 路径，不丢 pairing
