import Foundation

struct TableModel: Codable, Equatable {
    var rows: Int
    var cols: Int
    var cells: [[String]]

    init(rows: Int, cols: Int) {
        self.rows = max(1, rows)
        self.cols = max(1, cols)
        let row = Array(repeating: "", count: self.cols)
        self.cells = Array(repeating: row, count: self.rows)
    }

    mutating func addRow() {
        let row = Array(repeating: "", count: cols)
        cells.append(row)
        rows = cells.count
    }

    mutating func removeRow() {
        guard rows > 1 else { return }
        cells.removeLast()
        rows = cells.count
    }

    mutating func addColumn() {
        for idx in cells.indices {
            cells[idx].append("")
        }
        cols = cells.first?.count ?? 0
    }

    mutating func removeColumn() {
        guard cols > 1 else { return }
        for idx in cells.indices {
            if !cells[idx].isEmpty {
                cells[idx].removeLast()
            }
        }
        cols = cells.first?.count ?? 0
    }

    var plainText: String {
        cells.map { $0.joined(separator: "\t") }.joined(separator: "\n")
    }
}
