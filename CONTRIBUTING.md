# Contributing

This fork builds on [Cogria-AI/HeadOrbit](https://github.com/Cogria-AI/HeadOrbit). Keep the original MIT license and attribution with source and binary distributions.

## Development

Use macOS 14+ with Apple Command Line Tools (Swift 5.9+) or a configured Xcode installation. The scripts default to `/Library/Developer/CommandLineTools`; for full Xcode set `DEVELOPER_DIR` to the active developer directory.

```bash
./script/test.sh
./script/build_and_run.sh --build
git diff --check
```

`./script/build_and_run.sh` builds and launches the application, replacing a running HeadOrbit process. `--build` only builds. XcodeGen users can run `./build.sh`; `./package.sh` builds the release DMG.

## Pull requests

Describe the resulting behavior and relevant tradeoffs. For motion/recovery changes, add deterministic cases where they meaningfully cover a regression, run the replay suite, and record real-device observations separately. Keep README translations, the changelog, and version/build metadata consistent. Comments should explain non-obvious reasons.

Do not commit exported personal diagnostics, credentials, local preferences, or generated app bundles. Before sharing an issue, inspect any attached CSV/logs for information you do not want public.

## Reporting a problem

Use [Issues](https://github.com/jimzzzjones/HeadOrbit/issues). Include the full app version/build, macOS version, headphone model, reproduction steps, expected/actual behavior, and whether audio was connected while motion data was missing. State whether you tried manual recentering or reconnecting. Attach diagnostics only when useful and after reviewing them.
