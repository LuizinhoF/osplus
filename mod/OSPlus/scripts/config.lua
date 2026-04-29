local M = {}

M.VERSION = "v43-profile-tick-stop"
M.DEBUG = false

M.LOG_DIR  = os.getenv("LOCALAPPDATA") .. "\\OSPlus"
M.LOG_FILE = M.LOG_DIR .. "\\test_events.log"

M.PING_DURATION    = 5.0
M.LINE_TRACE_DIST  = 50000.0
M.MAX_ACTIVE_PINGS = 30
M.SFX_COOLDOWN     = 0.2

M.PI     = 3.14159265
M.TWO_PI = M.PI * 2

M.COLORS = {
    WHITE   = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 },
    RED     = { R = 1.0, G = 0.2, B = 0.2, A = 1.0 },
    GREEN   = { R = 0.2, G = 1.0, B = 0.4, A = 1.0 },
    YELLOW  = { R = 1.0, G = 0.9, B = 0.2, A = 1.0 },
    CYAN    = { R = 0.0, G = 0.86, B = 1.0, A = 1.0 },
    PURPLE  = { R = 0.7, G = 0.3, B = 1.0, A = 1.0 },
    NONE    = { R = 0,   G = 0,   B = 0,   A = 0   },
}

M.PING_TYPES = {
    { key = "GENERIC", name = "Ping",      color = M.COLORS.WHITE,  label = "Lbl_Ping"    },
    { key = "DANGER",  name = "Danger",    color = M.COLORS.RED,    label = "Lbl_Danger"  },
    { key = "ASSIST",  name = "Assist",    color = M.COLORS.CYAN,   label = "Lbl_Assist"  },
    { key = "OMW",     name = "On My Way", color = M.COLORS.GREEN,  label = "Lbl_OMW"     },
    { key = "RETREAT", name = "Retreat",   color = M.COLORS.YELLOW, label = "Lbl_Retreat"  },
    { key = "AWAKEN",  name = "Awaken",    color = M.COLORS.PURPLE, label = "Lbl_Awaken"  },
}

M.PING_SPRITE_MATS = {
    GENERIC  = "/Game/CustomPings/VFX/MI_PingSprite_Generic",
    DANGER   = "/Game/CustomPings/VFX/MI_PingSprite_Danger",
    ASSIST   = "/Game/CustomPings/VFX/MI_PingSprite_Assist",
    OMW      = "/Game/CustomPings/VFX/MI_PingSprite_OMW",
    RETREAT  = "/Game/CustomPings/VFX/MI_PingSprite_Retreat",
    AWAKEN   = "/Game/CustomPings/VFX/MI_PingSprite_Awaken",
}

M.PING_SFX = {
    DANGER = "/Game/CustomPings/SFX/SFX_Danger",
}

M.ANIM_POP_DUR      = 0.15
M.ANIM_SETTLE_DUR   = 0.15
M.ANIM_SHRINK_DUR   = 1.5
M.ANIM_POP_SCALE    = 1.2
M.ANIM_PULSE_AMP    = 0.05
M.ANIM_PULSE_CYCLES = 3

M.ANIM_POP_END      = M.ANIM_POP_DUR
M.ANIM_SETTLE_END   = M.ANIM_POP_END + M.ANIM_SETTLE_DUR
M.ANIM_SHRINK_START  = M.PING_DURATION - M.ANIM_SHRINK_DUR

M.WHEEL_KEY       = 0x56  -- V
M.WHEEL_START_ANG = -M.PI / 2
M.WHEEL_DEADZONE  = 30

M.VIS_VISIBLE              = 0
M.VIS_COLLAPSED            = 1
M.VIS_HIDDEN               = 2
M.VIS_HIT_TEST_INVISIBLE   = 3
M.VIS_SELF_HIT_TEST_INVIS  = 4

M.CHAT_KEY            = 0x0D  -- Enter (VK_RETURN)
M.CHAT_CANCEL_KEY     = 0x1B  -- Escape (VK_ESCAPE)
M.CHAT_MAX_MESSAGES   = 50
M.CHAT_PLAYER_NAME    = "Me"

M.IPC_DIR     = M.LOG_DIR
M.OUTBOX_FILE = M.IPC_DIR .. "\\outbox.jsonl"
M.INBOX_FILE  = M.IPC_DIR .. "\\inbox.jsonl"
M.HEARTBEAT_FILE = M.IPC_DIR .. "\\heartbeat.txt"
M.INBOX_POLL_INTERVAL = 10  -- ~300ms at 30ms/tick, plenty fast for chat
-- Sidecar shutdown: Lua touches HEARTBEAT_FILE every HEARTBEAT_INTERVAL ticks.
-- Sidecar exits if heartbeat hasn't been touched in HEARTBEAT_TIMEOUT_MS (see sidecar/index.js).
M.HEARTBEAT_INTERVAL = 150  -- ticks (~5s at 30ms/tick)

return M
