# Supabase Functions 测试指南（Dashboard）

下面两段是 **可直接粘贴** 的测试内容，请严格使用英文双引号（"），否则会出现 `invalid_json`。

---

## 1) auth-device

### 请求方式
- Method: `POST`
- URL: `https://<project-ref>.supabase.co/functions/v1/auth-device`

### Request Body（复制这行）
```json
{"deviceId":"test-device-1"}
```

### 期望响应（示例）
```json
{
  "accessToken": "<很长的token>",
  "expiresIn": 604800
}
```

---

## 2) ai/format

### 请求方式
- Method: `POST`
- URL: `https://<project-ref>.supabase.co/functions/v1/ai/format`

### Headers
```
Authorization: Bearer <把上一步的accessToken粘贴进来>
```

### Request Body（复制这段）
```json
{
  "text": "今天跟张三聊了需求：1）本周出原型 2）下周评审 3）需要确认交付时间",
  "locale": "zh-CN",
  "timezone": "Asia/Shanghai",
  "styleHint": "auto",
  "maxSections": 8
}
```

### 期望响应关键字段
- `cacheHit`
- `data.title`
- `data.summary`
- `data.sections`
- `data.metrics`
