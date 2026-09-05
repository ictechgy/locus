import UIKit

/// UIKit demo surface: outlet-configured controls with identifiers assigned in
/// viewDidLoad, plus one control that never gets an identifier.
final class CheckoutViewController: UIViewController {
    let payButton = UIButton(type: .system)
    let couponField = UITextField(frame: .zero)
    let cancelButton = UIButton(type: .system) // no identifier anywhere

    override func viewDidLoad() {
        super.viewDidLoad()
        payButton.setTitle("Pay", for: .normal)
        payButton.accessibilityIdentifier = "checkout.pay"
        couponField.placeholder = "Coupon code"
        couponField.accessibilityLabel = "Coupon code"
        couponField.accessibilityIdentifier = "checkout.coupon"
        cancelButton.setTitle("Cancel", for: .normal)
    }
}
