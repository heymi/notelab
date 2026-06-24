import Foundation

enum EditorCommand: Equatable {
    case paragraph
    case heading(level: Int)
    case bullet
    case numbered
    case todo
    case quote
    case code
    case table(rows: Int, cols: Int)
    case requestAttachment
    case insertAttachment(data: Data, type: AttachmentType, fileName: String)
    case bold
    case italic
    case inlineCode
    case increaseFontSize
    case decreaseFontSize
}

struct EditorCommandRequest: Equatable {
    let id: UUID
    let command: EditorCommand

    init(id: UUID = UUID(), command: EditorCommand) {
        self.id = id
        self.command = command
    }
}
