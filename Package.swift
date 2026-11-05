// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PowerSentry",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PowerSentry", targets: ["PowerSentry"])
    ],
    targets: [
        .executableTarget(
            name: "PowerSentry",
            path: "Sources/PowerSentry",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Charts"),
                .linkedFramework("IOKit"),
                .linkedFramework("UserNotifications"),
                .linkedLibrary("sqlite3")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
