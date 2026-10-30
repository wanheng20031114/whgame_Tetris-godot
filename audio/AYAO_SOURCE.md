# 阿咬逐字提示音

`ayao_dialogue_blip.wav` 原样复用本机 `arc-nice/resources/audio/ui/dialogue_blip.wav`（2026-10-30）。

逐字节奏参考 `arc-nice/scene/ui/shared/dialogue/dialogue_typewriter_controller.gd`：普通字符 35 ms、逗号 120 ms、句末标点 220 ms。Tetris 使用原生 Label 完整排版后逐字显示；AudioStreamRandomizer 在每次发声时微调音高（1 / 1.07 至 1.07）与音量（±1 dB）。音频经 Master 总线播放，遵循游戏音量与静音设置。
