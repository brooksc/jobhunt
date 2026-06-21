import ProjectDescription

let bundleId = "com.jobhunt-app.jobhunt"
let deploymentTarget: DeploymentTargets = .macOS("15.0")

// MARK: - Sparkle auto-update (DMG only)

// TASK-566: Sparkle 2 powers auto-update for Developer ID (DMG) builds. The Mac App Store bans
// third-party updaters, so Sparkle must NOT be linked into the MAS binary. Tuist can't scope a
// linked SPM package per build configuration, so instead `release-mas.yml` generates the project
// with TUIST_MAS_ONLY=1 and we omit Sparkle (package, dependency, and Info.plist keys) entirely.
// The default generation (local dev + `release-dmg.yml`) includes it.
let includeSparkle = !Environment.masOnly.getBoolean(default: false)

// EdDSA public key matching the private key used to sign DMGs in `release-dmg.yml`. Generated once
// via Sparkle's `generate_keys`; the private half lives only in the SPARKLE_EDDSA_PRIVATE_KEY CI
// secret. Replacing this invalidates every previously signed update.
let sparklePublicEDKey = "M+FYCXWxrdmjRzphUpv5wZMxaDh/ecJU22324+3o4zQ="
let sparkleFeedURL = "https://github.com/brooksc/jobhunt/releases/latest/download/appcast.xml"

// MARK: - Project-level configurations (four: debug+release × dmg+mas)

// TASK-401: Developer ID (DMG) builds MUST notarize with the hardened runtime. Set it explicitly
// at the project level (cascades to the app + bundled MCP helper) instead of relying on a
// generated default, so signing always produces `--options runtime` and notarization can't fail
// late. (MAS builds use the App Sandbox; hardened runtime is a separate, DMG-only concern.)
let projectConfigurations: [Configuration] = [
    .debug(name: "Debug-DMG", settings: ["ENABLE_HARDENED_RUNTIME": "YES"]),
    .release(name: "Release-DMG", settings: ["ENABLE_HARDENED_RUNTIME": "YES"]),
    .debug(name: "Debug-MAS", settings: ["SWIFT_ACTIVE_COMPILATION_CONDITIONS": "MAS_BUILD"]),
    .release(name: "Release-MAS", settings: ["SWIFT_ACTIVE_COMPILATION_CONDITIONS": "MAS_BUILD"]),
]

// MARK: - Base per-target settings

let sharedBase = SettingsDictionary()
    .automaticCodeSigning(devTeam: "")
    .marketingVersion("1.0.1")
    .currentProjectVersion("202606142301")
    .merging(["SWIFT_STRICT_CONCURRENCY": .string("complete")])

// MARK: - Target factory helpers

func frameworkTarget(
    name: String,
    bundleSuffix: String,
    sources: SourceFilesList,
    deps: [TargetDependency] = []
) -> Target {
    Target.target(
        name: name,
        destinations: [.mac],
        product: .framework,
        bundleId: "\(bundleId).\(bundleSuffix)",
        deploymentTargets: deploymentTarget,
        sources: sources,
        dependencies: deps,
        settings: .settings(
            base: sharedBase,
            configurations: projectConfigurations,
            defaultSettings: .recommended(excluding: [])
        )
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
        settings: .settings(
            base: sharedBase,
            configurations: projectConfigurations,
            defaultSettings: .recommended(excluding: [])
        )
    )
}

// MARK: - Library/framework targets

let coreTarget = frameworkTarget(
    name: "JobhuntCore",
    bundleSuffix: "core",
    sources: ["core/**/*.swift"],
    deps: []
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
    // productName ensures the built binary is "jobhunt-mcp" (not "JobhuntMCP"),
    // matching the path the copy script looks for: ${BUILT_PRODUCTS_DIR}/jobhunt-mcp (TASK-339).
    productName: "jobhunt-mcp",
    bundleId: "\(bundleId).mcp",
    deploymentTargets: deploymentTarget,
    sources: ["mcp/swift/**/*.swift"],
    dependencies: [.target(name: "JobhuntCore")],
    settings: .settings(
        base: sharedBase,
        configurations: projectConfigurations,
        defaultSettings: .recommended(excluding: [])
    )
)

// MARK: - Migrator executable (DMG only — one-time dev tool, not shipped in app bundles)

