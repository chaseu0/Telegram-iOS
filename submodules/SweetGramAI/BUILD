load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SweetGramAI",
    module_name = "SweetGramAI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    deps = [
        "//submodules/SweetGramCore:SweetGramCore",
    ],
    visibility = ["//visibility:public"],
)
