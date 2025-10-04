# StartMyApp

一个现代化的 macOS 应用启动器，提供直观的应用管理和快速启动体验。

## 核心理念

StartMyApp 采用模块化架构设计，遵循 SwiftUI 的声明式编程范式和单向数据流原则。整个应用围绕三个核心概念构建：

1. **应用发现与组织** - 自动扫描系统应用，支持自定义布局和文件夹组织
2. **智能搜索与排序** - 基于多维度的搜索和排序机制，快速定位目标应用
3. **快捷访问** - 通过全局快捷键和菜单栏图标实现随时随地的快速启动

## 架构设计

### 数据层 (Models)

#### DiscoveredApp
表示已发现的应用程序，包含：
- 基本信息：名称、Bundle ID、路径、版本
- 元数据：开发者、分类、关键词
- 系统标识：是否为系统应用
- 搜索优化：预计算的可搜索文本字段

#### AppCollectionItem
应用集合单元，支持两种类型：
- **App** - 单个应用引用
- **Folder** - 包含多个应用的文件夹

#### RecentLaunch
记录最近启动的应用及其使用频率：
- 启动时间戳
- 启动次数统计
- 用于"最近使用"和"最常使用"排序

### 业务逻辑层 (Services)

#### ApplicationDiscoveryService
应用发现服务，负责扫描文件系统并提取应用信息：
- 搜索路径：`/Applications`、`/System/Applications`、`~/Applications`
- Bundle 解析：提取应用元数据、图标、分类信息
- 系统应用识别：基于路径和 Bundle ID 判断

#### AppState
核心状态管理器，协调所有业务逻辑：
- **应用管理**：发现、刷新、排序、过滤
- **布局管理**：自定义顺序、文件夹创建/解散、拖拽重组
- **收藏与历史**：收藏管理、启动记录、最近使用跟踪
- **搜索引擎**：智能排序算法（基于收藏、最近使用、布局位置、系统属性的权重计算）
- **数据导出**：应用目录 JSON 导出功能

#### 持久化 Stores
- **FavoritesStore** - 收藏应用列表（Set 存储）
- **RecentsStore** - 最近启动记录（有序数组，限制数量）
- **LayoutStore** - 自定义布局配置（JSON 序列化）

#### WindowManager
窗口生命周期管理：
- 智能窗口查找与激活
- 多窗口场景处理
- 窗口状态恢复（最小化、隐藏等）

#### ShortcutCoordinator
全局快捷键协调器：
- 监听用户偏好设置
- 注册/注销快捷键
- 触发窗口显示

#### StatusItemCoordinator
菜单栏图标管理：
- 动态显示/隐藏
- 点击事件处理
- 与主窗口联动

#### GlobalShortcutCenter
低级别快捷键注册（Carbon API）：
- 系统级热键监听
- 事件处理器管理
- 键码和修饰符转换

#### AppIconCache
应用图标缓存系统：
- 异步加载应用图标
- 内存缓存优化
- NSImage 生成与缓存

### 表现层 (Views)

#### ContentView
主视图容器，协调：
- 搜索栏 + 结果展示
- 分段展示：收藏、最近使用、全部应用
- 搜索焦点管理（快捷键触发）
- 文件夹创建 Sheet

#### ApplicationsGridView
应用网格展示核心：
- 自适应网格布局（响应窗口大小）
- 拖拽系统实现：
  - 应用重排序
  - 拖拽创建文件夹（拖到其他应用上）
  - 添加到现有文件夹
- Drop Delegate 处理复杂的拖拽逻辑

#### AppGridSection
分段标题 + 应用网格组合组件：
- 标题与辅助信息展示
- 可选的右侧操作按钮
- 内嵌网格布局

#### AppTile
单个应用磁贴：
- 应用图标 + 名称 + 副标题
- 悬停效果与上下文菜单
- 拖拽状态视觉反馈

#### FolderTile
文件夹磁贴：
- 多应用图标堆叠展示
- 点击展开/收起
- 文件夹内应用管理（移除、重命名）
- 拖拽接收区域

#### SettingsView
偏好设置面板：
- 显示选项（系统应用、最近使用）
- 网格尺寸调整
- 快捷键配置
- 菜单栏图标开关

