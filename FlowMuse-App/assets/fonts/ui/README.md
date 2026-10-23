# FlowMuse Sans

界面专用字体，由 Google Fonts 收录的 Noto Sans SC 派生；不修改白板文档的字体或序列化数据。

- 上游：[google/fonts/ofl/notosanssc](https://github.com/google/fonts/tree/a85815a42757630ce188fdad368c2dfc444d4773/ofl/notosanssc)
- 固定版本：`a85815a42757630ce188fdad368c2dfc444d4773`
- 原始字体 Git blob：`fb0637bafbcd804fe32152370a1225990745b4bc`
- 许可证：随目录分发的 `OFL.txt`，SIL Open Font License 1.1。版权及许可证元数据也保留在字体中。
- 派生修改：生成 400、600、700 静态字重，保留 GB2312、界面源码所用字形及常用拉丁/标点字符，重命名为 FlowMuse Sans。罕见字、扩展文字及 Emoji 继续由字体回退处理；并未限制用户输入。
- 每个文件约 2.36 MB，避免将 17.77 MB 的完整可变字体引入初次加载。

在装有 Python fontTools 的开发环境（本次生成使用 4.66.0），将固定上游的 `NotoSansSC[wght].ttf`、`OFL.txt` 下载到构建目录后执行：

```powershell
python tool/prepare_ui_fonts.py 'build/ui-polish-round-one/NotoSansSC.ttf' 'build/ui-polish-round-one/OFL.txt'
```

脚本校验上游 Git blob、实际字重和裁剪后的字符覆盖；新增界面所需的罕见字符时重新生成。运行应用和 Flutter 构建不需要 Python 或 fontTools。
