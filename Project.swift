import ProjectDescription

let bundleId = "com.jobhunt-app.jobhunt"
let deploymentTarget: DeploymentTargets = .macOS("15.0")

// MARK: - Project-level configurations (four: debug+release × dmg+mas)

let projectConfigurations: [Configuration] = [
    .debug(name: "Debug-DMG"),
    .release(name: "Release-DMG"),
    .debug(name: "Debug-MAS", settings: ["SWIFT_ACTIVE_COMPILATION_CONDITIONS": "MAS_BUILD"]),
    .release(name: "Release-MAS", settings: ["SWIFT_ACTIVE_COMPILATION_CONDITIONS": "MAS_BUILD"]),
]

// MARK: - Base per-target settings

let sharedBase = SettingsDictionary()
    .automaticCodeSigning(devTeam: "")
    .marketingVersion("1.0.0")
    .currentProjectVersion("1")
    .merging(["SWIFT_STRICT_CONCURRENCY": .string("complete")])

// MARK: - Target factory helpers

func frameworkTarget(name: String, bundleSuffix: String, sources: SourceFilesList, deps: [TargetDependency] = []) -> Target {
    Target.target(
        name: name,
        destinations: [.mac],
        product: .framework,
        bundleId: "\(bundleId).\(bundleSuffix)",
        deploymentTargets: deploymentTarget,
        sources: sources,
        dependencies: deps,
        settings: .settings(base: sharedBase, configurations: projectConfigurations, defaultSettings: .recommended(excluding: []))
    )
}

func testTarget(name: String, bundleSuffix: String, sources: SourceFilesList, deps: [TargetDependency]) -> Target {
    Target.target(
        name: name,
        destinations: [.mac],
        product: .unitTests,
        bundleId: "\(bundleId).\(bundleSuffix)",
        deploymentTargets: deploymentTarget,
        sources: sources,
        dependencies: deps,
        settings: .settings(base: sharedBase, configurations: projectConfigurations, defaultSettings: .recommended(excluding: []))
    )
}

// MARK: - Library/framework targets

let coreTarget = frameworkTarget(
    name: "JobhuntCore",
    bundleSuffix: "core",
    sources: ["core/**/*.swift"]
)

let serverTarget = frameworkTarget(
    name: "JobhuntServer",
    bundleSuffix: "server",
    sources: ["server/swift/**/*.swift"],
    deps: [.target(name: "JobhuntCore")]
)

// MARK: - MCP executable (DMG only — excluded from MAS scheme build action)

let mcpTarget = Target.target(
    name: "JobhuntMCP",
    destinations: [.mac],
    product: .commandLineTool,
    bundleId: "\(bundleId).mcp",
    deploymentTargets: deploymentTarget,
    sources: ["mcp/swift/**/*.swift"],
    dependencies: [.target(name: "JobhuntCore")],
    settings: .settings(base: sharedBase, configurations: projectConfigurations, defaultSettings: .recommended(excluding: []))
)

// MARK: - App target

let appInfoPlist: [String: Plist.Value] = [
    "CFBundleName": "Jobhunt",
    "CFBundleDisplayName": "Jobhunt",
    "CFBundleIdentifier": .string(bundleId),
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "NSPrincipalClass": "NSApplication",
    "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)",
    "NSHumanReadableCopyright": "Copyright © 2025 Jobhunt",
    "LSApplicationCategoryType": "public.app-category.productivity",
    "CFBundleURLTypes": .array([
        .dictionary([
            "CFBundleURLName": .string(bundleId),
            "CFBundleURLSchemes": .array(["jobhunt"]),
        ])
    ]),
    "NSAppTransportSecurity": .dictionary([
        "NSAllowsLocalNetworking": true
    ]),
]

let dmgEntitlements: Path = "build/Jobhunt-DMG.entitlements"
let masEntitlements: Path = "build/Jobhunt-MAS.entitlements"

