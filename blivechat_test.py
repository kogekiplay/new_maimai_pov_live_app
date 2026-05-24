import asyncio
import json
import time
import sys

try:
    import websockets
except ImportError:
    print("ERROR: websockets not installed. Run: pip install websockets")
    sys.exit(1)

SERVERS = {
    "cn": "wss://api2.blive.chat/api/chat",
    "auto": "wss://api.blive.chat/api/chat",
    "cloudflare": "wss://cloudflare.blive.chat/api/chat",
    "vercel": "wss://vercel.blive.chat/api/chat",
}

CMD_NAMES = {
    0: "HEARTBEAT",
    1: "JOIN_ROOM",
    2: "ADD_TEXT",
    3: "ADD_GIFT",
    4: "ADD_MEMBER",
    5: "ADD_SUPER_CHAT",
    6: "DEL_SUPER_CHAT",
    7: "UPDATE_TRANSLATION",
    8: "FATAL_ERROR",
}

HEARTBEAT_INTERVAL = 10
RECONNECT_DELAY = 5
MAX_RECONNECT_DELAY = 30

TEXT_FIELD_NAMES = [
    "avatarUrl",       # 0
    "timestamp",       # 1
    "authorName",      # 2
    "authorType",      # 3: 0=normal, 1=member, 2=moderator, 3=streamer
    "content",         # 4
    "privilegeType",   # 5: 0=none, 1-3=guard levels
    "isGiftDanmaku",   # 6: 0=false, 1=true
    "authorLevel",     # 7
    "isNewbie",        # 8: 0=false, 1=true
    "isMobileVerified",# 9: 0=false, 1=true
    "medalLevel",      # 10
    "id",              # 11: message ID
    "translation",     # 12
    "contentType",     # 13: 0=text, 1=emoticon
    "contentTypeParams",# 14
    "textEmoticons",   # 15: deprecated
    "uid",             # 16
    "medalName",       # 17
]

AUTHOR_TYPE_NAMES = {0: "normal", 1: "member", 2: "moderator", 3: "streamer"}
PRIVILEGE_TYPE_NAMES = {0: "none", 1: "Governor", 2: "Admiral", 3: "Captain"}


