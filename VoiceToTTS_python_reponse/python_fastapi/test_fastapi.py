# save as main.py
from fastapi import FastAPI
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

# Allow all origins for LAN development (iPhone on same WiFi)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class Message(BaseModel):
    text: str

@app.post("/chat")
async def chat(msg: Message):
    print(f"[收到手机消息] {msg.text}")
    # Fixed reply for now; will connect to LLM later
    return {"reply": "hello world!"}

# Run with:
# conda activate firstpythonEnv310
# uvicorn main:app --host 0.0.0.0 --port 8000
#
# --host 0.0.0.0 makes the server listen on all network interfaces
# so your iPhone (on the same WiFi) can reach it via the Mac's LAN IP.
