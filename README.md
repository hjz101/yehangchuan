# 夜航船

iOS 小说阅读器 Demo，用于评估产品界面与交互逻辑。所有书籍、书源与段评均为本地模拟数据，无真实后端。

## 运行

打开 `YeHangChuan.xcodeproj`，选择 iPhone 模拟器运行（iOS 17+）。

```bash
xcodebuild -project YeHangChuan.xcodeproj -scheme YeHangChuan \
  -destination 'platform=iOS Simulator,name=iPhone 17e' build
```

## 演示范围

- 书架：继续阅读、搜索、类型筛选、阅读状态筛选、长按管理
- 阅读：横滑分页 / 上下滚动、字号、行距、日间/羊皮纸/夜间、目录、书签、段评
- 书源：启用与添加书源、按书源搜索并加入书架
- 设置：阅读偏好、导出与分发入口（占位）

未实现：真实导入解析、书源网络请求、持久化、漫画阅读器、音频播放器。
