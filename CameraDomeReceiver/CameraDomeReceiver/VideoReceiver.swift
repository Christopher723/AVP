import Foundation
import Network
import Combine

class UDPReceiver: ObservableObject {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "UDPReceiverQueue")
    @Published var receivedFrameData = Data()
    
    private var frameBuffers: [UInt32: [UInt16: Data]] = [:]
    private var expectedChunks: [UInt32: UInt16] = [:]
    private var frameTimestamps: [UInt32: Date] = [:]
    private let frameTimeout: TimeInterval = 1.0
    private var latestFrameId: UInt32 = 0
    
    init(port: UInt16) {
        setupListener(port: port)
    }
    
    private func setupListener(port: UInt16) {
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            print("Invalid port number: \(port)")
            return
        }

        do {
            listener = try NWListener(using: parameters, on: nwPort)
            
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("UDP Listener ready on port \(port)")
                case .failed(let error):
                    print("UDP Listener failed: \(error)")
                case .cancelled:
                    print("UDP Listener cancelled")
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener?.start(queue: queue)
        } catch {
            print("Failed to create UDP listener: \(error)")
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveNextMessage(on: connection)
    }
    
    private func receiveNextMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, isComplete, error in
            if let error = error {
                print("Error receiving message: \(error)")
                return
            }
            
            if let data = data, !data.isEmpty {
                self?.processReceivedData(data)
            }
            
            // Continue receiving next message
            self?.receiveNextMessage(on: connection)
        }
    }
    
    private func processReceivedData(_ data: Data) {
        guard data.count > 9 else { return }
        
        let frameId = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let chunkIndex = data[4..<6].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let totalChunks = data[6..<8].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let streamId = data[8]
        let frameData = data.subdata(in: 9..<data.count)
        
        guard streamId == 2 else { return }
        
        if isNewerFrame(frameId) {
            latestFrameId = frameId
            discardOldFrames(before: frameId)
        }
        
        cleanupOldFrames()
        
        if frameBuffers[frameId] == nil {
            frameBuffers[frameId] = [:]
            expectedChunks[frameId] = totalChunks
            frameTimestamps[frameId] = Date()
        }
        frameBuffers[frameId]?[chunkIndex] = frameData
        
        if let buffer = frameBuffers[frameId], buffer.count == Int(totalChunks) {
            var fullData = Data()
            for i in 0..<totalChunks {
                guard let chunk = buffer[i] else {
                    return
                }
                fullData.append(chunk)
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.receivedFrameData = fullData
            }
            
            frameBuffers.removeValue(forKey: frameId)
            expectedChunks.removeValue(forKey: frameId)
            frameTimestamps.removeValue(forKey: frameId)
        }
    }
    
    private func isNewerFrame(_ frameId: UInt32) -> Bool {
        // Simple check: handle wrap-around on UInt32
        return (frameId > latestFrameId && frameId - latestFrameId < UInt32(Int32.max)) ||
               (latestFrameId > UInt32.max / 2 && frameId < UInt32.max / 2)
    }
    
    private func discardOldFrames(before frameId: UInt32) {
        let framesToDiscard = frameBuffers.keys.filter { isOlderFrame($0, than: frameId) }
        for oldFrameId in framesToDiscard {
            frameBuffers.removeValue(forKey: oldFrameId)
            expectedChunks.removeValue(forKey: oldFrameId)
            frameTimestamps.removeValue(forKey: oldFrameId)
            print("Discarded old incomplete frame \(oldFrameId) as newer frame \(frameId) arrived")
        }
    }
    
    private func isOlderFrame(_ frameId1: UInt32, than frameId2: UInt32) -> Bool {
        return !isNewerFrame(frameId1) && frameId1 != frameId2
    }
    
    private func cleanupOldFrames() {
        let now = Date()
        let expiredFrames = frameTimestamps.filter { _, timestamp in
            now.timeIntervalSince(timestamp) > frameTimeout
        }.map { $0.key }
        
        for expiredFrameId in expiredFrames {
            frameBuffers.removeValue(forKey: expiredFrameId)
            expectedChunks.removeValue(forKey: expiredFrameId)
            frameTimestamps.removeValue(forKey: expiredFrameId)
            print("Dropped incomplete frame \(expiredFrameId) due to timeout")
        }
    }
    
    deinit {
        listener?.cancel()
    }
}
