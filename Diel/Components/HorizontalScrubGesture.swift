import SwiftUI
import UIKit

/// Rejects vertical movement before recognition so the enclosing scroll view owns it.
struct HorizontalScrubGesture: UIGestureRecognizerRepresentable {
  let changed: (CGPoint) -> Void
  /// Called once when the finger lifts or the scrub is cancelled.
  var ended: () -> Void = {}

  func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

  func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
    let recognizer = UIPanGestureRecognizer()
    recognizer.maximumNumberOfTouches = 1
    recognizer.cancelsTouchesInView = false
    recognizer.delegate = context.coordinator
    return recognizer
  }

  func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
    if recognizer.state == .began || recognizer.state == .changed || recognizer.state == .ended {
      changed(context.converter.localLocation)
    }
    if recognizer.state == .ended || recognizer.state == .cancelled
      || recognizer.state == .failed
    {
      ended()
    }
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
      let velocity = pan.velocity(in: pan.view)
      return abs(velocity.x) > abs(velocity.y)
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      if let scrollView = otherGestureRecognizer.view as? UIScrollView,
        otherGestureRecognizer === scrollView.panGestureRecognizer
      {
        return true
      }
      return otherGestureRecognizer is UILongPressGestureRecognizer
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      // The full-content back pan waits for a plot scrub to fail, only inside that plot.
      guard let navigation = navigationController(for: gestureRecognizer) else { return false }
      return otherGestureRecognizer === navigation.interactiveContentPopGestureRecognizer
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      // Keep the system's leading-screen-edge back gesture ahead of chart interaction.
      guard let navigation = navigationController(for: gestureRecognizer) else { return false }
      return otherGestureRecognizer === navigation.interactivePopGestureRecognizer
    }

    private func navigationController(for gestureRecognizer: UIGestureRecognizer)
      -> UINavigationController?
    {
      var responder: UIResponder? = gestureRecognizer.view
      while let current = responder {
        if let navigation = current as? UINavigationController { return navigation }
        if let controller = current as? UIViewController,
          let navigation = controller.navigationController
        {
          return navigation
        }
        responder = current.next
      }
      return nil
    }
  }
}

/// Touch feedback stays simultaneous with native scrolling and child controls.
struct CardPressGesture: UIGestureRecognizerRepresentable {
  let changed: (Bool) -> Void

  func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

  func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
    let recognizer = UILongPressGestureRecognizer()
    recognizer.minimumPressDuration = 0
    recognizer.cancelsTouchesInView = false
    recognizer.delegate = context.coordinator
    return recognizer
  }

  func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context)
  {
    switch recognizer.state {
    case .began:
      context.coordinator.start = context.converter.localLocation
      context.coordinator.moved = false
      changed(true)
    case .changed:
      let point = context.converter.localLocation
      let start = context.coordinator.start
      if hypot(point.x - start.x, point.y - start.y) > DesignTokens.Spacing.s8 {
        context.coordinator.moved = true
      }
      changed(!context.coordinator.moved)
    default:
      changed(false)
    }
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var start = CGPoint.zero
    var moved = false
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { true }
  }
}