let migratorTarget = Target.target(
    name: "JobhuntMigrator",
    destinations: [.mac],
    product: .commandLineTool,
    bundleId: "\(bundleId).migrator",
    deploymentTargets: deploymentTarget,
    sources: ["tools/migrator/**/*.swift"],
    dependencies: [.target(name: "JobhuntCore")],
    settings: .settings(
        // Add @executable_path to the runpath so the tool can locate JobhuntCore.framework
        // (which sits beside it in the build-products dir) when run directly from a shell.
        base: sharedBase.merging(
            ["LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path"]]
        ) { _, new in new },
        configurations: projectConfigurations,
        defaultSettings: .recommended(excluding: [])
    )
)

// MARK: - App target

let appInfoPlist: [String: Plist.Value] = [
    "CFBundleName": "JobHunt",
    "CFBundleDisplayName": "JobHunt",
    "CFBundleIdentifier": .string(bundleId),
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "NSPrincipalClass": "NSApplication",
    "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)",
    "NSHumanReadableCopyright": "Copyright © 2025 Brooks Cutter",
    "LSApplicationCategoryType": "public.app-category.productivity",
    "CFBundleURLTypes": .array([
        .dictionary([
            "CFBundleURLName": .string(bundleId),
            "CFBundleURLSchemes": .array(["jobhunt"]),
        ]),
    ]),
    "NSAppTransportSecurity": .dictionary([
        "NSAllowsLocalNetworking": true,
    ]),
].merging(includeSparkle ? [
    // Sparkle auto-update (DMG only) — see TASK-566. Omitted from MAS generation.
    "SUFeedURL": .string(sparkleFeedURL),
    "SUPublicEDKey": .string(sparklePublicEDKey),
] : [:]) { _, new in new }

let dmgEntitlements: Path = "config/entitlements/Jobhunt-DMG.entitlements"
let masEntitlements: Path = "config/entitlements/Jobhunt-MAS.entitlements"

