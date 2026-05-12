import SwiftUI
import AppKit
import Observation

@main
struct UsagiApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

	var body: some Scene {
		// All UI is driven by the AppDelegate's NSStatusItem + NSMenu.
		Settings { EmptyView() }
	}
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	private var statusItem: NSStatusItem!
	private var menu: NSMenu!
	private var appState: AppState!
	private var settingsWindow: NSWindow?
	private var redrawTimer: Timer?

	func applicationDidFinishLaunching(_: Notification) {
		// Menu-bar only — no dock icon.
		NSApp.setActivationPolicy(.accessory)

		appState = AppState()

		Task { @MainActor in
			await appState.load()
		}

		// A real NSMenu — opens instantly with native highlighting, key
		// equivalents, and dismissal. Its first item hosts the SwiftUI usage
		// bars; the rest are standard menu items, rebuilt per state in
		// menuNeedsUpdate(_:).
		menu = NSMenu()
		menu.delegate = self
		menu.autoenablesItems = false

		statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		statusItem.button?.image = makeStatusImage(usage: nil, remaining: nil, percent: nil, error: false)
		statusItem.menu = menu

		// Update the menu bar whenever AppState changes...
		observeMenuBar()
		// ...and once a minute regardless, so the time-remaining bar keeps draining
		// even between (or through failed) network refreshes.
		let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
			Task { @MainActor [weak self] in self?.updateMenuBarTitle() }
		}
		RunLoop.main.add(timer, forMode: .common)
		redrawTimer = timer

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleOpenSettings),
			name: .openSettings,
			object: nil
		)
	}

	// MARK: - Menu

	private func actionItem(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
		let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
		item.target = self
		return item
	}

	@objc private func handleSignIn() { appState.presentSignIn() }
	@objc private func handleSignOut() { appState.signOut() }
	@objc private func handleRetry() { Task { await appState.refresh() } }
	@objc private func handleQuit() { NSApplication.shared.terminate(nil) }

	@objc private func handleOpenSettings() {
		if let settingsWindow {
			settingsWindow.makeKeyAndOrderFront(nil)
			NSApp.activate(ignoringOtherApps: true)
			return
		}

		let host = NSHostingController(rootView: SettingsView(appState: appState))
		let window = NSWindow(contentViewController: host)
		window.title = "usagi Settings"
		window.styleMask = [.titled, .closable]
		window.setContentSize(NSSize(width: 460, height: 620))
		window.center()
		window.isReleasedWhenClosed = false
		window.delegate = self
		window.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		settingsWindow = window
	}

	// MARK: - Menu bar

	private func observeMenuBar() {
		updateMenuBarTitle()
		// Observation is per-access; re-register after each callback.
		withObservationTracking {
			_ = appState.menuBarTick
			_ = appState.phase
			_ = appState.snapshot
			_ = appState.showPercentInBars
		} onChange: { [weak self] in
			Task { @MainActor [weak self] in
				self?.updateMenuBarTitle()
				self?.observeMenuBar()
			}
		}
	}

	private func updateMenuBarTitle() {
		guard let button = statusItem?.button else { return }
		let isError: Bool = { if case .error = appState.phase { return true } else { return false } }()
		let image = makeStatusImage(
			usage: appState.sessionUsageFraction,
			remaining: appState.sessionTimeRemainingFraction,
			percent: appState.showPercentInBars ? appState.menuBarPercent : nil,
			error: isError,
			signedOut: appState.phase == .signedOut
		)
		let label = accessibilityLabel()
		image.accessibilityDescription = label
		button.image = image
		button.title = ""
		button.setAccessibilityLabel(label)
	}

	/// VoiceOver text for the status item — a short summary of the current state.
	private func accessibilityLabel() -> String {
		switch appState.phase {
		case .ready:
			var parts: [String] = []
			if let s = appState.snapshot?.fiveHour { parts.append("session \(Int(s.utilization.rounded()))%") }
			if let w = appState.snapshot?.sevenDay { parts.append("weekly \(Int(w.utilization.rounded()))%") }
			return "Claude usage — " + (parts.isEmpty ? "no data" : parts.joined(separator: ", "))
		case .signedOut:                 return "Claude usage — not signed in"
		case .error:                     return "Claude usage — failed to load"
		case .bootstrapping, .loading:   return "Claude usage — loading"
		}
	}

	/// Colour-codes the usage bar: green while there's plenty left, ramping
	/// through yellow and orange to red as the session quota fills.
	private static func usageColor(_ fraction: Double) -> NSColor {
		switch fraction {
		case ..<0.5:  return .systemGreen
		case ..<0.75: return .systemYellow
		case ..<0.9:  return .systemOrange
		default:      return .systemRed
		}
	}

	/// The countdown dial's colour: neutral while there's comfortably time left in
	/// the 5-hour window, warming to yellow then orange in the final minutes.
	private static func dialColor(_ remaining: Double?) -> NSColor {
		guard let f = remaining else { return .labelColor }
		switch f {
		case ..<0.033: return .systemOrange   // ≲ 10 min left
		case ..<0.10:  return .systemYellow   // ≲ 30 min left
		default:       return .labelColor
		}
	}

	/// The status-item image: a pie that empties clockwise as the 5-hour session
	/// window nears reset, next to a battery-style usage bar — a rounded-rect whose
	/// fill grows and shifts colour with usage, with the exact percent printed
	/// inside it. The dial warms to yellow/orange in the final minutes; on error it
	/// collapses to a red dot; when signed out it's a dimmed, slashed ring.
	private func makeStatusImage(usage: Double?, remaining: Double?, percent: String?, error: Bool, signedOut: Bool = false) -> NSImage {
		let height: CGFloat = 22
		let dialW: CGFloat = 15, dialH: CGFloat = 16
		let gap: CGFloat = 4
		let barW: CGFloat = 38, barH: CGFloat = 17
		let width = dialW + gap + barW

		let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
			let ink = NSColor.labelColor
			let stroke: CGFloat = 1.6

			// Draws `s` centred in `rect`, in white with a soft dark halo so it
			// stays legible over the colour-coded bar fill.
			func centeredLabel(_ s: String, in rect: NSRect, fontSize: CGFloat) {
				let shadow = NSShadow()
				shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
				shadow.shadowBlurRadius = 1.5
				shadow.shadowOffset = .zero
				let attrs: [NSAttributedString.Key: Any] = [
					.font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
					.foregroundColor: NSColor.white,
					.shadow: shadow,
				]
				let text = s as NSString
				let sz = text.size(withAttributes: attrs)
				text.draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2 + 0.5),
				          withAttributes: attrs)
			}

			// Left: a countdown dial — a disc that empties clockwise as the 5-hour
			// window nears reset, warming yellow→orange in the final minutes. On error
			// it collapses to a red dot.
			let slot = NSRect(x: 0, y: (height - dialH) / 2, width: dialW, height: dialH)
				.insetBy(dx: stroke / 2 + 0.5, dy: stroke / 2 + 0.5)
			let diameter = min(slot.width, slot.height)
			let dial = NSRect(x: slot.midX - diameter / 2, y: slot.midY - diameter / 2,
			                  width: diameter, height: diameter)
			if signedOut {
				// A dimmed, slashed ring — reads as "not connected", not "0% used".
				NSColor.labelColor.withAlphaComponent(0.4).setStroke()
				let ring = NSBezierPath(ovalIn: dial)
				ring.lineWidth = stroke
				ring.stroke()
				let slash = NSBezierPath()
				slash.move(to: NSPoint(x: dial.minX + dial.width * 0.18, y: dial.maxY - dial.height * 0.18))
				slash.line(to: NSPoint(x: dial.maxX - dial.width * 0.18, y: dial.minY + dial.height * 0.18))
				slash.lineWidth = stroke
				slash.stroke()
				return true
			}
			if error {
				NSColor.systemRed.setFill()
				let dot = dial.width * 0.6
				NSBezierPath(ovalIn: NSRect(x: dial.midX - dot / 2, y: dial.midY - dot / 2,
				                            width: dot, height: dot)).fill()
			} else {
				let dialInk = AppDelegate.dialColor(remaining)
				if let rf = remaining {
					let f = CGFloat(min(1, max(0, rf)))           // fraction of the window left
					dialInk.setFill()
					if f >= 1 {
						NSBezierPath(ovalIn: dial).fill()
					} else if f > 0 {
						// A wedge anchored at 12 o'clock, sweeping clockwise by f·360°,
						// so it shrinks back toward the top edge as the window drains.
						let center = NSPoint(x: dial.midX, y: dial.midY)
						let wedge = NSBezierPath()
						wedge.move(to: center)
						wedge.line(to: NSPoint(x: center.x, y: dial.maxY))
						wedge.appendArc(withCenter: center, radius: dial.width / 2,
						                startAngle: 90, endAngle: 90 - f * 360, clockwise: true)
						wedge.close()
						wedge.fill()
					}
					// f == 0 → no fill; the outline ring below shows an empty dial.
				}
				let ring = NSBezierPath(ovalIn: dial)
				ring.lineWidth = stroke
				dialInk.setStroke()
				ring.stroke()
			}

			// Right: battery-style usage gauge — an outline rounded-rect (so it
			// always reads as a bar over any menu-bar background), a colour-coded
			// fill, and the exact percent printed inside.
			let barRect = NSRect(x: dialW + gap, y: (height - barH) / 2, width: barW, height: barH)
				.insetBy(dx: stroke / 2 + 0.5, dy: stroke / 2 + 0.5)
			let r: CGFloat = 4
			if let f = usage, f > 0 {
				let pad: CGFloat = 2.2
				let innerW = barRect.width - pad * 2
				let innerH = barRect.height - pad * 2
				let w = max(2, min(innerW, innerW * CGFloat(f)))
				let fr = max(0.5, min(r - pad, w / 2))
				AppDelegate.usageColor(f).setFill()
				NSBezierPath(roundedRect: NSRect(x: barRect.minX + pad, y: barRect.minY + pad,
				                                 width: w, height: innerH), xRadius: fr, yRadius: fr).fill()
			}
			let outline = NSBezierPath(roundedRect: barRect, xRadius: r, yRadius: r)
			outline.lineWidth = stroke
			ink.setStroke()
			outline.stroke()
			if let percent { centeredLabel(percent, in: barRect, fontSize: 8.5) }
			return true
		}
		image.isTemplate = false
		return image
	}
}

