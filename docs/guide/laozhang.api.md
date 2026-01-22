# nano banana pro

## 文生图

### python SDK 示例

```python
import requests
import base64

# ========== 配置 ==========
API_KEY = "sk-YOUR_API_KEY"
API_URL = "https://api.laozhang.ai/v1beta/models/gemini-3-pro-image-preview:generateContent"
PROMPT = "一只可爱的橘猫"
ASPECT_RATIO = "1:1"
IMAGE_SIZE = "2K"  # Nano Banana Pro 支持: 1K, 2K, 4K
# ============================

headers = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}

payload = {
    "contents": [{"parts": [{"text": PROMPT}]}],
    "generationConfig": {
        "responseModalities": ["IMAGE"],
        "imageConfig": {
            "aspectRatio": ASPECT_RATIO,
            "imageSize": IMAGE_SIZE
        }
    }
}

response = requests.post(API_URL, headers=headers, json=payload, timeout=180)
result = response.json()

# 保存图片
image_data = result["candidates"][0]["content"]["parts"][0]["inlineData"]["data"]
with open("output.png", "wb") as f:
    f.write(base64.b64decode(image_data))

print("✅ 图片已保存: output.png")
```

## 图生图
### python SDK 示例

```python
import requests
import base64

# ========== 配置 ==========
API_KEY = "sk-YOUR_API_KEY"
API_URL = "https://api.laozhang.ai/v1beta/models/gemini-3-pro-image-preview:generateContent"

INPUT_IMAGE = "input.png"
PROMPT = "把这张图变成梵高星空风格的油画"
ASPECT_RATIO = "1:1"
IMAGE_SIZE = "2K"
# ============================

# 读取并编码图片
with open(INPUT_IMAGE, "rb") as f:
    image_b64 = base64.b64encode(f.read()).decode("utf-8")

headers = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}

payload = {
    "contents": [{
        "parts": [
            {"text": PROMPT},
            {"inline_data": {"mime_type": "image/jpeg", "data": image_b64}}
        ]
    }],
    "generationConfig": {
        "responseModalities": ["IMAGE"],
        "imageConfig": {
            "aspectRatio": ASPECT_RATIO,
            "imageSize": IMAGE_SIZE
        }
    }
}

response = requests.post(API_URL, headers=headers, json=payload, timeout=180)
result = response.json()

# 保存图片
output_data = result["candidates"][0]["content"]["parts"][0]["inlineData"]["data"]
with open("output_styled.png", "wb") as f:
    f.write(base64.b64decode(output_data))

print("✅ 图片已保存: output_styled.png")
```