SIM ?= iPhone 17
DD  := .build/DerivedData
IOS_APP := $(DD)/Build/Products/Debug-iphonesimulator/TheOldPod.app
MAC_APP := $(DD)/Build/Products/Debug/TheOldPod.app

.PHONY: gen test ios run-ios screenshot uitest mac-uitest mac run-mac clean

gen:
	xcodegen generate

test:
	swift test --package-path Packages/OldPodKit

ios:
	xcodebuild -project TheOldPod.xcodeproj -scheme TheOldPod-iOS \
		-destination 'platform=iOS Simulator,name=$(SIM)' \
		-derivedDataPath $(DD) build CODE_SIGNING_ALLOWED=NO

run-ios: ios
	xcrun simctl boot "$(SIM)" || true
	xcrun simctl install booted $(IOS_APP)
	xcrun simctl launch booted com.mattreed.theoldpod

screenshot:
	xcrun simctl io booted screenshot .build/shot.png
	@echo ".build/shot.png"

uitest:
	xcodebuild -project TheOldPod.xcodeproj -scheme TheOldPod-iOS \
		-destination 'platform=iOS Simulator,name=$(SIM)' \
		-derivedDataPath $(DD) test CODE_SIGNING_ALLOWED=NO \
		-only-testing:TheOldPod-UITests

mac-uitest:
	xcodebuild -project TheOldPod.xcodeproj -scheme TheOldPod-macOS \
		-derivedDataPath $(DD) test -allowProvisioningUpdates \
		-only-testing:TheOldPod-MacUITests

mac:
	xcodebuild -project TheOldPod.xcodeproj -scheme TheOldPod-macOS \
		-derivedDataPath $(DD) build -allowProvisioningUpdates

run-mac: mac
	open $(MAC_APP)

clean:
	rm -rf .build TheOldPod.xcodeproj
