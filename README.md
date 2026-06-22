# Codex Usage Dashboard

**A macOS widget for visualizing Codex usage quota (5-hour & weekly limits) in real time.**

一个 macOS 桌面小组件，用于可视化显示 Codex 的 5 小时 / 1 周额度使用情况。

> ⚠️ Unofficial project. Not affiliated with OpenAI.

---

## 🔍 Overview | 项目简介

Codex Usage Dashboard is a lightweight macOS widget system that visualizes your Codex usage limits in real time, including:

Codex Usage Dashboard 是一个轻量级 macOS Widget 工具，用于实时可视化 Codex 使用额度，包括：

- 5-hour rolling quota window（5 小时滚动窗口）
- Weekly quota window（每周额度）
- Local-first data reading（本地优先读取）
- Optional fallback API sync（可选接口补偿同步）

---

## 📸 Demo | 效果展示

![Codex Usage Dashboard Demo](demoimage.png)

---

## ✨ Features | 功能

- 🧭 macOS Widget (Medium size) with dual-ring visualization
- ⏱ Real-time display of 5-hour & weekly usage quota
- 🧠 Host app runs in background and syncs usage state
- 🗃 Reads local Codex data sources:
  - SQLite logs
  - session JSONL files
- 🔄 Fallback to API when local data is stale
- ⚠️ Safe fallback state (`??`) when no valid data exists
- 🚫 No high-frequency polling (designed for low system impact)

---

## 📦 Download & Install | 安装方式

1. Download latest release: `CodexUsageDashboard.app.zip`
2. Unzip and move `CodexQuotaDesktop.app` to `/Applications`
3. Launch the app (keep it running in background)
4. Add Widget → select **Codex Usage Dashboard**

If macOS blocks the app:

- Go to **System Settings → Privacy & Security**
- Click “Allow Anyway”

> Note: This release is not notarized.

---

## 📊 Data Sources | 数据来源

Local-first data pipeline:

- `~/.codex/sqlite/logs_2.sqlite`
- `~/.codex/sqlite/state_5.sqlite`
- `~/.codex/sessions/**/rollout-*.jsonl`

Fallback API (low frequency):
