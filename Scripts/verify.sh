#!/usr/bin/env bash
# 一条命令跑完全部门禁：两个内核包的单测 + App 构建。
# 用法：./Scripts/verify.sh
set -euo pipefail

cd "$(dirname "$0")/.."

# 本机 bash 可能跑在 Rosetta（x86_64）下，直接 swift test 会编译出 arm64
# 测试包却用 x86_64 进程加载，结果是「0 tests passed」但退出码为 0。
# 原生 Apple Silicon 下 uname -m 就是 arm64，不需要这层转换。
if [ "$(uname -m)" = "x86_64" ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ]; then
  SWIFT=(arch -arm64 swift)
else
  SWIFT=(swift)
fi

echo "==> YeHangCore 单元测试"
"${SWIFT[@]}" test --package-path Packages/YeHangCore --disable-sandbox

echo "==> LegadoCore 单元测试"
"${SWIFT[@]}" test --package-path Packages/LegadoCore --disable-sandbox

echo "==> App 构建（iOS 27 模拟器）"
xcodebuild -project YeHangChuan.xcodeproj -scheme YeHangChuan \
  -destination 'platform=iOS Simulator,name=iPhone 17e' \
  OTHER_SWIFT_FLAGS="-disable-sandbox" build

echo "全部通过"
