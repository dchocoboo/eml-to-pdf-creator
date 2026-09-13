import AppKit

final class EMLDropReceiver {
    static let registeredPasteboardTypes: [NSPasteboard.PasteboardType] = {
        let promisedTypes = NSFilePromiseReceiver.readableDraggedTypes
            .map { NSPasteboard.PasteboardType($0) }
        return [.fileURL, NSPasteboard.PasteboardType("NSFilesPromisePboardType")] + promisedTypes
    }()

    var onDropFiles: (([URL]) -> Void)?
    var onMailMessageDrop: (() -> Bool)?
    var onStatusChange: ((String) -> Void)?
    var onDebugLog: ((String) -> Void)?

    private let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "pdfmail promised file receiver"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var pendingPromiseReceivers: [NSFilePromiseReceiver] = []

    func accepts(_ sender: NSDraggingInfo) -> Bool {
        fileURLs(from: sender).contains { $0.pathExtension.lowercased() == "eml" }
            || isMailMessageDrop(sender)
            || !filePromiseReceivers(from: sender).isEmpty
    }

    func perform(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender).filter { $0.pathExtension.lowercased() == "eml" }
        if !urls.isEmpty {
            onDropFiles?(urls)
            return true
        }

        if isMailMessageDrop(sender), onMailMessageDrop?() == true {
            return true
        }

        return receivePromisedFiles(from: sender)
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        guard let values = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return []
        }

        return values
    }

    private func filePromiseReceivers(from sender: NSDraggingInfo) -> [NSFilePromiseReceiver] {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        ) as? [NSFilePromiseReceiver] ?? []
    }

    private func isMailMessageDrop(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.types?.contains {
            $0.rawValue.localizedCaseInsensitiveContains("com.apple.mail")
        } ?? false
    }

    private func receivePromisedFiles(from sender: NSDraggingInfo) -> Bool {
        let receivers = filePromiseReceivers(from: sender)
        guard !receivers.isEmpty else {
            return false
        }

        onStatusChange?("Receiving files from Mail...")
        pendingPromiseReceivers = receivers
        let pasteboardTypes = sender.draggingPasteboard.types?
            .map { $0.rawValue }
            .joined(separator: ", ") ?? "none"
        let promisedTypes = receivers.flatMap { $0.fileTypes }
            .joined(separator: ", ")
        onDebugLog?("Drop pasteboard types: \(pasteboardTypes)")
        onDebugLog?("Mail promised file types: \(promisedTypes)")

        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdfmailDrops-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: destinationURL,
                withIntermediateDirectories: true
            )
        } catch {
            onStatusChange?("Could not prepare drop folder: \(error.localizedDescription)")
            return false
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var receivedURLs: [URL] = []
        var errors: [Error] = []

        for receiver in receivers {
            group.enter()
            receiver.receivePromisedFiles(
                atDestination: destinationURL,
                options: [:],
                operationQueue: promiseQueue
            ) { fileURL, error in
                lock.lock()
                receivedURLs.append(fileURL)
                if let error {
                    errors.append(error)
                }
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else {
                return
            }

            let emlURLs = receivedURLs.filter { $0.pathExtension.lowercased() == "eml" }
            let receivedPaths = receivedURLs.map { $0.path }.joined(separator: ", ")
            self.onDebugLog?("Received promised files: \(receivedPaths)")
            self.pendingPromiseReceivers = []
            if !emlURLs.isEmpty {
                self.onDropFiles?(emlURLs)
            } else if let error = errors.first {
                self.onStatusChange?("Could not receive Mail file: \(error.localizedDescription)")
                self.onDebugLog?("Promise receive error: \(error.localizedDescription)")
            } else {
                self.onStatusChange?("Mail did not provide an .eml file.")
            }
        }

        return true
    }
}
