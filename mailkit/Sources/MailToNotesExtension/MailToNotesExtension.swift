import Foundation
import MailKit

final class MailToNotesExtension: NSObject, MEExtension {
    func handlerForMessageActions() -> any MEMessageActionHandler {
        MessageActionHandler.shared
    }
}

final class MessageActionHandler: NSObject, MEMessageActionHandler {
    static let shared = MessageActionHandler()

    func decideAction(
        for message: MEMessage,
        completionHandler: @escaping (MEMessageActionDecision?) -> Void
    ) {
        guard isPurchaseCandidate(message) else {
            completionHandler(nil)
            return
        }

        guard let rawData = message.rawData else {
            completionHandler(.invokeAgainWithBody)
            return
        }

        do {
            try MessageExporter().export(message: message, rawData: rawData)
            completionHandler(.action(.setBackgroundColor(markColor())))
        } catch {
            NSLog("pdfmail failed to export message: \(error.localizedDescription)")
            completionHandler(nil)
        }
    }

    private func isPurchaseCandidate(_ message: MEMessage) -> Bool {
        let haystack = [
            message.subject,
            message.fromAddress.rawString,
            message.fromAddress.addressString ?? ""
        ].joined(separator: " ").lowercased()

        return MailToNotesSettings.keywords.contains { haystack.contains($0) }
    }

    private func markColor() -> MEMessageAction.MessageColor {
        switch MailToNotesSettings.markColor {
        case "blue":
            return .blue
        case "gray":
            return .gray
        case "orange":
            return .orange
        case "purple":
            return .purple
        case "red":
            return .red
        case "yellow":
            return .yellow
        default:
            return .green
        }
    }
}

private struct QueuedMessageMetadata: Encodable {
    let subject: String
    let from: String
    let dateReceived: TimeInterval?
    let messageID: String?
    let emlFile: String
}

private struct MessageExporter {
    func export(message: MEMessage, rawData: Data) throws {
        let queueDirectory = try ensureQueueDirectory()
        let fileBase = fileBaseName(for: message)
        let emlURL = queueDirectory.appendingPathComponent("\(fileBase).eml")
        let metadataURL = queueDirectory.appendingPathComponent("\(fileBase).json")

        if FileManager.default.fileExists(atPath: emlURL.path) {
            return
        }

        try rawData.write(to: emlURL, options: .atomic)

        let metadata = QueuedMessageMetadata(
            subject: message.subject,
            from: message.fromAddress.rawString,
            dateReceived: nil,
            messageID: message.headers?["message-id"]?.first,
            emlFile: emlURL.lastPathComponent
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata).write(to: metadataURL, options: .atomic)
    }

    private func ensureQueueDirectory() throws -> URL {
        let queueDirectory = MailToNotesSettings.applicationSupportDirectory
            .appendingPathComponent(MailToNotesSettings.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("Incoming", isDirectory: true)

        try FileManager.default.createDirectory(
            at: queueDirectory,
            withIntermediateDirectories: true
        )

        return queueDirectory
    }

    private func fileBaseName(for message: MEMessage) -> String {
        let date = Date()
        let dateStamp = Self.dateFormatter.string(from: date)
        let identity = message.headers?["message-id"]?.first ?? "\(message.fromAddress.rawString)-\(message.subject)-\(date.timeIntervalSince1970)"
        return "\(dateStamp)-\(sanitize(identity))"
    }

    private func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars).replacingOccurrences(
            of: "-+",
            with: "-",
            options: .regularExpression
        )
        return String(collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(80))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