/// Anthropic's "burst" brand mark, drawn from its single SVG path so we ship no
/// asset files. Used as the popover's header glyph.
enum ClaudeMark {
	/// The mark's path data (viewBox 0 0 100 100), y-down as in SVG.
	private static let pathData = "m19.6 66.5 19.7-11 .3-1-.3-.5h-1l-3.3-.2-11.2-.3L14 53l-9.5-.5-2.4-.5L0 49l.2-1.5 2-1.3 2.9.2 6.3.5 9.5.6 6.9.4L38 49.1h1.6l.2-.7-.5-.4-.4-.4L29 41l-10.6-7-5.6-4.1-3-2-1.5-2-.6-4.2 2.7-3 3.7.3.9.2 3.7 2.9 8 6.1L37 36l1.5 1.2.6-.4.1-.3-.7-1.1L33 25l-6-10.4-2.7-4.3-.7-2.6c-.3-1-.4-2-.4-3l3-4.2L28 0l4.2.6L33.8 2l2.6 6 4.1 9.3L47 29.9l2 3.8 1 3.4.3 1h.7v-.5l.5-7.2 1-8.7 1-11.2.3-3.2 1.6-3.8 3-2L61 2.6l2 2.9-.3 1.8-1.1 7.7L59 27.1l-1.5 8.2h.9l1-1.1 4.1-5.4 6.9-8.6 3-3.5L77 13l2.3-1.8h4.3l3.1 4.7-1.4 4.9-4.4 5.6-3.7 4.7-5.3 7.1-3.2 5.7.3.4h.7l12-2.6 6.4-1.1 7.6-1.3 3.5 1.6.4 1.6-1.4 3.4-8.2 2-9.6 2-14.3 3.3-.2.1.2.3 6.4.6 2.8.2h6.8l12.6 1 3.3 2 1.9 2.7-.3 2-5.1 2.6-6.8-1.6-16-3.8-5.4-1.3h-.8v.4l4.6 4.5 8.3 7.5L89 80.1l.5 2.4-1.3 2-1.4-.2-9.2-7-3.6-3-8-6.8h-.5v.7l1.8 2.7 9.8 14.7.5 4.5-.7 1.4-2.6 1-2.7-.6-5.8-8-6-9-4.7-8.2-.5.4-2.9 30.2-1.3 1.5-3 1.2-2.5-2-1.4-3 1.4-6.2 1.6-8 1.3-6.4 1.2-7.9.7-2.6v-.2H49L43 72l-9 12.3-7.2 7.6-1.7.7-3-1.5.3-2.8L24 86l10-12.8 6-7.9 4-4.6-.1-.5h-.3L17.2 77.4l-4.7.6-2-2 .2-3 1-1 8-5.5Z"

