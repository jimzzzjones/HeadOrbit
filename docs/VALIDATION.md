# Validation scope — 0.1.6 (12)

## Build 12 regression checks

The suite now includes 49 replay scenarios, adding delayed-callback timing, timer/callback ordering, bounded expiry with continuous backlog, startup catch-up, clock rollback, stale calibration gating, and reset/restart of posture dwell. The timing regression uses a synthetic stream with a 1.044586-second arrival interval and only a 0.160-second sensor advance; no personal CSV is committed. Diagnostic exports now contain 22 columns.

On the locally installed build 12, a live headphone session established an automatic reference, paused on delayed delivery, and resumed with the same reference epoch. A subsequent actual disconnect invalidated the reference. This is one observed session, not coverage of every reconnection or long-term drift.

This fixes unintended reference resets after short delivery delays. It does not establish continuous hardware drift correction. Build 11's live-device observations below are historical and do not replace new-device validation.

## Historical build 11 evidence



The final application source passed **39 replay scenarios with zero failed assertions**, repeated independently. Re-run on macOS:

```bash
./script/test.sh
./script/build_and_run.sh --build
codesign --verify --strict dist/HeadOrbit.app
```

Coverage includes:

- 48 small-motion combinations: amplitudes ±1°, ±2°, ±3°; frequencies 0.35, 0.5, 0.8, 1.2 Hz; four phases.
- Tested continuous turns, conflicting windows, interrupted samples, timeout/cooldown, invalid timestamps, and bounded buffers.
- Representative reference selection, full relative Yaw/Pitch/Roll, and prevention of raw-yaw coupling during nodding.
- Action validity gates, posture dwell entry/exit/reset, Bluetooth input/output return, retry limits, and the 20-column diagnostic export format.

A locally installed build on **macOS 27.0 (26A428) with AirPods Pro** was observed on 2026-09-16 to recover a reference automatically, update Pitch, and activate/release the posture reminder. Installation and archive extraction signature checks passed. The observed executable SHA-256 was:

```text
ddf05ce43e5b6a7fecbab92f908c69523de602d59749478c7f47bdeb1cacd2bb
```

This identifies the observed local executable, not every future CI build. Compiler, architecture, signing, and bundle packaging can change artifact hashes. Personal raw motion traces are not included in this repository.

## What this does not establish

- Automatic recognition of upright posture, gaze, or the screen's location.
- Continuous drift correction, guaranteed recovery after every device switch, or compatibility with every advertised headphone model.
- Real-device coverage across all supported macOS versions. macOS 14 is the deployment target, not a claim that every version has been tested.
- Apple notarization. An ad-hoc signature check verifies integrity, not Apple's approval or distribution identity.

## Before publishing a binary

1. Run replay tests and build from the exact source revision being tagged.
2. Verify version/build in both `HeadOrbit/Info.plist` and `project.yml`, and check the built bundle.
3. Package with `./package.sh`; it verifies the signature and includes the MIT license.
4. Record artifact architecture and SHA-256; test extraction and launch on a target Mac with Motion & Fitness permission.
5. Publish release notes with completed checks and remaining limits. GitHub Actions results are separate from the local checks above.

## 中文摘要

本地最终应用源码 39/39 个回放场景通过，独立 QA 复测通过，其中包含 48 组小幅动作组合。一次 macOS 27.0 + AirPods Pro 实机过程确认了自动参考恢复、Pitch 更新和坐姿提醒触发/解除。此证据不代表所有耳机、所有系统版本和每次跨设备重连都成功，也不证明已解决持续漂移。临时签名验证不等于 Apple 公证。公开仓库不包含个人原始运动轨迹。
