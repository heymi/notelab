import Foundation
import Combine

final class TitleFocusBridge: ObservableObject {
    @Published var requestFocus: Bool = false
}
