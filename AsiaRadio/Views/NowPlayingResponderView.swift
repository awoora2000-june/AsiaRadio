import SwiftUI
import UIKit

final class NowPlayingResponderViewController: UIViewController {
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.beginReceivingRemoteControlEvents()
        _ = becomeFirstResponder()
    }
}

struct NowPlayingResponderView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> NowPlayingResponderViewController {
        NowPlayingResponderViewController()
    }

    func updateUIViewController(_ uiViewController: NowPlayingResponderViewController, context: Context) {
        guard !uiViewController.isFirstResponder else { return }
        UIApplication.shared.beginReceivingRemoteControlEvents()
        _ = uiViewController.becomeFirstResponder()
    }
}
