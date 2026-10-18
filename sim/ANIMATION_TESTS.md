# 动画检查

python sim/run_animation_tests.py --tools-dir <含bin与lib/ivl的Icarus目录> --full

完整运行29项RTL测试，其中两个播放器仿真较耗时；不加--full时运行其余27项。测试用合成FAT32扇区，不访问真实TF卡。详细结果见工程根目录仿真结果.md。

python sim/test_converter.py --ffmpeg <ffmpeg.exe路径>

验证GIF及真实MP4转换。不提供--ffmpeg时仅检查图片/GIF转换。转换器需要Pillow。
