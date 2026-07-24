import UIKit
import AudioToolbox

enum Feedback {
    static func success(vibrate: Bool, beep: Bool) {
        if vibrate {
            let notification = UINotificationFeedbackGenerator()
            notification.prepare()
            notification.notificationOccurred(.success)
            let medium = UIImpactFeedbackGenerator(style: .medium)
            medium.prepare()
            medium.impactOccurred(intensity: 1.0)
            let heavy = UIImpactFeedbackGenerator(style: .heavy)
            heavy.prepare()
            heavy.impactOccurred(intensity: 0.85)
            let rigid = UIImpactFeedbackGenerator(style: .rigid)
            rigid.prepare()
            rigid.impactOccurred(intensity: 0.45)
        }
        if beep {
            AudioServicesPlaySystemSound(1057)
        }
    }

    static func light(vibrate: Bool) {
        if vibrate {
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred(intensity: 0.95)
        }
    }

    static func photoUseConfirmed(vibrate: Bool, beep: Bool) {
        if vibrate {
            let heavy = UIImpactFeedbackGenerator(style: .heavy)
            heavy.prepare()
            heavy.impactOccurred(intensity: 1.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let rigid = UIImpactFeedbackGenerator(style: .rigid)
                rigid.prepare()
                rigid.impactOccurred(intensity: 1.0)
            }
        }
        if beep {
            AudioServicesPlaySystemSound(1057)
        }
    }

    /// Distinct capture shutter feedback for in-camera shots.
    static func shutterCapture(vibrate: Bool, beep: Bool) {
        if vibrate {
            let shutter = UIImpactFeedbackGenerator(style: .rigid)
            shutter.prepare()
            shutter.impactOccurred(intensity: 1.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                let light = UIImpactFeedbackGenerator(style: .light)
                light.prepare()
                light.impactOccurred(intensity: 0.55)
            }
        }
        if beep {
            AudioServicesPlaySystemSound(1108)
        }
    }
}
