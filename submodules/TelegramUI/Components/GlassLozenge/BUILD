load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")


load(
    "@build_bazel_rules_apple//apple:resources.bzl",
    "apple_resource_bundle",
    "apple_resource_group",
)

load("//build-system/bazel-utils:plist_fragment.bzl",
    "plist_fragment",
)

filegroup(
    name = "GlassLozengeSources",
    srcs = glob([
        "Shaders/**/*.metal",
    ]),
    visibility = ["//visibility:public"],
)

plist_fragment(
    name = "GlassLozengeBundleInfoPlist",
    extension = "plist",
    template =
    """
    <key>CFBundleIdentifier</key>
    <string>org.telegram.GlassLozenge</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleName</key>
    <string>GlassLozenge</string>
    """
)

apple_resource_bundle(
    name = "GlassLozengeBundle",
    infoplists = [
        ":GlassLozengeBundleInfoPlist",
    ],
    resources = [
        ":GlassLozengeSources",
    ],
)

swift_library(
    name = "GlassLozenge",
    module_name = "GlassLozenge",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
	data = [
		":GlassLozengeBundle",
	],
    deps = [
        "//submodules/Display",
		"//submodules/TelegramUI/Components/GlassLozengeUtils"
    ],
    visibility = [
        "//visibility:public",
    ],
)
