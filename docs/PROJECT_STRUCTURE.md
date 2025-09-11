# ChordPlayer 项目结构文档

本文档旨在提供 macOS 应用 ChordPlayer 的高层架构概述，帮助开发者快速理解项目的组织方式、核心组件及其交互。

## 1. 项目简介

ChordPlayer 是一个为音乐创作者设计的强大编曲和演奏工具。它允许用户通过 MIDI 设备，根据预设的和弦进行、演奏模式（指法）和鼓点节奏来实时演奏或自动播放音乐。应用的核心是高度可定制的预设系统和精准的 MIDI 调度引擎。

## 2. 目录结构

项目文件经过重构，现已按功能和类型组织在 `ChordPlayer/` 目录下，结构如下：

- **`/App`**: 应用入口和主视图（`ChordPlayerApp.swift`, `ContentView.swift`）。
- **`/Views`**: 存放所有 SwiftUI 视图。
  - **`/Components`**: 可复用的原子视图组件（如 `ChordDiagramView`, `FretboardView`）。
  - **`/Editors`**: 用于创建和编辑内容的视图（如 `CustomChordCreatorView`, `PlayingPatternEditorView`）。
  - **`/Library`**: 用于浏览和管理各种库的视图（如 `ChordLibraryView`, `CustomDrumPatternLibraryView`）。
  - **`/Main`**: 构成主工作区的核心视图（`PresetWorkspaceView`）。
  - **`/Sheets`**: 以 Sheet 形式弹出的视图。
- **`/Handlers`**: 处理用户输入的类（`KeyboardHandler.swift`）。
- **`/Managers`**: 负责管理应用状态、数据和核心逻辑的单例类。
- **`/Models`**: 定义应用所有数据结构的纯 Swift 文件（`DataModels.swift`, `Shortcut.swift`）。
- **`/Players`**: 核心播放器引擎（`ChordPlayer.swift`, `DrumPlayer.swift`）。
- **`/Resources`**: 存放应用的资源文件，如 `Assets.xcassets` 和本地化文件 (`.lproj`)。
- **`/Data`**: 存放应用自带的 JSON 数据（和弦、鼓点、指法库）。

## 3. 核心组件详解

应用的逻辑主要由以下几个核心组件驱动：

### 状态管理

- **`AppData` (`Managers/AppData.swift`)**: 
  - 作为应用唯一的“状态真理之源”（Single Source of Truth），它是一个 `ObservableObject`。
  - 封装了当前预设的几乎所有配置，如速度（Tempo）、拍号（Time Signature）、调性（Key）、和弦进行、选择的鼓点/演奏模式等。
  - SwiftUI 视图通过 `@EnvironmentObject` 订阅 `AppData` 的变化来更新 UI。

### 播放器引擎

- **`ChordPlayer` (`Players/ChordPlayer.swift`)**:
  - 负责将和弦定义和演奏指法（`GuitarPattern`）转换为精确的 MIDI 音符事件。
  - 处理复杂的时序逻辑，如量化（Quantization），确保音符在正确的时间点被调度。

- **`DrumPlayer` (`Players/DrumPlayer.swift`)**:
  - 负责鼓点模式的播放。
  - 包含独立的播放循环，可以作为节拍器，并能在主播放流程中无缝切换鼓点模式。
  - 为 `ChordPlayer` 提供节拍时钟信息，以实现精确的量化。

### MIDI 与输入处理

- **`MidiManager` (`Managers/MidiManager.swift`)**:
  - 封装了与 macOS CoreMIDI 的所有交互。
  - 负责扫描和选择 MIDI 输出设备。
  - 包含一个高精度的调度器，用于在未来的精确时间点发送 MIDI Note On/Off 消息。

- **`KeyboardHandler` (`Handlers/KeyboardHandler.swift`)**:
  - 监听全局键盘事件。
  - 将键盘快捷键（如 `P` 键播放/暂停，数字键切换模式）翻译成对 `DrumPlayer`、`AppData` 等的操作。

### 数据与持久化

- **`PresetManager` (`Managers/PresetManager.swift`)**:
  - 管理所有用户预设（Preset）的加载、保存、创建和删除。
  - 每个预设是一个包含 `PerformanceConfig` 和 `AppConfig` 的完整快照。

- **`Custom...Manager` (例如 `CustomChordManager.swift`)**:
  - 负责管理用户创建的自定义内容（和弦、鼓点、演奏模式）。
  - 将用户数据从文件中加载，并提供增删改查的接口。

- **`DataModels.swift` (`Models/DataModels.swift`)**:
  - 定义了整个应用的数据结构，包括 `Preset`, `PerformanceConfig`, `ChordPerformanceConfig`, `GuitarPattern`, `DrumPattern` 等。
  - 是理解数据如何在应用中流动的关键。

## 4. 简化数据流

一个典型的用户交互数据流如下：

1.  **用户输入**: 用户按下键盘快捷键（例如，一个和弦的快捷键）。
2.  **输入处理**: `KeyboardHandler` 捕获该事件。
3.  **动作分发**: `KeyboardHandler` 调用 `ChordPlayer` 的 `playChord` 方法。
4.  **MIDI 调度**: `ChordPlayer` 根据当前的 `AppData`（如调性、速度）和和弦数据，计算出需要播放的 MIDI 音符，并请求 `MidiManager` 在精确的时间进行调度。
5.  **状态更新**: `ChordPlayer` 或其他组件可能会更新 `AppData` 中的状态（例如，当前正在播放的和弦名称）。
6.  **UI 响应**: 由于 SwiftUI 视图正在监听 `AppData`，相关的 UI（例如，高亮当前和弦的卡片）会自动更新以反映新的状态。

