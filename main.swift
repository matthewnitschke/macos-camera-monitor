#!/usr/bin/env swift

import Foundation
import AVFoundation
import CoreMediaIO
import CoreAudio
import ObjectiveC

// Command line arguments
var verboseArg = false
var executablePath: String? = nil

var args = CommandLine.arguments
var i = 1 // Skip script name
while i < args.count {
    if args[i] == "--verbose" {
        verboseArg = true
        i += 1
    } else {
        // Positional arguments correlate to the executable path
        executablePath = args[i]
        i += 1
    }
}

func log(_ message: String, verbose: Bool = false) {
    if (verbose && !verboseArg) {
        return
    }
    print(message)
}

// Execute the provided script with connection state parameter and device ID
func executeScript(state: String, deviceID: CMIOObjectID) {
    guard let executablePath = executablePath else {
        return
    }
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = [state, String(deviceID)]
    
    do {
        try process.run()
        log("Executed: \(executablePath) \(state) \(deviceID)", verbose: true)
    } catch {
        log("ERROR: Failed to execute \(executablePath): \(error.localizedDescription)")
    }
}

// Store listener blocks to keep them alive
var listenerBlocks: [String: CMIOObjectPropertyListenerBlock] = [:]

func enableCameraAccess() {
    var allowScreenCapture: UInt32 = 1
    let dataSize: UInt32 = UInt32(MemoryLayout<UInt32>.size)
    var propertyAddress = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    
    CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &propertyAddress, 0, nil, dataSize, &allowScreenCapture)
}

func getDeviceID(_ device: AVCaptureDevice) -> CMIOObjectID? {
    let selector = NSSelectorFromString("connectionID")
    guard device.responds(to: selector) else {
        return nil
    }
    
    // Use methodForSelector to get the function pointer directly
    // This avoids the object return type issue with perform(_:)
    typealias ConnectionIDMethod = @convention(c) (AnyObject, Selector) -> UInt32
    guard let method = class_getMethodImplementation(type(of: device), selector) else {
        return nil
    }

    let imp = unsafeBitCast(method, to: ConnectionIDMethod.self)
    let connectionID = imp(device, selector)
    
    return CMIOObjectID(connectionID)
}

func getCameraState(_ deviceID: CMIOObjectID) -> UInt32 {
    var isRunning: UInt32 = 0
    var propertySize: UInt32 = UInt32(MemoryLayout<UInt32>.size)
    
    var propertyStruct = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kAudioDevicePropertyDeviceIsRunningSomewhere),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kAudioObjectPropertyElementMain)
    )
    
    let status = CMIOObjectGetPropertyData(
        deviceID,
        &propertyStruct,
        0,
        nil,
        UInt32(MemoryLayout<UInt32>.size),
        &propertySize,
        &isRunning
    )
    
    if status != noErr {
        return 0
    }
    
    return isRunning
}

func monitorCamera(_ device: AVCaptureDevice) {
    guard let deviceID = getDeviceID(device) else {
        log("ERROR: Failed to get device ID for \(device.localizedName)")
        return
    }
    
    log("Monitoring camera: \(device.localizedName) (ID: \(deviceID))", verbose: true)
    
    var propertyStruct = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kAudioDevicePropertyDeviceIsRunningSomewhere),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kAudioObjectPropertyElementMain)
    )
    
    // Create a dispatch queue for callbacks
    let queue = DispatchQueue(label: "camera.monitor.queue", attributes: .concurrent)
    
    // Track previous state (use a class to allow mutation in closure)
    class StateTracker {
        var previousState: UInt32
        let deviceName: String
        
        init(initialState: UInt32, deviceName: String) {
            self.previousState = initialState
            self.deviceName = deviceName
        }
    }
    
    let stateTracker = StateTracker(initialState: getCameraState(deviceID), deviceName: device.localizedName)
    
    let listenerBlock: CMIOObjectPropertyListenerBlock = { (inNumberAddresses, addresses) in
        let currentState = getCameraState(deviceID)
        
        if currentState != stateTracker.previousState {
            if currentState != 0 {
                log("Connected: \"\(stateTracker.deviceName)\" (ID: \(deviceID))")
                executeScript(state: "connected", deviceID: deviceID)
            } else {
                log("Disconnected: \"\(stateTracker.deviceName)\" (ID: \(deviceID))")
                executeScript(state: "disconnected", deviceID: deviceID)
            }
            stateTracker.previousState = currentState
        }
    }
    
    let status = CMIOObjectAddPropertyListenerBlock(deviceID, &propertyStruct, queue, listenerBlock)
    
    if status != noErr {
        log("ERROR: Failed to register listener for \(device.localizedName) (error: \(status))")
        return
    }
    
    // Store the listener block to keep it alive
    listenerBlocks[device.uniqueID] = listenerBlock
}

func startMonitoring() {
    enableCameraAccess()
    
    log("Starting camera monitoring...")
    
    // Get all video devices
    let discoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
        mediaType: .video,
        position: .unspecified
    )
    let videoDevices = discoverySession.devices
    
    if videoDevices.isEmpty {
        log("No cameras found")
        return
    }
    
    for device in videoDevices {
        // Skip virtual devices
        if device.localizedName.contains("Virtual") {
            continue
        }
        
        monitorCamera(device)
    }
    
    // Monitor for new/removed devices
    NotificationCenter.default.addObserver(
        forName: AVCaptureDevice.wasConnectedNotification,
        object: nil,
        queue: .main
    ) { notification in
        if let device = notification.object as? AVCaptureDevice {
            log("New camera connected: \(device.localizedName)")
            monitorCamera(device)
        }
    }
    NotificationCenter.default.addObserver(
        forName: AVCaptureDevice.wasDisconnectedNotification,
        object: nil,
        queue: .main
    ) { notification in
        if let device = notification.object as? AVCaptureDevice {
            log("Camera disconnected: \(device.localizedName)")
        }
    }
    
    // Keep the script running
    RunLoop.main.run()
}

startMonitoring()

