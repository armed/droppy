import CoreGraphics

enum SplitAxis {
    case horizontal, vertical
}

enum SplitDirection {
    case left, right, up, down

    var axis: SplitAxis {
        switch self {
        case .left, .right: .horizontal
        case .up, .down: .vertical
        }
    }

    var growsFirstChild: Bool { self == .right || self == .down }
}

enum SplitFocusTarget {
    case previous, next, direction(SplitDirection)
}

struct SplitDivider {
    let path: [Bool]
    let axis: SplitAxis
    let splitRect: CGRect
    let rect: CGRect
}

struct SplitLayout<Leaf> {
    var panes: [(leaf: Leaf, frame: CGRect)] = []
    var dividers: [SplitDivider] = []
}

// The first child of a vertical split is the upper one; coordinates are y-up like AppKit.
indirect enum SplitNode<Leaf: AnyObject> {
    case leaf(Leaf)
    case split(axis: SplitAxis, ratio: CGFloat, first: SplitNode<Leaf>, second: SplitNode<Leaf>)

    static var dividerThickness: CGFloat { 1 }
    static var minPaneLength: CGFloat { 80 }

    var leaves: [Leaf] {
        switch self {
        case .leaf(let leaf): [leaf]
        case .split(_, _, let first, let second): first.leaves + second.leaves
        }
    }

    func map<T: AnyObject>(_ transform: (Leaf) -> T) -> SplitNode<T> {
        switch self {
        case .leaf(let leaf):
            return .leaf(transform(leaf))
        case .split(let axis, let ratio, let first, let second):
            return .split(axis: axis, ratio: ratio, first: first.map(transform), second: second.map(transform))
        }
    }

    func contains(_ target: Leaf) -> Bool {
        leaves.contains { $0 === target }
    }

    static func clampedRatio(_ ratio: CGFloat, available: CGFloat) -> CGFloat {
        let minimum = min(minPaneLength / max(available, 1), 0.5)
        return min(max(ratio, minimum), 1 - minimum)
    }

    func inserting(_ new: Leaf, beside target: Leaf, direction: SplitDirection) -> SplitNode {
        switch self {
        case .leaf(let leaf):
            guard leaf === target else { return self }
            let existing = SplitNode.leaf(leaf)
            let added = SplitNode.leaf(new)
            let newComesFirst = !direction.growsFirstChild
            return .split(
                axis: direction.axis,
                ratio: 0.5,
                first: newComesFirst ? added : existing,
                second: newComesFirst ? existing : added
            )
        case .split(let axis, let ratio, let first, let second):
            guard contains(target) else { return self }
            return .split(
                axis: axis,
                ratio: ratio,
                first: first.inserting(new, beside: target, direction: direction),
                second: second.inserting(new, beside: target, direction: direction)
            )
        }
    }

    func removing(_ target: Leaf) -> SplitNode? {
        switch self {
        case .leaf(let leaf):
            return leaf === target ? nil : self
        case .split(let axis, let ratio, let first, let second):
            let newFirst = first.removing(target)
            let newSecond = second.removing(target)
            switch (newFirst, newSecond) {
            case (nil, nil): return nil
            case (nil, let only?): return only
            case (let only?, nil): return only
            case (let a?, let b?): return .split(axis: axis, ratio: ratio, first: a, second: b)
            }
        }
    }

    func sibling(of target: Leaf) -> Leaf? {
        guard case .split(_, _, let first, let second) = self else { return nil }
        if case .leaf(let leaf) = first, leaf === target { return second.leaves.first }
        if case .leaf(let leaf) = second, leaf === target { return first.leaves.last }
        return first.sibling(of: target) ?? second.sibling(of: target)
    }

    func layout(in rect: CGRect) -> SplitLayout<Leaf> {
        var result = SplitLayout<Leaf>()
        collect(in: rect, path: [], into: &result)
        return result
    }

    private func collect(in rect: CGRect, path: [Bool], into result: inout SplitLayout<Leaf>) {
        switch self {
        case .leaf(let leaf):
            result.panes.append((leaf, rect))
        case .split(let axis, let ratio, let first, let second):
            let (a, divider, b) = Self.divide(rect, axis: axis, ratio: ratio)
            result.dividers.append(SplitDivider(path: path, axis: axis, splitRect: rect, rect: divider))
            first.collect(in: a, path: path + [false], into: &result)
            second.collect(in: b, path: path + [true], into: &result)
        }
    }

    static func divide(_ rect: CGRect, axis: SplitAxis, ratio: CGFloat) -> (CGRect, CGRect, CGRect) {
        let thickness = dividerThickness
        switch axis {
        case .horizontal:
            let available = max(rect.width - thickness, 0)
            let firstLength = (available * clampedRatio(ratio, available: available)).rounded()
            return (
                CGRect(x: rect.minX, y: rect.minY, width: firstLength, height: rect.height),
                CGRect(x: rect.minX + firstLength, y: rect.minY, width: thickness, height: rect.height),
                CGRect(x: rect.minX + firstLength + thickness, y: rect.minY, width: available - firstLength, height: rect.height)
            )
        case .vertical:
            let available = max(rect.height - thickness, 0)
            let firstLength = (available * clampedRatio(ratio, available: available)).rounded()
            return (
                CGRect(x: rect.minX, y: rect.maxY - firstLength, width: rect.width, height: firstLength),
                CGRect(x: rect.minX, y: rect.maxY - firstLength - thickness, width: rect.width, height: thickness),
                CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: available - firstLength)
            )
        }
    }

    func settingRatio(_ newRatio: CGFloat, at path: [Bool]) -> SplitNode {
        guard case .split(let axis, let ratio, let first, let second) = self else { return self }
        guard let step = path.first else {
            return .split(axis: axis, ratio: newRatio, first: first, second: second)
        }
        let rest = Array(path.dropFirst())
        return step
            ? .split(axis: axis, ratio: ratio, first: first, second: second.settingRatio(newRatio, at: rest))
            : .split(axis: axis, ratio: ratio, first: first.settingRatio(newRatio, at: rest), second: second)
    }

    // The nearest enclosing split along the direction's axis moves its divider.
    func resizing(
        _ target: Leaf,
        direction: SplitDirection,
        amount: CGFloat,
        in rect: CGRect
    ) -> (node: SplitNode, handled: Bool) {
        guard case .split(let axis, let ratio, let first, let second) = self, contains(target) else {
            return (self, false)
        }
        let (firstRect, _, secondRect) = Self.divide(rect, axis: axis, ratio: ratio)
        if first.contains(target) {
            let inner = first.resizing(target, direction: direction, amount: amount, in: firstRect)
            if inner.handled {
                return (.split(axis: axis, ratio: ratio, first: inner.node, second: second), true)
            }
        } else {
            let inner = second.resizing(target, direction: direction, amount: amount, in: secondRect)
            if inner.handled {
                return (.split(axis: axis, ratio: ratio, first: first, second: inner.node), true)
            }
        }
        guard axis == direction.axis else { return (self, false) }
        let length = axis == .horizontal ? rect.width : rect.height
        let available = max(length - Self.dividerThickness, 1)
        let delta = amount / available * (direction.growsFirstChild ? 1 : -1)
        let updated = Self.clampedRatio(ratio + delta, available: available)
        return (.split(axis: axis, ratio: updated, first: first, second: second), true)
    }

    func equalized() -> SplitNode {
        guard case .split(let axis, _, let first, let second) = self else { return self }
        let firstWeight = first.weight(along: axis)
        let secondWeight = second.weight(along: axis)
        return .split(
            axis: axis,
            ratio: firstWeight / (firstWeight + secondWeight),
            first: first.equalized(),
            second: second.equalized()
        )
    }

    private func weight(along axis: SplitAxis) -> CGFloat {
        switch self {
        case .leaf: 1
        case .split(let own, _, let first, let second):
            own == axis
                ? first.weight(along: axis) + second.weight(along: axis)
                : max(first.weight(along: axis), second.weight(along: axis))
        }
    }

    func adjacent(to target: Leaf, _ focus: SplitFocusTarget, in layout: SplitLayout<Leaf>) -> Leaf? {
        let all = leaves
        guard let index = all.firstIndex(where: { $0 === target }) else { return nil }
        switch focus {
        case .previous: return all[(index + all.count - 1) % all.count]
        case .next: return all[(index + 1) % all.count]
        case .direction(let direction): return Self.neighbor(of: target, direction, in: layout.panes)
        }
    }

    static func neighbor(
        of target: Leaf,
        _ direction: SplitDirection,
        in panes: [(leaf: Leaf, frame: CGRect)]
    ) -> Leaf? {
        guard let origin = panes.first(where: { $0.leaf === target })?.frame else { return nil }
        let tolerance: CGFloat = 1.5
        var best: (leaf: Leaf, gap: CGFloat, overlap: CGFloat)?
        for pane in panes where pane.leaf !== target {
            let frame = pane.frame
            let gap: CGFloat
            let overlap: CGFloat
            switch direction {
            case .right:
                gap = frame.minX - origin.maxX
                overlap = min(frame.maxY, origin.maxY) - max(frame.minY, origin.minY)
            case .left:
                gap = origin.minX - frame.maxX
                overlap = min(frame.maxY, origin.maxY) - max(frame.minY, origin.minY)
            case .up:
                gap = frame.minY - origin.maxY
                overlap = min(frame.maxX, origin.maxX) - max(frame.minX, origin.minX)
            case .down:
                gap = origin.minY - frame.maxY
                overlap = min(frame.maxX, origin.maxX) - max(frame.minX, origin.minX)
            }
            guard gap >= -tolerance, overlap > 0 else { continue }
            if let current = best, (current.gap, -current.overlap) <= (gap, -overlap) { continue }
            best = (pane.leaf, gap, overlap)
        }
        return best?.leaf
    }
}
