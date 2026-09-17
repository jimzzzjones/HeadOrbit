# Changelog

## 0.1.6 (12) — 2026-09-17

- Preserve the existing Pitch/Yaw reference across brief callback delays; pause effects until current motion catches up. / 短暂回调延迟后保留 Pitch/Yaw 原参考，数据追上前暂停效果。
- Exclude buffered samples from actions, automatic recovery, and manual recentering. Restart action dwell after resuming. / 积压帧不参与动作或校准，恢复后重新计算动作持续时间。
- Invalidate on genuine sensor discontinuity, side change, reference jump, disconnect, or five seconds without fresh data; queued callbacks cannot renew that deadline. / 真正断档、换耳、参考跳变、断连或五秒无新鲜数据仍作废参考，旧回调不能延长等待。
- Add delivery state and relative delivery lag to diagnostic CSV (22 columns), with freshness reflected in controls. / 诊断 CSV 增加到达状态与相对延迟，共 22 列；界面同步显示等待状态。
- Add regression coverage for callback order, backlog, deadline, clock rollback, calibration gating, and effect reset. / 增加回调顺序、积压、期限、时间回退、校准限制与效果解除的回归覆盖。

## 0.1.6 (11) — 2026-09-17

Fork improvements based on [Cogria-AI/HeadOrbit v0.1.5](https://github.com/Cogria-AI/HeadOrbit/tree/v0.1.5).

### Added / 新增

- Activity-triggered automatic reference recovery after reconnecting, with a fixed observation period and tolerance for small natural movements. / 重连后由一次操作启动自动恢复，固定观察时间，允许自然小幅动作。
- Global `⌃⌥⌘C` shortcut to sit straight and recenter. / 全局快捷键坐正并归零。
- Detailed recovery states and a manual export of the last two minutes of motion diagnostics. / 更明确的恢复状态，可手动导出近两分钟运动诊断。
- Command Line Tools / SwiftPM build scripts and 39 deterministic replay scenarios. / 新增编译脚本及 39 个确定性回放场景。

### Fixed / 修复

- Calibrated Yaw, Pitch, and Roll use the same full relative attitude; nodding no longer substitutes raw Euler yaw for calibrated yaw. / 校准后三轴共用完整姿态参考，避免点头时原始 Yaw 混入。
- Pitch remains visible before calibration with an explicit uncentered label; posture reminders activate after a valid full-pose reference. / 未归零时保留真实 Pitch 显示，参考有效后接通坐姿提醒。
- Reconnection observes Bluetooth input and output changes and uses bounded retries without repeated callbacks endlessly postponing recovery. / 监听蓝牙输入、输出变化，限制重试次数，避免重复回调不断推迟恢复。
- Disconnects, stale samples, sensor changes, and sleep/session changes invalidate old references and clear effects. / 断连、过期数据、传感器变化及睡眠等状态变更后清除旧参考与效果。
- Lower-left version includes the build number: `0.1.6 (11)`. / 左下角显示完整版本与构建号。
- Build errors stop packaging; CI validates replay tests and app signing, and release packaging retains the MIT license. / 构建失败中止打包，CI 检查回放和签名，安装包保留 MIT 许可。

### Validation and limits / 验证与限制

- 39/39 local replay scenarios passed, including a 48-combination small-motion sweep; independent QA repeated the suite successfully. / 本地 39/39 场景通过，含 48 组小幅动作组合，独立 QA 复测通过。
- One AirPods Pro session confirmed automatic reference recovery, live Pitch, and posture reminder activation/release. / 一次 AirPods Pro 实机过程验证了自动参考恢复、实时 Pitch 及坐姿提醒触发与解除。
- Automatic reference means the current stable pose, not verified upright posture or screen direction. Continuous yaw drift correction and universal reconnection reliability are not established. / 自动参考代表当前稳定姿态，无法确认坐直或屏幕方向；未证实能持续修正 Yaw 漂移或保证所有重连成功。
- Builds are ad-hoc signed, not Apple-notarized. / 构建为临时签名，未经 Apple 公证。

See [Recovery](docs/RECOVERY.md) and [Validation](docs/VALIDATION.md) for scope and reproduction steps.
