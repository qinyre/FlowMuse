# Web 扫码解码器

- 文件：`FlowMuse-App/web/scanner/zxing-0.23.0.min.js`，362150 字节。
- 上游：[@zxing/library 0.23.0](https://www.npmjs.com/package/@zxing/library/v/0.23.0)，来自官方 npm registry 包的 `package/umd/index.min.js`。
- 许可证：Apache-2.0，原文随文件放在 `LICENSE.zxing`。
- 下载时已根据 npm registry 的 `dist.integrity` 校验整个 tarball 的 SHA-512。
- 解码器 SHA-256：`3ede94153fb0c5b67a12d7adff6decd827c2b22714fdc6faecf27a8f20937ea6`。

版本与 `mobile_scanner 7.4.2` 的 ZXing JS 适配保持一致。随 Web 发布，避免现场扫描必须访问外部 CDN；使用站点 base URI 解析资源路径，兼容子目录部署。升级扫码插件时应同时核对它的 JS 接口和本文件版本。

摄像头仅在用户点击扫码后申请，不上传视频帧或识别内容；二维码沿用现有 HTTPS 房间邀请格式，密钥留在 URL fragment。相机权限被拒绝或设备没有摄像头时保留原有粘贴入房方式。
