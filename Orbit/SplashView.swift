import SwiftUI

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onFinish: () -> Void

    @State private var litColumns = 0
    @State private var trailShown = 0
    @State private var showTile = false
    @State private var showWord = false

    // MARK: - Geometry
    //
    // The grid is the visual anchor, so it's what gets centred. The escaped
    // tile and its trail are drawn as overlays, which means they float
    // outside the grid's bounds without dragging the layout off-centre.

    private let cell: CGFloat = 30
    private let gap: CGFloat = 7
    private let cols = 5
    private let rows = 5
    private let heights = [1, 2, 2, 3, 4]
    private let tileSize: CGFloat = 42

    private var gridWidth: CGFloat { CGFloat(cols) * cell + CGFloat(cols - 1) * gap }
    private var gridHeight: CGFloat { CGFloat(rows) * cell + CGFloat(rows - 1) * gap }

    /// Tile position in bottom-leading coordinates relative to the grid.
    private var tileOrigin: CGPoint {
        CGPoint(x: gridWidth - tileSize * 0.30,
                y: -(gridHeight + tileSize * 0.62))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.172, green: 0.188, blue: 0.416),
                         Color(red: 0.051, green: 0.059, blue: 0.157)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 44) {
                mark
                Text("Orbit")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .opacity(showWord ? 1 : 0)
                    .offset(y: showWord ? 0 : 8)
            }
        }
        .task { await run() }
    }

    // MARK: - Mark

    private var mark: some View {
        grid
            .overlay(alignment: .bottomLeading) {
                ZStack(alignment: .bottomLeading) {
                    // Zero-size anchor so children position from the
                    // grid's bottom-left corner.
                    Color.clear.frame(width: 0, height: 0)

                    ForEach(0..<5, id: \.self) { index in
                        dot(index)
                    }

                    tile
                        .offset(x: tileOrigin.x, y: tileOrigin.y)
                        .scaleEffect(showTile ? 1 : 0.3, anchor: .center)
                        .opacity(showTile ? 1 : 0)
                }
            }
    }

    private var grid: some View {
        VStack(spacing: gap) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<cols, id: \.self) { col in
                        let fromBottom = rows - 1 - row
                        let isLit = fromBottom < heights[col]
                        let revealed = col < litColumns

                        RoundedRectangle(cornerRadius: cell * 0.27, style: .continuous)
                            .fill(isLit && revealed
                                  ? amber(Double(fromBottom) / Double(rows - 1))
                                  : Color.white.opacity(0.11))
                            .frame(width: cell, height: cell)
                            .scaleEffect(isLit && revealed ? 1 : 0.88)
                    }
                }
            }
        }
        .frame(width: gridWidth, height: gridHeight)
    }

    private var tile: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Color(red: 1.0, green: 0.914, blue: 0.706))
            .frame(width: tileSize, height: tileSize)
            .overlay {
                Image(systemName: "checkmark")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Color(red: 0.118, green: 0.129, blue: 0.298))
            }
            .rotationEffect(.degrees(-13))
    }

    /// Fixed-size box keeps differently sized dots centred on the curve
    /// rather than drifting by their corner.
    private func dot(_ index: Int) -> some View {
        let box: CGFloat = 16
        let point = trailPoint(index)
        let diameter = 5 + CGFloat(index) * 1.2

        return Circle()
            .fill(Color(red: 1.0, green: 0.894, blue: 0.682))
            .frame(width: diameter, height: diameter)
            .frame(width: box, height: box)
            .opacity(trailShown > index ? 0.35 + 0.13 * Double(index) : 0)
            .offset(x: point.x - box / 2, y: point.y - box / 2)
    }

    /// Quadratic curve from the top of the tallest column to the tile centre.
    /// Bottom-leading coordinates, so negative y is up.
    private func trailPoint(_ index: Int) -> CGPoint {
        let start = CGPoint(x: gridWidth - cell / 2, y: -(gridHeight - cell * 0.35))
        let end = CGPoint(x: tileOrigin.x + tileSize / 2,
                          y: tileOrigin.y + tileSize / 2)
        let control = CGPoint(x: start.x - cell * 0.55, y: end.y - 22)

        let t = 0.18 + 0.62 * (Double(index) / 4.0)
        let x = pow(1 - t, 2) * start.x + 2 * (1 - t) * t * control.x + pow(t, 2) * end.x
        let y = pow(1 - t, 2) * start.y + 2 * (1 - t) * t * control.y + pow(t, 2) * end.y
        return CGPoint(x: x, y: y)
    }

    private func amber(_ t: Double) -> Color {
        Color(red: (224 + (255 - 224) * t) / 255,
              green: (134 + (212 - 134) * t) / 255,
              blue: (44 + (128 - 44) * t) / 255)
    }

    // MARK: - Timeline

    private func run() async {
        if reduceMotion {
            litColumns = cols
            trailShown = 5
            showTile = true
            showWord = true
            try? await Task.sleep(for: .seconds(0.9))
            onFinish()
            return
        }

        for column in 1...cols {
            withAnimation(.snappy(duration: 0.24)) { litColumns = column }
            try? await Task.sleep(for: .seconds(0.075))
        }

        try? await Task.sleep(for: .seconds(0.08))
        for index in 1...5 {
            withAnimation(.easeOut(duration: 0.16)) { trailShown = index }
            try? await Task.sleep(for: .seconds(0.045))
        }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.6)) { showTile = true }
        try? await Task.sleep(for: .seconds(0.22))
        withAnimation(.easeOut(duration: 0.3)) { showWord = true }

        try? await Task.sleep(for: .seconds(0.65))
        onFinish()
    }
}

#Preview {
    SplashView(onFinish: {})
}
