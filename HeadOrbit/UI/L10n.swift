import AppKit
import Combine

enum Language: String, CaseIterable, Identifiable {
    case system, en, zh, ja
    var id: String { rawValue }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
}

/// 极简多语言：一张 key → (en, zh, ja) 表。运行时切换，不走 .strings 那套需要重启的机制。
final class L10n: ObservableObject {
    static let shared = L10n()

    @Published var language: Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "ui.language") }
    }
    @Published var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "ui.appearance"); applyAppearance() }
    }

    private init() {
        let d = UserDefaults.standard
        language = Language(rawValue: d.string(forKey: "ui.language") ?? "") ?? .system
        appearance = Appearance(rawValue: d.string(forKey: "ui.appearance") ?? "") ?? .system
        // 这里不要 applyAppearance()：App.init 阶段 NSApp 还没建好，会崩
    }

    /// 实际生效的语言：系统是中文就中文，日文就日文，其余一律英文
    var effective: Language {
        guard language == .system else { return language }
        let first = Locale.preferredLanguages.first ?? "en"
        if first.hasPrefix("zh") { return .zh }
        if first.hasPrefix("ja") { return .ja }
        return .en
    }

    func t(_ key: String) -> String {
        guard let row = Self.table[key] else { return key }
        switch effective {
        case .zh: return row.zh
        case .ja: return row.ja
        case .en, .system: return row.en
        }
    }

    func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    func applyAppearance() {
        let app = NSApplication.shared   // 用 shared 而不是 NSApp：前者按需创建，后者启动早期是 nil
        switch appearance {
        case .system: app.appearance = nil
        case .light: app.appearance = NSAppearance(named: .aqua)
        case .dark: app.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: - Strings

    private static let table: [String: (en: String, zh: String, ja: String)] = [
        "build.local": ("Local build", "本地改进版", "ローカルビルド"),
        // status
        "status.unsupported": ("Headphone motion not supported", "系统不支持耳机运动数据", "ヘッドフォンのモーションデータに非対応"),
        "status.denied": ("Motion & Fitness access denied", "「运动与健身」权限被拒绝", "「モーションとフィットネス」のアクセスが拒否されました"),
        "status.restricted": ("Motion access restricted", "权限受限", "モーションへのアクセスが制限されています"),
        "status.waitingPermission": ("Waiting for permission", "等待授权", "許可を待っています"),
        "status.waitingHeadphones": ("No head-tracking headphones", "未检测到支持头部追踪的耳机", "ヘッドトラッキング対応のヘッドフォンが見つかりません"),
        "status.tracking": ("Tracking (%@)", "正在追踪（%@）", "トラッキング中（%@）"),
        "side.left": ("left", "左耳", "左"),
        "side.right": ("right", "右耳", "右"),
        "side.unknown": ("unknown", "未知", "不明"),

        "status.waitingMotion": ("Waiting for motion", "等待运动数据", "モーションデータ待機中"),
        "status.restoringMotion": ("Bluetooth audio detected · restoring head tracking…", "已检测到蓝牙音频 · 正在恢复头部追踪…", "Bluetooth音声を検出 · 追跡を復元中…"),
        "status.motionUnavailable": ("Bluetooth audio is available, but head motion has not resumed. Keep headphones on and try briefly playing audio on this Mac, or retry below.", "蓝牙音频已连接，但尚未收到头部运动数据。保持佩戴，可尝试在这台 Mac 短暂播放音频，或点重新连接。", "Bluetooth音声は利用可能ですが、動作データはまだ届いていません。装着したままMacで音声を短く再生するか、再接続を試してください。"),

        // device section
        "device.systemSupport": ("System support", "系统支持", "システムの対応"),
        "device.yes": ("Yes", "是", "はい"),
        "device.no": ("No", "否", "いいえ"),
        "device.permission": ("Motion & Fitness", "运动与健身权限", "モーションとフィットネス"),
        "auth.authorized": ("Granted", "已授权", "許可済み"),
        "auth.denied": ("Denied", "已拒绝", "拒否"),
        "auth.restricted": ("Restricted", "受限", "制限あり"),
        "auth.notDetermined": ("Not asked", "未询问", "未確認"),
        "auth.unknown": ("Unknown", "未知", "不明"),
        "device.openSettings": ("Settings…", "去设置", "設定を開く…"),
        "device.source": ("Data source", "数据来源", "データソース"),
        "status.routedAway": ("Bluetooth audio not detected", "未检测到蓝牙音频设备", "Bluetooth音声デバイスが見つかりません"),
        "device.routedAwayHint": ("Mac has no Bluetooth audio device available. Check that your headphones are worn and connected to this Mac. HeadOrbit never changes audio routing.", "Mac 当前未检测到蓝牙音频设备。请确认已佩戴并连接到这台 Mac。HeadOrbit 不会主动切换音频路由。", "MacでBluetooth音声デバイスが見つかりません。装着し、このMacに接続されていることを確認してください。音声の接続先は変更しません。"),
        "device.reconnect": ("Reconnect", "重新连接", "再接続"),
        "device.reconnecting": ("Connecting…", "连接中…", "接続中…"),
        "device.hint": ("Wear AirPods / Beats that support head tracking, and make sure they are connected to this Mac, not your iPhone.", "戴上支持头部追踪的 AirPods / Beats，并确认它连接的是这台 Mac，不是 iPhone。", "ヘッドトラッキング対応の AirPods / Beats を装着し、iPhone ではなくこの Mac に接続されていることを確認してください。"),

        // pose section
        "pose.yaw": ("Yaw", "左右转头 Yaw", "左右の向き Yaw"),
        "pose.pitch": ("Pitch", "点头 Pitch", "上下の向き Pitch"),
        "pose.pitchUncalibrated": ("Pitch · not centered", "点头 Pitch · 未归零", "Pitch · 未校正"),
        "pose.roll": ("Roll", "歪头 Roll", "傾き Roll"),
        "pose.calibrate": ("Set current pose as forward", "以当前姿态为正前方", "現在の姿勢を正面に設定"),
        "pose.recalibrate": ("Recalibrate forward", "重新校准正前方", "正面を再キャリブレーション"),
        "pose.help": ("Sit up straight and look at the screen, then click. All angles are measured from this pose. Right turn and head-up are positive.", "坐正、平视屏幕时点一下，之后所有角度都相对这个姿态计算。右转、抬头为正。", "背筋を伸ばして画面をまっすぐ見た状態でクリックしてください。以降の角度はすべてこの姿勢を基準に計測します。右向きと上向きが正の値です。"),

        "recovery.waiting": ("Waiting for headphones · effects paused", "等待耳机 · 触发已暂停", "ヘッドフォン待機中 · 動作を一時停止"),
        "recovery.collecting": ("Quietly restoring direction…", "正在安静恢复方向…", "向きを静かに復元中…"),
        "recovery.reason.activity": ("Click, type or scroll, then keep facing the screen", "点击、按键或滚动后，保持朝向即可自动恢复", "クリック・入力・スクロール後、画面を向いてください"),
        "recovery.reason.warmingUp": ("Preparing to restore direction…", "正在准备方向恢复…", "向きの復元を準備中…"),
        "recovery.reason.moving": ("Head still moving · waiting for steady direction", "头部仍在移动 · 稳定后继续", "頭が動いています · 安定を待機中"),
        "recovery.reason.posture": ("Pose outside automatic range · sit straight or recenter", "姿态超出自动范围 · 可坐正或手动归零", "自動復元の範囲外 · 姿勢を整えるかリセット"),
        "recovery.reason.stabilizing": ("Confirming steady direction…", "正在确认稳定朝向…", "安定した向きを確認中…"),
        "recovery.reason.conflict": ("Directions differed · will retry with your next activity", "方向变化较大 · 稍后操作时重试", "向きが変わりました · 次の操作で再試行"),
        "recovery.reason.expired": ("No steady direction yet · will retry with your next activity", "尚未收集到稳定朝向 · 下次操作时重试", "安定した向きを取得できませんでした · 次の操作で再試行"),
        "recovery.reason.invalid": ("Motion data interrupted · waiting to retry", "运动数据有间断 · 等待重试", "動作データが途切れました · 再試行を待機中"),
        "recovery.reason.ready": ("Forward direction estimated", "已自动估计正前方", "正面方向を自動推定しました"),
        "recovery.waitingForActivity": ("Waiting for steady posture and activity · will resume automatically", "等待稳定姿态与操作 · 满足条件后自动恢复", "安定した姿勢と操作を待機中 · 自動で再開します"),
        "recovery.needsForward": ("Direction needs confirmation · effects paused", "方向待确认 · 触发已暂停", "向きの確認が必要 · 動作を一時停止"),
        "recovery.automatic": ("Forward direction estimated", "已自动估计正前方", "正面方向を自動推定しました"),
        "recovery.manual": ("Forward direction set", "正前方已校准", "正面方向を設定しました"),
        "recovery.center": ("Sit straight & recenter", "坐正并归零", "背筋を伸ばしてリセット"),
        "recovery.enabled": ("Quiet recovery after reconnecting", "重新佩戴后自动恢复方向", "再接続後に向きを自動復元"),
        "recovery.help": ("One click, keystroke or scroll starts observation. Small natural movements are allowed. Face the screen; sit straight and recenter if the reference feels off. No camera.", "一次点击、按键或滚动即可开始观察，允许自然的小幅动作。面向屏幕；参考有偏差时可坐正归零。不使用摄像头。", "クリック・入力・スクロール1回で観察を開始します。自然な小さな動きは許容します。画面を向き、ずれたら背筋を伸ばしてリセットしてください。カメラは使いません。"),
        "recovery.shortcutUnavailable": ("Shortcut unavailable", "快捷键未注册", "ショートカットを登録できません"),
        "recovery.posturePending": ("Waiting for a posture reference. Sit straight and recenter to set it now.", "等待姿态参考；坐正并归零可立即启用提醒。", "姿勢の基準を待機中。背筋を伸ばしてリセットすると設定できます。"),
        "recovery.postureEstimated": ("Using this session's steady pose as reference. Sit straight and recenter to adjust it.", "以本次稳定姿态为参考；坐正并归零可修正。", "今回の安定した姿勢を基準にしています。背筋を伸ばしてリセットすると調整できます。"),
        "recovery.postureCenter": ("Sit straight & calibrate posture", "坐正并校准坐姿", "背筋を伸ばして姿勢を校正"),

        "diagnostics.title": ("Motion diagnostics", "运动诊断", "モーション診断"),
        "diagnostics.help": ("If direction drifts, recenter and face the screen for 60 seconds, then export. Only the last two minutes of motion data are kept in memory; no audio or key contents.", "如方向持续漂移，归零后自然面向屏幕约 60 秒，再导出。仅在内存保留近两分钟运动数据，不含音频或按键内容。", "向きがずれる場合はリセット後に60秒ほど画面を向き、書き出してください。直近2分の動作データのみをメモリに保持し、音声やキー入力内容は含みません。"),
        "diagnostics.export": ("Export last 2 minutes…", "导出近两分钟诊断…", "直近2分の診断を書き出す…"),

        // blur action
        "blur.title": ("Blur screen when looking away", "看向别处时模糊屏幕", "よそ見したら画面をぼかす"),
        "blur.help": ("When your head turns left or right past the trigger angle and stays there, the screen blurs. It clears as soon as you look back.", "头向左或向右转过触发角度并停留一会儿，屏幕模糊；转回来即恢复。", "頭を左右にトリガー角度以上回してそのまま保つと、画面がぼけます。画面に視線を戻すとすぐに解除されます。"),
        "blur.threshold": ("Trigger angle", "触发角度", "トリガー角度"),
        "blur.dwell": ("Delay before blur", "转开多久后触发", "ぼかすまでの待ち時間"),
        "blur.dim": ("Dimming", "压暗程度", "暗さ"),
        "blur.blurred": ("Blurred", "已模糊", "ぼかし中"),

        // posture action
        "posture.title": ("Posture reminder", "坐姿提醒", "姿勢リマインダー"),
        "posture.help": ("When you slouch, your head tilts up to keep looking at the screen. If pitch rises above the trigger angle and stays there, the screen blurs until you sit up. Press Esc to dismiss and pause for a minute. Head-up is positive; the angle may be 0 or negative if your calibrated pose wasn't perfectly straight.", "弯腰塌下去时头会仰起来看屏幕。Pitch 高于触发角度并持续一段时间，屏幕模糊，坐直即恢复。按 Esc 解除并暂停 1 分钟。抬头为正；校准时没坐太直的话，角度也可以设成 0 或负数。", "猫背になると、画面を見続けるために頭が上を向きます。Pitch がトリガー角度を超えてそのまま続くと、背筋を伸ばすまで画面がぼけます。Esc キーで解除して 1 分間一時停止します。上向きが正の値です。キャリブレーション時の姿勢が完全にまっすぐでなかった場合は、角度を 0 や負の値にしても構いません。"),
        "posture.threshold": ("Trigger angle (now %@°)", "触发角度（当前 %@°）", "トリガー角度（現在 %@°）"),
        "posture.dwell": ("Hold before reminding", "持续多久后提醒", "リマインドまでの継続時間"),
        "posture.dismiss": ("Dismiss, pause 1 min", "解除并暂停 1 分钟", "解除して 1 分間停止"),
        "posture.reminding": ("Reminding", "提醒中", "リマインド中"),
        "posture.snoozed": ("Paused until %@", "已暂停至 %@", "%@ まで一時停止"),
        "posture.overlay": ("Sit up straight\nPitch %+.0f°\n\nPress Esc to pause for %.0f s", "坐直一点\nPitch %+.0f°\n\n按 Esc 暂停 %.0f 秒", "背筋を伸ばしましょう\nPitch %+.0f°\n\nEsc キーで %.0f 秒間一時停止"),

        // common
        "common.preview": ("Preview 2 s", "预览 2 秒", "2 秒プレビュー"),
        "common.quit": ("Quit", "退出", "終了"),
        "settings.language": ("Language", "语言", "言語"),
        "settings.appearance": ("Appearance", "外观", "外観"),
        "lang.system": ("System", "跟随系统", "システムに従う"),
        "lang.en": ("English", "English", "English"),
        "lang.zh": ("中文", "中文", "中文"),
        "lang.ja": ("日本語", "日本語", "日本語"),
        "appearance.system": ("System", "跟随系统", "システムに従う"),
        "appearance.light": ("Light", "亮色", "ライト"),
        "appearance.dark": ("Dark", "暗色", "ダーク"),
    ]
}
