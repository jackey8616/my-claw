# Hermes Gateway 調試指南

## 服務管理

### 檢查服務狀態
```bash
hermes gateway status
```

### 啟動/停止/重啟服務
```bash
hermes gateway start
hermes gateway stop
hermes gateway restart
```

## 日誌查看

### 實時查看所有日誌
```bash
hermes logs -f
```

### 查看錯誤日誌
```bash
hermes logs errors
```

### 查看最近的活動
```bash
hermes logs --since 1h     # 最近1小時
hermes logs --since 30m    # 最近30分鐘
hermes logs --since 10m    # 最近10分鐘
```

### 過濾特定消息
```bash
# 只看來自 Discord 的消息
hermes logs | grep -i discord

# 只看工具執行
hermes logs | grep "Tool:"

# 只看錯誤
hermes logs | grep -i error
```

## 故障排除

### 如果服務無法啟動
```bash
# 檢查配置
hermes config

# 檢查依賴
hermes doctor

# 重新安裝服務
hermes gateway uninstall
hermes gateway install
hermes gateway start
```

### 重置配置
```bash
# 如果需要完全重置
hermes config reset
hermes gateway uninstall
# 然後重新運行 setup script
```

## 常用調試組合

### 實時監控 Discord 活動
```bash
watch -n 2 'hermes logs --since 2m | grep -i discord'
```

### 查看當前對話上下文
```bash
# 查看最近的會話
hermes sessions list

# 在 Discord 中發送指令查看會話 ID
# 然後在這裡搜尋特定會話
hermes logs | grep "SESSION_ID"

# 或者實時監控特定會話
hermes logs -f | grep "SESSION_ID"
```

### 檢查模型使用情況
```bash
hermes logs | grep -i model
hermes logs | grep -i ollama
```