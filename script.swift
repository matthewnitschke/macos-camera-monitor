#!/usr/bin/env swift

import Foundation
import AVFoundation
import CoreMediaIO
import CoreAudio
import ObjectiveC

// Store listener blocks to keep them alive
var listenerBlocks: [String: CMIOObjectPropertyListenerBlock] = [:]

// Enable access to camera devices
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

// Get device ID from AVCaptureDevice using Objective-C runtime
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
    
    // Cast to the correct function signature
    let imp = unsafeBitCast(method, to: ConnectionIDMethod.self)
    
    // Call the method directly
    let connectionID = imp(device, selector)
    
    return CMIOObjectID(connectionID)
}

// Check if camera is running
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

// Monitor a camera device
func monitorCamera(_ device: AVCaptureDevice) {
    guard let deviceID = getDeviceID(device) else {
        print("ERROR: Failed to get device ID for \(device.localizedName)")
        return
    }
    
    print("Monitoring camera: \(device.localizedName) (ID: \(deviceID))")
    
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
    
    // Listener block
    let listenerBlock: CMIOObjectPropertyListenerBlock = { (inNumberAddresses, addresses) in
        let currentState = getCameraState(deviceID)
        
        // Only print if state changed
        if currentState != stateTracker.previousState {
            if currentState != 0 {
                print("📸 Camera CONNECTED: \(stateTracker.deviceName)")
            } else {
                print("📸 Camera DISCONNECTED: \(stateTracker.deviceName)")
            }
            stateTracker.previousState = currentState
        }
    }
    
    // Register the listener
    let status = CMIOObjectAddPropertyListenerBlock(deviceID, &propertyStruct, queue, listenerBlock)
    
    if status != noErr {
        print("ERROR: Failed to register listener for \(device.localizedName) (error: \(status))")
        return
    }
    
    // Store the listener block to keep it alive
    listenerBlocks[device.uniqueID] = listenerBlock
}

// Main monitoring function
func startMonitoring() {
    // Enable camera access first
    enableCameraAccess()
    
    print("Starting camera monitoring...")
    print("Press Ctrl+C to stop\n")
    
    // Note: Camera permission may be required, but we'll proceed anyway
    // The system will prompt if needed
    continueMonitoring()
}

func continueMonitoring() {
    // Get all video devices
    let discoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
        mediaType: .video,
        position: .unspecified
    )
    
    let videoDevices = discoverySession.devices
    
    if videoDevices.isEmpty {
        print("No cameras found")
        return
    }
    
    // Monitor each camera
    for device in videoDevices {
        // Skip virtual devices
        if device.localizedName.contains("Virtual") {
            continue
        }
        
        monitorCamera(device)
    }
    
    // Also monitor for new devices
    NotificationCenter.default.addObserver(
        forName: AVCaptureDevice.wasConnectedNotification,
        object: nil,
        queue: .main
    ) { notification in
        if let device = notification.object as? AVCaptureDevice {
            print("New camera connected: \(device.localizedName)")
            monitorCamera(device)
        }
    }
    
    NotificationCenter.default.addObserver(
        forName: AVCaptureDevice.wasDisconnectedNotification,
        object: nil,
        queue: .main
    ) { notification in
        if let device = notification.object as? AVCaptureDevice {
            print("Camera disconnected: \(device.localizedName)")
        }
    }
    
    // Keep the script running
    RunLoop.main.run()
}

// Start monitoring
startMonitoring()

