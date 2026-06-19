load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SweetGramUIHooks",
    module_name = "SweetGramUIHooks",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    deps = [
        "//submodules/SweetGramIntegration:SweetGramIntegration",
        "//submodules/SweetGramAI:SweetGramAI",
        "//submodules/SweetGramCore:SweetGramCore",
        "//submodules/BuildConfig:BuildConfig",
        "//submodules/AppBundle:AppBundle",
        "//submodules/LocalizedPeerData:LocalizedPeerData",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Display:Display",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramStringFormatting:TelegramStringFormatting",
        "//submodules/AccountContext:AccountContext",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/ContextUI:ContextUI",
        "//submodules/OverlayStatusController:OverlayStatusController",
        "//submodules/AlertUI:AlertUI",
        "//submodules/LegacyMediaPickerUI:LegacyMediaPickerUI",
    ],
    visibility = ["//visibility:public"],
)
