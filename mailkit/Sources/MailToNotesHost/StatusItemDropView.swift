import AppKit

enum MenuBarConversionState {
    case idle
    case receiving
    case converting
    case succeeded
    case failed
}

final class StatusItemDropView: NSView {
    var onDropFiles: (([URL]) -> Void)?
    var onMailMessageDrop: (() -> Bool)?
    var onStatusChange: ((String) -> Void)?
    var onDebugLog: ((String) -> Void)?
    var onClick: (() -> Void)?
    var onSymbolChange: ((String, String) -> Void)?

    var conversionState: MenuBarConversionState = .idle {
        didSet { updateImage() }
    }

    var statusText = "Ready — drag Mail messages here" {
        didSet { toolTip = statusText }
    }

    private var isDropTargeted = false
    private lazy var receiver: EMLDropReceiver = {
        let receiver = EMLDropReceiver()
        receiver.onDropFiles = { [weak self] urls in self?.onDropFiles?(urls) }
        receiver.onMailMessageDrop = { [weak self] in self?.onMailMessageDrop?() ?? false }
        receiver.onStatusChange = { [weak self] status in
            self?.statusText = status
            self?.onStatusChange?(status)
        }
        receiver.onDebugLog = { [weak self] message in self?.onDebugLog?(message) }
        return receiver
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard receiver.accepts(sender) else {
            return []
        }

        isDropTargeted = true
        updateImage()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        receiver.accepts(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTargeted = false
        updateImage()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTargeted = false
        let accepted = receiver.perform(sender)
        updateImage()
        return accepted
    }

    private func setup() {
        registerForDraggedTypes(EMLDropReceiver.registeredPasteboardTypes)
        toolTip = statusText
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("pdfmail menu. Drag Mail messages here to convert them.")

        updateImage()
    }

    private func updateImage() {
        let symbolName: String
        let accessibilityDescription: String

        if isDropTargeted {
            symbolName = "tray.and.arrow.down.fill"
            accessibilityDescription = "Drop email to convert"
        } else {
            switch conversionState {
            case .idle:
                symbolName = "envelope"
                accessibilityDescription = "pdfmail"
            case .receiving:
                symbolName = "tray.and.arrow.down"
                accessibilityDescription = "Receiving email"
            case .converting:
                symbolName = "arrow.triangle.2.circlepath"
                accessibilityDescription = "Converting email"
            case .succeeded:
                symbolName = "checkmark.circle"
                accessibilityDescription = "Email conversion complete"
            case .failed:
                symbolName = "exclamationmark.triangle"
                accessibilityDescription = "Email conversion failed"
            }
        }

        onSymbolChange?(symbolName, accessibilityDescription)
    }
}
