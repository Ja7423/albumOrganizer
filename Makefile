# fastlane 指令捷徑，全部透過 bundle exec 執行（版本鎖在 Gemfile.lock）。
#
# 可選參數：
#   BUILD_NUMBER=42   指定 build number（build / beta）
#   WAIT=true         上傳後等 App Store Connect 處理完成（beta / upload）
#   IPA=path/to.ipa   指定要上傳的 ipa（upload）
#   VERSION=1.0.1:12  版本號:build number，build number 可省略（version）

FASTLANE := bundle exec fastlane ios

# 只把有設定的參數傳給 fastlane
LANE_OPTS := $(if $(BUILD_NUMBER),build_number:$(BUILD_NUMBER)) \
             $(if $(WAIT),wait:$(WAIT)) \
             $(if $(IPA),ipa:$(IPA)) \
             $(if $(VERSION),version:$(VERSION))

.DEFAULT_GOAL := help
.PHONY: help install version certs certs-appstore certs-fetch certs-init build beta upload lanes

help: ## 列出可用指令
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

install: ## 安裝 Gemfile 裡的 gem（fastlane）
	bundle install

version: ## 修改版本號與 build number（VERSION=1.0.1:12）
	$(FASTLANE) set_version $(LANE_OPTS)

certs: ## 下載開發用憑證與 profile（唯讀）
	$(FASTLANE) certs

certs-appstore: ## 下載上架用憑證與 profile（唯讀）
	$(FASTLANE) certs_appstore

certs-fetch: ## 下載憑證與 profile（唯讀）
	$(FASTLANE) certs
	$(FASTLANE) certs_appstore

certs-init: ## 第一次建立憑證並推到 cert repo
	$(FASTLANE) certs_init

build: ## 編譯 App Store ipa 到 build/（BUILD_NUMBER=）
	$(FASTLANE) build_appstore $(LANE_OPTS)

beta: ## 編譯並用 asc 上傳（BUILD_NUMBER= WAIT=true）
	$(FASTLANE) beta $(LANE_OPTS)

upload: ## 只用 asc 上傳已編譯的 ipa（IPA= WAIT=true）
	$(FASTLANE) upload $(LANE_OPTS)

lanes: ## 列出 Fastfile 裡所有 lane
	bundle exec fastlane lanes