	private static let bezier = SVGPath.parse(pathData)

	/// Fills the mark, scaled to fit `rect` (minus `inset`) and y-flipped to
	/// AppKit's coordinate space, using the current fill colour.
	static func draw(in rect: NSRect, inset: CGFloat = 1) {
		let b = bezier.bounds
		let scale = min((rect.width - 2 * inset) / b.width, (rect.height - 2 * inset) / b.height)
		let drawnW = b.width * scale, drawnH = b.height * scale
		var t = AffineTransform()
		t.translate(x: rect.minX + (rect.width - drawnW) / 2, y: rect.minY + (rect.height - drawnH) / 2)
		t.scale(scale)
		t.translate(x: -b.minX, y: -b.minY)
		t.translate(x: b.minX, y: b.minY + b.height)
		t.scale(x: 1, y: -1)
		t.translate(x: -b.minX, y: -b.minY)
		let glyph = bezier.copy() as! NSBezierPath
		glyph.transform(using: t)
		glyph.fill()
	}

	/// A square template `NSImage` of the mark — tints to its surroundings.
	static func image(side: CGFloat) -> NSImage {
		let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
			NSColor.black.setFill()
			draw(in: rect)
			return true
		}
		img.isTemplate = true
		return img
	}
}

/// Minimal SVG path-data parser: supports the M/m, L/l, H/h, V/v, C/c, Z/z commands used by the Claude mark.
private enum SVGPath {
	static func parse(_ d: String) -> NSBezierPath {
		let path = NSBezierPath()
		var current = NSPoint.zero
		var start = NSPoint.zero
		var idx = d.startIndex
		var command: Character = " "

		func skipSeparators() {
			while idx < d.endIndex, d[idx] == " " || d[idx] == "," || d[idx] == "\n" || d[idx] == "\t" { idx = d.index(after: idx) }
		}
		func readNumber() -> CGFloat {
			skipSeparators()
			var s = ""
			var sawDot = false
			if idx < d.endIndex, d[idx] == "-" || d[idx] == "+" { s.append(d[idx]); idx = d.index(after: idx) }
			while idx < d.endIndex {
				let c = d[idx]
				if c == "." {
					if sawDot { break } // a second dot begins a new number
					sawDot = true
					s.append(c); idx = d.index(after: idx)
				} else if c.isNumber {
					s.append(c); idx = d.index(after: idx)
				} else {
					break // separator, sign, or command letter ends the number
				}
			}
			return CGFloat(Double(s) ?? 0)
		}
		func hasMoreArgs() -> Bool {
			skipSeparators()
			guard idx < d.endIndex else { return false }
			let c = d[idx]
			return c.isNumber || c == "-" || c == "+" || c == "."
		}

		while idx < d.endIndex {
			skipSeparators()
			guard idx < d.endIndex else { break }
			if d[idx].isLetter {
				command = d[idx]
				idx = d.index(after: idx)
			}
			let relative = command.isLowercase
			switch command.lowercased().first! {
			case "m":
				let x = readNumber(), y = readNumber()
				current = relative ? NSPoint(x: current.x + x, y: current.y + y) : NSPoint(x: x, y: y)
				path.move(to: current)
				start = current
				command = relative ? "l" : "L" // subsequent pairs are implicit linetos
				while hasMoreArgs() {
					let lx = readNumber(), ly = readNumber()
					current = relative ? NSPoint(x: current.x + lx, y: current.y + ly) : NSPoint(x: lx, y: ly)
					path.line(to: current)
				}
			case "l":
				repeat {
					let x = readNumber(), y = readNumber()
					current = relative ? NSPoint(x: current.x + x, y: current.y + y) : NSPoint(x: x, y: y)
					path.line(to: current)
				} while hasMoreArgs()
			case "h":
				repeat {
					let x = readNumber()
					current = relative ? NSPoint(x: current.x + x, y: current.y) : NSPoint(x: x, y: current.y)
					path.line(to: current)
				} while hasMoreArgs()
			case "v":
				repeat {
					let y = readNumber()
					current = relative ? NSPoint(x: current.x, y: current.y + y) : NSPoint(x: current.x, y: y)
					path.line(to: current)
				} while hasMoreArgs()
			case "c":
				repeat {
					let c1x = readNumber(), c1y = readNumber()
					let c2x = readNumber(), c2y = readNumber()
					let ex = readNumber(), ey = readNumber()
					let cp1 = relative ? NSPoint(x: current.x + c1x, y: current.y + c1y) : NSPoint(x: c1x, y: c1y)
					let cp2 = relative ? NSPoint(x: current.x + c2x, y: current.y + c2y) : NSPoint(x: c2x, y: c2y)
					current = relative ? NSPoint(x: current.x + ex, y: current.y + ey) : NSPoint(x: ex, y: ey)
					path.curve(to: current, controlPoint1: cp1, controlPoint2: cp2)
				} while hasMoreArgs()
			case "z":
				path.close()
				current = start
			default:
				// Unsupported command (none expected in the Claude mark); bail to avoid an infinite loop.
				return path
			}
		}
		return path
	}
}

