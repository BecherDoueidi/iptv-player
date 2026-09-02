# These targets only work on macOS (Xcode/xcodegen required).
# On Windows, edit source files directly and let GitHub Actions (see
# .github/workflows/) run these same steps in CI.

.PHONY: generate build test clean

generate:
	xcodegen generate

build: generate
	xcodebuild build \
		-project IPTVPlayer.xcodeproj \
		-scheme IPTVPlayer \
		-destination 'generic/platform=iOS' \
		CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

test:
	swift test --package-path Packages/IPTVCore

clean:
	rm -rf build IPTVPlayer.xcodeproj ipa_root IPTVPlayer-unsigned.ipa
