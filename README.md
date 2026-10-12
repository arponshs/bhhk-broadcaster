# 📢 BHHK BROADCASTER v2.0

Telegram Bot message broadcaster for Termux.

## 🚀 Install

```bash
pkg install git -y
git clone https://github.com/arponshs/bhhk-broadcaster.git
cd bhhk-broadcaster
bash install.sh
```

## 🎯 Usage

```bash
bhhk-broadcast
```

## 📖 Setup Guide

### 1. Create Bot
- Open Telegram → search `@BotFather`
- Send `/newbot`
- Choose name and username
- Copy the API token

### 2. Setup in Tool
- Run `bhhk-broadcast`
- Select `[1] Setup Bot`
- Paste token → auto verified

### 3. Get Users
- Users must send `/start` to your bot
- Then click `[2] Fetch Users`
- All user IDs auto-collected

### 4. Broadcast
- Click `[3] Send Broadcast`
- Type message (HTML supported)
- Watch live delivery progress

## ✨ Features

- ✅ Real Telegram Bot API
- ✅ Auto token verification
- ✅ Auto user collection
- ✅ Live delivery progress
- ✅ HTML formatting support
- ✅ Rate-limit safe (20/sec)
- ✅ Success/fail tracking
- ✅ Broadcast log
- ✅ Test message
- ✅ Statistics

## ⚠️ Important

- Users **must** /start your bot first
- Bots cannot initiate chats with strangers
- Telegram rate limit: 30 msg/sec
- This tool uses safe 20 msg/sec

## 📁 Data

```
~/.bhhk_broadcaster/
├── users.txt       (user IDs)
├── broadcast.log   (history)
├── config.conf     (bot token)
└── stats.dat       (last run)
```

## 📄 License

MIT — Free for personal use.