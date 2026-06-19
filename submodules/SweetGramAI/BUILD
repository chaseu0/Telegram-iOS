load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

objc_library(
    name = "SweetGramSQLite",
    enable_modules = True,
    module_name = "SweetGramSQLite",
    srcs = [
        "Sources/SweetGramSQLite.m",
    ],
    hdrs = [
        "Sources/SweetGramSQLite.h",
    ],
    includes = [
        "Sources",
    ],
    deps = [
        "//submodules/sqlcipher:sqlcipher",
    ],
    sdk_frameworks = [
        "Foundation",
    ],
    visibility = ["//visibility:public"],
)

swift_library(
    name = "SweetGramAI",
    module_name = "SweetGramAI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    deps = [
        "//submodules/SweetGramCore:SweetGramCore",
        ":SweetGramSQLite",
    ],
    visibility = ["//visibility:public"],
)
