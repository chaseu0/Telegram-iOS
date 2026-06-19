load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SweetGramAI",
    module_name = "SweetGramAI",
    srcs = glob([
        "Sources/**/*.swift",
    ]) + [
        "Sources/SweetGramSQLite.m",
    ],
    deps = [
        "//submodules/SweetGramCore:SweetGramCore",
        "//submodules/sqlcipher:sqlcipher",
    ],
    visibility = ["//visibility:public"],
)