let appConfigurations: [Configuration] = [
    .debug(name: "Debug-DMG", settings: ["CODE_SIGN_ENTITLEMENTS": .string("build/Jobhunt-DMG.entitlements")]),
    .release(name: "Release-DMG", settings: ["CODE_SIGN_ENTITLEMENTS": .string("build/Jobhunt-DMG.entitlements")]),
    .debug(name: "Debug-MAS", settings: [
        "CODE_SIGN_ENTITLEMENTS": .string("build/Jobhunt-MAS.entitlements"),
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "MAS_BUILD",
    ]),
    .release(name: "Release-MAS", settings: [
        "CODE_SIGN_ENTITLEMENTS": .string("build/Jobhunt-MAS.entitlements"),
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "MAS_BUILD",
    ]),
]

let appTarget = Target.target(
    name: "Jobhunt",
    destinations: [.mac],
    product: .app,
    bundleId: bundleId,
    deploymentTargets: deploymentTarget,
    infoPlist: .extendingDefault(with: appInfoPlist),
    sources: ["app/**/*.swift"],
    resources: ["app/Resources/**"],
    dependencies: [
        .target(name: "JobhuntCore"),
        .target(name: "JobhuntServer"),
    ],
    settings: .settings(
        base: sharedBase,
        configurations: appConfigurations,
        defaultSettings: .recommended(excluding: [])
    )
)

// MARK: - Test targets

let coreTestsTarget = testTarget(
    name: "CoreTests",
    bundleSuffix: "CoreTests",
    sources: ["Tests/CoreTests/**/*.swift"],
    deps: [.target(name: "JobhuntCore")]
)

let serverTestsTarget = testTarget(
    name: "ServerTests",
    bundleSuffix: "ServerTests",
    sources: ["Tests/ServerTests/**/*.swift"],
    deps: [.target(name: "JobhuntServer")]
)

let mcpTestsTarget = testTarget(
    name: "MCPTests",
    bundleSuffix: "MCPTests",
    sources: ["Tests/MCPTests/**/*.swift"],
    deps: [.target(name: "JobhuntMCP")]
)

let appUITestsTarget = testTarget(
    name: "AppUITests",
    bundleSuffix: "AppUITests",
    sources: ["Tests/AppUITests/**/*.swift"],
    deps: [.target(name: "Jobhunt")]
)

// MARK: - Schemes

let dmgScheme = Scheme.scheme(
    name: "Jobhunt-DMG",
    buildAction: .buildAction(targets: [
        .target("Jobhunt"),
        .target("JobhuntCore"),
        .target("JobhuntServer"),
        .target("JobhuntMCP"),
    ]),
    testAction: .targets(
        [.testableTarget(target: .target("CoreTests")),
         .testableTarget(target: .target("ServerTests"))],
        configuration: "Debug-DMG"
    ),
    runAction: .runAction(configuration: "Debug-DMG", executable: .target("Jobhunt")),
    archiveAction: .archiveAction(configuration: "Release-DMG")
)

let masScheme = Scheme.scheme(
    name: "Jobhunt-MAS",
    buildAction: .buildAction(targets: [
        .target("Jobhunt"),
        .target("JobhuntCore"),
        .target("JobhuntServer"),
        // JobhuntMCP intentionally excluded from MAS scheme
    ]),
    testAction: .targets(
        [.testableTarget(target: .target("CoreTests")),
         .testableTarget(target: .target("ServerTests"))],
        configuration: "Debug-MAS"
    ),
    runAction: .runAction(configuration: "Debug-MAS", executable: .target("Jobhunt")),
    archiveAction: .archiveAction(configuration: "Release-MAS")
)

// MARK: - Project

let project = Project(
    name: "Jobhunt",
    organizationName: "Jobhunt",
    options: .options(
        defaultKnownRegions: ["en"],
        developmentRegion: "en"
    ),
    settings: .settings(
        base: sharedBase,
        configurations: projectConfigurations,
        defaultSettings: .recommended(excluding: [])
    ),
    targets: [
        coreTarget, coreTestsTarget,
        serverTarget, serverTestsTarget,
        mcpTarget, mcpTestsTarget,
        appTarget, appUITestsTarget,
    ],
    schemes: [dmgScheme, masScheme]
)