#### AppInfoView
应用详情弹窗：
- 详细信息展示（版本、开发者、文件大小等）
- 权限信息
- 一键复制详情

### 配置层 (AppPreferences)

用户偏好设置管理，使用 UserDefaults 持久化：

- **显示选项**
  - `showSystemApps` - 显示/隐藏系统应用
  - `showRecentApps` - 显示最近使用区域
  - `showMenuBarIcon` - 菜单栏图标可见性

- **布局选项**
  - `gridScale` - 网格尺寸（紧凑/舒适/宽敞）
  - `sortOption` - 排序方式（自定义/字母/最常用/最近用）

- **快捷键选项**
  - `isGlobalShortcutEnabled` - 启用全局快捷键
  - `globalShortcut` - 快捷键配置（键码 + 修饰符）

使用 Combine 框架实现响应式绑定，自动同步到 UserDefaults。

## 数据流架构

```
User Action
    ↓
View (SwiftUI)
    ↓
AppState (ObservableObject)
    ↓
Service Layer (Discovery/Store/Manager)
    ↓
Data Layer (Models)
    ↓
@Published Properties
    ↓
SwiftUI Re-render
```

所有状态变更通过 `AppState` 集中管理，视图层通过 `@EnvironmentObject` 注入依赖，确保单向数据流。

## 关键技术特性

### 1. 智能搜索排序

搜索权重算法（`searchRank` 方法）：
```
权重 = 收藏权重(20)
     + 最近使用权重(10)
     + 布局位置权重(15-index)
     + 非系统应用加分(1)
```

### 2. 拖拽交互系统

三种拖拽模式识别：
- **Reorder** - 重新排序（拖到网格间隙）
- **Folder Creation** - 创建文件夹（拖到应用中心区域）
- **Folder Append** - 添加到文件夹（拖到文件夹上）

通过 `DropDelegate` 的 `dropUpdated` 方法实时计算热区位置。

### 3. 布局同步机制

应用刷新时自动同步布局（`syncLayoutWithDiscoveredApps`）：
1. 移除不存在的应用引用
2. 检查文件夹有效性（至少2个应用）
3. 将孤立应用重新加入布局
4. 保持用户自定义顺序

### 4. 异步应用发现

使用 `Task.detached` 在后台线程执行文件系统扫描，避免阻塞 UI：
```swift
Task.detached(priority: .userInitiated) {
    let apps = discoveryService.discoverApplications(...)
    await MainActor.run {
        // Update UI
    }
}
```

### 5. 全局快捷键实现

使用 Carbon API 实现系统级热键监听：
- 注册 EventHandler 监听 `kEventHotKeyPressed`
- 转换 SwiftUI KeyboardShortcut 到 Carbon 键码
- 管理生命周期（注册/注销）

## 文件结构

```
StartMyApp/
├── Models/                      # 数据模型
│   ├── DiscoveredApp.swift     # 应用信息
│   ├── AppCollectionItem.swift # 集合单元（应用/文件夹）
│   ├── RecentLaunch.swift      # 启动记录
│   ├── AppPreferences.swift    # 用户偏好
│   └── KeyboardShortcutPreference.swift  # 快捷键配置
│
├── Services/                    # 业务逻辑
│   ├── ApplicationDiscoveryService.swift  # 应用发现
│   ├── FavoritesStore.swift    # 收藏持久化
│   ├── RecentsStore.swift      # 历史持久化
│   ├── LayoutStore.swift       # 布局持久化
│   ├── AppIconCache.swift      # 图标缓存
│   ├── WindowManager.swift     # 窗口管理
│   ├── ShortcutCoordinator.swift     # 快捷键协调
│   ├── StatusItemCoordinator.swift   # 菜单栏协调
│   ├── GlobalShortcutCenter.swift    # 底层快捷键
│   └── AboutWindowController.swift   # 关于窗口
│
├── Views/                       # 视图组件
│   ├── ContentView.swift       # 主容器
│   ├── ApplicationsGridView.swift    # 网格视图
│   ├── AppGridSection.swift    # 分段组件
│   ├── AppTile.swift           # 应用磁贴
│   ├── FolderTile.swift        # 文件夹磁贴
│   ├── SettingsView.swift      # 设置面板
│   ├── AppInfoView.swift       # 应用详情
│   ├── ShortcutRecorderView.swift    # 快捷键录制
│   ├── AboutView.swift         # 关于页面
│   └── VisualEffectBackground.swift  # 背景效果
│
├── Extensions/                  # 扩展
│   ├── Bundle+AppName.swift    # Bundle 扩展
│   └── NSApplication+Utilities.swift # AppKit 扩展
│
├── AppState.swift              # 核心状态管理
└── StartMyAppApp.swift         # 应用入口
```

