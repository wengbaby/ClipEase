import SwiftUI

struct CheckerboardView: View {
    private let cellSize: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let columns = Int(size.width / cellSize) + 1
            let rows = Int(size.height / cellSize) + 1

            for row in 0..<rows {
                for column in 0..<columns {
                    let isTinted = (row + column).isMultiple(of: 2)
                    let rect = CGRect(
                        x: CGFloat(column) * cellSize,
                        y: CGFloat(row) * cellSize,
                        width: cellSize,
                        height: cellSize
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isTinted ? Color.gray.opacity(0.12) : Color.white)
                    )
                }
            }
        }
    }
}

