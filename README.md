# macos-camera-monitor

A simple cli script to monitor when macos is using a camera or not. Can be used for security reasons, or to trigger simple workflows

## Usage

```
swift ./main.swift
```

Optionally pass a path to a shell script that will be ran when a camera connects or disconnects. The first argument passed to this script will be "connected" or "disconnected", correlating to the new camera state, and the second argument will be the deviceId

```
swift ./main.swift "./path/to/my/script.sh"
```

Additionally, the cli has a `--verbose` flag for additional output
```
swift ./main.swift --verbose
```

## Credit

Logic for this script was adapted from the [OverSight project](https://github.com/objective-see/OverSight). For a more security oriented solution to this, see that application. This is a bit more lightweight, "in the background" version of that