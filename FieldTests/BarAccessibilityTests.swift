import Testing
import UIKit
@testable import Field

@MainActor struct BarAccessibilityTests {
    /// Assistive activation has no physical UIEvent. UIControl's eventless
    /// action dispatch exercises the same target/action contract.
    @Test func theAddressCanBeActivatedWithoutATouchEvent() throws {
        let browser = Browser(restoring: false)
        browser.tab.load(URL(string: "https://example.com/")!)
        let controller = FieldSurface(browser: browser)
        controller.loadViewIfNeeded()
        func address(in view: UIView) -> UIButton? {
            if view.accessibilityIdentifier == "bar.address" { return view as? UIButton }
            return view.subviews.lazy.compactMap { address(in: $0) }.first
        }
        let button = try #require(address(in: controller.view))
        #expect(!button.isHidden)
        browser.bar.track(from: 100, to: 160, limit: 1000)
        #expect(browser.bar.amount == 1)
        button.sendActions(for: .touchUpInside)
        #expect(browser.bar.amount == 0)
        #expect(!button.isHidden)
        button.sendActions(for: .touchUpInside)
        #expect(button.isHidden)
    }
    @Test func backgroundingDropsKeyboardCorrections() throws {
        let controller = FieldSurface(browser: Browser(restoring: false))
        controller.loadViewIfNeeded()
        func find(in view: UIView) -> SurfaceView? {
            if let surface = view as? SurfaceView { return surface }
            return view.subviews.lazy.compactMap { find(in: $0) }.first
        }
        let surface = try #require(find(in: controller.view))
        for key in ["keepOnKeyboard", "letKeepGo"] {
            let animation = CABasicAnimation(keyPath: "transform.translation.y")
            animation.fromValue = 20
            animation.toValue = 0
            animation.duration = 1
            surface.layer.add(animation, forKey: key)
        }
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        #expect(surface.layer.animation(forKey: "keepOnKeyboard") == nil)
        #expect(surface.layer.animation(forKey: "letKeepGo") == nil)
    }

    @Test func openingDuringATabGlideEditsTheAdvertisedTab() throws {
        let browser = Browser(restoring: false)
        let first = browser.tabs.current
        first.load(URL(string: "https://first.example/")!)
        let second = browser.tabs.newTab(URL(string: "https://second.example/path")!)
        browser.tabs.select(first)
        let stage = Stage(tabs: browser.tabs, bar: browser.bar, scroller: Scroller(bar: browser.bar))
        stage.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        browser.tabs.stage = stage
        let controller = FieldSurface(browser: browser)
        controller.loadViewIfNeeded()
        func find(in view: UIView) -> SurfaceView? {
            if let surface = view as? SurfaceView { return surface }
            return view.subviews.lazy.compactMap { find(in: $0) }.first
        }
        let surface = try #require(find(in: controller.view))
        stage.switchTab(by: 1)
        #expect(browser.tabs.arriving == second.url)
        surface.bar.address.sendActions(for: .touchDown)
        #expect(browser.tabs.current === first, "touch-down must still allow catching the glide")
        #expect(browser.tabs.arriving == second.url)
        surface.bar.address.sendActions(for: .touchUpInside)
        #expect(browser.tabs.current === second)
        #expect(surface.field.text == "second.example/path")
    }

    /// Put the known rider spring 80 ms into its close, inside the nine-frame
    /// window that separate XCUITest taps cannot reach reliably.
    @Test func anEarlyReopenThenCloseDoesNotStackCorrections() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let browser = Browser(restoring: false)
        browser.tab.load(URL(string: "about:blank")!)
        let controller = FieldSurface(browser: browser)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        func find(in view: UIView) -> SurfaceView? {
            if let surface = view as? SurfaceView { return surface }
            return view.subviews.lazy.compactMap { find(in: $0) }.first
        }
        let surface = try #require(find(in: controller.view))
        let rider = try #require(surface.superview)
        let scrim = try #require(controller.view.subviews.compactMap { $0 as? Scrim }.first)
        #expect(controller.view.safeAreaInsets.bottom > FieldSurface.gap)
        surface.bar.address.sendActions(for: .touchUpInside)
        scrim.cancel()
        let ride = CASpringAnimation(keyPath: "position")
        ride.mass = 1
        ride.stiffness = 555.0265
        ride.damping = 47.118
        ride.duration = 0.3833
        ride.fromValue = NSValue(cgPoint: CGPoint(x: 0, y: -267))
        ride.toValue = NSValue(cgPoint: .zero)
        ride.isAdditive = true
        ride.beginTime = rider.layer.convertTime(CACurrentMediaTime(), from: nil) - 0.08
        rider.layer.add(ride, forKey: "position")
        NotificationCenter.default.post(name: UIResponder.keyboardWillHideNotification, object: nil)
        #expect(surface.layer.animation(forKey: "keepOnKeyboard") != nil)
        surface.bar.address.sendActions(for: .touchUpInside)
        let release = try #require(surface.layer.animation(forKey: "letKeepGo") as? CABasicAnimation)
        #expect((release.fromValue as? Double ?? 0) > 10)
        #expect(release.duration == 0.14)
        #expect(release.isRemovedOnCompletion)
        #expect(surface.layer.animation(forKey: "keepOnKeyboard") == nil)
        scrim.cancel()
        NotificationCenter.default.post(name: UIResponder.keyboardWillHideNotification, object: nil)
        #expect(surface.layer.animation(forKey: "letKeepGo") == nil)
        #expect(surface.layer.animation(forKey: "keepOnKeyboard") != nil)
        controller.viewSafeAreaInsetsDidChange()
        #expect(surface.layer.animation(forKey: "keepOnKeyboard") == nil)
    }

}
