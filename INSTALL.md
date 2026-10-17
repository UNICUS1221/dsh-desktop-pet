# 安装教程 · dsh-pet-unicus

> 🐟 **由大肥鱼完成的项目喵**

> 本文适用于 **Windows 10/11 + DeepSeek Harness（DSH）桌面版**。
> 全程不需要编译，插件是纯 JS + PowerShell 的喵。

---

## 0. 先确认前提

| 需要 | 怎么确认 |
|---|---|
| DSH 桌面版已安装并能正常对话 | 打开 App，随便问一句有回复 |
| 找到自己的 profile 目录 | 默认在 `C:\Users\<你的用户名>\.dsh\profiles\desktop` |
| 有 PowerShell 5.1 | 开始菜单搜「Windows PowerShell」能打开即可 |
| 装了 Git（可选，用 `link:` 方式时需要） | `git --version` 有输出 |

profile 目录里应该能看到这些文件喵：

```
C:\Users\<你>\.dsh\profiles\desktop\
├─ package.json          # 插件清单
├─ cordis.patch.yml      # 插件配置
└─ node_modules\         # 插件实体
```

---

## 1. 把插件文件放到本地

把 `dsh-desktop-pet` 整个文件夹放在一个**不会随便移动**的位置，例如：

```
D:\dsh-plugins\dsh-desktop-pet
```

> ⚠️ 路径里**尽量别有空格和中文**，PowerShell 传参会省心很多喵。

检查关键文件在不在：

```powershell
Get-ChildItem D:\dsh-plugins\dsh-desktop-pet
# 应该看到：package.json / cordis.patch.yml / icon.png / lib / pet
```

---

## 2. 方法一（推荐）：用包名装

插件已发布到 npm，名字是 **`dsh-pet-unicus`**喵。

1. DSH 左侧 **插件** → 右上角 **「添加插件」**；
2. 输入框填：
   ```
   dsh-pet-unicus
   ```
3. 点 **安装**，等它跑完；
4. **重启 DSH**，小鲸鱼就上桌了喵。

装完文件在：
`C:\Users\<你>\.dsh\profiles\desktop\node_modules\dsh-pet-unicus\`

> 想升级：插件页移除再用同样名字装一次即可喵。

## 3. 方法二（可选）：GitHub 地址 / 本地目录

内置「添加插件」同样认这两种写法：

- Git 仓库：`https://github.com/UNICUS1221/dsh-desktop-pet`
- 本地目录（绝对路径）：`D:\dsh-plugins\dsh-desktop-pet`

## 4. 方法三（手动）：改 profile


### 2.1 改 profile 的 `package.json`

打开 `C:\Users\<你>\.dsh\profiles\desktop\package.json`，加两处：

```json
{
  "dependencies": {
    "dsh-desktop-pet": "link:D:/dsh-plugins/dsh-desktop-pet"
  },
  "dsh": {
    "profile": {
      "bundles": ["dsh-desktop-pet"]
    }
  }
}
```

- `link:` 指向你上一步放插件的目录（**正斜杠**，路径用 `D:/...` 这种写法）；
- 想更稳一点就直接把文件夹**复制**到
  `C:\Users\<你>\.dsh\profiles\desktop\node_modules\dsh-desktop-pet`，
  `dependencies` 里写 `"dsh-desktop-pet": "file:./node_modules/dsh-desktop-pet"` 也行喵。

### 2.2 改 `cordis.patch.yml`

在文件里加入（如果已有 `insert:` 段，就把它加到列表里）：

```yaml
insert:
  - id: desktop-pet
    name: dsh-desktop-pet
```

可以顺便在下面写配置（都是可选的喵）：

```yaml
  - id: desktop-pet
    name: dsh-desktop-pet
    config:
      alertBelow: 5      # 余额低于多少喊一次（0 = 关闭）
      budget: 10         # 今日预算超了喊一次（0 = 关闭）
      selfwake:
        enabled: true
        intervalMinutes: 60
        jitterMinutes: 8
        minIdleMinutes: 45
        maxUnanswered: 7
        quietStartHour: 22
        quietEndHour: 8
        dailyMax: 3
```

### 2.3 装依赖（用了 `link:` 的话）

```powershell
cd C:\Users\<你>\.dsh\profiles\desktop
pnpm install
```

