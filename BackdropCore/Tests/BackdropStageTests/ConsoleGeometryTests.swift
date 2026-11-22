import CoreGraphics
import Testing
@testable import BackdropStage

private let sizes: [CGSize] = [CGSize(width: 900, height: 600), CGSize(width: 1280, height: 800), CGSize(width: 2560, height: 1440)]
private let aspects: [CGFloat] = [16 / 9, 4 / 3, 16 / 10]

/// No two frames share any area, and each lies inside the window. Empty
/// frames, for parts not shown, are left out.
private func check(_ frames: [CGRect], in bounds: CGRect, _ where: String) {
    let shown = frames.filter { $0.width > 0 && $0.height > 0 }
    for frame in shown {
        #expect(bounds.contains(frame), "\(frame) is outside \(bounds) (\(`where`))")
    }
    for (i, a) in shown.enumerated() {
        for b in shown[(i + 1)...] {
            let overlap = a.intersection(b)
            #expect(overlap.isNull || overlap.width < 0.5 || overlap.height < 0.5,
                    "\(a) and \(b) overlap (\(`where`))")
        }
    }
}

private func ratio(_ rect: CGRect) -> CGFloat { rect.width / rect.height }

@Suite("Console geometry")
struct ConsoleGeometryTests {
    @Test("The Booth's parts never overlap and stay in the window")
    func boothFits() {
        for size in sizes {
            for rail in [260, 340, 520] as [CGFloat] {
                for bands in [0, 48, 96] as [CGFloat] {
                    let bounds = CGRect(origin: .zero, size: size)
                    let f = ConsoleGeometry.booth(in: bounds, railWidth: rail, outputAspect: 16 / 9, stopBands: bands)
                    // The labels sit over the monitors' columns, the rest down the main column.
                    check([f.header, f.stopBands, f.rail, f.onStageLabel, f.onStage, f.nextLabel, f.next, f.arrow,
                           f.card, f.goPlate, f.keyRow], in: bounds, "\(size), rail \(rail), bands \(bands)")
                }
            }
        }
    }

    @Test("The Booth's monitors keep the projector's shape")
    func boothAspect() {
        for size in sizes {
            for aspect in aspects {
                let f = ConsoleGeometry.booth(in: CGRect(origin: .zero, size: size), railWidth: 340, outputAspect: aspect)
                #expect(abs(ratio(f.onStage) - aspect) < 0.03)
                #expect(f.onStage.size == f.next.size)
            }
        }
    }

    @Test("The Booth at 1280 × 800: the header, the plate and key row at the foot, and the card")
    func boothAt1280() {
        let f = ConsoleGeometry.booth(in: CGRect(x: 0, y: 0, width: 1280, height: 800), railWidth: 340, outputAspect: 16 / 9)
        #expect(f.header.height == 56)
        #expect(f.keyRow.maxY == CGFloat(800 - 24))
        #expect(f.keyRow.height == 24)
        #expect(f.goPlate.height == 94)
        #expect(f.goPlate.maxY == f.keyRow.minY - 12)
        #expect(f.column.minX == CGFloat(340 + 1 + 24))
        #expect(f.card.height >= ConsoleGeometry.cardMinHeight)
        // As wide as the column lets them, with the arrow's room between.
        #expect(f.onStage.width == ((f.column.width - 132) / 2).rounded(.down))
        #expect(f.onStage.minX == f.column.minX)
        #expect(f.next.maxX == f.column.maxX)
    }

    @Test("On a small window the monitors keep their least width before the card keeps its height")
    func boothSmall() {
        let f = ConsoleGeometry.booth(in: CGRect(x: 0, y: 0, width: 1100, height: 600), railWidth: 260, outputAspect: 16 / 9)
        #expect(f.onStage.width >= ConsoleGeometry.monitorMinWidth)
        #expect(f.card.height < ConsoleGeometry.cardMinHeight)
    }

