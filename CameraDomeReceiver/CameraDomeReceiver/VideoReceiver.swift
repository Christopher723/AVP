import Foundation
import Network
import Combine

class UDPReceiver: ObservableObject {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "UDPReceiverQueue")
    @Published var receivedFrameData = Data()
    private var frameBuffers: [UInt32: [UInt16: Data]] = [:]
        private var expectedChunks: [UInt32: UInt16] = [:]

        private func processReceivedData(_ data: Data) {
            guard data.count > 9 else { return }

            let frameId = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            let chunkIndex = data[4..<6].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            let totalChunks = data[6..<8].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            let streamId = data[8]
            let frameData = data.subdata(in: 9..<data.count)

            guard streamId == 2 else { return }

            // Buffer the chunk
            if frameBuffers[frameId] == nil {
                frameBuffers[frameId] = [:]
                expectedChunks[frameId] = totalChunks
            }
            frameBuffers[frameId]?[chunkIndex] = frameData

            // Check if all chunks received
            if let buffer = frameBuffers[frameId], buffer.count == Int(totalChunks) {
                // Reassemble
                var fullData = Data()
                for i in 0..<totalChunks {
                    if let chunk = buffer[i] {
                        fullData.append(chunk)
                    } else {
                        // Missing chunk, abort
                        return
                    }
                }
                DispatchQueue.main.async { [weak self] in
                    self?.receivedFrameData = fullData
                }
                // Clean up
                frameBuffers.removeValue(forKey: frameId)
                expectedChunks.removeValue(forKey: frameId)
            }
        }

    init(port: UInt16) {
        setupListener(port: port)
    }

    private func setupListener(port: UInt16) {
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true

        do {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                print("Invalid port number: \(port)")
                return
            }

            listener = try NWListener(using: parameters, on: nwPort)

            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("UDP Listener ready on port \(port)")
                case .failed(let error):
                    print("UDP Listener failed: \(error)")
                case .cancelled:
                    print("UDP Listener cancelled")
                default: break
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

    deinit {
        listener?.cancel()
    }
}