let appConfigurations: [Configuration] = [
    .debug(name: "Debug-DMG", settings: ["CODE_SIGN_ENTITLEMENTS": .string("config/entitlements/Jobhunt-DMG.entitlements")]),
    .release(name: "Release-DMG", settings: ["CODE_SIGN_ENTITLEMENTS": .string("config/entitlements/Jobhunt-DMG.entitlements")]),
    .debug(name: "Debug-MAS", settings: [
        "CODE_SIGN_ENTITLEMENTS": .string("config/entitlements/Jobhunt-MAS.entitlements"),
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "MAS_BUILD",
    ]),
    .release(name: "Release-MAS", settings: [
        "CODE_SIGN_ENTITLEMENTS": .string("config/entitlements/Jobhunt-MAS.entitlements"),
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
    scripts: [
        // Copy jobhunt-mcp into Contents/Helpers/ for DMG builds (TASK-339).
        // MAS builds skip this (no MCP entitlement in the sandbox).
        // The binary name "jobhunt-mcp" is enforced via productName on the JobhuntMCP target.
        .post(
            script: """
            case "$CONFIGURATION" in
              *MAS*) exit 0 ;;
            esac
            MCP_SRC="${BUILT_PRODUCTS_DIR}/jobhunt-mcp"
            HELPERS="${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}/Contents/Helpers"
            if [ -f "$MCP_SRC" ]; then
              mkdir -p "$HELPERS"
              cp "$MCP_SRC" "$HELPERS/jobhunt-mcp"
            fi
            """,
            name: "Copy MCP Helper into Contents/Helpers (DMG only)",
            basedOnDependencyAnalysis: false
        )
    ],
    dependencies: [
        .target(name: "JobhuntCore"),
        .target(name: "JobhuntServer"),
        .target(name: "JobhuntMCP"),
    ] + (includeSparkle ? [.package(product: "Sparkle")] : []),
    settings: .settings(
        base: sharedBase,
        configurations: appConfigurations,
        defaultSettings: .recommended(excluding: [])
    )
)

// MARK: - Test targets

// Migration.swift, Patch.swift, and SQLiteHelpers.swift are compiled directly into CoreTests
// because JobhuntMigrator is a commandLineTool and cannot be linked as a dependency.
let coreTestsTarget = testTarget(
    name: "CoreTests",
    bundleSuffix: "CoreTests",
    sources: [
        "tests/CoreTests/**/*.swift",
        // Shared mock OpenAI server (also compiled into AppUITests) for the keyless inference path.
        "tests/Support/MockLLM/**/*.swift",
        "tools/migrator/Migration.swift",
        "tools/migrator/Patch.swift",
        "tools/migrator/SQLiteHelpers.swift",
        "tools/migrator/RepairJobNumbers.swift",
        "tools/migrator/Args.swift",
    ],
    deps: [.target(name: "JobhuntCore")]
)

let serverTestsTarget = testTarget(
    name: "ServerTests",
    bundleSuffix: "ServerTests",
    sources: ["tests/ServerTests/**/*.swift"],
    deps: [.target(name: "JobhuntServer")]
)

// MCPHelpers.swift is compiled directly into MCPTests because JobhuntMCP is a
// commandLineTool and cannot be linked as a dependency (same pattern as CoreTests).
let mcpTestsTarget = testTarget(
    name: "MCPTests",
    bundleSuffix: "MCPTests",
    sources: [
        "tests/MCPTests/**/*.swift",
        "mcp/swift/MCPHelpers.swift",
    ],
    deps: [.target(name: "JobhuntCore")]
)

// AppUITests uses .uiTests (not .unitTests) so Xcode knows to launch the
// host app rather than inject the bundle into a unit test runner process.
// Without this, xcodebuild reports "No target application path specified".
let appUITestsTarget = Target.target(
    name: "AppUITests",
    destinations: [.mac],
    product: .uiTests,
    bundleId: "\(bundleId).AppUITests",
    deploymentTargets: deploymentTarget,
    sources: [
        "tests/AppUITests/**/*.swift",
        // Mock OpenAI server hosted by the test runner so the app (pointed at it via --llm-mock-port)
        // exercises the AI path with no key.
        "tests/Support/MockLLM/**/*.swift",
    ],
    dependencies: [.target(name: "Jobhunt")],
    settings: .settings(
        base: sharedBase,
        configurations: projectConfigurations,
        defaultSettings: .recommended(excluding: [])
    )
)

let llmEvalTarget = testTarget(
    name: "LLMEval",
    bundleSuffix: "LLMEval",
    sources: ["tests/LLMEval/**/*.swift"],
    deps: [.target(name: "JobhuntCore")]
)

// MARK: - Schemes

let dmgScheme = Scheme.scheme(
    name: "Jobhunt-DMG",
    buildAction: .buildAction(targets: [
        .target("Jobhunt"),
        .target("JobhuntCore"),
        .target("JobhuntServer"),
        .target("JobhuntMCP"),
        .target("JobhuntMigrator"),
    ]),
    testAction: .targets(
        [
            .testableTarget(target: .target("CoreTests")),
            .testableTarget(target: .target("ServerTests")),
            .testableTarget(target: .target("MCPTests")),
            .testableTarget(target: .target("AppUITests")),
        ],
        configuration: "Debug-DMG",
        options: .options(
            coverage: true,
            codeCoverageTargets: [.target("JobhuntCore"), .target("JobhuntServer")]
        )
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
        [
            .testableTarget(target: .target("CoreTests")),
            .testableTarget(target: .target("ServerTests")),
        ],
        configuration: "Debug-MAS"
    ),
    runAction: .runAction(configuration: "Debug-MAS", executable: .target("Jobhunt")),
    archiveAction: .archiveAction(configuration: "Release-MAS")
)

// Opt-in eval scheme — runs the LLM extraction benchmark against a real OpenAI-compatible
// endpoint (e.g. LM Studio). Kept out of the DMG/MAS schemes so it never runs in the normal
// test gate; invoke explicitly via scripts/run-eval.sh.
let evalScheme = Scheme.scheme(
    name: "Jobhunt-Eval",
    buildAction: .buildAction(targets: [.target("JobhuntCore"), .target("LLMEval")]),
    testAction: .targets(
        [.testableTarget(target: .target("LLMEval"))],
        configuration: "Debug-DMG"
    )
)

// MARK: - Project

let project = Project(
    name: "Jobhunt",
    organizationName: "Jobhunt",
    options: .options(
        defaultKnownRegions: ["en"],
        developmentRegion: "en"
    ),
    packages: includeSparkle
        ? [.remote(url: "https://github.com/sparkle-project/Sparkle", requirement: .upToNextMajor(from: "2.6.4"))]
        : [],
    settings: .settings(
        base: sharedBase,
        configurations: projectConfigurations,
        defaultSettings: .recommended(excluding: [])
    ),
    targets: [
        coreTarget, coreTestsTarget,
        serverTarget, serverTestsTarget,
        mcpTarget, mcpTestsTarget,
        migratorTarget,
        appTarget, appUITestsTarget,
        llmEvalTarget,
    ],
    schemes: [dmgScheme, masScheme, evalScheme]
)
