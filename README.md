# 原神 7.1 本地服（单机自用）

在**你自己电脑上**运行的离线本地服：服务端、数据库、存档都只在本机（`127.0.0.1`），不连接任何别人的服务器，也不开放公网端口。

> 本仓库**不包含**游戏客户端、游戏资源或任何人的账号密码。
> 游戏客户端约 136 GB，太大无法放进 GitHub，由脚本从 **HoYoverse 官方 CDN** 下载 7.1.0 版本。
> 仅供个人学习研究；请勿用米哈游账号密码登录本地服，也不要把本地服开放给他人。

## 需要准备

| 项目 | 说明 |
| --- | --- |
| Windows 10/11 x64 | 脚本基于 PowerShell 5.1 |
| Java 17 或更高 | <https://adoptium.net/> 安装后 `java` 在 PATH 里即可 |
| .NET 9 运行时 | 客户端下载器需要：<https://dotnet.microsoft.com/download/dotnet/9.0>（选 .NET Runtime） |
| 磁盘空间 | 客户端约 150 GB（本体 122.9 GiB + 中文语音 13.1 GiB），服务端资源约 2 GB |
| 内存 | 建议 16 GB 以上（服务端最多占 4 GB） |

## 使用步骤

1. 下载本仓库：右上角 **Code → Download ZIP** 解压，或 `git clone`。路径里最好不要有中文和空格。
2. 双击 **`Setup.cmd`**（只需一次）。会自动：
   - 询问客户端存放目录（默认是本文件夹下的 `client-7.1`）；
   - 从本仓库 Release 下载服务端 `grasscutter.jar`、插件、客户端补丁和下载器（带 SHA256 校验）；
   - 从 MongoDB 官网下载 MongoDB 8.0.12（便携版，不安装服务）；
   - 从 [MeChen618/AstaPS-Resource](https://github.com/MeChen618/AstaPS-Resource) 下载服务端资源；
   - 让你**自己输入游戏用户名和密码**（直接回车则用户名为 `player`、密码随机生成），
     保存到 `credentials.local.json`，并创建账号（UID 10001）；网页控制台密码随机生成。
   首次启动服务端加载资源约需 5 分钟。
3. 双击 **`Download-Client.cmd`** 从官方 CDN 下载 7.1.0 客户端（可中断，重新运行会跳过已校验文件）。
   双击 **`Download-Status.cmd`** 查看进度。
4. 下载完成后双击 **`Install-Patch.cmd`**，给这份客户端装上本地服补丁（原版 DLL 自动备份）。
5. 双击 **`Play-Local.cmd`** 开玩，用第 2 步设置的用户名和密码登录（忘了可查看 `credentials.local.json`）。

想改密码：双击 **`Change-Password.cmd`**。用户名 3–20 位字母/数字/下划线，密码至少 6 位、不能有空格。
不要使用米哈游账号的密码。

## 日常管理

| 文件 | 作用 |
| --- | --- |
| `Start.cmd` / `Stop.cmd` | 启动 / 安全保存并关闭服务端 |
| `Play-Local.cmd` | 检查补丁和服务端后启动游戏 |
| `Local-Manager.ps1` | 图形管理器 |
| <http://127.0.0.1:8088/console> | 网页控制台，密码为 `consolePassword`；命令不带斜杠，`help` 查看全部 |
| `console-command.ps1 -Command 'help'` | 命令行执行服务端命令 |
| `Restore-Client.cmd` | 把客户端恢复成官方原版 DLL |
| `Change-Password.cmd` | 修改游戏账号密码 |
| `verify-local.ps1` | 检查端口、登录接口等是否正常 |

端口：HTTP `8088`、游戏 UDP `22101`、MongoDB `27018`，全部只绑定 `127.0.0.1`。

## 可选设置 `local-config.json`

`Setup.cmd` 会根据 `config/local-config.example.json` 生成，可手动修改：

- `java`：java.exe 完整路径（留空则用 PATH 里的）
- `clientPath`：客户端目录
- `directInterface`：开了 TUN/VPN 时，可填网卡名（如 `WLAN`）让下载直连官方 CDN
- `cdnIp`：仅当本机 DNS 解析不到官方 CDN 时手动指定

## 游戏本体怎么下载

**方法一（推荐）：用自带脚本从官方下载**
1. 先装 [.NET 9 运行时](https://dotnet.microsoft.com/download/dotnet/9.0)，并运行过 `Setup.cmd`。
2. 双击 `Download-Client.cmd`，自动下载 7.1.0 国际版本体 + 中文语音（约 136 GB）到 `local-config.json` 里的 `clientPath`。
3. 双击 `Download-Status.cmd` 看进度；断网或关机后重新双击 `Download-Client.cmd` 即可续传。
4. 状态显示 `completed` 后运行 `Install-Patch.cmd`。

**方法二：已有 7.1.0 国际版客户端**
把 `local-config.json` 中的 `clientPath` 改成你的客户端目录（里面有 `GenshinImpact.exe`），然后直接运行 `Install-Patch.cmd`。
建议复制一份单独的客户端，补丁会替换其中的 `Astrolabe.dll`（可用 `Restore-Client.cmd` 恢复）。

## 客户端下载链接说明

客户端文件全部来自 HoYoverse 官方 Sophon CDN，`manifests/` 里是官方接口返回的 7.1.0 版本清单快照，
下载器基于 [DangoRepo/SophonDownloader](https://github.com/DangoRepo/SophonDownloader)（源码在 `runtime/SophonDownloader-master`），会逐个文件做 MD5 校验。
官方启动器（<https://genshin.hoyoverse.com/>）只会下载最新版本，**本地服需要的是 7.1.0 国际版**，因此请用 `Download-Client.cmd`。
如果你已经有 7.1.0 国际版客户端，把 `local-config.json` 的 `clientPath` 指向它即可跳过下载。

## 来源与许可

- 服务端：[MeChen618/AstaPS](https://github.com/MeChen618/AstaPS)（Grasscutter 分支，AGPL-3.0，见 `server/LICENSE`），本仓库附带本地改动版本
- 服务端资源：[MeChen618/AstaPS-Resource](https://github.com/MeChen618/AstaPS-Resource)（固定在提交 `c0213668`）
- 客户端补丁：[capyb2222/animegamepatch](https://github.com/capyb2222/animegamepatch)，源码在 `runtime/animegamepatch-master`
- 本地插件 LocalStatueCompat：源码在 `runtime/statue-compat`
- MongoDB：<https://www.mongodb.com/>

## 已知问题

- 资源包缺少 `StatuePromoteExcelConfigData`，神像升级等相关玩法可能不正常。
- 缺少泰语 TextMapTH，不影响中文。
- 本项目与米哈游 / HoYoverse 无关。
