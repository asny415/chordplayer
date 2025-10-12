# ChordPlayer for macOS

### ⚠️ 重要声明
这是一个完全由 AI 驱动的项目。我本人（项目作者）没有任何 SwiftUI 或 macOS App 开发经验。整个应用程序是通与大语言模型（主要是 Google的 Gemini 2.5 Pro）进行“氛围编程（Vibe Coding）”构建的。因此，代码中可能存在不规范、不优雅或完全错误的地方。欢迎提出任何改进建议！

<!-- 在这里插入应用主界面的截图 -->
![应用主界面](/samples/cover.jpg)

## 快速入门 (Get Started)
要使用本应用，你需要一个能够接收MIDI信号的宿主程序（DAW），例如 Logic Pro, GarageBand, Ableton Live 等。以下以免费的 Logic Pro 为例进行说明。

### 第一步：启用 IAC 驱动
1. 打开 macOS 的 “音频MIDI设置” (Audio MIDI Setup) 应用 (可以在“应用程序/实用工具”里找到)。
2. 在菜单栏选择 “窗口” -> “显示MIDI工作室”。
3. 双击 “IAC 驱动” (IAC Driver) 图标。
4. 在弹出的窗口中，勾选 “设备在线” (Device is online)。
5. 在端口部分，你可以保留默认的 "IAC Bus 1"，或点击“+”来添加一个新的虚拟MIDI端口。请确保至少有一个端口存在。

### 第二步：下载并设置 Logic Pro
1. 从 Mac App Store 或者苹果官网下载并安装 Logic Pro（新用户通常有90天的免费试用期）。
2. 打开 Logic Pro 并创建一个新的空项目，选择“软件乐器”轨道。
3. Logic Pro 会自动将键盘或MIDI输入分配给新轨道。为了确保它能接收来自 ChordPlayer 的信号，你可以检查 Logic Pro 的 `设置 > MIDI > 输入`，但通常默认设置即可工作。

<!-- 在这里插入 Logic Pro 设置界面的截图 -->
![Logic Pro 设置](/samples/logic.jpg)

### 第三步：导入并演奏乐曲
1. 启动 ChordPlayer 应用。
2. 在 ChordPlayer 的MIDI输出设置中，选择 "IAC Driver IAC Bus 1" 作为输出设备。
3. 本项目在 `sample` 目录下提供了一个示例乐曲。
4. 在 ChordPlayer 中导入该乐曲文件。
5. 点击播放，你应该能在 Logic Pro 中听到由 ChordPlayer 实时演奏的音乐！

## 主要功能
*   **和弦进行编辑**：轻松创建和编辑歌曲的和弦进行。
*   **鼓点编辑器**：为你的歌曲创建和自定义鼓点。
*   **旋律与歌词**：试验性的旋律和歌词编辑器。
*   **MIDI 输出**：将所有内容通过虚拟MIDI端口发送给你最喜欢的数字音频工作站（DAW）。

## 愿景
这个项目的目标是打造一个 macOS 上的“自己动手”版本的 Band-in-a-Box。虽然目前功能还很初级，但它展示了通过 AI 辅助编程来快速实现复杂软件原型的可能性。

## 贡献
欢迎任何形式的贡献！如果你发现了 Bug，有新的功能想法，或者想改进代码，请随时提交 Pull Request 或创建 Issue。

## 许可
本项目采用 [MIT 许可证](LICENSE)。
