# DSRemote —— iPhone 遥控端（自签用）

电脑上跑主程序，iPhone 上跑这个 App，两者在同一个 Wi-Fi 里对话。

```
iPhone (DSRemote)  ── HTTP/SSE ──>  电脑 (python main.py --mobile)
                                        │
                                        ├── OSR / 伺服 / 压力（USB）
                                        └── 郊狼（蓝牙或扫码）
```

手机端只做三件事：**收消息、发消息、按急停**。所有设备逻辑都在电脑上，安全层也一并复用。

## 三步走

### 第 1 步：推到 GitHub

```bash
cd DSRemote
git init
git add .
git commit -m "init"
git branch -M main
git remote add origin https://github.com/你的用户名/DSRemote.git
git push -u origin main
```

没有仓库就先在 GitHub 上新建一个 **Private** 仓库（不勾 README）。

### 第 2 步：等 Actions 编译

推上去后，仓库页 → **Actions** → 左侧 `iOS Build` → 那次运行 → 等约 5 分钟 →

页面底部 **Artifacts** → 下载 `DSRemote-unsigned-ipa` → 解压得到 `DSRemote-unsigned.ipa`

（以后改了代码，`git push` 就会自动重编。）

### 第 3 步：Windows 上签名装进手机

1. 装 [Sideloadly](https://sideloadly.io/)（Windows 版）
2. 装 iTunes（微软商店版也行，Sideloadly 要用它的驱动）
3. iPhone 插线，信任这台电脑
4. Sideloadly 里：`IPA` 选刚才那个文件，`Apple ID` 填你的免费账号
5. 点 **Start**，输入 Apple ID 密码（会走二次验证）
6. 手机：设置 → 通用 → VPN与设备管理 → 信任你的开发者证书

装好后 7 天内可用。到期重签：Sideloadly 再跑一遍第 4~6 步（约 1 分钟）。

> 想省事可以用 **AltStore + AltServer**：电脑上常驻 AltServer，7 天自动续签，不用手动重装。

## 第一次打开要做什么

App 顶部那个地址框填你电脑的地址，默认 `192.168.0.103:8080`（和终端里打印的一致）。

然后：

1. 电脑上先跑 `python main.py --mobile`
2. iPhone 连**同一个 Wi-Fi**
3. App 里点「连接」→ 圆点变绿
4. 发一条消息，看有没有回复

## 为什么这么设计

| 决定 | 理由 |
|---|---|
| 手机不带设备驱动 | USB 串口在 iOS 上根本用不了，必须电脑中转 |
| 用 HTTP + SSE 而不是自定义协议 | 后端一行不改，`mobile.py` 现成 |
| 只做聊天 + 动作 + 急停 | 第一版先跑通签名链路，别一次上太多 |
| 地址可改 | 换网络、换电脑不用重新编译 |

## 免费账号的限制

- 证书 **7 天**过期，过期 App 打不开（重签即可，数据还在）
- 最多同时签 3 个 App
- 没有推送、iCloud、App Groups（这个 App 都不需要）
- Bundle ID 用 `com.dsremote.app`，想换成别的改 `project.yml` 里那一行

## 已知问题

- 这个工程**没有在本机编译验证过**（Windows 上没有 Xcode）。第一次 Actions 跑的时候如果报错，把日志贴给我，我改。
- 后台运行：切到别的 App 后 SSE 会断，切回来会自动重连（3 秒重试）。
