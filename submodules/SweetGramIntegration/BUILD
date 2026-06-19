load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SweetGramIntegration",
    module_name = "SweetGramIntegration",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    deps = [
        "//submodules/SweetGramCore:SweetGramCore",
        "//submodules/SweetGramAI:SweetGramAI",
    ],
    visibility = ["//visibility:public"],
)
