# MIDISequencer API 设计文档

## 1. 目标

`MIDISequencer` 是一个全新的类，旨在为应用提供一个现代化、高性能、高精度的MIDI序列播放引擎。

它的核心任务是替代现有 `MidiManager` 中基于10ms轮询的旧调度机制，解决其性能、功耗和计时精度问题。此类将专门负责处理预先编排好的MIDI序列（`MusicSequence`）的播放，而将实时MIDI消息的发送任务留给未来的 `MIDIOutputManager`。

这标志着项目重构的第一步，旨在将功能职责清晰地分离。

## 2. 架构与职责

- **单一职责**: `MIDISequencer` 只负责“序列播放”相关的任务。它不关心MIDI设备的扫描、选择，也不负责发送即时的、非序列化的MIDI消息。
- **UI友好**: 作为一个 `ObservableObject`，它可以方便地与SwiftUI视图进行数据绑定，实时更新UI状态（如播放/暂停按钮、进度条）。
- **高性能**: 底层封装Apple的 `MusicPlayer` API，将计时和调度任务完全交给系统内核和Core Audio实时线程，实现采样级别的精度，同时将CPU和功耗降至最低。

## 3. API 详解

### 3.1. 类定义

```swift
class MIDISequencer: ObservableObject
```

### 3.2. 公开属性 (Published Properties)

#### `@Published var isPlaying: Bool = false`
- **描述**: 向UI层报告播放器当前是否正在播放。
- **用途**: 用于动态更新UI元素，例如将“播放”按钮的图标切换为“暂停”。

#### `@Published var currentTimeInBeats: MusicTimeStamp = 0.0`
- **描述**: 实时报告当前播放头所在的节拍（Beat）位置。`MusicTimeStamp` 是一个 `Double` 类型。
- **用途**: 用于驱动UI上的播放进度条，让用户可以实时看到播放进程。

### 3.3. 公开方法 (Public Methods)

#### `func play(sequence: MusicSequence, on endpoint: MIDIEndpointRef)`
- **描述**: 播放一个新的 `MusicSequence`。这是核心的播放指令。
- **参数**:
    - `sequence: MusicSequence`: 要播放的音乐数据对象。
    - `endpoint: MIDIEndpointRef`: 目标MIDI输出设备，由 `MIDIOutputManager` 提供。
- **核心逻辑**:
    1. 停止当前正在播放的任何内容。
    2. 将新的 `sequence` 加载到内部持有的 `MusicPlayer` 实例中。
    3. 通过 `MusicSequenceSetMIDIEndpoint` 将 `endpoint` 关联到序列，指定MIDI事件的发送目标。
    4. 启动 `MusicPlayer`，并更新 `isPlaying` 状态为 `true`。

#### `func stop()`
- **描述**: 完全停止播放，并将播放头重置到序列的开头（0时刻）。
- **核心逻辑**:
    1. 调用 `MusicPlayerStop()`。
    2. 更新 `isPlaying` 状态为 `false`。
    3. **依赖项**: 调用 `MIDIOutputManager.sendPanic()` (或类似方法) 来发送 "All Notes Off" 消息，以防止因 `NoteOff` 事件未被发送而导致的音符粘连问题。

#### `func pause()`
- **描述**: 暂停播放，但保持当前播放头的位置，以便后续可以继续。
- **核心逻辑**:
    1. 通过 `MusicPlayerGetTime()` 获取并存储当前的播放位置（节拍）。
    2. 调用 `MusicPlayerStop()`。
    3. 更新 `isPlaying` 状态为 `false`。

#### `func resume(on endpoint: MIDIEndpointRef)`
- **描述**: 从上次暂停的位置继续播放。
- **核心逻辑**:
    1. 通过 `MusicPlayerSetTime()` 将播放头恢复到之前保存的暂停位置。
    2. 重新确认 `endpoint`，以防MIDI输出设备在暂停期间发生变化。
    3. 调用 `MusicPlayerStart()`。
    4. 更新 `isPlaying` 状态为 `true`。

#### `func seek(to beats: MusicTimeStamp)`
- **描述**: 将播放头即时移动到指定的节拍（beat）位置。
- **参数**:
    - `beats: MusicTimeStamp`: 目标节拍位置。
- **核心逻辑**:
    1. 直接调用 `MusicPlayerSetTime()`。
    2. 此操作无论在播放、暂停还是停止状态下都即时生效。
    3. 更新 `currentTimeInBeats` 属性，以便UI同步更新。

## 4. 依赖关系

`MIDISequencer` 为了能独立工作，同时又与系统其他部分解耦，存在以下明确的依赖关系：

- 它需要从外部（未来的 `MIDIOutputManager`）获取一个 `MIDIEndpointRef`，来知道应该将音乐发送到哪个设备。
- 在执行 `stop()` 操作时，它需要调用外部的一个方法来发送全局恐慌消息（All Notes Off），以确保声音完全停止。