class BlivechatTester:
    def __init__(self, server_key="cn", room_key_type=2, room_key_value=""):
        self.server_url = SERVERS.get(server_key, SERVERS["cn"])
        self.room_key_type = room_key_type
        self.room_key_value = room_key_value
        self.ws = None
        self.heartbeat_task = None
        self.running = False
        self.reconnect_delay = RECONNECT_DELAY
        self.msg_count = {}
        self.total_msgs = 0
        self.first_text_logged = False
        self.first_gift_logged = False
        self.first_member_logged = False
        self.first_sc_logged = False

    async def connect(self):
        print(f"[CONNECT] Connecting to {self.server_url} ...")
        try:
            origin = self.server_url.replace("wss://", "https://").replace("/api/chat", "")
            extra_headers = {
                "Origin": origin,
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            }
            print(f"[CONNECT] Headers: Origin={origin}")
            import ssl
            ssl_context = ssl.create_default_context()
            self.ws = await websockets.connect(
                self.server_url,
                ping_interval=None,
                ping_timeout=None,
                close_timeout=5,
                additional_headers=extra_headers,
                ssl=ssl_context,
            )
            print(f"[CONNECT] Connected!")
            self.reconnect_delay = RECONNECT_DELAY
            return True
        except Exception as e:
            print(f"[CONNECT] Failed: {type(e).__name__}: {e}")
            return False

    async def send_heartbeat(self):
        while self.running and self.ws:
            try:
                msg = json.dumps({"cmd": 0})
                await self.ws.send(msg)
                print(f"[HEARTBEAT] Sent at {time.strftime('%H:%M:%S')}")
            except Exception as e:
                print(f"[HEARTBEAT] Error: {e}")
                break
            await asyncio.sleep(HEARTBEAT_INTERVAL)

    async def join_room(self):
        key_type_name = "ROOM_ID" if self.room_key_type == 1 else "AUTH_CODE"
        join_msg = {
            "cmd": 1,
            "data": {
                "roomKey": {
                    "type": self.room_key_type,
                    "value": self.room_key_value,
                },
                "config": {
                    "autoTranslate": False,
                },
            },
        }
        payload = json.dumps(join_msg)
        display_value = str(self.room_key_value)[:8] + "..." if len(str(self.room_key_value)) > 8 else self.room_key_value
        print(f"[JOIN_ROOM] type={key_type_name}({self.room_key_type}), value={display_value}")
        await self.ws.send(payload)

    def parse_add_text(self, data):
        if isinstance(data, list):
            result = {}
            for i, val in enumerate(data):
                name = TEXT_FIELD_NAMES[i] if i < len(TEXT_FIELD_NAMES) else f"field_{i}"
                result[name] = val
            result["_totalFields"] = len(data)
            return result
        elif isinstance(data, dict):
            return data
        else:
            return {"raw": data}

    def parse_add_gift(self, data):
        if isinstance(data, dict):
            return {
                "id": data.get("id"),
                "avatarUrl": (data.get("avatarUrl") or "")[:60],
                "timestamp": data.get("timestamp"),
                "authorName": data.get("authorName"),
                "totalCoin": data.get("totalCoin"),
                "totalFreeCoin": data.get("totalFreeCoin"),
                "giftName": data.get("giftName"),
                "num": data.get("num"),
                "giftIconUrl": (data.get("giftIconUrl") or "")[:60],
                "privilegeType": data.get("privilegeType"),
                "medalLevel": data.get("medalLevel"),
            }
        elif isinstance(data, list):
            result = {}
            for i, v in enumerate(data):
                result[f"field_{i}"] = v
            result["_totalFields"] = len(data)
            return result
        else:
            return {"raw": data}

    def parse_add_member(self, data):
        if isinstance(data, dict):
            return {
                "id": data.get("id"),
                "avatarUrl": (data.get("avatarUrl") or "")[:60],
                "timestamp": data.get("timestamp"),
                "authorName": data.get("authorName"),
                "privilegeType": data.get("privilegeType"),
                "giftName": data.get("giftName"),
                "num": data.get("num"),
                "totalCoin": data.get("totalCoin"),
                "price": data.get("price"),
            }
        elif isinstance(data, list):
            result = {}
            for i, v in enumerate(data):
                result[f"field_{i}"] = v
            result["_totalFields"] = len(data)
            return result
        else:
            return {"raw": data}

    def parse_add_super_chat(self, data):
        if isinstance(data, dict):
            return {
                "id": data.get("id"),
                "avatarUrl": (data.get("avatarUrl") or "")[:60],
                "timestamp": data.get("timestamp"),
                "authorName": data.get("authorName"),
                "price": data.get("price"),
                "content": data.get("content"),
                "translation": data.get("translation"),
                "privilegeType": data.get("privilegeType"),
                "medalLevel": data.get("medalLevel"),
            }
        elif isinstance(data, list):
            result = {}
            for i, v in enumerate(data):
                result[f"field_{i}"] = v
            result["_totalFields"] = len(data)
            return result
        else:
            return {"raw": data}

    def parse_fatal_error(self, data):
        if isinstance(data, dict):
            return {
                "code": data.get("code"),
                "msg": data.get("msg"),
            }
        else:
            return {"raw": data}

    async def handle_message(self, raw_msg):
        try:
            msg = json.loads(raw_msg)
        except json.JSONDecodeError:
            print(f"[RAW] Non-JSON message: {raw_msg[:200]}")
            return

        cmd = msg.get("cmd", -1)
        data = msg.get("data")
        cmd_name = CMD_NAMES.get(cmd, f"UNKNOWN({cmd})")

        self.msg_count[cmd] = self.msg_count.get(cmd, 0) + 1
        self.total_msgs += 1

        if cmd == 0:
            print(f"[{cmd_name}] Heartbeat at {time.strftime('%H:%M:%S')}")
            return

        if cmd == 2:
            parsed = self.parse_add_text(data)
            content = parsed.get("content", "?")
            username = parsed.get("authorName", "?")
            uid = parsed.get("uid", "?")
            author_type = parsed.get("authorType", "?")
            author_type_name = AUTHOR_TYPE_NAMES.get(author_type, str(author_type)) if isinstance(author_type, int) else str(author_type)
            privilege = parsed.get("privilegeType", 0)
            privilege_name = PRIVILEGE_TYPE_NAMES.get(privilege, str(privilege)) if isinstance(privilege, int) else str(privilege)
            medal_level = parsed.get("medalLevel", 0)
            medal_name = parsed.get("medalName", "")
            print(f"[{cmd_name}] {username}(uid={uid}, type={author_type_name}, priv={privilege_name}, medal=Lv{medal_level}{medal_name}): {content}")
            if not self.first_text_logged:
                self.first_text_logged = True
                print(f"  [FIRST_MSG_DETAIL] Full parsed data:")
                print(f"  {json.dumps(parsed, ensure_ascii=False, indent=4)}")
            return

        if cmd == 3:
            parsed = self.parse_add_gift(data)
            gift_name = parsed.get("giftName", "?")
            username = parsed.get("authorName", "?")
            total_coin = parsed.get("totalCoin", 0)
            total_free_coin = parsed.get("totalFreeCoin", 0)
            num = parsed.get("num", 0)
            is_paid = total_coin >= 1000 if isinstance(total_coin, int) else False
            coin_type = "paid(gold)" if is_paid else "free(silver)"
            print(f"[{cmd_name}] {username} sent {gift_name} x{num} (totalCoin={total_coin}, totalFreeCoin={total_free_coin}, {coin_type})")
            if not self.first_gift_logged:
                self.first_gift_logged = True
                print(f"  [FIRST_MSG_DETAIL] Full parsed data:")
                print(f"  {json.dumps(parsed, ensure_ascii=False, indent=4)}")
            return

        if cmd == 4:
            parsed = self.parse_add_member(data)
            username = parsed.get("authorName", "?")
            privilege_type = parsed.get("privilegeType", "?")
            priv_name = PRIVILEGE_TYPE_NAMES.get(privilege_type, f"type={privilege_type}") if isinstance(privilege_type, int) else f"type={privilege_type}"
            print(f"[{cmd_name}] {username} became {priv_name}")
            if not self.first_member_logged:
                self.first_member_logged = True
                print(f"  [FIRST_MSG_DETAIL] Full parsed data:")
                print(f"  {json.dumps(parsed, ensure_ascii=False, indent=4)}")
            return

        if cmd == 5:
            parsed = self.parse_add_super_chat(data)
            username = parsed.get("authorName", "?")
            price = parsed.get("price", "?")
            content = parsed.get("content", "?")
            print(f"[{cmd_name}] {username} SC CNY{price}: {content}")
            if not self.first_sc_logged:
                self.first_sc_logged = True
                print(f"  [FIRST_MSG_DETAIL] Full parsed data:")
                print(f"  {json.dumps(parsed, ensure_ascii=False, indent=4)}")
            return

        if cmd == 6:
            print(f"[{cmd_name}] SC deleted: {json.dumps(data, ensure_ascii=False)[:200]}")
            return

        if cmd == 7:
            print(f"[{cmd_name}] Translation update: {json.dumps(data, ensure_ascii=False)[:200]}")
            return

        if cmd == 8:
            parsed = self.parse_fatal_error(data)
            print(f"[{cmd_name}] ERROR! code={parsed.get('code')}, msg={parsed.get('msg')}")
            print(f"  [DETAIL] Full parsed: {json.dumps(parsed, ensure_ascii=False, indent=2)}")
            self.running = False
            return

        print(f"[{cmd_name}] Unknown cmd={cmd}: {json.dumps(msg, ensure_ascii=False)[:300]}")

    async def run(self):
        self.running = True
        while self.running:
            connected = await self.connect()
            if not connected:
                print(f"[RECONNECT] Will retry in {self.reconnect_delay}s ...")
                await asyncio.sleep(self.reconnect_delay)
                self.reconnect_delay = min(self.reconnect_delay * 2, MAX_RECONNECT_DELAY)
                continue

            try:
                await asyncio.sleep(1)
                await self.join_room()

                self.heartbeat_task = asyncio.create_task(self.send_heartbeat())

                async for raw_msg in self.ws:
                    await self.handle_message(raw_msg)

            except websockets.ConnectionClosed as e:
                print(f"[DISCONNECT] Code={e.code}, Reason={e.reason}")
            except Exception as e:
                print(f"[ERROR] {type(e).__name__}: {e}")
            finally:
                if self.heartbeat_task:
                    self.heartbeat_task.cancel()
                    try:
                        await self.heartbeat_task
                    except asyncio.CancelledError:
                        pass
                    self.heartbeat_task = None

            if self.running:
                print(f"[RECONNECT] Will retry in {self.reconnect_delay}s ...")
                await asyncio.sleep(self.reconnect_delay)
                self.reconnect_delay = min(self.reconnect_delay * 2, MAX_RECONNECT_DELAY)

    async def stop(self):
        self.running = False
        if self.heartbeat_task:
            self.heartbeat_task.cancel()
        if self.ws:
            await self.ws.close()
        print(f"\n[STATS] Total messages: {self.total_msgs}")
        for cmd, count in sorted(self.msg_count.items()):
            if count > 0:
                print(f"  {CMD_NAMES.get(cmd, f'cmd={cmd}')}: {count}")


