---
description: 添加一次 FlatPark remote，就能安装任意应用，可以只给自己装，也可以给整台电脑装。
order: 1
---

# 配置 FlatPark

FlatPark 是一个已签名的 Flatpak remote。添加一次，再添加提供运行时的 Flathub，目录里的每个应用都能用一条命令安装，或者在应用页面点"安装"按钮。

你需要先有 Flatpak 本身；大多数发行版自带，或者装一个包就有（[flatpak.org/setup](https://flatpak.org/setup/)）。

## 只给自己装（推荐）

装在你的主目录里，不需要管理员权限。

```sh
flatpak --user remote-add --if-not-exists flatpark https://dl.flatpark.org/flatpark.flatpakrepo
flatpak --user remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak --user install flatpark <app-id>
```

## 给整台电脑装

同样的命令去掉 `--user`，Flatpak 会要求输入管理员密码。

```sh
flatpak remote-add --if-not-exists flatpark https://dl.flatpark.org/flatpark.flatpakrepo
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install flatpark <app-id>
```

两种方式选一种用到底：系统级安装的应用，remote 也要按系统级添加。如果已经配过 Flathub，第二条命令什么也不会做。

## 从应用页面安装

每个应用页面都写着它的 id，还有一个"安装"按钮，点一下会复制安装命令。按钮的菜单里还能下载 `.flatpakref` 文件，用软件中心（GNOME Software、KDE Discover）打开即可安装。

整个 remote 用同一把密钥签名，客户端会用它校验每一次下载。[信任与安全](../project/trust.md)说明了这能保证什么。
