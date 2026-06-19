load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SweetGramCore",
    module_name = "SweetGramCore",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    sdk_frameworks = [
        "Foundation",
        "Security",
    ],
    visibility = ["//visibility:public"],
)
