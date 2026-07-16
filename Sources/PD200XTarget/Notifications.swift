import Foundation

public enum PD200XNotifications {
    public static let changeMode = Notification.Name(
        "com.maulik.pd200x-button.change-mode"
    )
    public static let physicalButtonPressed = Notification.Name(
        "com.maulik.pd200x-button.physical-button-pressed"
    )
    public static let showSettings = Notification.Name(
        "com.maulik.pd200x-button.show-settings"
    )
}
