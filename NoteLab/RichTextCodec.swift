import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum RichTextCodec {
    static func encodeRTF(from attributed: AttributedString) -> Data? {
        #if canImport(UIKit)
        let nsAttributed = NSAttributedString(string: String(attributed.characters))
        let range = NSRange(location: 0, length: nsAttributed.length)
        return try? nsAttributed.data(from: range, documentAttributes: [NSAttributedString.DocumentAttributeKey.documentType: NSAttributedString.DocumentType.rtf])
        #else
        return nil
        #endif
    }

    static func decodeRTF(_ data: Data) -> AttributedString {
        #if canImport(UIKit)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf
        ]
        if let nsAttributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return AttributedString(nsAttributed)
        }
        #endif
        return AttributedString("")
    }

    static func plainText(from data: Data?) -> String? {
        guard let data else { return nil }
        return plainText(from: decodeRTF(data))
    }

    static func plainText(from attributed: AttributedString) -> String {
        String(attributed.characters)
    }
}
