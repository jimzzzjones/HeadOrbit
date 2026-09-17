# Automatic recovery / 自动恢复

## Everyday use / 日常使用

1. Wear supported headphones and connect them to this Mac. Enable **Quiet recovery after reconnecting / 重新佩戴后自动恢复方向**.
2. Face the screen and click, type, or scroll once. HeadOrbit's own panel counts. You do not need to keep clicking or hold your head perfectly still.
3. The app collects several consistent short motion windows. A successful reference enables the configured effects. If the attempt fails, follow the displayed reason or use **Sit straight & recenter / 坐正并归零** (`⌃⌥⌘C`).

戴好耳机并连接到这台 Mac。面向屏幕后点击、输入或滚动一次即可启动观察，允许自然的小幅头部动作，无需反复操作或完全不动。成功后启用已打开的功能；未成功时可查看等待原因，或坐正后按 `⌃⌥⌘C` 立即归零。

## What is estimated / 估计的是什么

The reference is a representative real attitude sample from stable observations. All three axes are measured relative to it. The reference is frozen after recovery; the app does not keep adapting to a gradually changing posture.

自动恢复从稳定观察中选择一帧具有代表性的真实姿态，作为三轴共同参考；完成后保持固定，不会逐渐把新的坐姿学成零点。

There is no camera or screen-position measurement. A stable sideways pose or a sufficiently slow turn may look like “forward” to the sensor. A stable pose is not proof of sitting upright. For a deliberate posture baseline, sit straight, face the screen, and recenter manually. Long-term sensor drift can still require recentering.

应用不使用摄像头，也不测量屏幕位置。持续侧向静止或足够缓慢的转头可能被误当作正前方；稳定不代表坐直。需要明确的坐姿基准时，请坐直面向屏幕手动归零。长时间传感器漂移仍可能需要重新归零。

## Capture behavior / 观察规则

- One recent click, key, or scroll opens a fixed 15-second observation period. Repeated activity does not extend it. A failed attempt has a 5-second cooldown and needs fresh activity to retry.
- After a 2-second warmup, three windows of at least 1.5 seconds and 15 samples must agree. The windows are separated by 1 second.
- Trimmed angle ranges tolerate small oscillations and isolated spikes. Large movement or excessive acceleration clears the current window, while inconsistent direction, data gaps, or invalid timestamps can reject the attempt.
- Tested motion tolerance includes ±1–3° oscillations at 0.35–1.2 Hz across four phases. This is a bounded replay test, not a guarantee for every human movement.
- Effects wait for a valid reference. Uncentered Pitch is still shown and clearly labeled. Disconnects and invalid sensor references clear the previous calibration.

一次操作开启固定 15 秒观察，重复操作不会延长；失败后冷却 5 秒，再由新操作触发重试。预热 2 秒后，需要三个相互一致的短窗口。采用去除极端样本后的角度范围，允许小幅摆动；大幅运动会清除当前窗口，持续方向变化或数据异常可能中止本次尝试。

## Reconnection / 重连

Audio connectivity does not prove that Core Motion is streaming. HeadOrbit watches Bluetooth input/output route changes, retries up to three times per retry budget, and leaves a manual reconnect button when automatic retries finish. A new route-return event or manual retry can start another budget; repeated identical callbacks cannot keep restarting it. The app never forces an audio route or plays audio automatically.

音频连上不等于已经收到运动数据。应用观察蓝牙输入、输出变化，每轮最多自动重试三次；结束后可手动重新连接。新的路由返回事件或手动重试可开启新一轮，重复相同回调不会无休止重启。应用不会强制切换音频路由或自动播放声音。

Brief playback on the Mac helped motion resume in one observed case. It is offered as a troubleshooting suggestion, not a guaranteed recovery mechanism.

曾观察到在 Mac 短暂播放音频可加快恢复，仅作为排查建议，不能保证有效。

## Diagnostics and privacy / 诊断与隐私

A bounded, approximately 10 Hz rolling buffer holds up to two minutes of motion diagnostics in memory. Export is explicit through a save dialog. CSV columns include relative/raw angles, sensor side, validity, input-event age, recovery reason, and reference source. No audio or typed text is captured. The app does not upload the export.

近两分钟运动诊断保存在有上限的内存缓冲中，约每秒十条。只有你主动选择导出并指定路径时才生成 CSV，包含角度、耳机侧别、有效性、操作距今时间、恢复原因和参考来源，不包含音频或输入文字，也不会上传。公开分享前请自行检查并删去不想公开的信息。