## 核心流程

### 应用启动流程

1. `StartMyAppApp.init()` - 初始化依赖链
   - 创建 `AppPreferences`
   - 创建 `AppState`（注入 preferences）
   - 创建 `ShortcutCoordinator`
   - 创建 `StatusItemCoordinator`

2. `AppState.init()` - 加载持久化数据
   - 从 FavoritesStore 加载收藏
   - 从 RecentsStore 加载历史
   - 从 LayoutStore 加载布局
   - 触发应用发现（`refreshApps()`）

3. `ApplicationDiscoveryService.discoverApplications()` - 扫描应用
   - 遍历搜索路径
   - 解析 Bundle 信息
   - 过滤系统应用（根据偏好）
   - 返回 `DiscoveredApp` 数组

4. `AppState.handleDiscoveredApps()` - 处理发现结果
   - 更新 `apps` 数组（触发 UI 刷新）
   - 构建 identifier 索引
   - 同步布局（移除无效引用）

### 应用启动流程

1. 用户点击应用磁贴
2. `AppTile` 触发 `appState.launch(app)`
3. `NSWorkspace.openApplication()` 异步启动
4. 成功回调 → `updateRecents()` 更新历史记录
   - 增加启动计数
   - 更新时间戳
   - 移到列表顶部
   - 保存到 RecentsStore

### 拖拽创建文件夹流程

1. 用户拖拽 App A 到 App B 中心区域
2. `ApplicationsDropDelegate.dropUpdated()` 检测位置
   - 计算与磁贴中心的距离
   - 小于阈值 → 设置 `folderCreationTargetID`
3. `AppTile` 显示视觉反馈（高亮边框）
4. 用户释放 → `performDrop()` 调用
5. `appState.createFolder(byCombining:and:)`
   - 从布局移除两个应用
   - 生成文件夹名（基于应用分类）
   - 创建 `AppCollectionItem.folder`
   - 插入到原位置
   - 保存布局

### 搜索流程

1. 用户输入搜索文本 → `searchText` 更新
2. `ContentView.onChange(of: searchText)` → 更新 `appState.searchQuery`
3. `appsMatchingSearch()` 计算结果
   - 过滤匹配的应用（基于 `searchableText`）
   - 使用 `searchRank()` 排序
4. SwiftUI 自动重新渲染 `AppGridSection`

### 全局快捷键流程

1. `ShortcutCoordinator` 监听 preferences 变化
2. `isGlobalShortcutEnabled` 或 `globalShortcut` 改变
3. `GlobalShortcutCenter.register()` 注册热键
   - 安装 EventHandler
   - 注册 HotKey（Carbon API）
4. 用户按下快捷键
5. Carbon 事件 → `handle(event:)` → 回调
6. `WindowManager.showMainWindow()`
   - 查找/创建主窗口
   - 激活应用
   - 显示窗口
   - 聚焦搜索框

## 扩展方向

- **iCloud 同步** - 同步布局和收藏到多台设备
- **应用统计** - 可视化使用时长和启动频率
- **标签系统** - 多维度应用分类
- **Spotlight 集成** - 系统级搜索支持
- **AppleScript 支持** - 自动化脚本控制
- **主题定制** - 自定义配色和图标风格

## 技术栈

- **框架**: SwiftUI, AppKit, Combine
- **系统 API**: Carbon (热键), NSWorkspace (应用管理), FileManager (文件系统)
- **架构模式**: MVVM, Observer Pattern, Repository Pattern
- **数据持久化**: UserDefaults, JSON Encoding
- **并发**: async/await, Task, MainActor

## 开发准备

- Xcode 14.0+
- macOS 12.0+
- Swift 5.7+