def print_usage():
    print("Usage:")
    print("  python blivechat_test.py <identity_code> [server]")
    print("  python blivechat_test.py --room-id <room_id> [server]")
    print()
    print("Options:")
    print("  <identity_code>   blivechat auth code (type=2)")
    print("  --room-id <id>    use room ID instead of auth code (type=1)")
    print("  server            cn (default) | auto | cloudflare | vercel")
    print()
    print("Examples:")
    print("  python blivechat_test.py abc123def456")
    print("  python blivechat_test.py abc123def456 cn")
    print("  python blivechat_test.py --room-id 12345")


async def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print_usage()
        sys.exit(0)

    room_key_type = 2
    room_key_value = ""
    server_key = "cn"

    if sys.argv[1] == "--room-id":
        if len(sys.argv) < 3:
            print("ERROR: --room-id requires a room ID argument")
            print_usage()
            sys.exit(1)
        room_key_type = 1
        room_key_value = int(sys.argv[2])
        if len(sys.argv) >= 4:
            server_key = sys.argv[3]
    else:
        room_key_value = sys.argv[1]
        if len(sys.argv) >= 3:
            server_key = sys.argv[2]

    if not room_key_value:
        print("ERROR: Room key value is required!")
        print_usage()
        sys.exit(1)

    key_type_name = "ROOM_ID" if room_key_type == 1 else "AUTH_CODE"

    print(f"=== blivechat Chat API Protocol Tester ===")
    print(f"Server: {server_key} ({SERVERS[server_key]})")
    print(f"Room key: {key_type_name}({room_key_type}) = {str(room_key_value)[:8]}...")
    print(f"Press Ctrl+C to stop\n")

    tester = BlivechatTester(
        server_key=server_key,
        room_key_type=room_key_type,
        room_key_value=room_key_value,
    )

    try:
        await tester.run()
    except KeyboardInterrupt:
        await tester.stop()
        print("\nStopped.")


if __name__ == "__main__":
    asyncio.run(main())