    @Test("The stop bands push everything below them down")
    func boothBands() {
        let bounds = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let without = ConsoleGeometry.booth(in: bounds, railWidth: 340, outputAspect: 16 / 9)
        let with = ConsoleGeometry.booth(in: bounds, railWidth: 340, outputAspect: 16 / 9, stopBands: 40)
        #expect(with.stopBands == CGRect(x: 0, y: 56, width: 1280, height: 40))
        #expect(with.rail.minY == without.rail.minY + 40)
        #expect(with.onStage.minY == without.onStage.minY + 40)
        #expect(with.keyRow == without.keyRow)
    }

    @Test("The card's number grows with the card, from 72 to 104")
    func cardNumber() {
        #expect(ConsoleGeometry.cardNumberSize(forCardHeight: 100) == 72)
        #expect(ConsoleGeometry.cardNumberSize(forCardHeight: 220) == 72)
        #expect(ConsoleGeometry.cardNumberSize(forCardHeight: 270) == 88)
        #expect(ConsoleGeometry.cardNumberSize(forCardHeight: 320) == 104)
        #expect(ConsoleGeometry.cardNumberSize(forCardHeight: 900) == 104)
    }

    @Test("The Studio's parts never overlap and stay in the window")
    func studioFits() {
        for size in sizes {
            for tracks in [nil, 0, 3, 8] as [Int?] {
                for inspector in [300, 350, 640] as [CGFloat] {
                    let bounds = CGRect(origin: .zero, size: size)
                    let f = ConsoleGeometry.studio(in: bounds, railWidth: 340, inspectorWidth: inspector,
                                                   outputAspect: 16 / 9, timelineTracks: tracks)
                    check([f.toolbar, f.stopBands, f.rail, f.canvasHeader, f.canvas, f.timeline, f.joinLine, f.inspector],
                          in: bounds, "\(size), \(tracks.map(String.init) ?? "no") tracks, inspector \(inspector)")
                    #expect(f.middle.width >= ConsoleGeometry.middleMinWidth || f.inspector.width == 0)
                }
            }
        }
    }

    @Test("The Studio's canvas keeps the projector's shape, as large as fits")
    func studioCanvas() {
        for size in sizes {
            for aspect in aspects {
                let f = ConsoleGeometry.studio(in: CGRect(origin: .zero, size: size), railWidth: 340, inspectorWidth: 350,
                                               outputAspect: aspect)
                #expect(abs(ratio(f.canvas) - aspect) < 0.03)
                // Touching one side of the middle or the other.
                #expect(f.canvas.width == f.middle.width.rounded(.down) || abs(f.canvas.maxY - f.middle.maxY) <= 1)
            }
        }
    }

    @Test("The Studio's timeline sits under the canvas, and the canvas shrinks for it")
    func studioTimeline() {
        // Wide enough that the canvas is limited by its height.
        let bounds = CGRect(x: 0, y: 0, width: 1600, height: 800)
        let without = ConsoleGeometry.studio(in: bounds, railWidth: 340, inspectorWidth: 350, outputAspect: 16 / 9)
        let with = ConsoleGeometry.studio(in: bounds, railWidth: 340, inspectorWidth: 350, outputAspect: 16 / 9, timelineTracks: 3)
        #expect(without.timeline == .zero)
        #expect(with.timeline.minY == with.canvas.maxY + 16)
        #expect(with.timeline.height == CGFloat(64 + 3 * 38))
        #expect(with.joinLine.minY == with.timeline.maxY)
        #expect(with.canvas.width < without.canvas.width)
    }

    @Test("On a short window the canvas stops shrinking at 240 wide")
    func studioShort() {
        let f = ConsoleGeometry.studio(in: CGRect(x: 0, y: 0, width: 1280, height: 600), railWidth: 340, inspectorWidth: 350,
                                       outputAspect: 16 / 9, timelineTracks: 8)
        #expect(f.canvas.width == 240)
    }

    @Test("The rail and the Inspector keep to their ranges")
    func widths() {
        let bounds = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let narrow = ConsoleGeometry.studio(in: bounds, railWidth: 100, inspectorWidth: 100, outputAspect: 16 / 9)
        #expect(narrow.rail.width == 260)
        #expect(narrow.inspector.width == 300)
        let wide = ConsoleGeometry.booth(in: bounds, railWidth: 900, outputAspect: 16 / 9)
        #expect(wide.rail.width == 520)
    }
}
