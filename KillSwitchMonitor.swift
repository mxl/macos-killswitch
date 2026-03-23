import Foundation
import Darwin

final class KillSwitchMonitor {
    private let startScript: String
    private let debounceInterval: TimeInterval = 0.05
    private var debounceTimer: DispatchSourceTimer?
    private var lastMode: String?
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(startScript: String) {
        self.startScript = startScript
    }

    func run() {
        log("starting routing-socket monitor with script \(startScript)")
        syncNow(reason: "startup")

        let routeSocket = socket(PF_ROUTE, SOCK_RAW, 0)
        guard routeSocket >= 0 else {
            logError("failed to open PF_ROUTE socket")
            exit(1)
        }

        let currentFlags = fcntl(routeSocket, F_GETFL)
        if currentFlags == -1 || fcntl(routeSocket, F_SETFL, currentFlags | O_NONBLOCK) == -1 {
            logError("failed to set PF_ROUTE socket nonblocking mode")
            close(routeSocket)
            exit(1)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: routeSocket, queue: DispatchQueue.global(qos: .utility))
        source.setEventHandler { [weak self] in
            let drained = self?.drainRouteSocket(routeSocket) ?? 0
            self?.log("received \(drained) PF_ROUTE message(s)")
            self?.scheduleSync(reason: "route-event")
        }
        source.setCancelHandler {
            close(routeSocket)
        }
        source.resume()

        log("monitor is waiting for PF_ROUTE events")
        dispatchMain()
    }

    @discardableResult
    private func drainRouteSocket(_ fd: Int32) -> Int {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var messageCount = 0

        while true {
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead > 0 {
                messageCount += 1
                continue
            }

            if bytesRead == 0 {
                logError("PF_ROUTE socket closed")
                return messageCount
            }

            if errno == EWOULDBLOCK || errno == EAGAIN {
                return messageCount
            }

            logError("PF_ROUTE read failed with errno \(errno)")
            return messageCount
        }
    }

    private func scheduleSync(reason: String) {
        debounceTimer?.cancel()
        log("scheduled sync for \(reason) after \(debounceInterval)s debounce")
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + debounceInterval)
        timer.setEventHandler { [weak self] in
            self?.syncNow(reason: reason)
        }
        debounceTimer = timer
        timer.resume()
    }

    private func currentTimestamp() -> String {
        formatter.string(from: Date())
    }

    private func log(_ message: String) {
        print("\(currentTimestamp()) \(message)")
        fflush(stdout)
    }

    private func logError(_ message: String) {
        fputs("\(currentTimestamp()) ERROR: \(message)\n", stderr)
        fflush(stderr)
    }

    private func parseMode(from output: String) -> String? {
        for line in output.split(separator: "\n") {
            if line.hasPrefix("Mode: ") {
                return String(line.dropFirst("Mode: ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func syncNow(reason: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [startScript]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let mode = parseMode(from: output)

            if let mode {
                if let lastMode, lastMode != mode {
                    log("\(reason) transition \(lastMode) -> \(mode)")
                } else if lastMode == nil {
                    log("\(reason) initial mode \(mode)")
                } else {
                    log("\(reason) mode unchanged at \(mode)")
                }
                lastMode = mode
            } else {
                log("\(reason) completed without an explicit mode line")
            }

            if !output.isEmpty {
                for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
                    let text = String(line)
                    if !text.isEmpty {
                        log("\(reason) stdout: \(text)")
                    }
                }
            }
            if !error.isEmpty {
                for line in error.split(separator: "\n", omittingEmptySubsequences: false) {
                    let text = String(line)
                    if !text.isEmpty {
                        logError("\(reason) stderr: \(text)")
                    }
                }
            }
            if process.terminationStatus != 0 {
                logError("\(reason) start-killswitch exited with status \(process.terminationStatus)")
            }
        } catch {
            logError("\(reason) failed to run start-killswitch: \(error)")
        }
    }
}

let startScript: String
if CommandLine.arguments.count > 1 {
    startScript = CommandLine.arguments[1]
} else {
    startScript = "/usr/local/libexec/killswitch/killswitch"
}

setvbuf(stdout, nil, _IOLBF, 0)
setvbuf(stderr, nil, _IONBF, 0)

let monitor = KillSwitchMonitor(startScript: startScript)
monitor.run()
