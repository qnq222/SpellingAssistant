import Foundation

struct WordCorrection: Equatable, Identifiable, Codable {
    let id: UUID
    let original: String
    let corrected: String

    init(id: UUID = UUID(), original: String, corrected: String) {
        self.id = id
        self.original = original
        self.corrected = corrected
    }

    static func == (lhs: WordCorrection, rhs: WordCorrection) -> Bool {
        lhs.original == rhs.original && lhs.corrected == rhs.corrected
    }
}
