// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CodexQuotaWidget",
    products: [
        .library(
            name: "CodexQuotaWidget",
            targets: ["CodexQuotaWidget"]
        ),
        .executable(
            name: "CodexQuotaWidgetVerification",
            targets: ["CodexQuotaWidgetVerification"]
        ),
    ],
    targets: [
        .target(
            name: "CodexQuotaWidget",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "CodexQuotaWidgetVerification",
            dependencies: ["CodexQuotaWidget"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
