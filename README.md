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

## Run at login

launchd can be configured to execute this script at login

```
mkdir -P ~/Library/LaunchAgents
touch ~/Library/LaunchAgents/com.personal.macos-camera-monitor.plist
```

Add the following xml to the new plist file

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.personal.macos-camera-monitor</string>

  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/swift</string>
    <string>/ABSOLUTE_PATH_TO/macos-camera-monitor/main.swift</string>
    <string>/ABSOLUTE_PATH_TO/your-script.sh</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>StandardOutPath</key>
  <string>/tmp/macos-camera-monitor.out</string>
  <key>StandardErrorPath</key>
  <string>/tmp/macos-camera-monitor.err</string>
</dict>
</plist>
```

run the following command to load the new plist file in launchd

```console
$ launchd load ./com.personal.macos-camera-monitor.plist

# optionally start the service
$ launchd start ./com.personal.macos-camera-monitor.plist
```

## Credit

Logic for this script was adapted from the [OverSight project](https://github.com/objective-see/OverSight). For a more security oriented solution to this, see that application. This is a bit more lightweight, "in the background" version of that