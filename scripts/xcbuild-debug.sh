#!/bin/bash
set -o pipefail && xcodebuild build \
  -scheme NFBrowser \
  -destination "platform=macOS" \
  -configuration Debug \
  -skipPackagePluginValidation \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO | xcbeautify
