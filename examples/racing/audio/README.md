# 赛车基础音效

六个原创PCM16/48kHz/单声道WAV由dot按主线任务单程序合成交付，不提取现成游戏声音。原ZIP SHA256：`ce59b827b85eff3c94d52b0d027588ddc6beccee862bd6aa96ba81374a920e4b`；ZIP 2923915字节，六个运行WAV合计812424字节。循环各2秒，碰墙0.28秒，倒计时0.18秒。

`source/generate_audio.py` 是可复现合成源，需要Python和NumPy，仅用于制作；游戏运行不需要这些依赖。`source/validate_audio.py` 用标准库校验。生成脚本的输出目录按原交付安排，重新制作请在独立目录运行，不覆盖正在验收的文件。

主线核对了全包哈希、PCM格式、无静音/削顶、循环接缝与三连试听数据。原交付及主线都不以波形校验声称真实听感通过；轮胎、发动机、氮气和提示音的混音需用户试玩试听。原报告、试听HTML和四个三连WAV留在主线artifacts/dot-racing-audio-candidate，不打入游戏运行包。
