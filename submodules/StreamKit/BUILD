load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "StreamKit",
    module_name = "StreamKit",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/FFMpegBinding:FFMpegBinding",
        "//submodules/RingBuffer:RingBuffer",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)