extension AppDelegate: NSMenuDelegate {
	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()

		// The usage bars (or a sign-in prompt / spinner / error) as a
		// non-interactive header. A fresh hosting view each time keeps it simple;
		// the SwiftUI content has no controls of its own.
		let host = NSHostingView(rootView: MenuBarPopover(appState: appState))
		host.layoutSubtreeIfNeeded()
		host.frame.size = host.fittingSize
		let header = NSMenuItem()
		header.view = host
		header.isEnabled = false
		menu.addItem(header)

		menu.addItem(.separator())
		menu.addItem(actionItem("Settings…", #selector(handleOpenSettings), key: ","))

		switch appState.phase {
		case .signedOut:
			menu.addItem(actionItem("Sign In…", #selector(handleSignIn)))
		case .ready:
			menu.addItem(actionItem("Sign Out", #selector(handleSignOut)))
		case .error:
			menu.addItem(actionItem("Try Again", #selector(handleRetry)))
			menu.addItem(actionItem("Sign Out", #selector(handleSignOut)))
		case .bootstrapping, .loading:
			break
		}

		menu.addItem(.separator())
		menu.addItem(actionItem("Quit usagi", #selector(handleQuit), key: "q"))
	}

	func menuWillOpen(_ menu: NSMenu) {
		Task { await appState.refresh() }
	}
}

extension AppDelegate: NSWindowDelegate {
	func windowWillClose(_ notification: Notification) {
		if (notification.object as? NSWindow) === settingsWindow {
			settingsWindow = nil
		}
	}
}

extension Notification.Name {
	static let openSettings = Notification.Name("ie.duggan.usagi.openSettings")
}
