import SwiftUI
import UIKit

/// A pan that only begins when the finger moves mostly sideways, so vertical
/// drags still reach the enclosing ScrollView. A SwiftUI DragGesture inside a
/// ScrollView swallows vertical scrolling even as a simultaneous gesture.
struct HorizontalPan: UIGestureRecognizerRepresentable {
    enum Phase {
        /// Points are in global (screen) coordinates.
        case began(start: CGPoint, location: CGPoint)
        case changed(location: CGPoint)
        case ended
    }

    var isEnabled = true
    let action: (Phase) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.maximumNumberOfTouches = 1
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let location = context.converter.location(in: .global)
        switch recognizer.state {
        case .began:
            let t = recognizer.translation(in: recognizer.view)
            action(.began(start: CGPoint(x: location.x - t.x, y: location.y - t.y), location: location))
        case .changed:
            action(.changed(location: location))
        default:
            action(.ended)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}