> DSH 自带 pnpm；如果你没有，可以跳过这步直接**复制文件夹**的方式喵。

---

## 3. 重启 DSH

1. 完全退出 DSH（托盘图标也要退）；
2. 重新打开；
3. 左上角「插件」页 →「已安装」里应该能看到 **dsh-desktop-pet** 和它的图标喵；
4. 几秒后桌面上会出现小鲸鱼。

> 桌宠本体是 PowerShell 起的独立进程，插件被停用后她可能还在；
> 想让她下班：右键她 →「退出」，或删掉 `%TEMP%\dsh-pet-quit.txt` 触发退出喵。

---

## 4. 首次使用

| 操作 | 效果 |
|---|---|
| 左键点她一下 | 弹余额卡（余额 / 今日已用） |
| 再点 | 换一句台词；连点 6 次以上会生气（红泡） |
| 鼠标悬停 | 右侧出现 ☰ 菜单按钮 |
| 右键她 | 打开菜单（大小 / 音效 / 吸附 / 用量记录 / 退出） |
| 按住拖动 | 拖到任意位置，贴边会吸附 |

配置文件在 `dsh-desktop-pet\pet\config.json`，常用项喵：

```json
{
  "scale": 220,            // 形象大小（像素）
  "autoCardMinutes": 12,   // 多久没说话就自己报一次余额（0 = 关闭）
  "memeEnabled": true,     // 每天抓一条网络梗
  "alertBelow": 5,
  "budget": 10,
  "snap": true,
  "clickSound": true
}
```

词库在 `dsh-desktop-pet\pet\lines.txt`，`## 分区名` 开分区，一行一条；改完点她一下或
右键「资源管理 → 换一批台词」就生效喵。

---

## 5. 排错清单

| 现象 | 原因 / 处理 |
|---|---|
| 插件页看不到她 | `dsh.profile.bundles` 里没加名字，或没重启 DSH |
| 桌面上没有形象 | 看 `pet\pet.log` 最后几行；常见是没有权限运行 PowerShell |
| 余额一直显示「—」 | 刚启动前 60 秒是正常的，`credentials` 还没注册好 |
| 形象出现在屏幕外 | 删掉 `pet\config.json` 让她回到默认位置，再重新拖 |
| 菜单按钮不出现 | 鼠标要停在她**身上**（窗口范围内）；或菜单里「隐藏菜单按钮」被打开了 |
| 每天没有新梗 | 断网/接口被墙会走本地兜底；看 `lines.txt` 的 `## 网络梗` 分区 |
| 两个声音重复说话 | 同时装了 `dsh-selfwake`，关掉其中一个喵 |

日志位置：`dsh-desktop-pet\pet\pet.log`
（每行一条，含启动时的 DPI / 位置 / 尺寸，出问题先看它喵）

---

## 6. 卸载

1. 右键桌宠 →「退出」；
2. profile 的 `package.json` 里删掉 `dsh-desktop-pet` 依赖与 bundles 里的名字；
3. `cordis.patch.yml` 里删掉对应 `insert` 项；
4. 删掉 `node_modules\dsh-desktop-pet`（如果是 `link:` 方式，只是删链接）；
5. 重启 DSH。

---

## 附：它由哪些部分组成

```
宿主侧（lib/index.js）  —— 在 DSH 进程里跑
  · 从 credentials / deepseekAccount 读余额
  · 记每轮消耗（事件 + 账本兜底）
  · 自唤醒闸门（间隔 / 抖动 / 静默时段 / 每日上限）
  · 把要说的话写进 %TEMP%\dsh-pet-inbox.jsonl

桌宠侧（pet/pet.ps1）  —— 独立 WPF 进程
  · 透明置顶窗口 + 形象 + ☰ 菜单
  · 气泡（余额卡 / 情绪台词 / 通知）
  · 读取 inbox、写心跳、响应退出
```

两边靠 `%TEMP%` 下的三个文件通信喵：

| 文件 | 作用 |
|---|---|
| `dsh-pet-inbox.jsonl` | 宿主 → 桌宠，一行一条要说的话 |
| `dsh-pet-alive.txt` | 桌宠心跳（宿主判断她是否活着） |
| `dsh-pet-quit.txt` | 宿主 → 桌宠，让她退出 |
