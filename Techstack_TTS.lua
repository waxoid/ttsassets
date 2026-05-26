--[[ Lua code. See documentation: https://api.tabletopsimulator.com/ --]]
-- Global script handlers for the TTS implementation of board game Techstack (playtesting)

-- ============================================================
-- SECTION: Utility/Helper Routines
-- support functions, no game state dependencies
-- ============================================================

EDIT_MODE = false -- Toggle in chat with: editmode (also supports !editmode and /editmode)

local function debugPrint(msg)
    if EDIT_MODE then
        print(msg)
    end
end

local function marketLog(msg)
    if MARKET_DEBUG then
        debugPrint("[MARKET] " .. msg)
    end
end

local function stackLog(msg)
    if STACK_DEBUG then
        debugPrint("[STACK] " .. msg)
    end
end

function colorChangeLog(message)
    if not EDIT_MODE then return end
    print("[COLOR_CHANGE] " .. tostring(message))
end

local function debugBroadcastToColor(message, player_color)
    if EDIT_MODE then
        broadcastToColor(message, player_color)
    end
end

local function makeVec3(x, y, z)
    return {
        x = tonumber(x) or 0,
        y = tonumber(y) or 0,
        z = tonumber(z) or 0
    }
end

local function getPrimaryHandPositionForPlayer(p)
    if not p or not p.getHandTransform then return nil end

    -- In most setups each seated player has one primary hand transform.
    for i = 1, 4 do
        local ok, hand = pcall(function() return p.getHandTransform(i) end)
        if ok and hand and hand.position then
            return hand.position
        end
    end

    for i = 0, 1 do
        local ok, hand = pcall(function() return p.getHandTransform(i) end)
        if ok and hand and hand.position then
            return hand.position
        end
    end

    return nil
end

-- ============================================================
-- SECTION: Game State & Infrastructure
-- game state, game load, event dispatch, player seats
-- ============================================================

local MARKER_MARBLE_OWNER_BY_GUID = {
    ["455985"] = "Blue",
    ["b4ad63"] = "Yellow",
    ["0edcd3"] = "Green",
    ["7eda46"] = "Purple",
    ["2b1f08"] = "Neutral",
}
local MARKER_MARBLE_BUTTON_SIZE = 440
local MARKER_SPAWN_HEIGHT_OFFSET = 0.20
local MARKER_SPAWN_CLEARANCE = 0.42
local MARKER_SPAWN_LATERAL_INSET = 0.20
local MARKER_SPAWN_UP_REDUCTION = 0.30
local MARKER_SPAWN_DOWN_SHIFT = 0.40

local BRAND_TRACK_START_POSITIONS = {
    {x = -7.21, y = 1.39, z = 18.76},
    {x = -6.43, y = 1.39, z = 18.76},
    {x = -7.21, y = 1.39, z = 18.37},
    {x = -6.43, y = 1.39, z = 18.37},
}

local MORALE_TRACK_START_POSITIONS = {
    {x = -6.67, y = 1.39, z = 25.45},
    {x = -6.30, y = 1.39, z = 25.45},
    {x = -6.67, y = 1.39, z = 25.03},
    {x = -6.30, y = 1.39, z = 25.03},
}

-- Market row configuration
DEVELOPER_DECK_GUID = "d70f0d" -- needed for dev deck functionality, but NOTE also enables tag menu (rebuild utility)
TECH_DECK_GUID = "90412a"
ANALYST_DECK_GUID = "207668"
STARTER_PROJECT_DECK_GUID = "cc6ab0"
STARTER_DEVELOPER_DECK_GUID = "e75ad4"
START_GAME_BUTTON_GUID = "7a82ee"
START_BEGINNER_BUTTON_GUID = "79268f"
local MARKET_SLOT_THRESHOLD = 0.9
local TALENT_ROW_SLOT_THRESHOLD = 0.9
local DEV_DECK_SLOT_THRESHOLD = 0.85
local DEV_FACE_DOWN_Z = 180
local DEV_FACE_UP_Z = 0
local DEV_SNAP_DX = 0.78        -- snap-grid spacing (visual; may be within TTS merge radius)
local DEV_ANTI_MERGE_DX = 1.5  -- split offset used when TTS merges two dev cards; must exceed TTS merge radius
local DEV_RECENT_SPLITS = {}    -- [cardGuid] = true while a just-split card is in cooldown

local ANALYST_CARD_POSITIONS = {
    {x = -14.16, y = 1.21, z = 23.85},
    {x = -14.16, y = 1.21, z = 20.75}
}

DISCARD_TILE_GUID = "9f37fc"
RESHUFFLE_BUTTON_GUID = "3af8c8"
TECH_DECK_TILE_GUID = "fe3621"

DEV_DECK_TILE_GUID = "8b98a3"
DEV_DISCARD_TILE_GUID = "5c153d"
DEV_RESHUFFLE_BUTTON_GUID = "287741"

local TALENT_ROW_PLACEHOLDER_GUIDS = {
    "394666",
    "4ef354",
    "ae4041",
    "2416ff",
    "1d983a",
}

local DISCARD_SLOT_THRESHOLD = 1.35  -- was 1.2; expanded for more forgiving discard detection
local DISCARD_ROTATION = {x = 0, y = 90, z = 0}
local RESHUFFLE_CONFIRM_SECONDS = 6
local RESHUFFLE_PENDING_BY_COLOR = {}
local DEV_RESHUFFLE_PENDING_BY_COLOR = {}
local TECH_DECK_HOME_POSITION = nil
local TECH_DECK_HOME_ROTATION = nil
local DEV_DECK_HOME_POSITION = nil
local DEV_DECK_HOME_ROTATION = nil
local DEV_LAST_DRAG_INFO = nil  -- {guid, dropX} of most-recently dropped developer card
local DEV_RECENTLY_LEFT_HAND = {} -- [guid] = true for a short window after leaving a hand zone

local REFERENCE_ROUND_GUIDE_URL = "https://raw.githubusercontent.com/waxoid/ttsassets/main/guide_front.png"
local REFERENCE_CARD_ICON_URL = "https://raw.githubusercontent.com/waxoid/ttsassets/main/guide_back.png"
local REFERENCE_ROUND_PANEL_ID = "ref_panel_round_guide"
local REFERENCE_CARD_ICON_PANEL_ID = "ref_panel_card_icon"
local REFERENCE_MENU_ATTACHED = false
local CAMERA_MENU_ATTACHED = false
local MARKER_MENU_ATTACHED = false
local PASS_HUD_PANEL_ID = "pass_hud_panel"
local PASS_HUD_MAX_LINES = 4
local STARTING_PLAYER_TOKEN_GUID = "83cc6f"
local OWNER_SNAP_POINT = {
    position = {x = 0.89368, y = 0.20929, z = -1.20459},
    rotation = {x = 0, y = 0, z = 0},
    rotation_snap = true,
    tags = {"marker"}
}
local BOARD_SNAP_MENU_ATTACHED_BY_GUID = {}
local PASSED_BY_COLOR = {} -- [playerColor] = true when that player has passed for the round
local HUD_PLAYER_CACHE = {}
local STARTED_PLAYER_COLORS = {}
local STARTED_PLAYER_NAME_BY_COLOR = {}
local RESERVED_PLAYER_COLORS = {
    Black = true,
}
local PLAYABLE_COLOR_PRIORITY = {"Blue", "Yellow", "Green", "Purple"}
local COLOR_ENFORCE_BUSY = false
local STARTED_COLOR_ENFORCE_BUSY = false
local FREE_JOINS = false
local ROUND_MARKER_GUID = "b5def1"
local ROUND3_MARKER_Z = 23.16
local ROUND3_MARKER_Z_TOLERANCE = 0.20
local ROUND3_BASES_COLLECTED = false
local ROUND3_BASES_COLLECT_IN_PROGRESS = false
local ROUND3_BASES_RECENTLY_MOVED_GUIDS = {}

local ROUND3_BASE_ROW_1_Z = -12.21
local ROUND3_BASE_ROW_2_Z = -15.51
local ROUND3_BASE_ROW_Z_TOLERANCE = 0.25
local ROUND3_BASES_COLLECT_DEST = {x = -39.40, y = 1.17, z = 39.69}
local ROUND3_BASE_ROW_1_GUIDS = {"8acc6e", "0fd6f3", "96b59c", "997214", "7a3216"}
local ROUND3_BASE_ROW_2_GUIDS = {"a07e1f", "68d6d6", "c39848", "4a3853", "57c844"}

function normalizePlayerNameKey(value)
    return string.lower(tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function getStartedColorForPlayerName(playerName)
    local wanted = normalizePlayerNameKey(playerName)
    if wanted == "" then return nil end

    for color, startedName in pairs(STARTED_PLAYER_NAME_BY_COLOR or {}) do
        if normalizePlayerNameKey(startedName) == wanted then
            return normalizePlayerColorLabel(color)
        end
    end

    return nil
end

function isGameStartedWithRoster()
    return STARTED_PLAYER_COLORS and #STARTED_PLAYER_COLORS > 0
end

function findSeatedPlayerByName(playerName)
    local wanted = normalizePlayerNameKey(playerName)
    if wanted == "" then return nil end

    for _, color in ipairs(Player.getColors()) do
        local p = getPlayerByColorSafe(color)
        if p and p.seated and normalizePlayerNameKey(p.steam_name) == wanted then
            return p
        end
    end
    return nil
end

function setStartedPlayersFromState(colors, namesByColor)
    local ordered = {}
    local seen = {}

    for _, rawColor in ipairs(colors or {}) do
        local color = normalizePlayerColorLabel(rawColor)
        if color and not seen[color] and color ~= "Neutral" then
            table.insert(ordered, color)
            seen[color] = true
        end
    end

    STARTED_PLAYER_COLORS = ordered
    STARTED_PLAYER_NAME_BY_COLOR = {}

    for color, rawName in pairs(namesByColor or {}) do
        local normalizedColor = normalizePlayerColorLabel(color)
        if normalizedColor and normalizedColor ~= "Neutral" then
            STARTED_PLAYER_NAME_BY_COLOR[normalizedColor] = tostring(rawName or normalizedColor)
        end
    end
end

function getOrderedColorsFromSet(colorSet)
    local ordered = {}
    local seen = {}

    for _, color in ipairs(Player.getColors()) do
        if colorSet[color] and not seen[color] then
            table.insert(ordered, color)
            seen[color] = true
        end
    end

    for color, _ in pairs(colorSet) do
        if not seen[color] then
            table.insert(ordered, color)
            seen[color] = true
        end
    end

    return ordered
end

function isHostColor(player_color)
    if not player_color then return false end
    local p = getPlayerByColorSafe(player_color)
    return p and p.host == true
end

-- 6 locked low-opacity square tile GUIDs that represent card market positions (left to right)
local MARKET_PLACEHOLDER_GUIDS = {
    "56d87a",
    "422e82",
    "2b56d1",
    "d570bb",
    "5a43b8",
    "ac51d9",
}

local BOARD_CAMERA_BY_PRESET = {
    ["1"] = {guid = "cf7ce4", yaw = 0},
    ["2"] = {guid = "a2b1bb", yaw = 90},
    ["3"] = {guid = "169a56", yaw = 180},
    ["4"] = {guid = "d132c0", yaw = 270},
}

local function getCameraPresetLookAt(player_color, presetName)
    local preset = string.lower(tostring(presetName or ""))
    local TOP_DOWN_PITCH = 90

    local boardSpec = BOARD_CAMERA_BY_PRESET[preset]
    if boardSpec then
        local boardObj = getObjectFromGUID(boardSpec.guid)
        if not boardObj then
            return nil
        end

        local bagPos = boardObj.getPosition()
        local boardPitch = (82 + TOP_DOWN_PITCH) / 2
        return {
            position = {x = bagPos.x, y = bagPos.y + 0.5, z = bagPos.z},
            pitch = boardPitch,
            yaw = boardSpec.yaw,
            distance = 18,
        }
    end

    local function getMarketLookAt()
        local devCorner = getObjectFromGUID(TALENT_ROW_PLACEHOLDER_GUIDS[1])
        local marketCorner = getObjectFromGUID(MARKET_PLACEHOLDER_GUIDS[6])
        if devCorner and marketCorner then
            local devPos = devCorner.getPosition()
            local marketPos = marketCorner.getPosition()
            local centerX = (devPos.x + marketPos.x) / 2
            local centerY = (devPos.y + marketPos.y) / 2
            local centerZ = (devPos.z + marketPos.z) / 2
            local marketPitch = (65 + TOP_DOWN_PITCH) / 2

            return {
                position = {x = centerX, y = centerY + 0.25, z = centerZ},
                pitch = marketPitch,
                yaw = 0,
                distance = 24,
            }
        end
        return nil
    end

    if preset == "stack" then
        local stackPitch = (82 + TOP_DOWN_PITCH) / 2
        return {
            position = {
                x = STACK_TOPLEFT_POSITION.x + (STACK_LAYOUT_DX * 3.5),
                y = STACK_TOPLEFT_POSITION.y,
                z = STACK_TOPLEFT_POSITION.z - 2.2,
            },
            pitch = stackPitch,
            yaw = 0,
            distance = 24,
        }
    end

    if preset == "market" then
        return getMarketLookAt()
    end

    return nil
end

local function focusCameraPreset(player_color, presetName)
    if not player_color then return end
    local p = Player[player_color]
    if not p then return end

    local lookAt = getCameraPresetLookAt(player_color, presetName)
    if not lookAt then
        broadcastToColor("Unknown camera preset: " .. tostring(presetName), player_color)
        broadcastToColor("Try: cam 1, cam 2, cam 3, cam 4, cam stack, cam market", player_color)
        return
    end

    lookAt.smooth = false

    pcall(function()
        p.lookAt(lookAt)
    end)
end


-- ============================================================
-- SECTION: Stack & Marker Placement
-- Spawn markers and auto-spawn on base and stack placement
-- ============================================================

local PLAYER_TINTS = {
    White  = {1, 1, 1},
    Brown  = {0.443, 0.231, 0.09},
    Red    = {0.856, 0.1, 0.094},
    Orange = {0.956, 0.392, 0.113},
    Yellow = {0.905, 0.898, 0.172},
    Green  = {0.192, 0.701, 0.168},
    Teal   = {0.129, 0.694, 0.607},
    Blue   = {0.118, 0.53, 1},
    Purple = {0.627, 0.125, 0.941},
    Pink   = {0.96, 0.439, 0.807},
    Grey   = {0.5, 0.5, 0.5},
    Black  = {0.25, 0.25, 0.25}
}

local function getPlayerTint(color)
    if not PLAYER_TINTS then return {1, 1, 1} end

    local key = tostring(color or "")
    if key == "" then
        return {1, 1, 1}
    end

    local tint = PLAYER_TINTS[key]
    if not tint and key == "Gray" then tint = PLAYER_TINTS["Grey"] end
    if not tint and key == "Grey" then tint = PLAYER_TINTS["Gray"] end
    if not tint then tint = PLAYER_TINTS["White"] end
    if not tint then tint = {1, 1, 1} end

    return {tint[1] or 1, tint[2] or 1, tint[3] or 1}
end

local function useDirectMarkerSupply()
    return true
end

local function normalizeColor(value, fallback)
    local fb = fallback or {r = 1, g = 1, b = 1}
    local r = value and (value.r or value[1]) or fb.r
    local g = value and (value.g or value[2]) or fb.g
    local b = value and (value.b or value[3]) or fb.b
    if r == nil then r = fb.r end
    if g == nil then g = fb.g end
    if b == nil then b = fb.b end
    return {r = r, g = g, b = b}
end

function normalizePlayerColorLabel(value)
    local wanted = string.lower(tostring(value or ""))
    if wanted == "" then return nil end
    if wanted == "neutral" then return "Neutral" end
    if wanted == "gray" then wanted = "grey" end

    for color, _ in pairs(PLAYER_TINTS) do
        if string.lower(color) == wanted then
            return color
        end
    end

    return nil
end

function normalizeSeatColorKey(value)
    local normalized = normalizePlayerColorLabel(value)
    if not normalized then return tostring(value or "") end
    if normalized == "Grey" then return "Gray" end
    return normalized
end

function getPlayerByColorSafe(color)
    local key = normalizeSeatColorKey(color)
    if key == "" then return nil end

    local ok, p = pcall(function() return Player[key] end)
    if ok then return p end

    -- Fallback alias support if this table uses the alternate spelling.
    if key == "Gray" then
        local okGrey, pGrey = pcall(function() return Player["Grey"] end)
        if okGrey then return pGrey end
    end

    return nil
end

local function getDirectMarkerTint(ownerLabel)
    local normalizedOwner = normalizePlayerColorLabel(ownerLabel)
    if normalizedOwner == "White" then
        return normalizeColor({r = 0.733, g = 0.898, b = 0.910})
    end
    if normalizedOwner == "Neutral" then
        return normalizeColor(getPlayerTint("Black"))
    end
    if normalizedOwner then
        return normalizeColor(getPlayerTint(normalizedOwner))
    end
    return normalizeColor({r = 1, g = 1, b = 1})
end

local function spawnDirectMarkerForOwner(ownerLabel, targetPos, markerName, markerNotes, extraTag)
    if not targetPos then return false end

    local okSpawn, spawnErr = pcall(function()
        spawnObject({
            type = "BlockSquare",
            position = {x = targetPos.x, y = (targetPos.y or 1) + 0.2, z = targetPos.z},
            scale = {x = 0.3, y = 0.3, z = 0.3},
            rotation = {x = 0, y = 0, z = 0},
            callback_function = function(marker)
                if not marker then
                    stackLog("direct marker spawn returned nil owner=" .. tostring(ownerLabel))
                    return
                end

                pcall(function()
                    marker.addTag("marker")
                    if extraTag and extraTag ~= "" then
                        marker.addTag(extraTag)
                    end
                    if markerName then
                        marker.setName(markerName)
                    end
                    if markerNotes and marker.setGMNotes then
                        marker.setGMNotes(markerNotes)
                    end
                    marker.setColorTint(getDirectMarkerTint(ownerLabel))
                    marker.setPosition(targetPos)
                end)
            end
        })
    end)

    if not okSpawn then
        stackLog("direct marker spawn failed owner=" .. tostring(ownerLabel) .. " err=" .. tostring(spawnErr))
        return false
    end
    return true
end

local function getMarkerMarbleTooltip(ownerLabel)
    local key = tostring(ownerLabel or "")
    if key == "Neutral" then
        return "neutral markers"
    end
    return string.lower(key) .. " markers"
end

local function getObjectPlanarSize(obj)
    if not obj then return 2.0, 2.0 end
    local okBN, bn = pcall(function()
        return obj.getBoundsNormalized and obj.getBoundsNormalized() or nil
    end)
    local size = okBN and bn and bn.size or nil
    if not size then
        local okB, b = pcall(function()
            return obj.getBounds and obj.getBounds() or nil
        end)
        size = okB and b and b.size or nil
    end
    local sx = size and (size.x or 2.0) or 2.0
    local sz = size and (size.z or 2.0) or 2.0
    return sx, sz
end

local safeGetPosition

local function normalizePlanar(dx, dz)
    local mag = math.sqrt((dx * dx) + (dz * dz))
    if mag <= 0.0001 then return 0, 0 end
    return dx / mag, dz / mag
end

local function dotPlanar(ax, az, bx, bz)
    return (ax * bx) + (az * bz)
end

local function isMarkerNearPosition(targetPos, radius)
    if not targetPos then return false end
    local r2 = (radius or MARKER_SPAWN_CLEARANCE)
    r2 = r2 * r2
    for _, obj in ipairs(getAllObjects()) do
        if obj and safeHasTag(obj, "marker") then
            local pos = safeGetPosition(obj)
            if pos then
                local dx = (pos.x or 0) - (targetPos.x or 0)
                local dz = (pos.z or 0) - (targetPos.z or 0)
                local d2 = (dx * dx) + (dz * dz)
                if d2 <= r2 then
                    return true
                end
            end
        end
    end
    return false
end

-- Asset groups for each of the 4 player positions.
-- 1st GUID = main player board, 2nd GUID = tracking tile, 3rd GUID = "A" VC card.
-- (NOTE these guid mappings are used for calculating marker creation zones, detecting player board proximity)
-- Remaining GUIDs are default starting cards/tokens for that seat.
local PLAYER_POSITION_ASSET_GROUPS = {
    {
        label = "south",
        guids = {"cf7ce4", "a76793", "9f1d38", "cbcc83", "09aa49", "8759b3", "88f03c", "ae079a", "131c5e", "89c959", "3d02e3", "455985"},
    },
    {
        label = "west",
        guids = {"a2b1bb", "629342", "b884c0", "436366", "83b114", "fd7cc7", "85add2", "9155e1", "5b5e31", "4b5411", "cf756d", "b4ad63"},
    },
    {
        label = "north",
        guids = {"169a56", "bec6ed", "85e5db", "f9c9a5", "d152e9", "481840", "ba5da7", "2cf636", "ad6628", "3e1b69", "6205f3", "0edcd3"},
    },
    {
        label = "east",
        guids = {"d132c0", "755ddf", "2a342f", "679185", "9923f5", "847e5f", "37093b", "406064", "4ed232", "3f15d3", "ce53f7", "7eda46"},
    },
}

local function getSeatAssetGroupForPlayerColor(playerColor)
    local p = getPlayerByColorSafe(playerColor)
    local handPos = getPrimaryHandPositionForPlayer(p)
    if not handPos then return nil end

    local bestGroup = nil
    local bestD2 = nil
    for _, group in ipairs(PLAYER_POSITION_ASSET_GROUPS or {}) do
        local boardGuid = group and group.guids and group.guids[1] or nil
        local boardObj = boardGuid and getObjectFromGUID(boardGuid) or nil
        local boardPos = safeGetPosition(boardObj)
        if boardPos then
            local dx = (boardPos.x or 0) - (handPos.x or 0)
            local dz = (boardPos.z or 0) - (handPos.z or 0)
            local d2 = (dx * dx) + (dz * dz)
            if not bestD2 or d2 < bestD2 then
                bestD2 = d2
                bestGroup = group
            end
        end
    end

    return bestGroup
end

local function computeMarkerSpawnRectForPlayer(playerColor)
    local group = getSeatAssetGroupForPlayerColor(playerColor)
    if not group or not group.guids then return nil end

    local board = getObjectFromGUID(group.guids[1] or "")
    local trackingTile = getObjectFromGUID(group.guids[2] or "")
    local avcCard = getObjectFromGUID(group.guids[3] or "")
    if not board or not trackingTile or not avcCard then return nil end

    local boardPos = safeGetPosition(board)
    local tilePos = safeGetPosition(trackingTile)
    local avcPos = safeGetPosition(avcCard)
    if not boardPos or not tilePos or not avcPos then return nil end

    local upDx, upDz = normalizePlanar(-(boardPos.x or 0), -(boardPos.z or 0))
    if upDx == 0 and upDz == 0 then
        upDx, upDz = normalizePlanar((avcPos.x or 0) - (boardPos.x or 0), (avcPos.z or 0) - (boardPos.z or 0))
    end
    if upDx == 0 and upDz == 0 then
        return nil
    end

    local rightDx, rightDz = upDz, -upDx

    local tileWidth = select(1, getObjectPlanarSize(trackingTile))
    local avcWidth, avcDepth = getObjectPlanarSize(avcCard)
    local avcHeight = math.max(avcWidth, avcDepth)

    local tileRightX = (tilePos.x or 0) + rightDx * (tileWidth * 0.5)
    local tileRightZ = (tilePos.z or 0) + rightDz * (tileWidth * 0.5)
    local avcLeftX = (avcPos.x or 0) - rightDx * (avcWidth * 0.5)
    local avcLeftZ = (avcPos.z or 0) - rightDz * (avcWidth * 0.5)

    local latFromTile = dotPlanar(tileRightX - (avcPos.x or 0), tileRightZ - (avcPos.z or 0), rightDx, rightDz)
    local latFromAvc = dotPlanar(avcLeftX - (avcPos.x or 0), avcLeftZ - (avcPos.z or 0), rightDx, rightDz)
    local latMin = math.min(latFromTile, latFromAvc)
    local latMax = math.max(latFromTile, latFromAvc)

    -- Pull each lateral edge inward slightly so spawn points stay clear of side boundaries.
    local inset = MARKER_SPAWN_LATERAL_INSET
    local minSpanAfterInset = 0.20
    if (latMax - latMin) > ((2 * inset) + minSpanAfterInset) then
        latMin = latMin + inset
        latMax = latMax - inset
    end

    if (latMax - latMin) < 0.20 then
        local centerLat = (latMin + latMax) * 0.5
        latMin = centerLat - 0.10
        latMax = centerLat + 0.10
    end

    local spanUp = math.max(0.20, (avcHeight * (5.0 / 6.0)) - MARKER_SPAWN_UP_REDUCTION)
    local upMin = -MARKER_SPAWN_DOWN_SHIFT

    return {
        center = {x = avcPos.x, y = avcPos.y, z = avcPos.z},
        upDx = upDx,
        upDz = upDz,
        rightDx = rightDx,
        rightDz = rightDz,
        latMin = latMin,
        latMax = latMax,
        upMin = upMin,
        spanUp = spanUp,
    }
end

local function getMarkerSpawnPointForPlayer(playerColor)
    local rect = computeMarkerSpawnRectForPlayer(playerColor)
    if not rect then
        local p = getPlayerByColorSafe(playerColor)
        local handPos = getPrimaryHandPositionForPlayer(p)
        if not handPos then return nil end
        return {
            x = (handPos.x or 0) + ((math.random() - 0.5) * 0.8),
            y = (handPos.y or 1) + MARKER_SPAWN_HEIGHT_OFFSET,
            z = (handPos.z or 0) + ((math.random() - 0.5) * 0.8),
        }
    end

    for _ = 1, 16 do
        local lat = rect.latMin + ((rect.latMax - rect.latMin) * math.random())
        local up = (rect.upMin or 0) + (rect.spanUp * math.random())
        local point = {
            x = (rect.center.x or 0) + (rect.rightDx * lat) + (rect.upDx * up),
            y = (rect.center.y or 1) + MARKER_SPAWN_HEIGHT_OFFSET,
            z = (rect.center.z or 0) + (rect.rightDz * lat) + (rect.upDz * up),
        }
        if not isMarkerNearPosition(point, MARKER_SPAWN_CLEARANCE) then
            return point
        end
    end

    return {
        x = (rect.center.x or 0) + (rect.upDx * ((rect.upMin or 0) + (rect.spanUp * 0.5))),
        y = (rect.center.y or 1) + MARKER_SPAWN_HEIGHT_OFFSET,
        z = (rect.center.z or 0) + (rect.upDz * ((rect.upMin or 0) + (rect.spanUp * 0.5))),
    }
end

function onMarkerMarbleClick(obj, player_color, alt_click)
    local marbleGuid = safeGetGuid(obj)
    local designatedOwner = marbleGuid and MARKER_MARBLE_OWNER_BY_GUID[marbleGuid] or nil
    if not designatedOwner then return end

    local playerRef = getPlayerByColorSafe(player_color)
    if not playerRef or not playerRef.seated then
        return
    end

    local spawnPos = getMarkerSpawnPointForPlayer(player_color)
    if not spawnPos then return end

    local markerName = string.lower(tostring(designatedOwner)) .. " marker"
    spawnDirectMarkerForOwner(designatedOwner, spawnPos, markerName, nil, "marker")
end

local function addMarkerForClicker(player_color, ownerLabel)
    local playerRef = getPlayerByColorSafe(player_color)
    if not playerRef or not playerRef.seated then
        return
    end

    local spawnPos = getMarkerSpawnPointForPlayer(player_color)
    if not spawnPos then return end

    local markerName = string.lower(tostring(ownerLabel)) .. " marker"
    spawnDirectMarkerForOwner(ownerLabel, spawnPos, markerName, nil, "marker")
end

local function getActiveSeatMarkerColorsClockwise()
    local present = {}
    if STARTED_PLAYER_COLORS and #STARTED_PLAYER_COLORS > 0 then
        for _, color in ipairs(STARTED_PLAYER_COLORS) do
            local normalized = normalizePlayerColorLabel(color)
            if normalized then
                present[normalized] = true
            end
        end
    end

    local ordered = {}
    for _, color in ipairs({"Blue", "Yellow", "Green", "Purple"}) do
        if present[color] then
            table.insert(ordered, color)
        end
    end
    return ordered
end

function attachMarkerSpawnMenu()
    if MARKER_MENU_ATTACHED then return end
    if not isGameStartedWithRoster() then return end

    local mat = getObjectFromGUID(STACK_MAT_GUID)
    if not mat then return end

    local ordered = getActiveSeatMarkerColorsClockwise()
    if #ordered == 0 then return end

    mat.addContextMenuItem("────────", function(player_color)
        -- Divider before marker-add actions.
    end)

    for _, color in ipairs(ordered) do
        local owner = color
        mat.addContextMenuItem("Add " .. string.lower(color) .. " marker", function(player_color)
            addMarkerForClicker(player_color, owner)
        end)
    end

    if #ordered < 4 then
        mat.addContextMenuItem("Add neutral marker", function(player_color)
            addMarkerForClicker(player_color, "Neutral")
        end)
    end

    MARKER_MENU_ATTACHED = true
end

function setupMarkerMarbleButtons(removeUnusedNeutralMarble)
    local activeCount = 0
    if STARTED_PLAYER_COLORS and #STARTED_PLAYER_COLORS > 0 then
        activeCount = #STARTED_PLAYER_COLORS
    else
        local seatedNow = getActiveSeatedPlayers()
        activeCount = seatedNow and #seatedNow or 0
    end
    local useNeutral = activeCount < 4
    local allowNeutralCleanup = removeUnusedNeutralMarble == true

    for marbleGuid, ownerLabel in pairs(MARKER_MARBLE_OWNER_BY_GUID or {}) do
        local marble = getObjectFromGUID(marbleGuid)
        if marble then
            if ownerLabel == "Neutral" and not useNeutral and allowNeutralCleanup then
                pcall(function() marble.destruct() end)
            else
                pcall(function()
                    marble.clearButtons()
                    marble.createButton({
                        click_function = "onMarkerMarbleClick",
                        function_owner = Global,
                        label = "",
                        position = {0, 0.18, 0},
                        rotation = {0, 0, 0},
                        width = MARKER_MARBLE_BUTTON_SIZE,
                        height = MARKER_MARBLE_BUTTON_SIZE,
                        font_size = 1,
                        color = {0, 0, 0, 0},
                        font_color = {0, 0, 0, 0},
                        tooltip = getMarkerMarbleTooltip(ownerLabel),
                    })
                end)
            end
        end
    end
end

function hasUsableHandTransformForPlayer(p)
    if not p or not p.getHandTransform then return false end

    for i = 1, 4 do
        local okHand, hand = pcall(function() return p.getHandTransform(i) end)
        if okHand and hand and hand.position then
            return true
        end
    end

    return false
end


-- ============================================================
-- SECTION: Card Handling
-- card rows, discard, market, placement, drop/pickup events
-- ============================================================

STACK_MAT_GUID = "c2221a"
STACK_COUNTER_TEMPLATE_GUIDS = {"131c5e", "cf756d", "ad6628", "ce53f7"}
STACK_TOPLEFT_POSITION = {x = -18.07, y = 1.15, z = 8.91}
STACK_LAYOUT_DX = 5.2
STACK_LAYOUT_DZ = 0.66
STACK_DZ_MULTIPLE = 5
STACK_COLUMNS = 8
STACK_ROWS = 10
STACK_COUNTER_DX = 0.10
STACK_COUNTER_DZ = 2.05
STACK_COUNTER_Y = 1.13
STACK_IMPROVEMENT_DY = 0.02
STACK_IMPROVEMENT_LAYER_DY = 0.04   -- increased from 0.005 for visible separation between improvement layers
AUTOMARKER_BOUNDARY_Z = -21.4
PROJECT_CONVENIENCE_DZ = 0.6
STACK_PROJECT_SNAP_ROTATION = {x = 0, y = 0, z = 0}

local STACK_POSITION_TOLERANCE = 0.45
local STACK_BASE_DETECT_RADIUS = 1.5
local STACK_COLUMN_FALLBACK_TOLERANCE = 1.20
local STACK_COUNTER_TAG = "stackcounter"
local STACK_BASE_MARKER_TAG = "stackmarkerauto"
local STACK_AUTOMARKER_SNAP_ROT_Y = 180
local STACK_AUTOMARKER_SNAP_ROT_Y_TOLERANCE = 2
local STACK_COUNTER_TEMPLATE_GUID_CACHE = nil
local STACK_DEBUG = true
local STACK_TUCKED_IMPROVEMENT_GUIDS = {} -- [guid] = true for cards we intentionally tucked as improvements
local HAND_REARRANGE_GUIDS = {}           -- [guid] = true for cards lifted from a hand zone (suppress re-rotation on re-entry)
local HAND_PENDING_ROTATION_TOKEN = {}    -- [guid] monotonic token to cancel stale delayed hand-rotation callbacks
local START_GAME_BUSY = false             -- prevents re-entrant start clicks from racing setup operations
local START_GAME_SETUP_IN_PROGRESS = false -- suppresses event side-effects while startup is populating the board

local function resolveStackCounterTemplate()
    if STACK_COUNTER_TEMPLATE_GUID_CACHE then
        local cached = getObjectFromGUID(STACK_COUNTER_TEMPLATE_GUID_CACHE)
        if cached then
            return cached
        end
        STACK_COUNTER_TEMPLATE_GUID_CACHE = nil
    end

    for _, guid in ipairs(STACK_COUNTER_TEMPLATE_GUIDS or {}) do
        local obj = getObjectFromGUID(guid)
        if obj then
            STACK_COUNTER_TEMPLATE_GUID_CACHE = guid
            debugPrint("[STACK] resolved stack counter template guid=" .. tostring(guid))
            return obj
        end
    end

    return nil
end

local function cloneStackCounterFromTemplate(template, targetPos, targetRot)
    if not template then return nil, "nil-template" end

    local okClone, clonedOrErr = pcall(function()
        return template.clone({
            position = {
                x = targetPos.x,
                y = targetPos.y + 2,
                z = targetPos.z
            },
            rotation = targetRot,
            sound = false,
            snap_to_grid = false
        })
    end)

    if not okClone then
        return nil, tostring(clonedOrErr)
    end

    return clonedOrErr, nil
end


local MARKET_PLACEHOLDER_SLOT_BY_GUID = {}
local MARKET_PICKUP_SLOT_BY_GUID = {}
local TALENT_ROW_SLOT_BY_GUID = {}
local TALENT_ROW_PICKUP_SLOT_BY_GUID = {}
local ROW_PLACEHOLDER_BUTTON_WIDTH = 720   -- 60% of previous width (1200)
local ROW_PLACEHOLDER_BUTTON_HEIGHT = 800  -- 50% of previous height (1600)
local PROJECT_PICKUP_INTERSECTING_GUIDS_BY_GUID = {} -- [projectGuid] = { [otherGuid] = true }
local PROJECT_CONVENIENCE_GROUP_MEMBER_BY_GUID = {} -- [cardGuid] = true once card participates in convenience layering
local MARKET_DEBUG = true

local function getDiscardTile()
    if not DISCARD_TILE_GUID or DISCARD_TILE_GUID == "" or DISCARD_TILE_GUID == "xxxxxx" then
        return nil
    end
    return getObjectFromGUID(DISCARD_TILE_GUID)
end

local function getReshuffleButtonHost()
    if not RESHUFFLE_BUTTON_GUID or RESHUFFLE_BUTTON_GUID == "" or RESHUFFLE_BUTTON_GUID == "xxxxxx" then
        return nil
    end
    return getObjectFromGUID(RESHUFFLE_BUTTON_GUID)
end

local function getTechDeckTile()
    if not TECH_DECK_TILE_GUID or TECH_DECK_TILE_GUID == "" or TECH_DECK_TILE_GUID == "xxxxxx" then
        return nil
    end
    return getObjectFromGUID(TECH_DECK_TILE_GUID)
end

local function getDevDeckTile()
    if not DEV_DECK_TILE_GUID or DEV_DECK_TILE_GUID == "" or DEV_DECK_TILE_GUID == "xxxxxx" then
        return nil
    end
    return getObjectFromGUID(DEV_DECK_TILE_GUID)
end

local function getDevDiscardTile()
    if not DEV_DISCARD_TILE_GUID or DEV_DISCARD_TILE_GUID == "" or DEV_DISCARD_TILE_GUID == "xxxxxx" then
        return nil
    end
    return getObjectFromGUID(DEV_DISCARD_TILE_GUID)
end

local function getDevReshuffleButtonHost()
    if not DEV_RESHUFFLE_BUTTON_GUID or DEV_RESHUFFLE_BUTTON_GUID == "" or DEV_RESHUFFLE_BUTTON_GUID == "xxxxxx" then
        return nil
    end
    return getObjectFromGUID(DEV_RESHUFFLE_BUTTON_GUID)
end

local function getTechDeckHomeTransform()
    local tile = getTechDeckTile()
    local rot = TECH_DECK_HOME_ROTATION

    if tile then
        local pos = tile.getPosition()
        if not rot then
            rot = tile.getRotation()
        end
        return {x = pos.x, y = pos.y + 0.25, z = pos.z}, rot
    end

    return TECH_DECK_HOME_POSITION, rot
end

local function getDevDeckHomeTransform()
    local tile = getDevDeckTile()
    local rot = DEV_DECK_HOME_ROTATION

    if tile then
        local pos = tile.getPosition()
        if not rot then
            rot = tile.getRotation()
        end
        return {x = pos.x, y = pos.y + 0.25, z = pos.z}, rot
    end

    return DEV_DECK_HOME_POSITION, rot
end

local function getDiscardPilePosition()
    local tile = getDiscardTile()
    if not tile then return nil end

    local pos = tile.getPosition()
    return {x = pos.x, y = pos.y + 0.25, z = pos.z}
end

local function getDevDiscardPilePosition()
    local tile = getDevDiscardTile()
    if not tile then return nil end

    local pos = tile.getPosition()
    return {x = pos.x, y = pos.y + 0.25, z = pos.z}
end

local function getLiveObjectByGUID(guid)
    if not guid or guid == "" then return nil end
    return getObjectFromGUID(guid)
end

local function clamp01(v)
    local n = tonumber(v) or 0
    if n < 0 then return 0 end
    if n > 1 then return 1 end
    return n
end

local function rgbToHex(color)
    local r = math.floor((clamp01(color[1] or color.r or 1) * 255) + 0.5)
    local g = math.floor((clamp01(color[2] or color.g or 1) * 255) + 0.5)
    local b = math.floor((clamp01(color[3] or color.b or 1) * 255) + 0.5)
    return string.format("#%02X%02X%02X", r, g, b)
end

local function rebuildHudPlayerCache()
    if STARTED_PLAYER_COLORS and #STARTED_PLAYER_COLORS > 0 then
        local entries = {}

        for _, color in ipairs(STARTED_PLAYER_COLORS) do
            local p = getPlayerByColorSafe(color)
            local pos = getPrimaryHandPositionForPlayer(p)
            local liveName = p and p.steam_name
            if liveName and liveName ~= "" then
                STARTED_PLAYER_NAME_BY_COLOR[color] = liveName
            end

            local displayName = STARTED_PLAYER_NAME_BY_COLOR[color] or (liveName and liveName ~= "" and liveName or color)
            table.insert(entries, {color = color, name = displayName, pos = pos})
        end

        HUD_PLAYER_CACHE = entries
        return
    end

    local entries = {}
    local okPlayers, players = pcall(function()
        return Player.getPlayers()
    end)
    if okPlayers and players then
        for _, p in ipairs(players) do
            local color = p and p.color or nil
            if color then
                local pos = getPrimaryHandPositionForPlayer(p)
                local name = tostring((p.steam_name and p.steam_name ~= "") and p.steam_name or color)
                table.insert(entries, {color = color, name = name, pos = pos})
            end
        end
    end

    if #entries <= 1 then
        local single = {}
        for _, e in ipairs(entries) do
            table.insert(single, e)
        end
        HUD_PLAYER_CACHE = single
        return
    end

    local cx, cz, n = 0, 0, 0
    for _, e in ipairs(entries) do
        if e.pos then
            cx = cx + (e.pos.x or 0)
            cz = cz + (e.pos.z or 0)
            n = n + 1
        end
    end
    if n == 0 then
        table.sort(entries, function(a, b) return a.color < b.color end)
        local fallback = {}
        for _, e in ipairs(entries) do table.insert(fallback, e) end
        HUD_PLAYER_CACHE = fallback
        return
    end
    cx = cx / n
    cz = cz / n

    local twoPi = math.pi * 2
    local southAngle = nil
    for _, e in ipairs(entries) do
        if e.pos then
            e.angle = math.atan((e.pos.z or 0) - cz, (e.pos.x or 0) - cx)
        else
            e.angle = nil
        end
        if e.color == "Blue" and e.angle then
            southAngle = e.angle
        end
    end

    local startAngle = southAngle
    if not startAngle then
        for _, e in ipairs(entries) do
            if e.angle then
                startAngle = e.angle
                break
            end
        end
    end
    if not startAngle then startAngle = 0 end

    for _, e in ipairs(entries) do
        if e.angle then
            e.cw = (startAngle - e.angle) % twoPi
        else
            e.cw = twoPi + 1
        end
    end

    table.sort(entries, function(a, b)
        if a.cw ~= b.cw then return a.cw < b.cw end
        return a.color < b.color
    end)

    local ordered = {}
    for _, e in ipairs(entries) do
        table.insert(ordered, e)
    end
    HUD_PLAYER_CACHE = ordered
end

local function getHudOrderedEntries()
    return HUD_PLAYER_CACHE or {}
end

local function getStartingPlayerColorFromToken(hudEntries)
    local token = getObjectFromGUID(STARTING_PLAYER_TOKEN_GUID)
    if not token then return nil end

    local tokenPos = token.getPosition()
    if not tokenPos then return nil end

    local bestColor = nil
    local bestD2 = nil
    for _, entry in ipairs(hudEntries or {}) do
        if entry and entry.pos then
            local dx = (entry.pos.x or 0) - (tokenPos.x or 0)
            local dz = (entry.pos.z or 0) - (tokenPos.z or 0)
            local d2 = (dx * dx) + (dz * dz)
            if not bestD2 or d2 < bestD2 then
                bestD2 = d2
                bestColor = entry.color
            end
        end
    end

    return bestColor
end

local function updatePassHud()
    if not UI or not UI.setAttribute then return end

    local orderedEntries = getHudOrderedEntries()
    local tintByColor = PLAYER_TINTS or {}
    local startingColor = getStartingPlayerColorFromToken(orderedEntries)
    for i = 1, PASS_HUD_MAX_LINES do
        local lineId = "pass_hud_line_" .. tostring(i)
        local entry = orderedEntries[i]
        if entry then
            local color = entry.color
            local baseName = entry.name or color
            local isStartingPlayer = (startingColor and color == startingColor)
            local label = (isStartingPlayer and ("► " .. baseName) or baseName)
            local passed = PASSED_BY_COLOR[color] == true
            local lineText = passed and (label .. " (passed)") or label
            local lineColor = passed and {0.6, 0.6, 0.6} or (tintByColor[color] or {1, 1, 1})
            UI.setAttribute(lineId, "text", lineText)
            UI.setAttribute(lineId, "color", rgbToHex(lineColor))
            UI.setAttribute(lineId, "active", "true")
        else
            UI.setAttribute(lineId, "text", "")
            UI.setAttribute(lineId, "active", "false")
        end
    end
end

local function refreshPassHudSafe(reasonLabel)
    local ok, err = pcall(function()
        rebuildHudPlayerCache()
        updatePassHud()
    end)
    if not ok then
        print("[PASS_HUD] refresh failed reason=" .. tostring(reasonLabel) .. " err=" .. tostring(err))
    end
    return ok
end

local function normalizeYaw(y)
    local yaw = tonumber(y) or 0
    yaw = yaw % 360
    if yaw < 0 then yaw = yaw + 360 end
    return yaw
end

local function getHandRelativeCardYaw(zone, isIndustry)
    local zoneYaw = 0
    if zone and zone.getRotation then
        local zr = zone.getRotation()
        zoneYaw = normalizeYaw(zr and zr.y or 0)
    end

    -- South hand baseline: project cards use 180, industry cards use 90.
    -- Offset these baselines by the hand-zone yaw so all seats render consistently.
    if isIndustry then
        return normalizeYaw(zoneYaw + 90)
    end
    return normalizeYaw(zoneYaw + 180)
end

local function bumpHandRotationToken(guid)
    if not guid or guid == "" then return nil end
    local nextToken = (HAND_PENDING_ROTATION_TOKEN[guid] or 0) + 1
    HAND_PENDING_ROTATION_TOKEN[guid] = nextToken
    return nextToken
end

local function objectIsCurrentlyInAnyHandZone(obj)
    if not obj or not obj.getZones then return false end
    local okZones, zones = pcall(function() return obj.getZones() end)
    if not okZones or type(zones) ~= "table" then return false end
    for _, z in ipairs(zones) do
        if z and z.tag == "Hand" then
            return true
        end
    end
    return false
end

local function scheduleHandRotationIfCurrent(obj, zone, isIndustry, delayFrames, reasonLabel)
    if not obj or not zone then return end
    local guid = obj.getGUID and obj.getGUID() or nil
    if not guid then return end

    local token = bumpHandRotationToken(guid)

    Wait.frames(function()
        local liveObj = getObjectFromGUID(guid)
        if not liveObj then
            return
        end
        if HAND_PENDING_ROTATION_TOKEN[guid] ~= token then
            return
        end
        if not objectIsCurrentlyInAnyHandZone(liveObj) then
            return
        end

        local yaw = getHandRelativeCardYaw(zone, isIndustry)
        pcall(function()
            liveObj.setRotationSmooth({x = 0, y = yaw, z = 0}, false, true)
        end)
    end, delayFrames or 0)

end

local function isObjectAtDiscardPile(obj)
    if not obj then return false end
    if obj.hasTag and obj.hasTag("developer") then return false end

    local discardPos = getDiscardPilePosition()
    if not discardPos then return false end

    local pos = obj.getPosition()
    local dx = pos.x - discardPos.x
    local dz = pos.z - discardPos.z

    -- If the card is closer to the main deck than the discard pile, let main deck logic handle it
    local mainDeck = getLiveObjectByGUID and getLiveObjectByGUID(TECH_DECK_GUID)
    if mainDeck then
        local deckPos = mainDeck.getPosition()
        local deckDx = pos.x - deckPos.x
        local deckDz = pos.z - deckPos.z
        local deckDist2 = deckDx * deckDx + deckDz * deckDz
        local discardDist2 = dx * dx + dz * dz
        if deckDist2 < discardDist2 then
            return false
        end
    end

    return (dx * dx + dz * dz) <= (DISCARD_SLOT_THRESHOLD * DISCARD_SLOT_THRESHOLD)
end

local function isObjectAtDevDiscardPile(obj)
    if not obj then return false end
    if not obj.hasTag or not obj.hasTag("developer") then return false end

    local discardPos = getDevDiscardPilePosition()
    if not discardPos then return false end

    local pos = obj.getPosition()
    local dx = pos.x - discardPos.x
    local dz = pos.z - discardPos.z

    return (dx * dx + dz * dz) <= (DISCARD_SLOT_THRESHOLD * DISCARD_SLOT_THRESHOLD)
end

local function orientObjectForDiscard(obj)
    if not obj then return end

    local guid = obj.getGUID()
    local discardPos = getDiscardPilePosition()
    if not discardPos then return end

    local function applyDiscardPose(target)
        if not target then return end

        pcall(function()
            if target.type == "Card" and target.is_face_down then
                target.flip()
            end

            -- Always anchor to discard tile height so dragged mini-decks cannot hover.
            target.setPositionSmooth({x = discardPos.x, y = discardPos.y, z = discardPos.z}, false, true)
            target.setRotationSmooth(DISCARD_ROTATION, false, true)
        end)
    end

    applyDiscardPose(obj)

    Wait.frames(function()
        applyDiscardPose(getLiveObjectByGUID(guid))
    end, 2)
end

local function getDiscardPileObjects()
    local discardPos = getDiscardPilePosition()
    if not discardPos then return {} end

    local matches = {}

    for _, obj in ipairs(getAllObjects()) do
        if obj and (obj.type == "Deck" or obj.type == "Card") and (not obj.hasTag or not obj.hasTag("developer")) then
            local ok, pos = pcall(function()
                return obj.getPosition()
            end)

            if ok and pos then
                local dx = pos.x - discardPos.x
                local dz = pos.z - discardPos.z
                local d2 = (dx * dx) + (dz * dz)

                if d2 <= (DISCARD_SLOT_THRESHOLD * DISCARD_SLOT_THRESHOLD) then
                    table.insert(matches, {obj = obj, objType = obj.type, dist = d2})
                end
            end
        end
    end

    table.sort(matches, function(a, b)
        if a.objType ~= b.objType then
            return a.objType == "Deck"
        end
        return a.dist < b.dist
    end)

    local results = {}
    for _, entry in ipairs(matches) do
        table.insert(results, entry.obj)
    end

    return results
end

local function getDevDiscardPileObjects()
    local discardPos = getDevDiscardPilePosition()
    if not discardPos then return {} end

    local matches = {}

    for _, obj in ipairs(getAllObjects()) do
        if obj and (obj.type == "Deck" or obj.type == "Card") and obj.hasTag and obj.hasTag("developer") then
            local ok, pos = pcall(function()
                return obj.getPosition()
            end)

            if ok and pos then
                local dx = pos.x - discardPos.x
                local dz = pos.z - discardPos.z
                local d2 = (dx * dx) + (dz * dz)

                if d2 <= (DISCARD_SLOT_THRESHOLD * DISCARD_SLOT_THRESHOLD) then
                    table.insert(matches, {obj = obj, objType = obj.type, dist = d2})
                end
            end
        end
    end

    table.sort(matches, function(a, b)
        if a.objType ~= b.objType then
            return a.objType == "Deck"
        end
        return a.dist < b.dist
    end)

    local results = {}
    for _, entry in ipairs(matches) do
        table.insert(results, entry.obj)
    end

    return results
end

local function getDiscardDeckObject()
    local objects = getDiscardPileObjects()
    return objects[1]
end

local function getDevDiscardDeckObject()
    local objects = getDevDiscardPileObjects()
    return objects[1]
end

-- Returns another developer Card within merge-range of obj, or nil.
-- Used to detect and prevent accidental deck formation outside allowed zones.
local function findNearbyDeveloperCard(obj)
    if not obj then return nil end
    local pos = obj.getPosition()
    local guid = obj.getGUID()
    local MERGE_RADIUS_SQ = 1.5 * 1.5  -- generous radius; TTS merges ~0.5-1.0 units
    for _, other in ipairs(getAllObjects()) do
        if other.type == "Card" and other.getGUID() ~= guid
                and other.hasTag and other.hasTag("developer") then
            local opos = other.getPosition()
            local dx = pos.x - opos.x
            local dz = pos.z - opos.z
            if (dx * dx + dz * dz) <= MERGE_RADIUS_SQ then
                return other
            end
        end
    end
    return nil
end

-- True if pos is within the dev-deck tile zone (tag-free position check).
local function posNearDevDeckZone(pos)
    if not pos then return false end
    local tile = getDevDeckTile()
    local ref = tile and tile.getPosition() or DEV_DECK_HOME_POSITION
    if not ref then
        local d = getObjectFromGUID(DEVELOPER_DECK_GUID)
        ref = d and d.getPosition() or nil
    end
    if not ref then return false end
    local dx, dz = pos.x - ref.x, pos.z - ref.z
    return (dx*dx + dz*dz) <= (DEV_DECK_SLOT_THRESHOLD * DEV_DECK_SLOT_THRESHOLD)
end

-- True if pos is within the dev-discard tile zone.
local function posNearDevDiscardZone(pos)
    if not pos then return false end
    local discardPos = getDevDiscardPilePosition()
    if not discardPos then return false end
    local dx, dz = pos.x - discardPos.x, pos.z - discardPos.z
    return (dx*dx + dz*dz) <= (DISCARD_SLOT_THRESHOLD * DISCARD_SLOT_THRESHOLD)
end

-- Returns true if any contained object in a Deck has the "developer" tag.
local function deckContainsDeveloperCard(deckObj)
    if not deckObj or deckObj.type ~= "Deck" then return false end
    local ok, objs = pcall(function() return deckObj.getObjects() end)
    if not ok or not objs then return false end
    for _, d in ipairs(objs) do
        if d.tags then
            for _, t in ipairs(d.tags) do
                if t == "developer" then return true end
            end
        end
    end
    return false
end

-- Splits a developer Deck that formed outside allowed zones, scattering
-- all cards except the last one (which remains as a lone Card automatically).
local function splitRogueDeveloperDeck(deckObj)
    if not deckObj or deckObj.type ~= "Deck" then return end
    local pos = deckObj.getPosition()
    if posNearDevDeckZone(pos) or posNearDevDiscardZone(pos) then return end
    if not deckContainsDeveloperCard(deckObj) then return end

    local guid = deckObj.getGUID()
    local count = #deckObj.getObjects()
    marketLog("splitting rogue developer deck guid=" .. guid .. " count=" .. count)

    local function scatterNext(iter)
        local live = getObjectFromGUID(guid)
        if not live or live.type ~= "Deck" then return end
        local dp = live.getPosition()
        local angle = ((iter - 1) / math.max(count - 1, 1)) * 2 * math.pi
        pcall(function()
            live.takeObject({
                index      = 0,
                position   = {x = dp.x + math.cos(angle) * 1.8,
                              y = dp.y + 0.5,
                              z = dp.z + math.sin(angle) * 1.8},
                smooth     = false,
            })
        end)
        if iter < count - 1 then
            Wait.frames(function() scatterNext(iter + 1) end, 2)
        end
    end

    scatterNext(1)
end

local function resetReshuffleConfirmation(player_color)
    if player_color then
        RESHUFFLE_PENDING_BY_COLOR[player_color] = nil
    end

    local host = getReshuffleButtonHost()
    if host and host.editButton then
        pcall(function()
            host.editButton({
                index = 0,
                label = "",
                width = 2250,
                height = 630,
                color = {0.2, 0.2, 0.2, 0},
                tooltip = "Shuffle discard pile into main tech deck"
            })
        end)
    end
end

local function resetDevReshuffleConfirmation(player_color)
    if player_color then
        DEV_RESHUFFLE_PENDING_BY_COLOR[player_color] = nil
    end

    local host = getDevReshuffleButtonHost()
    if host and host.editButton then
        pcall(function()
            host.editButton({
                index = 0,
                label = "",
                width = 2250,
                height = 630,
                color = {0.2, 0.2, 0.2, 0},
                tooltip = "Shuffle developer discard into developer deck"
            })
        end)
    end
end

local function updateTechDeckProtection()
    local shouldLock = not EDIT_MODE

    local deck = getObjectFromGUID(TECH_DECK_GUID)
    if deck then
        if not TECH_DECK_HOME_POSITION then
            TECH_DECK_HOME_POSITION = deck.getPosition()
        end
        if not TECH_DECK_HOME_ROTATION then
            TECH_DECK_HOME_ROTATION = deck.getRotation()
        end
        deck.setLock(shouldLock and deck.type == "Deck")
    end

    for _, discardObj in ipairs(getDiscardPileObjects()) do
        discardObj.setLock(shouldLock and discardObj.type == "Deck")
    end

    marketLog("deck protection refreshed; deck-only locks=" .. tostring(shouldLock))
end

local function updateDevDeckProtection()
    local shouldLock = not EDIT_MODE

    local deck = getObjectFromGUID(DEVELOPER_DECK_GUID)
    if deck then
        if not DEV_DECK_HOME_POSITION then
            DEV_DECK_HOME_POSITION = deck.getPosition()
        end
        if not DEV_DECK_HOME_ROTATION then
            DEV_DECK_HOME_ROTATION = deck.getRotation()
        end
        deck.setLock(shouldLock and deck.type == "Deck")
    end

    for _, discardObj in ipairs(getDevDiscardPileObjects()) do
        discardObj.setLock(shouldLock and discardObj.type == "Deck")
    end

    marketLog("developer deck protection refreshed; deck-only locks=" .. tostring(shouldLock))
end

local function isObjectAtMainDeck(obj)
    if not obj then return false end
    if obj.hasTag and obj.hasTag("developer") then return false end

    local mainDeck = getObjectFromGUID(TECH_DECK_GUID)
    if not mainDeck or obj.getGUID() == mainDeck.getGUID() then return false end

    local deckPos = mainDeck.getPosition()
    local pos = obj.getPosition()
    local dx = pos.x - deckPos.x
    local dz = pos.z - deckPos.z

    return (dx * dx + dz * dz) <= (DISCARD_SLOT_THRESHOLD * DISCARD_SLOT_THRESHOLD)
end

local function isObjectAtDevMainDeck(obj)
    if not obj then return false end
    if not obj.hasTag or not obj.hasTag("developer") then return false end

    local mainDeck = getObjectFromGUID(DEVELOPER_DECK_GUID)
    if not mainDeck or obj.getGUID() == mainDeck.getGUID() then return false end

    local deckPos = mainDeck.getPosition()
    local pos = obj.getPosition()
    local dx = pos.x - deckPos.x
    local dz = pos.z - deckPos.z

    return (dx * dx + dz * dz) <= (DEV_DECK_SLOT_THRESHOLD * DEV_DECK_SLOT_THRESHOLD)
end

local function handleMainDeckDrop(obj)
    if not obj or (obj.type ~= "Card" and obj.type ~= "Deck") then return false end
    if obj.type == "Card" and not obj.hasTag("tech") then return false end
    if not isObjectAtMainDeck(obj) then return false end

    local mainDeck = getLiveObjectByGUID(TECH_DECK_GUID)
    if not mainDeck or mainDeck.getGUID() == obj.getGUID() then return false end

    local deckPos = mainDeck.getPosition()
    local _, deckRot = getTechDeckHomeTransform()
    deckRot = deckRot or mainDeck.getRotation()
    local guid = obj.getGUID()

    pcall(function()
        mainDeck.setLock(false)

        if obj.type == "Card" and not obj.is_face_down then
            obj.flip()
        end

        obj.setRotationSmooth(deckRot, false, true)
        obj.setPositionSmooth({x = deckPos.x, y = deckPos.y + 0.35, z = deckPos.z}, false, true)
    end)

    Wait.frames(function()
        local liveDeck = getLiveObjectByGUID(TECH_DECK_GUID)
        local liveObj = getLiveObjectByGUID(guid)
        if liveDeck and liveObj and liveObj.getGUID() ~= liveDeck.getGUID() then
            pcall(function()
                if liveObj.type == "Card" and not liveObj.is_face_down then
                    liveObj.flip()
                end
                liveObj.setRotation(deckRot)
                liveDeck.putObject(liveObj)
            end)
        end

        Wait.frames(function()
            updateTechDeckProtection()
        end, 8)
    end, 8)

    marketLog("tech stack dropped onto main deck guid=" .. tostring(guid) .. " type=" .. tostring(obj.type))
    return true
end




local function handleDiscardDrop(obj)
    if not obj or (obj.type ~= "Card" and obj.type ~= "Deck") then return false end
    if obj.hasTag and obj.hasTag("developer") then return false end
    if not isObjectAtDiscardPile(obj) then return false end

    local discardPos = getDiscardPilePosition()
    if not discardPos then return false end

    -- Always face up, y=90 (industry orientation)
    local targetRot = {x = 0, y = 90, z = 0}
    local yOffset = 0.35

    -- Find the current discard deck (if any)
    local discardDeck = getDiscardDeckObject()
    local stackHeight = 0
    if discardDeck then
        local pos = discardDeck.getPosition()
        local bounds = discardDeck.getBounds and discardDeck.getBounds() or {size={x=0,y=0,z=0}}
        stackHeight = (bounds.size and bounds.size.y or 0) * 0.5
        discardPos = {x = pos.x, y = pos.y + stackHeight, z = pos.z}
    end


    if EDIT_MODE then
        print("discard: handleDiscardDrop obj=" .. tostring(obj.getGUID()) .. " type=" .. tostring(obj.type))
        print("discard: discardPos=" .. string.format("{x=%.2f, y=%.2f, z=%.2f}", discardPos.x, discardPos.y, discardPos.z))
        print("discard: targetRot=" .. string.format("{x=%.2f, y=%.2f, z=%.2f}", targetRot.x, targetRot.y, targetRot.z))
        if discardDeck then
            print("discard: discardDeck present, stackHeight=" .. tostring(stackHeight))
        else
            print("discard: discardDeck is nil (first card)")
        end
        local pos = obj.getPosition()
        print("discard: obj initial pos=" .. string.format("{x=%.2f, y=%.2f, z=%.2f}", pos.x, pos.y, pos.z))
    end

    -- Move the dropped object to the top of the discard pile and flip face up

    local okMove, moveErr = pcall(function()
        if obj.type == "Card" and obj.is_face_down then
            obj.flip()
        end
        obj.setRotationSmooth(targetRot, false, true)
        obj.setPositionSmooth({x = discardPos.x, y = discardPos.y + yOffset, z = discardPos.z}, false, true)
    end)
    if EDIT_MODE then
        print("discard: setPositionSmooth to {x=" .. discardPos.x .. ", y=" .. (discardPos.y + yOffset) .. ", z=" .. discardPos.z .. "} ok=" .. tostring(okMove) .. (not okMove and (" err=" .. tostring(moveErr)) or ""))
    end

    -- If it's a deck, split and stack each card on top, flipping face up
    if obj.type == "Deck" then
        Wait.frames(function()
            local liveDeck = getLiveObjectByGUID(obj.getGUID())
            if liveDeck and liveDeck.type == "Deck" then
                local count = #liveDeck.getObjects()
                for i = count, 2, -1 do
                    Wait.frames(function()
                        local card = nil
                        pcall(function()
                            card = liveDeck.takeObject({index = i-1, position = {x = discardPos.x, y = discardPos.y + yOffset + (count-i)*0.05, z = discardPos.z}, smooth = true})
                        end)
                        if card then
                            pcall(function()
                                if card.type == "Card" and card.is_face_down then
                                    card.flip()
                                end
                                card.setRotationSmooth(targetRot, false, true)
                            end)
                        end
                    end, (count-i)*2)
                end
            end
        end, 16)
    end

    -- Robust deck reordering: ensure dropped card is always on top after merge and face up
    Wait.frames(function()
        local discardDeck = getDiscardDeckObject()
        if discardDeck and discardDeck.type == "Deck" then
            local objs = discardDeck.getObjects()
            if objs and #objs > 1 then
                -- Find the dropped card by GUID
                local droppedGuid = obj.getGUID()
                local droppedIndex = nil
                for i, d in ipairs(objs) do
                    if d.guid == droppedGuid then
                        droppedIndex = i
                        break
                    end
                end
                if droppedIndex and droppedIndex ~= 1 then
                    -- Take the dropped card and put it back on top, flipping face up
                    discardDeck.takeObject({
                        index = droppedIndex - 1,
                        position = {x = discardPos.x, y = discardPos.y + yOffset + 0.2, z = discardPos.z},
                        smooth = false,
                        callback_function = function(card)
                            Wait.frames(function()
                                if card and discardDeck then
                                    if card.type == "Card" and card.is_face_down then
                                        card.flip()
                                    end
                                    card.setRotationSmooth(targetRot, false, true)
                                    discardDeck.putObject(card)
                                end
                            end, 2)
                        end
                    })
                end
            end
        end
    end, 40)

    Wait.frames(function()
        updateTechDeckProtection()
    end, 24)

    marketLog("object dropped on discard tile guid=" .. tostring(obj.getGUID()) .. " type=" .. tostring(obj.type))
    return true
end

local function orientObjectForDevFaceDown(obj, targetPos, targetRot)
    if not obj then return end

    pcall(function()
        local alreadyFaceDown = obj.type == "Card" and obj.is_face_down
        if obj.type == "Card" and not alreadyFaceDown then
            obj.flip()
        end
        if targetRot then
            -- If card is already face-down, preserve its Z (180) so setRotationSmooth
            -- doesn't animate it through a face-up orientation mid-move.
            local rot = {x = targetRot.x, y = targetRot.y, z = targetRot.z}
            if alreadyFaceDown then
                rot.z = DEV_FACE_DOWN_Z
            end
            obj.setRotationSmooth(rot, false, true)
        end
        if targetPos then
            obj.setPositionSmooth(targetPos, false, true)
        end
    end)
end

local function handleDevMainDeckDrop(obj)
    if not obj or (obj.type ~= "Card" and obj.type ~= "Deck") then return false end
    if not obj.hasTag or not obj.hasTag("developer") then return false end
    if not isObjectAtDevMainDeck(obj) then return false end

    local mainDeck = getLiveObjectByGUID(DEVELOPER_DECK_GUID)
    if not mainDeck or mainDeck.getGUID() == obj.getGUID() then return false end

    local deckPos = mainDeck.getPosition()
    local _, deckRot = getDevDeckHomeTransform()
    deckRot = deckRot or mainDeck.getRotation()
    local guid = obj.getGUID()

    pcall(function()
        mainDeck.setLock(false)
        orientObjectForDevFaceDown(obj, {x = deckPos.x, y = deckPos.y + 0.35, z = deckPos.z}, deckRot)
    end)

    Wait.frames(function()
        local liveDeck = getLiveObjectByGUID(DEVELOPER_DECK_GUID)
        local liveObj = getLiveObjectByGUID(guid)
        if liveDeck and liveObj and liveObj.getGUID() ~= liveDeck.getGUID() then
            pcall(function()
                if liveObj.type == "Card" and not liveObj.is_face_down then
                    liveObj.flip()
                end
                liveObj.setRotation(deckRot)
                liveDeck.putObject(liveObj)
            end)
        end

        Wait.frames(function()
            updateDevDeckProtection()
        end, 8)
    end, 8)

    marketLog("developer stack dropped onto developer deck guid=" .. tostring(guid) .. " type=" .. tostring(obj.type))
    return true
end

local function handleDevDiscardDrop(obj)
    if not obj or (obj.type ~= "Card" and obj.type ~= "Deck") then return false end
    if not obj.hasTag or not obj.hasTag("developer") then return false end
    if not isObjectAtDevDiscardPile(obj) then return false end

    local discardGuid = obj.getGUID()
    local discardTarget = getDevDiscardDeckObject()
    local discardPos = getDevDiscardPilePosition()
    local discardRot = nil
    local discardTile = getDevDiscardTile()
    if discardTile then
        discardRot = discardTile.getRotation()
    end

    if discardTarget and discardTarget.getGUID() ~= discardGuid then
        pcall(function()
            discardTarget.setLock(false)
        end)
    end

    orientObjectForDevFaceDown(obj, discardPos and {x = discardPos.x, y = obj.getPosition().y, z = discardPos.z} or nil, discardRot)

    Wait.frames(function()
        local liveObj = getLiveObjectByGUID(discardGuid)
        local liveDiscard = getDevDiscardDeckObject()
        if liveObj and liveDiscard and liveObj.getGUID() ~= liveDiscard.getGUID() then
            pcall(function()
                liveDiscard.setLock(false)
                liveDiscard.putObject(liveObj)
            end)
        end

        Wait.frames(function()
            updateDevDeckProtection()
        end, 8)
    end, 8)

    marketLog("developer object dropped on developer discard tile guid=" .. tostring(discardGuid) .. " type=" .. tostring(obj.type))
    return true
end

function setupDevReshuffleButton()
    local host = getDevReshuffleButtonHost()
    if not host then
        debugPrint("⚠️ Developer reshuffle button host not found: " .. tostring(DEV_RESHUFFLE_BUTTON_GUID))
        return
    end

    host.clearButtons()
    host.createButton({
        click_function = "onDevDiscardReshuffleClick",
        function_owner = Global,
        label = "",
        position = {0, 0.15, 0},
        rotation = {0, 0, 0},
        width = 2250,
        height = 630,
        font_size = 210,
        color = {0.2, 0.2, 0.2, 0},
        font_color = {1, 1, 1, 0},
        tooltip = "Shuffle developer discard into developer deck"
    })
end

function reshuffleDevDiscardIntoDevDeck(player_color, silent)
    local mainDeck = getObjectFromGUID(DEVELOPER_DECK_GUID)
    local discardObjects = getDevDiscardPileObjects()
    local discardObj = discardObjects[1]

    if not discardObj then
        if not silent then
            debugBroadcastToColor("No developer discard deck or card found on the developer discard tile", player_color or "White")
        end
        return false
    end

    local targetPos, targetRot = getDevDeckHomeTransform()
    targetPos = targetPos or discardObj.getPosition()
    targetRot = targetRot or discardObj.getRotation()

    if not mainDeck then
        discardObj.setLock(false)
        if discardObj.randomize then
            discardObj.randomize()
        end

        DEVELOPER_DECK_GUID = discardObj.getGUID()

        Wait.frames(function()
            local promotedDeck = getObjectFromGUID(DEVELOPER_DECK_GUID)
            if promotedDeck then
                for _, extraObj in ipairs(discardObjects) do
                    if extraObj and extraObj.getGUID() ~= promotedDeck.getGUID() then
                        extraObj.setLock(false)
                        pcall(function()
                            promotedDeck.putObject(extraObj)
                        end)
                    end
                end

                if promotedDeck.is_face_down ~= nil and not promotedDeck.is_face_down then
                    promotedDeck.flip()
                end
                promotedDeck.setRotation(targetRot)
                promotedDeck.setPosition(targetPos)
            end
            updateDevDeckProtection()
        end, 1)

        marketLog("promoted developer discard pile to developer deck guid=" .. tostring(DEVELOPER_DECK_GUID))

        if not silent then
            debugBroadcastToColor("Developer discard became the new developer deck", player_color or "White")
        end
        return true
    end

    local movedAny = false

    mainDeck.setLock(false)

    for _, extraObj in ipairs(discardObjects) do
        if extraObj and extraObj.getGUID() ~= mainDeck.getGUID() then
            extraObj.setLock(false)
            if extraObj.randomize then
                extraObj.randomize()
            end

            local ok = pcall(function()
                mainDeck.putObject(extraObj)
            end)

            if ok then
                movedAny = true
            end
        end
    end

    if movedAny then
        Wait.frames(function()
            local updatedDeck = getObjectFromGUID(DEVELOPER_DECK_GUID)
            if updatedDeck and updatedDeck.randomize then
                updatedDeck.randomize()
            end
            if updatedDeck then
                if updatedDeck.is_face_down ~= nil and not updatedDeck.is_face_down then
                    updatedDeck.flip()
                end
                updatedDeck.setRotation(targetRot or updatedDeck.getRotation())
                updatedDeck.setPosition(targetPos)
            end
            updateDevDeckProtection()
        end, 10)

        if not silent then
            debugBroadcastToColor("Developer discard shuffled into the developer deck", player_color or "White")
        end
        return true
    else
        if not silent then
            debugBroadcastToColor("Developer reshuffle failed: could not move discard cards", player_color or "White")
        end
        return false
    end
end

function onDevDiscardReshuffleClick(obj, player_color, alt_click)
    if not DEV_RESHUFFLE_PENDING_BY_COLOR[player_color] then
        DEV_RESHUFFLE_PENDING_BY_COLOR[player_color] = true

        local host = getDevReshuffleButtonHost()
        if host and host.editButton then
            pcall(function()
                host.editButton({
                    index = 0,
                    label = "",
                    width = 2250,
                    height = 630,
                    color = {0.65, 0.25, 0.2, 0.25},
                    tooltip = "Click again to reshuffle developer discard into the developer deck"
                })
            end)
        end

        debugBroadcastToColor("Click the developer reshuffle button again within " .. tostring(RESHUFFLE_CONFIRM_SECONDS) .. " seconds to confirm", player_color)

        Wait.time(function()
            resetDevReshuffleConfirmation(player_color)
        end, RESHUFFLE_CONFIRM_SECONDS)
        return
    end

    resetDevReshuffleConfirmation(player_color)
    reshuffleDevDiscardIntoDevDeck(player_color)
end

function setupReshuffleButton()
    local tile = getDiscardTile()
    if tile then
        tile.clearButtons()
    end

    local host = getReshuffleButtonHost()
    if not host then
        debugPrint("⚠️ Reshuffle button host not found: " .. tostring(RESHUFFLE_BUTTON_GUID))
        return
    end

    host.clearButtons()
    host.createButton({
        click_function = "onDiscardReshuffleClick",
        function_owner = Global,
        label = "",
        position = {0, 0.15, 0},
        rotation = {0, 0, 0},
        width = 2250,
        height = 630,
        font_size = 210,
        color = {0.2, 0.2, 0.2, 0},
        font_color = {1, 1, 1, 0},
        tooltip = "Shuffle discard pile into main tech deck"
    })
end

function reshuffleDiscardIntoMainDeck(player_color, silent)
    local mainDeck = getObjectFromGUID(TECH_DECK_GUID)
    local discardObjects = getDiscardPileObjects()
    local discardObj = discardObjects[1]

    if not discardObj then
        if not silent then
            debugBroadcastToColor("No discard deck or card found on the discard tile", player_color or "White")
        end
        return false
    end

    local targetPos, targetRot = getTechDeckHomeTransform()
    targetPos = targetPos or discardObj.getPosition()
    targetRot = targetRot or discardObj.getRotation()

    if not mainDeck then
        discardObj.setLock(false)
        if discardObj.randomize then
            discardObj.randomize()
        end

        TECH_DECK_GUID = discardObj.getGUID()

        Wait.frames(function()
            local promotedDeck = getObjectFromGUID(TECH_DECK_GUID)
            if promotedDeck then
                for _, extraObj in ipairs(discardObjects) do
                    if extraObj and extraObj.getGUID() ~= promotedDeck.getGUID() then
                        extraObj.setLock(false)
                        pcall(function()
                            promotedDeck.putObject(extraObj)
                        end)
                    end
                end

                if promotedDeck.is_face_down ~= nil and not promotedDeck.is_face_down then
                    promotedDeck.flip()
                end
                promotedDeck.setRotation(targetRot)
                promotedDeck.setPosition(targetPos)
            end
            updateTechDeckProtection()
        end, 1)

        marketLog("promoted discard pile to main deck guid=" .. tostring(TECH_DECK_GUID))

        if not silent then
            debugBroadcastToColor("Discard pile became the new main tech deck", player_color or "White")
        end
        return true
    end

    local movedAny = false

    mainDeck.setLock(false)

    for _, extraObj in ipairs(discardObjects) do
        if extraObj and extraObj.getGUID() ~= mainDeck.getGUID() then
            extraObj.setLock(false)
            if extraObj.randomize then
                extraObj.randomize()
            end

            local ok = pcall(function()
                mainDeck.putObject(extraObj)
            end)

            if ok then
                movedAny = true
            end
        end
    end

    if movedAny then
        Wait.frames(function()
            local updatedDeck = getObjectFromGUID(TECH_DECK_GUID)
            if updatedDeck and updatedDeck.randomize then
                updatedDeck.randomize()
            end
            if updatedDeck then
                if updatedDeck.is_face_down ~= nil and not updatedDeck.is_face_down then
                    updatedDeck.flip()
                end
                updatedDeck.setRotation(targetRot or updatedDeck.getRotation())
                updatedDeck.setPosition(targetPos)
            end
            updateTechDeckProtection()
        end, 10)

        if not silent then
            debugBroadcastToColor("Discard shuffled into the main deck", player_color or "White")
        end
        return true
    else
        if not silent then
            debugBroadcastToColor("Reshuffle failed: could not move discard cards", player_color or "White")
        end
        return false
    end
end

function onDiscardReshuffleClick(obj, player_color, alt_click)
    if not RESHUFFLE_PENDING_BY_COLOR[player_color] then
        RESHUFFLE_PENDING_BY_COLOR[player_color] = true

        local host = getReshuffleButtonHost()
        if host and host.editButton then
            pcall(function()
                host.editButton({
                    index = 0,
                    label = "",
                    width = 2250,
                    height = 630,
                    color = {0.65, 0.25, 0.2, 0.25},
                    tooltip = "Click again to reshuffle the discard pile into the main deck"
                })
            end)
        end

        debugBroadcastToColor("Click the reshuffle button again within " .. tostring(RESHUFFLE_CONFIRM_SECONDS) .. " seconds to confirm", player_color)

        Wait.time(function()
            resetReshuffleConfirmation(player_color)
        end, RESHUFFLE_CONFIRM_SECONDS)
        return
    end

    resetReshuffleConfirmation(player_color)
    reshuffleDiscardIntoMainDeck(player_color)
end

local function isSnapPatternEligible(obj)
    if not obj then return false end
    local objType = safeGetType(obj)
    if objType ~= "Card" and objType ~= "Deck" then return false end
    return safeHasTag(obj, "tech") or safeHasTag(obj, "base")
end


-- ============================================================
-- SECTION: Setup & Orchestration
-- OnLoad, startGame, initialization flows
-- ============================================================

function toggleEditMode(player_color)
    EDIT_MODE = not EDIT_MODE
    print("EDIT_MODE = " .. tostring(EDIT_MODE))
    setupMarketRowPlaceholders()
    setupTalentRowPlaceholders()
    attachSnapPatternMenusToTechObjects()
    attachDevSnapMenusToDevObjects()
    updateTechDeckProtection()
    updateDevDeckProtection()

    if player_color then
        broadcastToColor("TTS edit mode is now " .. (EDIT_MODE and "ON" or "OFF"), player_color)
    end

    if EDIT_MODE then
        attachBoardSnapSyncMenus()
    end
end

--[[ The onLoad event is called after the game save finishes loading. --]]
function onSave()
    local state = {
        started_player_colors = STARTED_PLAYER_COLORS,
        started_player_names = STARTED_PLAYER_NAME_BY_COLOR,
        round3_bases_collected = ROUND3_BASES_COLLECTED,
    }

    return JSON.encode(state)
end

local attachFixImprovementsMenus

function attachTagMenu(deck, tagString)
    deck.addContextMenuItem("Tag as " .. tagString, function(player_color)
        tagDeck(deck, tagString)
    end)
end

function onLoad(saved_state)
    if saved_state and saved_state ~= "" then
        local okDecode, decoded = pcall(function()
            return JSON.decode(saved_state)
        end)
        if okDecode and type(decoded) == "table" then
            setStartedPlayersFromState(decoded.started_player_colors, decoded.started_player_names)
            ROUND3_BASES_COLLECTED = decoded.round3_bases_collected == true
        end
    end

    -- Deck utility checks – see below
    local deck = getObjectFromGUID(PROJECT_DECK_GUID)
    if deck then
        attachTagMenu(deck, "project tech")
    end
    deck = getObjectFromGUID(DEVELOPER_DECK_GUID)
    if deck then
        attachTagMenu(deck, "developer")
    end
    deck = getObjectFromGUID(INDUSTRY_DECK_GUID)
    if deck then
        attachTagMenu(deck, "industry tech")
    end

    attachSnapPatternMenusToTechObjects()
    attachDevSnapMenusToDevObjects()
    setupMarketRowPlaceholders()
    setupTalentRowPlaceholders()
    if isGameStartedWithRoster() then
        setupMarkerMarbleButtons(false)
    end
    setupReshuffleButton()
    setupDevReshuffleButton()
    initializeReferenceSystem()
    attachCameraPresetMenu()
    if isGameStartedWithRoster() then
        attachMarkerSpawnMenu()
    end
    attachBoardSnapSyncMenus()
    updateTechDeckProtection()
    updateDevDeckProtection()
    Wait.frames(function()
        refreshPassHudSafe("onLoad")
    end, 2)

    -- Reload safety pass: money chips can intermittently fail to render until nudged.
    Wait.frames(function()
        refreshVisibleMoneyChipsOnTable()
    end, 12)
    Wait.frames(function()
        refreshVisibleMoneyChipsOnTable()
    end, 60)
    Wait.frames(function()
        refreshVisibleMoneyChipsOnTable()
    end, 180)

    -- Attach fix-improvement menus to all base cards and eligible decks already on the table.
    Wait.frames(function()
        for _, obj in ipairs(getAllObjects()) do
            local okAttach, attachErr = pcall(function()
                attachFixImprovementsMenus(obj)
            end)
            if not okAttach then
                stackLog("onLoad attachFixImprovementsMenus failed guid=" .. tostring(safeGetGuid(obj)) .. " err=" .. tostring(attachErr))
            end
        end
    end, 5)

    marketLog("onLoad complete. placeholders configured=" .. tostring(#MARKET_PLACEHOLDER_GUIDS))
end

local function getFirstOpenPlayableColor()
    for _, color in ipairs(PLAYABLE_COLOR_PRIORITY) do
        if not RESERVED_PLAYER_COLORS[color] then
            local p = getPlayerByColorSafe(color)
            if p and not p.seated then
                return color
            end
        end
    end
    return nil
end

function enforceReservedColorForPlayer(player)
    if FREE_JOINS then return end
    if COLOR_ENFORCE_BUSY then return end
    if not player or not player.seated then return end
    if not RESERVED_PLAYER_COLORS[player.color] then return end

    local fallback = getFirstOpenPlayableColor()
    if not fallback then
        broadcastToColor("Black is reserved for Neutral and no open player colors are available.", player.color)
        return
    end

    COLOR_ENFORCE_BUSY = true
    local ok, err = pcall(function()
        player.changeColor(fallback)
    end)

    Wait.frames(function()
        COLOR_ENFORCE_BUSY = false
        if ok then
            broadcastToColor("Black is reserved for Neutral. Moved you to " .. fallback .. ".", fallback)
        else
            broadcastToColor("Black is reserved for Neutral. Could not change color: " .. tostring(err), player.color)
        end
    end, 1)
end

function enforceStartedColorForPlayer(player)
    if FREE_JOINS then return end
    if STARTED_COLOR_ENFORCE_BUSY then return end
    if not isGameStartedWithRoster() then return end
    if not player or not player.seated then return end

    local expectedColor = getStartedColorForPlayerName(player.steam_name)
    if not expectedColor or expectedColor == "Neutral" then return end
    if player.color == expectedColor then return end

    local expectedSeat = getPlayerByColorSafe(expectedColor)
    if expectedSeat and expectedSeat.seated then
        broadcastToColor(
            "Player previously joined as " .. string.lower(expectedColor) .. ", but that seat is occupied.",
            player.color
        )
        return
    end

    STARTED_COLOR_ENFORCE_BUSY = true
    local sourceColor = player.color
    local playerNameDisplay = tostring((player and player.steam_name and player.steam_name ~= "") and player.steam_name or "Player")
    local ok, err = pcall(function()
        player.changeColor(expectedColor)
    end)

    Wait.frames(function()
        STARTED_COLOR_ENFORCE_BUSY = false
        if ok then
            broadcastToColor(
                playerNameDisplay .. " previously joined as " .. string.lower(expectedColor) .. ", re-assigned to " .. string.lower(expectedColor),
                expectedColor
            )
        else
            broadcastToColor(
                "Could not re-assign to started color " .. string.lower(expectedColor) .. ": " .. tostring(err),
                sourceColor
            )
        end
    end, 1)
end

function onPlayerChangeColor(player_color)
    local p = getPlayerByColorSafe(player_color)
    local playerName = p and p.steam_name or nil
    colorChangeLog("onPlayerChangeColor event color=" .. tostring(player_color) .. " name=" .. tostring(playerName or ""))
    
    enforceReservedColorForPlayer(p)
    Wait.frames(function()
        local livePlayer = findSeatedPlayerByName(playerName) or getPlayerByColorSafe(player_color)
        enforceStartedColorForPlayer(livePlayer)
        refreshPassHudSafe("playerChangeColor")
    end, 2)
end

function onPlayerConnect(player)
    local playerName = player and player.steam_name or nil
    enforceReservedColorForPlayer(player)
    Wait.frames(function()
        Wait.frames(function()
            local livePlayer2 = findSeatedPlayerByName(playerName) or player
            enforceStartedColorForPlayer(livePlayer2)
            refreshPassHudSafe("playerConnect")
        end, 1)
    end, 2)
end

function onPlayerDisconnect(player)
    Wait.frames(function()
        refreshPassHudSafe("playerDisconnect")
    end, 2)
end

-- ** spawn player bags with infinite markers on game start **
function getSeatedPlayers(requireNamedPlayer)
    local seated = {}
    local seenByColor = {}

    local playersByColorFromList = {}
    local okPlayers, players = pcall(function()
        return Player.getPlayers()
    end)
    if okPlayers and type(players) == "table" then
        for _, lp in ipairs(players) do
            local c = tostring((lp and lp.color) or "")
            if c ~= "" and not playersByColorFromList[c] then
                playersByColorFromList[c] = lp
            end
        end
    end

    local function addSeatedCandidate(color, playerRef)
        local colorKey = tostring(color or "")
        if colorKey == "" or seenByColor[colorKey] then return end

        local p = playerRef or getPlayerByColorSafe(colorKey)
        if not p or not p.seated then return end

        local name = tostring(p.steam_name or "")
        if requireNamedPlayer and name == "" then
            colorChangeLog("ignoring ghost seated slot color=" .. tostring(colorKey) .. " (no steam_name)")
            return
        end

        if requireNamedPlayer then
            local listed = playersByColorFromList[colorKey]
            if not listed or tostring(listed.steam_name or "") == "" then
                colorChangeLog("ignoring non-listed seat color=" .. tostring(colorKey) .. " (not in Player.getPlayers)")
                return
            end

            if not hasUsableHandTransformForPlayer(listed) and not hasUsableHandTransformForPlayer(p) then
                colorChangeLog("ignoring seat without hand transform color=" .. tostring(colorKey) .. " name=" .. tostring(name))
                return
            end

            p = listed or p
        end

        table.insert(seated, {color = colorKey, player = p})
        seenByColor[colorKey] = true
    end

    if okPlayers and type(players) == "table" then
        for _, p in ipairs(players) do
            addSeatedCandidate(p and p.color or nil, p)
        end
    end

    if not requireNamedPlayer then
        for _, color in ipairs(Player.getColors()) do
            local success, p = pcall(function() return Player[color] end)
            if success then
                addSeatedCandidate(color, p)
            end
        end
    end

    return seated
end

function getActiveSeatedPlayers()
    local seated = getSeatedPlayers(true)
    if #seated == 0 then
        return seated
    end

    for _, pdata in ipairs(seated) do
        local p = pdata.player
        colorChangeLog(
            "active seated color=" .. tostring(pdata.color) ..
            " name=" .. tostring((p and p.steam_name) or "") ..
            " seated=" .. tostring((p and p.seated) or false)
        )
    end
    return seated
end

function setupAnalystCards()
    local deck = getObjectFromGUID(ANALYST_DECK_GUID)
    if not deck then
        debugPrint("⚠️ Analyst deck not found: " .. tostring(ANALYST_DECK_GUID))
        return
    end

    if deck.type == "Deck" then
        deck.randomize()

        Wait.frames(function()
            local liveDeck = getObjectFromGUID(ANALYST_DECK_GUID)
            if not liveDeck then
                debugPrint("⚠️ Analyst deck missing after shuffle")
                return
            end

            for _, pos in ipairs(ANALYST_CARD_POSITIONS) do
                if liveDeck.type == "Deck" then
                    pcall(function()
                        liveDeck.takeObject({
                            index = 0,
                            position = pos,
                            smooth = false,
                            callback_function = function(card)
                                if card then
                                    pcall(function() card.addTag("analyst") end)
                                end
                            end
                        })
                    end)
                elseif liveDeck.type == "Card" then
                    pcall(function()
                        liveDeck.setPositionSmooth(pos, false, true)
                        liveDeck.addTag("analyst")
                    end)
                    break
                end
            end

            Wait.frames(function()
                local remainder = getObjectFromGUID(ANALYST_DECK_GUID)
                if remainder then
                    pcall(function() remainder.destruct() end)
                end
            end, 10)
        end, 10)
    elseif deck.type == "Card" then
        deck.setPositionSmooth(ANALYST_CARD_POSITIONS[1], false, true)
        deck.addTag("analyst")
    else
        debugPrint("⚠️ Analyst deck object has unsupported type: " .. tostring(deck.type))
    end
end

function dealOneCardToPlayer(sourceObj, playerColor)
    if not sourceObj or not playerColor then return false end
    local ok = pcall(function()
        sourceObj.deal(1, playerColor)
    end)
    return ok
end

function randomizeDeckByGuid(guid, label)
    local obj = getObjectFromGUID(guid)
    if not obj then
        if label then
            debugPrint("⚠️ Could not randomize " .. tostring(label) .. ": object not found (" .. tostring(guid) .. ")")
        end
        return false
    end

    if not obj.randomize then
        return false
    end

    local ok = pcall(function()
        obj.randomize()
    end)

    if not ok and label then
        debugPrint("⚠️ Randomize failed for " .. tostring(label) .. " (" .. tostring(guid) .. ")")
    end

    return ok
end

-- Removes pre-placed default player assets (boards, cards) for any position that has no seated player.
-- Uses the first GUID in each group as a spatial anchor and checks proximity to seated hand zones.
function removeUnseatedPlayerAssets(attemptsLeft)
    local PROXIMITY_THRESHOLD = 12  -- units between player board and seated player's hand zone

    -- Collect hand zone world positions for all seated players.
    -- These are reliable once TTS has finished loading player seats.
    local seatedHandPositions = {}
    for _, color in ipairs(STARTED_PLAYER_COLORS or {}) do
        local p = getPlayerByColorSafe(color)
        if p and p.seated then
            local handPos = getPrimaryHandPositionForPlayer(p)
            if handPos then
                table.insert(seatedHandPositions, handPos)
                stackLog("removeUnseatedPlayerAssets: hand pos for " .. color .. " x=" .. string.format("%.2f", handPos.x) .. " z=" .. string.format("%.2f", handPos.z))
            end
        end
    end

    -- If no hand positions yet, retry a few times to wait for TTS to settle.
    if #seatedHandPositions == 0 then
        if (attemptsLeft or 0) > 0 then
            Wait.frames(function() removeUnseatedPlayerAssets(attemptsLeft - 1) end, 10)
        else
            stackLog("removeUnseatedPlayerAssets: no hand positions found after wait, skipping to avoid deleting all assets")
        end
        return
    end

    for _, group in ipairs(PLAYER_POSITION_ASSET_GROUPS) do
        local anchorGuid = group.guids[1]
        local anchorObj = getObjectFromGUID(anchorGuid)
        if not anchorObj then
            stackLog("removeUnseatedPlayerAssets: anchor not found for " .. group.label .. " (guid=" .. anchorGuid .. "), skipping group")
        else
            local okAnchorPos, anchorPos = pcall(function()
                return anchorObj.getPosition()
            end)
            if not okAnchorPos or not anchorPos then
                stackLog("removeUnseatedPlayerAssets: anchor position unavailable for " .. group.label .. " (guid=" .. anchorGuid .. "), skipping group")
                anchorPos = nil
            end
            local isOccupied = false
            if anchorPos then
                for _, handPos in ipairs(seatedHandPositions) do
                    local dx = anchorPos.x - handPos.x
                    local dz = anchorPos.z - handPos.z
                    if math.sqrt(dx * dx + dz * dz) <= PROXIMITY_THRESHOLD then
                        isOccupied = true
                        break
                    end
                end
            end

            if anchorPos and not isOccupied then
                stackLog("removeUnseatedPlayerAssets: removing " .. #group.guids .. " assets for empty " .. group.label .. " position")
                for _, guid in ipairs(group.guids) do
                    local obj = getObjectFromGUID(guid)
                    if obj then
                        pcall(function() obj.destruct() end)
                    end
                end
            else
                stackLog("removeUnseatedPlayerAssets: " .. group.label .. " position occupied, keeping assets")
            end
        end
    end
end

local function removeStartButtons()
    for _, guid in ipairs({START_GAME_BUTTON_GUID, START_BEGINNER_BUTTON_GUID}) do
        local obj = getObjectFromGUID(guid)
        if obj then
            pcall(function()
                obj.destruct()
            end)
        end
    end
end

local function mergeStarterIntoMainDeck(starterGuid, mainGuid, label, onDone)
    local doneFired = false
    local function complete(mergeConfirmed)
        if doneFired then return end
        doneFired = true
        if onDone then
            pcall(function()
                onDone(mergeConfirmed == true)
            end)
        end
    end

    local starter = getObjectFromGUID(starterGuid)
    if not starter then
        complete(true)
        return
    end

    local mainDeck = getObjectFromGUID(mainGuid)
    if not mainDeck then
        debugPrint("⚠️ Could not merge " .. tostring(label) .. " starter into main deck: main deck missing (" .. tostring(mainGuid) .. ")")
        complete(false)
        return
    end

    local okMainPos, mainPos = pcall(function()
        return mainDeck.getPosition()
    end)
    local okMainRot, mainRot = pcall(function()
        return mainDeck.getRotation()
    end)
    if not okMainPos or not mainPos then
        debugPrint("⚠️ Could not merge " .. tostring(label) .. " starter into main deck: main deck position unavailable (" .. tostring(mainGuid) .. ")")
        complete(false)
        return
    end
    if not okMainRot or not mainRot then
        mainRot = nil
    end

    pcall(function()
        mainDeck.setLock(false)
    end)

    pcall(function()
        if starter.type == "Deck" then
            starter.randomize()
        end
    end)

    -- Deck-to-deck putObject has been the most fragile startup operation.
    -- Move the starter pile onto the main pile and let TTS merge by contact.
    pcall(function()
        mainDeck.setLock(false)
        if mainRot then
            starter.setRotation(mainRot)
        end
        -- Use immediate placement so merge has the best chance to resolve before follow-up dealing.
        starter.setPosition({x = mainPos.x, y = mainPos.y + 0.06, z = mainPos.z})
    end)

    local function finalizeAfterMerge(attemptsLeft, forcedRestackUsed)
        local okMergeCallback, mergeCallbackErr = pcall(function()
            if STARTUP_DEBUG_LOGS then
                print("[START] begin merge callback label=" .. tostring(label) .. " main=" .. tostring(mainGuid) .. " starter=" .. tostring(starterGuid) .. " attemptsLeft=" .. tostring(attemptsLeft) .. " forcedRestack=" .. tostring(forcedRestackUsed == true))
            end

            local liveMain = getObjectFromGUID(mainGuid)
            local liveStarter = getObjectFromGUID(starterGuid)
            local mergedSettled = (liveStarter == nil)

            if mergedSettled and liveMain and liveMain.randomize then
                pcall(function()
                    liveMain.randomize()
                end)
                complete(true)
            elseif not mergedSettled and (attemptsLeft or 0) > 0 then
                Wait.frames(function()
                    finalizeAfterMerge((attemptsLeft or 0) - 1, forcedRestackUsed)
                end, 2)
                return
            elseif not mergedSettled and liveMain and liveStarter and not forcedRestackUsed then
                -- One forced re-stack pass for stubborn physics states before declaring timeout.
                pcall(function()
                    local forcedPos = liveMain.getPosition()
                    if forcedPos then
                        liveStarter.setPosition({x = forcedPos.x, y = forcedPos.y + 0.03, z = forcedPos.z})
                    end
                end)
                Wait.frames(function()
                    finalizeAfterMerge(20, true)
                end, 2)
                return
            elseif liveMain and liveMain.randomize then
                -- Last-resort shuffle if merge confirmation timed out.
                pcall(function()
                    liveMain.randomize()
                end)
                debugPrint("⚠️ Merge settle timed out for " .. tostring(label) .. " starter; deck was shuffled anyway. Verify and manually shuffle if needed.")
                if mainGuid == TECH_DECK_GUID then
                    broadcastToAll("Startup note: could not confirm starter-tech merge before final shuffle. Please verify and manually shuffle the tech deck if needed.", {1, 0.4, 0.2})
                end
                complete(false)
            else
                complete(false)
            end

            if mainGuid == TECH_DECK_GUID then
                local okProtect, protectErr = pcall(function()
                    updateTechDeckProtection()
                end)
                if not okProtect and STARTUP_DEBUG_LOGS then
                    print("[START] error merge callback updateTechDeckProtection label=" .. tostring(label) .. " err=" .. tostring(protectErr))
                end
            elseif mainGuid == DEVELOPER_DECK_GUID then
                local okProtect, protectErr = pcall(function()
                    updateDevDeckProtection()
                end)
                if not okProtect and STARTUP_DEBUG_LOGS then
                    print("[START] error merge callback updateDevDeckProtection label=" .. tostring(label) .. " err=" .. tostring(protectErr))
                end
            end

            if STARTUP_DEBUG_LOGS then
                print("[START] end merge callback label=" .. tostring(label) .. " main=" .. tostring(mainGuid) .. " starter=" .. tostring(starterGuid))
            end
        end)

        if not okMergeCallback and STARTUP_DEBUG_LOGS then
            print("[START] error merge callback label=" .. tostring(label) .. " main=" .. tostring(mainGuid) .. " starter=" .. tostring(starterGuid) .. " err=" .. tostring(mergeCallbackErr))
        end
        if not okMergeCallback then
            complete(false)
        end
    end

    Wait.frames(function()
        finalizeAfterMerge(40, false)
    end, 2)
end

local function dealStarterCardsPerPlayer(starterGuid, seatedPlayers, cardsPerPlayer)
    local dealtByColor = {}
    for _, pdata in ipairs(seatedPlayers) do
        dealtByColor[pdata.color] = 0
    end

    for _ = 1, cardsPerPlayer do
        for _, pdata in ipairs(seatedPlayers) do
            local starter = getObjectFromGUID(starterGuid)
            if starter and dealOneCardToPlayer(starter, pdata.color) then
                dealtByColor[pdata.color] = dealtByColor[pdata.color] + 1
            end
        end
    end

    return dealtByColor
end

local function dealFromMainDeckToPlayers(mainGuid, seatedPlayers, countByColor)
    local mainDeck = getObjectFromGUID(mainGuid)
    if not mainDeck then
        debugPrint("⚠️ Main deck missing for dealing: " .. tostring(mainGuid))
        return
    end

    for _, pdata in ipairs(seatedPlayers) do
        local count = countByColor[pdata.color] or 0
        for _ = 1, count do
            local liveDeck = getObjectFromGUID(mainGuid)
            if not liveDeck then
                debugPrint("⚠️ Main deck exhausted or missing while dealing: " .. tostring(mainGuid))
                return
            end
            dealOneCardToPlayer(liveDeck, pdata.color)
        end
    end
end

function addStartingStackBasesForLowPlayerCount(seatedCount)
    local numToMove = 0
    if seatedCount == 1 then
        numToMove = 2
    elseif seatedCount == 2 then
        numToMove = 1
    else
        return
    end

    local candidates = {
        {guid = "8acc6e", pos = {x = -12.87, y = 1.15, z = 8.91}},
        {guid = "0fd6f3", pos = {x = -7.67, y = 1.15, z = 8.91}},
        {guid = "96b59c", pos = {x = -2.47, y = 1.15, z = 8.91}},
        {guid = "997214", pos = {x = 2.73, y = 1.15, z = 8.91}},
        {guid = "7a3216", pos = {x = 7.93, y = 1.15, z = 8.91}},
    }

    for i = #candidates, 2, -1 do
        local j = math.random(i)
        candidates[i], candidates[j] = candidates[j], candidates[i]
    end

    for i = 1, numToMove do
        local spec = candidates[i]
        local baseCard = getObjectFromGUID(spec.guid)
        if not baseCard then
            debugPrint("⚠️ Starting base card missing: " .. tostring(spec.guid))
        else
            pcall(function()
                baseCard.setPositionSmooth(spec.pos, false, true)
            end)

            local okBaseGuid, baseGuid = pcall(function()
                return baseCard.getGUID()
            end)
            if not okBaseGuid or not baseGuid then
                stackLog("auto-base skipped: failed to read base guid for spec=" .. tostring(spec.guid))
            else
                local function placeCounterWhenSettled(attemptsLeft)
                    local liveBase = getObjectFromGUID(baseGuid)
                    if not liveBase then return end

                    local okPos, p = pcall(function()
                        return liveBase.getPosition and liveBase.getPosition() or nil
                    end)
                    if not okPos then p = nil end
                    if not p then
                        if attemptsLeft > 0 then
                            Wait.frames(function()
                                placeCounterWhenSettled(attemptsLeft - 1)
                            end, 5)
                        else
                            stackLog("auto-base settle timeout: no position guid=" .. tostring(baseGuid))
                        end
                        return
                    end
                    local dx = math.abs((p.x or 0) - spec.pos.x)
                    local dy = math.abs((p.y or 0) - spec.pos.y)
                    local dz = math.abs((p.z or 0) - spec.pos.z)
                    local settled = (dx <= 0.05 and dy <= 0.08 and dz <= 0.05)

                    if settled then
                        Wait.frames(function()
                            local settledBase = getObjectFromGUID(baseGuid)
                            if settledBase then
                                local okCounter, counterErr = pcall(function()
                                    handleBaseCardCounter(settledBase, "Neutral", true)
                                end)
                                if not okCounter then
                                    stackLog("auto-base counter failed guid=" .. tostring(baseGuid)
                                        .. " err=" .. tostring(counterErr))
                                end
                            end
                        end, 15)
                        return
                    end

                    if attemptsLeft > 0 then
                        Wait.frames(function()
                            placeCounterWhenSettled(attemptsLeft - 1)
                        end, 5)
                    else
                        stackLog("auto-base settle timeout; placing counter anyway guid=" .. tostring(baseGuid)
                            .. " dx=" .. string.format("%.3f", dx)
                            .. " dy=" .. string.format("%.3f", dy)
                            .. " dz=" .. string.format("%.3f", dz))
                        Wait.frames(function()
                            local timeoutBase = getObjectFromGUID(baseGuid)
                            if timeoutBase then
                                local okCounter, counterErr = pcall(function()
                                    handleBaseCardCounter(timeoutBase, "Neutral", true)
                                end)
                                if not okCounter then
                                    stackLog("auto-base timeout counter failed guid=" .. tostring(baseGuid)
                                        .. " err=" .. tostring(counterErr))
                                end
                            end
                        end, 15)
                    end
                end

                Wait.frames(function()
                    placeCounterWhenSettled(40)
                end, 10)
            end
        end
    end
end

function notifyStartRequiresSeated(player_color)
    local msg = "Game must be started by a seated player; use 'Change Color' on player name to select a seat position."
    local target = tostring(player_color or "")

    if target ~= "" and target ~= "Grey" then
        broadcastToColor(msg, target)
    else
        -- Unseated/spectator clicks may report as Grey or nil; announce globally so the clicker sees it.
        broadcastToAll(msg, {1, 0.3, 0.3})
    end
end

function runStartStep(label, fn)
    if STARTUP_DEBUG_LOGS then
        print("[START] begin immediate " .. tostring(label))
    end
    local ok, err = pcall(fn)
    if not ok then
        if STARTUP_DEBUG_LOGS then
            print("[START] error immediate " .. tostring(label) .. " err=" .. tostring(err))
        end
        debugPrint("⚠️ start step failed (" .. tostring(label) .. "): " .. tostring(err))
        colorChangeLog("start step failed (" .. tostring(label) .. "): " .. tostring(err))
    else
        if STARTUP_DEBUG_LOGS then
            print("[START] end immediate " .. tostring(label))
        end
    end
    return ok
end

local START_GAME_RUN_ID = 0
local STARTUP_DEBUG_LOGS = false

local function startLog(message)
    if STARTUP_DEBUG_LOGS then
        print("[START] " .. tostring(message))
    end
end

local function scheduleStartStep(stepLabel, delayFrames, fn)
    startLog("schedule " .. tostring(stepLabel) .. " delay=" .. tostring(delayFrames) .. "f")
    Wait.frames(function()
        startLog("begin " .. tostring(stepLabel))
        local ok, err = pcall(fn)
        if not ok then
            startLog("error " .. tostring(stepLabel) .. " err=" .. tostring(err))
        end
        startLog("end " .. tostring(stepLabel))
    end, delayFrames)
end

function doStartGame(player_color, isBeginnerMode)
    if START_GAME_BUSY then
        local target = tostring(player_color or "")
        local msg = "Game start is already in progress."
        if target ~= "" and target ~= "Grey" then
            broadcastToColor(msg, target)
        else
            broadcastToAll(msg, "White")
        end
        colorChangeLog("start blocked: start already in progress")
        return
    end

    local clicker = getPlayerByColorSafe(player_color)
    if not clicker or not clicker.seated then
        notifyStartRequiresSeated(player_color)
        colorChangeLog("start blocked: clicker not seated color=" .. tostring(player_color))
        return
    end

    local seated = getActiveSeatedPlayers()
    if #seated == 0 then
        colorChangeLog("start blocked: no active seated players")
        return
    end

    START_GAME_BUSY = true
    START_GAME_SETUP_IN_PROGRESS = true
    START_GAME_RUN_ID = (START_GAME_RUN_ID or 0) + 1
    startLog("run=" .. tostring(START_GAME_RUN_ID) .. " begin clicker=" .. tostring(player_color) .. " beginner=" .. tostring(isBeginnerMode))
    Wait.frames(function()
        if START_GAME_BUSY then
            START_GAME_BUSY = false
            colorChangeLog("start lock auto-released after timeout")
            startLog("run=" .. tostring(START_GAME_RUN_ID) .. " lock auto-released")
        end
    end, 360)

    -- Shuffle all involved decks before any market/hand dealing.
    runStartStep("shuffle tech", function() randomizeDeckByGuid(TECH_DECK_GUID, "main tech deck") end)
    runStartStep("shuffle developer", function() randomizeDeckByGuid(DEVELOPER_DECK_GUID, "main developer deck") end)
    runStartStep("shuffle starter project", function() randomizeDeckByGuid(STARTER_PROJECT_DECK_GUID, "starter project deck") end)
    runStartStep("shuffle starter developer", function() randomizeDeckByGuid(STARTER_DEVELOPER_DECK_GUID, "starter developer deck") end)

    runStartStep("refresh market", function() refreshMarket() end)
    runStartStep("refresh talent row", function() refreshTalentRow(player_color) end)
    runStartStep("setup analyst cards", function() setupAnalystCards() end)

    local startedColors = {}
    local startedNames = {}
    for _, pdata in ipairs(seated) do
        local color = normalizePlayerColorLabel(pdata.color)
        if color then
            table.insert(startedColors, color)
            local snapName = tostring((pdata.player and pdata.player.steam_name and pdata.player.steam_name ~= "") and pdata.player.steam_name or color)
            startedNames[color] = snapName
        end
    end
    setStartedPlayersFromState(startedColors, startedNames)

    -- Placeholder refresh buttons are only active after game start.
    runStartStep("setup market placeholders", function() setupMarketRowPlaceholders() end)
    runStartStep("setup talent placeholders", function() setupTalentRowPlaceholders() end)
    runStartStep("setup marker marbles", function() setupMarkerMarbleButtons(true) end)
    runStartStep("setup marker menu", function() attachMarkerSpawnMenu() end)

    -- Tech cards: 8 total. Beginner mode gives 1 from starter project deck first.
    -- Wait a few frames so takeObject calls from refreshMarket/refreshTalentRow
    -- have been processed by the game engine before we start merging and dealing.
    scheduleStartStep("deal block", 5, function()
        local okDeal, dealErr = pcall(function()
            local function runDealSubstep(stepLabel, fn)
                local okStep, errStep = pcall(fn)
                if not okStep then
                    colorChangeLog("start deal substep failed: " .. tostring(stepLabel) .. ": " .. tostring(errStep))
                end
                return okStep, errStep
            end

            local starterTechDealtByColor = {}
            for _, pdata in ipairs(seated) do
                starterTechDealtByColor[pdata.color] = 0
            end

            if isBeginnerMode then
                runDealSubstep("starter project deal", function()
                    starterTechDealtByColor = dealStarterCardsPerPlayer(STARTER_PROJECT_DECK_GUID, seated, 1)
                end)
            end

            local function beginDeveloperPhase()
                -- Developer cards: beginner gives 2 from starter deck, standard gives 3 from main.
                if isBeginnerMode then
                    runDealSubstep("starter developer deal", function()
                        dealStarterCardsPerPlayer(STARTER_DEVELOPER_DECK_GUID, seated, 2)
                    end)
                end

                runDealSubstep("merge starter developer", function()
                    mergeStarterIntoMainDeck(STARTER_DEVELOPER_DECK_GUID, DEVELOPER_DECK_GUID, "developer", function(_mergeConfirmed)
                        if isBeginnerMode then
                            return
                        end

                        local devMainCounts = {}
                        for _, pdata in ipairs(seated) do
                            devMainCounts[pdata.color] = 3
                        end
                        runDealSubstep("deal developer from main", function()
                            dealFromMainDeckToPlayers(DEVELOPER_DECK_GUID, seated, devMainCounts)
                        end)
                    end)
                end)
            end

            runDealSubstep("merge starter project", function()
                mergeStarterIntoMainDeck(STARTER_PROJECT_DECK_GUID, TECH_DECK_GUID, "project", function(_mergeConfirmed)
                    local techMainCounts = {}
                    for _, pdata in ipairs(seated) do
                        local starterCount = starterTechDealtByColor[pdata.color] or 0
                        local remainder = 8 - starterCount
                        if remainder < 0 then remainder = 0 end
                        techMainCounts[pdata.color] = remainder
                    end

                    runDealSubstep("deal tech from main", function()
                        dealFromMainDeckToPlayers(TECH_DECK_GUID, seated, techMainCounts)
                    end)

                    beginDeveloperPhase()
                end)
            end)
        end)

        if not okDeal then
            debugPrint("⚠️ start deal block failed: " .. tostring(dealErr))
            colorChangeLog("start deal block failed: " .. tostring(dealErr))
        end
    end) -- end delayed deal block

    runStartStep("low-player bases", function() addStartingStackBasesForLowPlayerCount(#seated) end)
    runStartStep("initialize track markers", function() initializeTrackMarkers() end)
    scheduleStartStep("initialize track markers delayed", 90, function()
        runStartStep("initialize track markers delayed", function() initializeTrackMarkers() end)
    end)
    scheduleStartStep("initialize track markers late", 180, function()
        runStartStep("initialize track markers late", function() initializeTrackMarkers() end)
    end)
    -- Delay so that TTS hand zone transforms are ready before proximity check runs.
    scheduleStartStep("remove unseated player assets", 30, function()
        runStartStep("remove unseated player assets", function()
            removeUnseatedPlayerAssets(20)
        end)
    end)

    Wait.frames(function()
        startLog("begin hud refresh callback")
        refreshPassHudSafe("startGame")
        startLog("end hud refresh callback")
    end, 2)

    if #seated == 4 then
        Wait.frames(function()
            runStartStep("position community upgrades", function()
                local deck = getObjectFromGUID("9b2c50")
                if not deck then return end

                local pos = safeGetPosition(deck)
                if not pos then return end

                pcall(function()
                    deck.setPositionSmooth({x = -39.36, y = pos.y, z = 39.82}, false, true)
                end)
            end)
        end, 2)
    end

    runStartStep("remove start buttons", function() removeStartButtons() end)

    -- Keep the lock for a short settle window so duplicate clicks cannot race delayed setup passes.
    scheduleStartStep("release start lock", 90, function()
        START_GAME_BUSY = false
        START_GAME_SETUP_IN_PROGRESS = false
    end)
end

function startGame(player_color)
    doStartGame(player_color, false)
end

function startBeginnerGame(player_color)
    doStartGame(player_color, true)
end

-- ** reveal and rotate landscape projects entering hand **
function onObjectEnterZone(zone, obj)
    if not zone or not obj then return end
    
    local isHandZone = (safeGetTag(zone) == "Hand")
    if not isHandZone then return end
 
    if isHandZone then
        local objGuid = safeGetGuid(obj)
        if not objGuid then return end
        -- Hand zone: flip and rotate projects    
        Wait.frames(function()
            local liveObj = getObjectFromGUID(objGuid)
            if not liveObj then return end

            if safeHasTag(liveObj, "developer") then
                local okType, objType = pcall(function() return liveObj.type end)
                local okFaceDown, isFaceDown = pcall(function() return liveObj.is_face_down end)
                if okType and objType == "Card" and okFaceDown and not isFaceDown then
                    pcall(function() liveObj.flip() end)
                end
            else
                local okFaceDown, isFaceDown = pcall(function() return liveObj.is_face_down end)
                if okFaceDown and isFaceDown then
                    pcall(function() liveObj.flip() end)
                end
            end

            -- Rotate relative to the hand zone orientation so all seats see cards upright.
            -- Skip if this card was just rearranged from the same hand (avoids flicker).
            local isRearrange = HAND_REARRANGE_GUIDS[objGuid] == true
            HAND_REARRANGE_GUIDS[objGuid] = nil -- consume the flag once used

            if isRearrange then
                -- Cancel any older delayed callbacks so in-hand drags don't get a late re-rotation.
                bumpHandRotationToken(objGuid)
                stackLog("hand-rotate suppress rearrange guid=" .. tostring(objGuid))
            else
                if safeHasTag(liveObj, "industry") then
                    scheduleHandRotationIfCurrent(liveObj, zone, true, 15, "enter-hand")
                elseif safeHasTag(liveObj, "project") then
                    scheduleHandRotationIfCurrent(liveObj, zone, false, 15, "enter-hand")
                end
            end

            if MARKET_PICKUP_SLOT_BY_GUID[objGuid] then
                MARKET_PICKUP_SLOT_BY_GUID[objGuid] = nil
                Wait.frames(function()
                    refreshMarket()
                end, 20)
            end
        end, 1)
    end
end

function onObjectLeaveZone(zone, obj)
    if not zone or not obj then return end
    if safeGetTag(zone) ~= "Hand" then return end

    local guid = safeGetGuid(obj)
    if not guid then return end

    -- Mark any card that leaves a hand zone as a potential rearrange.
    -- onObjectEnterZone will consume this flag if the card goes back to a hand,
    -- suppressing the unnecessary rotation fix.  onObjectDrop cleans it up if
    -- the card ends up on the table instead.
    local objType = safeGetType(obj)
    if objType == "Card" then
        HAND_REARRANGE_GUIDS[guid] = true
        bumpHandRotationToken(guid)
        stackLog("hand-rotate mark-rearrange guid=" .. tostring(guid))
    end

    if not safeHasTag(obj, "developer") then return end

    DEV_RECENTLY_LEFT_HAND[guid] = true
    Wait.time(function()
        DEV_RECENTLY_LEFT_HAND[guid] = nil
    end, 2)
end

function onObjectPickUp(player_color, obj)
    if not obj then return end
    if START_GAME_SETUP_IN_PROGRESS then return end

    local pickupType = safeGetType(obj)
    local pickupGuid = safeGetGuid(obj)

    if pickupType == "Card" and safeHasTag(obj, "base") then
        removeStackCounterForBase(obj)
    end

    if pickupType == "Card" and safeHasTag(obj, "improvement") then
        if pickupGuid then STACK_TUCKED_IMPROVEMENT_GUIDS[pickupGuid] = nil end
    end

    -- HAND_REARRANGE_GUIDS is now populated via onObjectLeaveZone (more reliable
    -- than checking getZones() at pickup time, which is timing-sensitive).

    if safeHasTag(obj, "tech") then
        local slot = getMarketSlotIndexFromPosition(safeGetPosition(obj))
        if pickupGuid then
            if slot then
                MARKET_PICKUP_SLOT_BY_GUID[pickupGuid] = slot
                marketLog("pickup tech card from slot " .. tostring(slot) .. " by " .. tostring(player_color))
            else
                MARKET_PICKUP_SLOT_BY_GUID[pickupGuid] = nil
                marketLog("pickup tech card outside market by " .. tostring(player_color))
            end
        end
    end

    if safeHasTag(obj, "developer") then
        local devSlot = getTalentRowSlotIndexFromPosition(safeGetPosition(obj))
        if pickupGuid then
            if devSlot then
                TALENT_ROW_PICKUP_SLOT_BY_GUID[pickupGuid] = devSlot
                marketLog("pickup developer card from talent slot " .. tostring(devSlot) .. " by " .. tostring(player_color))
            else
                TALENT_ROW_PICKUP_SLOT_BY_GUID[pickupGuid] = nil
                marketLog("pickup developer card outside talent row by " .. tostring(player_color))
            end
        end
    end

    if pickupType == "Card" and safeHasTag(obj, "project") and not safeHasTag(obj, "improvement") then
        local projectGuid = safeGetGuid(obj)
        if not projectGuid then return end
        local seen = {}

        local okB, bounds = pcall(function()
            if obj.getBoundsNormalized then return obj.getBoundsNormalized() end
            if obj.getBounds then return obj.getBounds() end
            return nil
        end)

        if okB and bounds and bounds.center and bounds.size then
            local c = bounds.center
            local s = bounds.size
            local minX = (c.x or 0) - ((s.x or 0) * 0.5)
            local maxX = (c.x or 0) + ((s.x or 0) * 0.5)
            local minZ = (c.z or 0) - ((s.z or 0) * 0.5)
            local maxZ = (c.z or 0) + ((s.z or 0) * 0.5)

            for _, other in ipairs(getAllObjects()) do
                if other and other.type == "Card" then
                    local okOtherGuid, otherGuid = pcall(function() return other.getGUID() end)
                    if okOtherGuid and otherGuid and otherGuid ~= projectGuid then
                        local okOB, ob = pcall(function()
                            if other.getBoundsNormalized then return other.getBoundsNormalized() end
                            if other.getBounds then return other.getBounds() end
                            return nil
                        end)
                        if okOB and ob and ob.center and ob.size then
                            local oc = ob.center
                            local os = ob.size
                            local ominX = (oc.x or 0) - ((os.x or 0) * 0.5)
                            local omaxX = (oc.x or 0) + ((os.x or 0) * 0.5)
                            local ominZ = (oc.z or 0) - ((os.z or 0) * 0.5)
                            local omaxZ = (oc.z or 0) + ((os.z or 0) * 0.5)

                            local xOverlap = math.max(0, math.min(maxX, omaxX) - math.max(minX, ominX))
                            local zOverlap = math.max(0, math.min(maxZ, omaxZ) - math.max(minZ, ominZ))
                            if xOverlap > 0 and zOverlap > 0 then
                                seen[otherGuid] = true
                            end
                        end
                    end
                end
            end
        end

        PROJECT_PICKUP_INTERSECTING_GUIDS_BY_GUID[projectGuid] = seen
    end
end

function safeHasTag(obj, tag)
    if not obj or not obj.hasTag then return false end
    local ok, has = pcall(function()
        return obj.hasTag(tag)
    end)
    return ok and has or false
end

safeGetPosition = function(obj)
    if not obj or not obj.getPosition then return nil end
    local ok, pos = pcall(function()
        return obj.getPosition()
    end)
    if ok then return pos end
    return nil
end

function safeGetGuid(obj)
    if not obj or not obj.getGUID then return nil end
    local ok, guid = pcall(function()
        return obj.getGUID()
    end)
    if ok then return guid end
    return nil
end

function safeGetName(obj)
    if not obj or not obj.getName then return "" end
    local ok, name = pcall(function()
        return obj.getName() or ""
    end)
    if ok then return tostring(name or "") end
    return ""
end

function safeGetType(obj)
    if not obj then return nil end
    local ok, objType = pcall(function()
        return obj.type
    end)
    if ok then return objType end
    return nil
end

function safeGetTag(obj)
    if not obj then return nil end
    local ok, tag = pcall(function()
        return obj.tag
    end)
    if ok then return tag end
    return nil
end

local function isMoneyChipByName(obj)
    if not obj or not obj.getName then return false end
    local ok, name = pcall(function()
        return tostring(obj.getName() or "")
    end)
    if not ok then return false end
    return name == "$1" or name == "$5" or name == "$10"
end

local function isPossibleMoneyChipObject(obj)
    if not obj then return false end
    if isMoneyChipByName(obj) then return true end

    local objType = string.lower(tostring(obj.type or ""))
    if string.find(objType, "chip", 1, true) ~= nil then
        return true
    end

    return false
end

local function queueMoneyChipVisualRefresh(obj)
    if not obj or not obj.getGUID then return end
    local guid = obj.getGUID()
    local LIFT_DY = 0.2
    -- Stagger the lift timing randomly between 120 and 200 frames for faster settling.
    local delay = 120 + math.random(0, 80)
    Wait.frames(function()
        local live = getObjectFromGUID(guid)
        if not live then return end
        local p = safeGetPosition(live)
        if not p then return end
        pcall(function()
            live.setPosition({x = p.x, y = p.y + LIFT_DY, z = p.z})
        end)
        -- Do not restore; let physics drop the chip naturally.
    end, delay)
end

local function queueMoneyChipRefreshAfterSettle(obj, frameDelays)
    if not obj or not obj.getGUID then return end
    local guid = obj.getGUID()
    local delays = frameDelays or {0, 2, 8}

    for _, delay in ipairs(delays) do
        local function tryRefresh()
            local live = getObjectFromGUID(guid)
            if not live then return end
            -- On load, chip names can initialize late; allow type/name detection.
            if isPossibleMoneyChipObject(live) then
                queueMoneyChipVisualRefresh(live)
            end
        end

        if delay and delay > 0 then
            Wait.frames(tryRefresh, delay)
        else
            tryRefresh()
        end
    end
end

function refreshVisibleMoneyChipsOnTable()
    local refreshed = 0
    for _, obj in ipairs(getAllObjects()) do
        if isPossibleMoneyChipObject(obj) then
            queueMoneyChipRefreshAfterSettle(obj, {0, 4, 16, 48, 360})
            refreshed = refreshed + 1
        end
    end
    marketLog("money chip refresh settle-pass queued for " .. tostring(refreshed) .. " chip candidates")
end

local function findExistingMarkerNearPosition(targetPos, excludeGuid)
    if not targetPos then return nil end

    local MAX_DX = 0.35
    local MAX_DZ = 0.35
    local MAX_DY = 1.0

    for _, obj in ipairs(getAllObjects()) do
        if obj then
            local okGuid, guid = pcall(function()
                return obj.getGUID and obj.getGUID() or nil
            end)
            if not okGuid then guid = nil end
            if guid and guid ~= excludeGuid and (safeHasTag(obj, STACK_BASE_MARKER_TAG) or safeHasTag(obj, "marker")) then
                local pos = safeGetPosition(obj)
                if pos then
                    local dx = math.abs((pos.x or 0) - (targetPos.x or 0))
                    local dz = math.abs((pos.z or 0) - (targetPos.z or 0))
                    local dy = math.abs((pos.y or 0) - (targetPos.y or 0))
                    if dx <= MAX_DX and dz <= MAX_DZ and dy <= MAX_DY then
                        return obj
                    end
                end
            end
        end
    end

    return nil
end

local function cardHasMarkers(cardObj)
    if not cardObj then return false end
    local okHasAttachments = pcall(function()
        return cardObj.getAttachments
    end)
    if not okHasAttachments then return false end
    local okAttach, attachments = pcall(function()
        return cardObj.getAttachments() or {}
    end)
    if not okAttach or type(attachments) ~= "table" then return false end
    return #attachments > 0
end

local function collectRound3StartingBasesIfEligible()
    if ROUND3_BASES_COLLECTED then return end
    if ROUND3_BASES_COLLECT_IN_PROGRESS then return end
    if not isGameStartedWithRoster() then return end

    ROUND3_BASES_COLLECT_IN_PROGRESS = true

    local moveQueue = {}

    local function collectRow(rowGuids, rowZ)
        for _, guid in ipairs(rowGuids or {}) do
            local card = getObjectFromGUID(guid)
            local isCard = false
            if card then
                local okType, objType = pcall(function() return card.type end)
                isCard = okType and objType == "Card"
            end
            if isCard then
                local pos = safeGetPosition(card)
                if pos and math.abs((pos.z or 0) - rowZ) <= ROUND3_BASE_ROW_Z_TOLERANCE then
                    -- Do not relocate if the card already has a marker on/near it.
                    local nearbyMarker = findExistingMarkerNearPosition(pos, nil)
                    if not nearbyMarker and not cardHasMarkers(card) then
                        table.insert(moveQueue, guid)
                    end
                end
            end
        end
    end

    collectRow(ROUND3_BASE_ROW_1_GUIDS, ROUND3_BASE_ROW_1_Z)
    collectRow(ROUND3_BASE_ROW_2_GUIDS, ROUND3_BASE_ROW_2_Z)

    local function finalizeRound3Collect()
        ROUND3_BASES_COLLECTED = true
        pcall(function()
            broadcastToAll("Round 3 – remaining base cards moved to NW\nFirst checkpoint at the end of this round", {1, 1, 1})
        end)
        stackLog("round3 base tidy-up complete")

        -- Hold suppression briefly after movement so delayed drop/physics callbacks are ignored.
        Wait.frames(function()
            ROUND3_BASES_COLLECT_IN_PROGRESS = false
        end, 180)
    end

    local function moveQueued(index)
        if index > #moveQueue then
            finalizeRound3Collect()
            return
        end

        local guid = moveQueue[index]
        local liveCard = guid and getObjectFromGUID(guid) or nil
        if liveCard then
            ROUND3_BASES_RECENTLY_MOVED_GUIDS[guid] = true
            pcall(function()
                -- Non-smooth move reduces physics churn and startup-style race events.
                liveCard.setPosition(ROUND3_BASES_COLLECT_DEST)
            end)
            Wait.frames(function()
                ROUND3_BASES_RECENTLY_MOVED_GUIDS[guid] = nil
            end, 300)
        end

        -- Stagger movement to avoid event bursts from many cards moving at once.
        Wait.frames(function()
            moveQueued(index + 1)
        end, 4)
    end

    moveQueued(1)
end

local function getCardBoundsXZ(obj)
    if not obj then return nil end
    local okB, bounds = pcall(function()
        -- Prefer getBounds() (world-axis-aligned bounding box) over getBoundsNormalized()
        -- because getBoundsNormalized returns the object's natural/pre-rotation dimensions,
        -- which are transposed in world XZ for cards rotated 90° (West/East player cards).
        if obj.getBounds then return obj.getBounds() end
        if obj.getBoundsNormalized then return obj.getBoundsNormalized() end
        return nil
    end)
    if not okB or not bounds or not bounds.center or not bounds.size then return nil end

    local c = bounds.center
    local s = bounds.size
    local halfX = (s.x or 0) * 0.5
    local halfZ = (s.z or 0) * 0.5
    return {
        minX = (c.x or 0) - halfX,
        maxX = (c.x or 0) + halfX,
        minZ = (c.z or 0) - halfZ,
        maxZ = (c.z or 0) + halfZ,
        sizeX = (s.x or 0),
        sizeZ = (s.z or 0),
    }
end

local function hasAnyMarkerOnOrNearCard(cardObj)
    if not cardObj then return false end
    if cardHasMarkers(cardObj) then return true end

    local b = getCardBoundsXZ(cardObj)
    if not b then return false end
    local pad = 0.20

    for _, o in ipairs(getAllObjects()) do
        if o and (safeHasTag(o, STACK_BASE_MARKER_TAG) or safeHasTag(o, "marker")) then
            local p = safeGetPosition(o)
            if p then
                if p.x >= (b.minX - pad) and p.x <= (b.maxX + pad)
                    and p.z >= (b.minZ - pad) and p.z <= (b.maxZ + pad)
                then
                    return true
                end
            end
        end
    end

    return false
end

local function isPosInStackAreaBounds(pos)
    if not pos then return false end
    local stackRows = ((STACK_ROWS - 1) * STACK_DZ_MULTIPLE) + 1
    local minX = STACK_TOPLEFT_POSITION.x - STACK_POSITION_TOLERANCE
    local maxX = STACK_TOPLEFT_POSITION.x + ((STACK_COLUMNS - 1) * STACK_LAYOUT_DX) + STACK_POSITION_TOLERANCE
    local maxZ = STACK_TOPLEFT_POSITION.z + STACK_POSITION_TOLERANCE
    local minZ = (STACK_TOPLEFT_POSITION.z - (STACK_DZ_MULTIPLE * STACK_LAYOUT_DZ))
        - ((stackRows - 1) * STACK_LAYOUT_DZ)
        - STACK_POSITION_TOLERANCE
    return pos.x >= minX and pos.x <= maxX and pos.z <= maxZ and pos.z >= minZ
end

local function getConvenienceAxisAndSign(referenceThing, player_color)
    -- Determine which axis to fan along and in which direction (away from the player).
    -- Primary: use the specific dropping player's hand zone directly — most reliable.
    -- Fallback: nearest seated player's hand zone.
    -- Last resort: card rotation.

    local referencePos = nil
    if referenceThing and referenceThing.getPosition then
        local okPos, pos = pcall(function() return referenceThing.getPosition() end)
        if okPos and pos then referencePos = pos end
    elseif type(referenceThing) == "table" then
        referencePos = referenceThing
    end

    local refX = referencePos and (referencePos.x or 0) or 0
    local refZ = referencePos and (referencePos.z or 0) or 0

    local function axisFromYaw(yaw)
        local y = normalizeYaw(yaw or 0)
        -- Hand/seat rotations are effectively cardinal; classify by nearest cardinal bucket.
        -- 0/180 => horizontal edge facing N/S, so fan along Z.
        -- 90/270 => vertical edge facing E/W, so fan along X.
        local isEastWestFacing = (y >= 45 and y < 135) or (y >= 225 and y < 315)
        if isEastWestFacing then
            return "x"
        end
        return "z"
    end

    local function signAwayFromPlayer(axis, handPos)
        if not handPos then return 1 end
        if axis == "x" then
            local toPlayerX = (handPos.x or 0) - refX
            return (toPlayerX >= 0) and -1 or 1
        end
        local toPlayerZ = (handPos.z or 0) - refZ
        return (toPlayerZ >= 0) and -1 or 1
    end

    -- 1. Try the specific player's own hand transform rotation first.
    -- Rotation gives a stable seat axis; use position only to choose sign (away from player).
    if player_color then
        local p = getPlayerByColorSafe(player_color)
        if p and p.seated and p.getHandTransform then
            local okHand, hand = pcall(function() return p.getHandTransform(1) end)
            if okHand and hand and hand.position then
                local axis = axisFromYaw(hand.rotation and hand.rotation.y or 0)
                local sign = signAwayFromPlayer(axis, hand.position)
                return axis, sign
            end
        end
    end

    -- 2. Fall back to nearest seated player's hand transform rotation.
    local okPlayers, players = pcall(function()
        return Player.getPlayers()
    end)

    if okPlayers and type(players) == "table" then
        local hands = {}
        for _, p in ipairs(players) do
            if p and p.seated and p.getHandTransform then
                local okHand, hand = pcall(function() return p.getHandTransform(1) end)
                local pos = okHand and hand and hand.position or nil
                if pos then
                    table.insert(hands, hand)
                end
            end
        end

        if #hands > 0 then
            local nearest = nil
            local bestD2 = nil
            for _, hp in ipairs(hands) do
                local hPos = hp.position
                local dx = (hPos and hPos.x or 0) - refX
                local dz = (hPos and hPos.z or 0) - refZ
                local d2 = (dx * dx) + (dz * dz)
                if not bestD2 or d2 < bestD2 then
                    bestD2 = d2
                    nearest = hp
                end
            end

            if nearest then
                local axis = axisFromYaw(nearest.rotation and nearest.rotation.y or 0)
                local sign = signAwayFromPlayer(axis, nearest.position)
                return axis, sign
            end
        end
    end

    -- Last resort: fall back to card rotation when no player positions are available.
    if referenceThing and referenceThing.getRotation then
        local okRot, rot = pcall(function() return referenceThing.getRotation() end)
        if okRot and rot then
            local yaw = normalizeYaw(rot.y or 0)
            if yaw >= 45 and yaw < 135 then
                return "x", 1
            elseif yaw >= 135 and yaw < 225 then
                return "z", -1
            elseif yaw >= 225 and yaw < 315 then
                return "x", -1
            end
        end
    end

    return "z", 1
end

local function findProjectConvenienceTarget(droppedProject, player_color)
        -- Only allow convenience stacking if both cards are in the 'face up in hand' orientation for the player seat
        local function isCardInHandLandscapeOrientation(card, player_color)
            if not card or not player_color then return false end
            local rot = card.getRotation()
            local expectedYaw = getHandRelativeCardYaw(nil, false) -- nil zone, project card
            local function closeEnough(a, b)
                return math.abs(((a or 0) - (b or 0) + 180) % 360 - 180) <= 5
            end
            return closeEnough(rot.y, expectedYaw)
        end
    if not droppedProject or droppedProject.type ~= "Card" then return nil end
    if not safeHasTag(droppedProject, "project") or safeHasTag(droppedProject, "improvement") then return nil end

    -- Restrict: never convenience stack if at/near discard pile
    if isObjectAtDiscardPile and (isObjectAtDiscardPile(droppedProject) or (isObjectAtDevDiscardPile and isObjectAtDevDiscardPile(droppedProject))) then
        return nil
    end

    local droppedGuid = droppedProject.getGUID()
    local droppedPos = safeGetPosition(droppedProject)
    if not droppedPos then return nil end

    local droppedBounds = getCardBoundsXZ(droppedProject)
    if not droppedBounds then return nil end

    local axis, sign = getConvenienceAxisAndSign(droppedProject, player_color)

    local prevIntersect = PROJECT_PICKUP_INTERSECTING_GUIDS_BY_GUID[droppedGuid] or {}

    local droppedPrimarySize = (axis == "x") and droppedBounds.sizeX or droppedBounds.sizeZ
    local minPrimaryOverlap = 0.20 * droppedPrimarySize
    local maxPrimaryOverlap = 0.98 * droppedPrimarySize

    local scannedCount = 0
    local prevIntersectSkip = 0
    local stackAreaSkip = 0
    local markerSkip = 0
    local behindSkip = 0
    local boundsSkip = 0
    local overlapSkip = 0

    local best = nil
    local bestAlong = nil

    for _, other in ipairs(getAllObjects()) do
        if other and other.type == "Card" then
            -- Only allow if both cards are in hand landscape orientation for this player
            if not (isCardInHandLandscapeOrientation(droppedProject, player_color) and isCardInHandLandscapeOrientation(other, player_color)) then
                goto continue
            end
            -- Restrict: never convenience stack onto a card at/near discard pile
            if isObjectAtDiscardPile and (isObjectAtDiscardPile(other) or (isObjectAtDevDiscardPile and isObjectAtDevDiscardPile(other))) then
                goto continue
            end
            -- Restrict: only allow if orientation matches (within 5 degrees on all axes)
            local r1 = droppedProject.getRotation()
            local r2 = other.getRotation()
            local function closeEnough(a, b)
                return math.abs(((a or 0) - (b or 0) + 180) % 360 - 180) <= 5
            end
            if not (closeEnough(r1.x, r2.x) and closeEnough(r1.y, r2.y) and closeEnough(r1.z, r2.z)) then
                goto continue
            end
            local okOtherGuid, otherGuid = pcall(function() return other.getGUID() end)
            if okOtherGuid and otherGuid and otherGuid ~= droppedGuid then
                scannedCount = scannedCount + 1
                if not prevIntersect[otherGuid] then
                    local otherPos = safeGetPosition(other)
                    if otherPos and not isPosInStackAreaBounds(otherPos) and not hasAnyMarkerOnOrNearCard(other) then
                        local droppedAlong = sign * (((axis == "x") and droppedPos.x) or droppedPos.z)
                        local otherAlong = sign * (((axis == "x") and otherPos.x) or otherPos.z)
                        if otherAlong > droppedAlong then
                            local ob = getCardBoundsXZ(other)
                            if ob then
                                local xOverlap = math.max(0, math.min(droppedBounds.maxX, ob.maxX) - math.max(droppedBounds.minX, ob.minX))
                                local zOverlap = math.max(0, math.min(droppedBounds.maxZ, ob.maxZ) - math.max(droppedBounds.minZ, ob.minZ))
                                local primaryOverlap = (axis == "x") and xOverlap or zOverlap
                                local crossOverlap = (axis == "x") and zOverlap or xOverlap
                                local minCrossSize = (axis == "x")
                                    and math.min(droppedBounds.sizeZ, ob.sizeZ)
                                    or math.min(droppedBounds.sizeX, ob.sizeX)

                                if primaryOverlap >= minPrimaryOverlap and primaryOverlap <= maxPrimaryOverlap and crossOverlap >= (0.45 * minCrossSize) then
                                    local dAlong = otherAlong - droppedAlong
                                    if not bestAlong or dAlong < bestAlong then
                                        best = other
                                        bestAlong = dAlong
                                    end
                                else
                                    overlapSkip = overlapSkip + 1
                                end
                            else
                                boundsSkip = boundsSkip + 1
                            end
                        else
                            behindSkip = behindSkip + 1
                        end
                    else
                        if not otherPos then
                            boundsSkip = boundsSkip + 1
                        elseif isPosInStackAreaBounds(otherPos) then
                            stackAreaSkip = stackAreaSkip + 1
                        else
                            markerSkip = markerSkip + 1
                        end
                    end
                else
                    prevIntersectSkip = prevIntersectSkip + 1
                end
            end
        end
        ::continue::
    end

    if best then
        stackLog("convenience target selected dropped=" .. tostring(droppedGuid)
            .. " target=" .. tostring(best.getGUID())
            .. " axis=" .. tostring(axis)
            .. " sign=" .. tostring(sign)
            .. " dAlong=" .. string.format("%.3f", bestAlong or 0)
            .. " scanned=" .. tostring(scannedCount))
    else
        stackLog("convenience target none dropped=" .. tostring(droppedGuid)
            .. " axis=" .. tostring(axis)
            .. " sign=" .. tostring(sign)
            .. " scanned=" .. tostring(scannedCount)
            .. " prevIntersect=" .. tostring(prevIntersectSkip)
            .. " stackArea=" .. tostring(stackAreaSkip)
            .. " marker=" .. tostring(markerSkip)
            .. " behind=" .. tostring(behindSkip)
            .. " bounds=" .. tostring(boundsSkip)
            .. " overlap=" .. tostring(overlapSkip)
            .. " minPrimary=" .. string.format("%.3f", minPrimaryOverlap)
            .. " maxPrimary=" .. string.format("%.3f", maxPrimaryOverlap))
    end

    return best
end

local CONVENIENCE_CARD_Y_OFFSET = 0.15   -- enough clearance above target to prevent TTS auto-merge

local function applyProjectConvenienceDrop(droppedProject, targetCard, player_color)
    if not droppedProject or not targetCard then return end
    local droppedGuid = droppedProject.getGUID()
    local targetGuid = targetCard.getGUID()
    local targetPosAtDrop = safeGetPosition(targetCard)

    PROJECT_CONVENIENCE_GROUP_MEMBER_BY_GUID[droppedGuid] = true
    PROJECT_CONVENIENCE_GROUP_MEMBER_BY_GUID[targetGuid] = true

    -- Compute the authoritative destination once, using the target's position at drop time.
    -- Place on the player side of the target so the far edge of the underlying card remains readable.
    local function computeDestination(liveTarget)
        local tPos = safeGetPosition(liveTarget)
        if not tPos then return nil, nil end
        local axis, sign = getConvenienceAxisAndSign(liveTarget, player_color)
        local offsetX = (axis == "x") and (-sign * PROJECT_CONVENIENCE_DZ) or 0
        local offsetZ = (axis == "z") and (-sign * PROJECT_CONVENIENCE_DZ) or 0
        local dest = {
            x = (tPos.x or 0) + offsetX,
            y = (tPos.y or 0) + CONVENIENCE_CARD_Y_OFFSET,
            z = (tPos.z or 0) + offsetZ,
        }
        local tRot = nil
        local okRot, rot = pcall(function() return liveTarget.getRotation() end)
        if okRot then tRot = rot end
        return dest, tRot
    end

    local function applyOnce()
        local liveDropped = getObjectFromGUID(droppedGuid)
        local liveTarget = getObjectFromGUID(targetGuid)
        if not liveDropped or not liveTarget then return end
        -- If TTS already merged them into a deck, ground the deck at the target Y.
        if liveDropped.type == "Deck" or liveTarget.type == "Deck" then
            local deck = (liveDropped.type == "Deck") and liveDropped or liveTarget
            local anchor = safeGetPosition(deck)
            local baseY = (targetPosAtDrop and targetPosAtDrop.y) or (anchor and anchor.y) or 1
            if anchor then
                pcall(function()
                    deck.setPosition({x = anchor.x, y = baseY, z = anchor.z})
                end)
            end
            return
        end
        if liveDropped.type ~= "Card" or liveTarget.type ~= "Card" then return end

        local dest, tRot = computeDestination(liveTarget)
        if not dest then return end

        stackLog("convenience place dropped=" .. tostring(droppedGuid)
            .. " target=" .. tostring(targetGuid)
            .. " dest=" .. string.format("(%.3f, %.3f, %.3f)", dest.x, dest.y, dest.z))

        pcall(function()
            -- Use immediate (non-smooth) transforms to prevent in-flight TTS auto-merge.
            if tRot then liveDropped.setRotation(tRot) end
            liveDropped.setPosition(dest)
        end)
    end

    -- Apply immediately and on two follow-up passes to counter physics settling.
    applyOnce()
    Wait.frames(applyOnce, 2)
    Wait.frames(applyOnce, 8)
end

local function cardIntersectsOtherCards(cardObj)
    if not cardObj then return false end
    local cardGuid = cardObj.getGUID()
    local cardPos = cardObj.getPosition and cardObj.getPosition() or nil
    if not cardPos then return false end
    
    local ok, cardBounds = pcall(function()
        if cardObj.getBoundsNormalized then
            return cardObj.getBoundsNormalized()
        end
        if cardObj.getBounds then
            return cardObj.getBounds()
        end
        return nil
    end)
    
    if not ok or not cardBounds or not cardBounds.center or not cardBounds.size then
        return false
    end
    
    local cardCenter = cardBounds.center
    local cardSize = cardBounds.size
    local cardHalfX = (cardSize.x or 0) * 0.5
    local cardHalfZ = (cardSize.z or 0) * 0.5
    local cardMinX = (cardCenter.x or 0) - cardHalfX
    local cardMaxX = (cardCenter.x or 0) + cardHalfX
    local cardMinZ = (cardCenter.z or 0) - cardHalfZ
    local cardMaxZ = (cardCenter.z or 0) + cardHalfZ

    local gridRows = ((STACK_ROWS - 1) * STACK_DZ_MULTIPLE) + 1
    local stackMinX = STACK_TOPLEFT_POSITION.x - STACK_POSITION_TOLERANCE
    local stackMaxX = STACK_TOPLEFT_POSITION.x + ((STACK_COLUMNS - 1) * STACK_LAYOUT_DX) + STACK_POSITION_TOLERANCE
    local stackMaxZ = STACK_TOPLEFT_POSITION.z + STACK_POSITION_TOLERANCE
    local stackMinZ = (STACK_TOPLEFT_POSITION.z - (STACK_DZ_MULTIPLE * STACK_LAYOUT_DZ))
        - ((gridRows - 1) * STACK_LAYOUT_DZ)
        - STACK_POSITION_TOLERANCE
    
    for _, obj in ipairs(getAllObjects()) do
        if obj and obj ~= cardObj and obj.type == "Card" then
            local okGuid, guid = pcall(function() return obj.getGUID() end)
            if okGuid and guid and guid ~= cardGuid then
                local otherPos = safeGetPosition(obj)
                local okProjectTag, hasProjectTag = pcall(function() return obj.hasTag("project") end)
                local okBaseTag, hasBaseTag = pcall(function() return obj.hasTag("base") end)
                local okImprovementTag, hasImprovementTag = pcall(function() return obj.hasTag("improvement") end)
                local isStackCard = (okProjectTag and hasProjectTag) or (okBaseTag and hasBaseTag) or (okImprovementTag and hasImprovementTag)
                -- Only test cards that are actually part of the stack space/layer.
                if otherPos
                    and otherPos.x >= stackMinX and otherPos.x <= stackMaxX
                    and otherPos.z <= stackMaxZ and otherPos.z >= stackMinZ
                    and math.abs((otherPos.y or 0) - (cardPos.y or 0)) <= 1.0
                    and isStackCard
                then
                local ok2, otherBounds = pcall(function()
                    if obj.getBoundsNormalized then
                        return obj.getBoundsNormalized()
                    end
                    if obj.getBounds then
                        return obj.getBounds()
                    end
                    return nil
                end)
                
                if ok2 and otherBounds and otherBounds.center and otherBounds.size then
                    local otherCenter = otherBounds.center
                    local otherSize = otherBounds.size
                    local otherHalfX = (otherSize.x or 0) * 0.5
                    local otherHalfZ = (otherSize.z or 0) * 0.5
                    local otherMinX = (otherCenter.x or 0) - otherHalfX
                    local otherMaxX = (otherCenter.x or 0) + otherHalfX
                    local otherMinZ = (otherCenter.z or 0) - otherHalfZ
                    local otherMaxZ = (otherCenter.z or 0) + otherHalfZ
                    
                    local xOverlaps = cardMaxX >= otherMinX and cardMinX <= otherMaxX
                    local zOverlaps = cardMaxZ >= otherMinZ and cardMinZ <= otherMaxZ
                    if xOverlaps and zOverlaps then
                        stackLog("cardIntersectsOtherCards: overlap guid=" .. tostring(cardGuid)
                            .. " with=" .. tostring(guid))
                        return true
                    end
                end
                end
            end
        end
    end
    
    return false
end

local function posNearTechMainDeckZone(pos)
    if not pos then return false end
    local deckObj = getObjectFromGUID(TECH_DECK_GUID)
    if not deckObj then return false end
    local refPos = safeGetPosition(deckObj)
    if not refPos then return false end
    local dx = pos.x - refPos.x
    local dz = pos.z - refPos.z
    return (dx * dx + dz * dz) <= (DISCARD_SLOT_THRESHOLD * DISCARD_SLOT_THRESHOLD)
end

local function posNearTechDiscardZone(pos)
    if not pos then return false end
    local discardPos = getDiscardPilePosition()
    if not discardPos then return false end
    local dx = pos.x - discardPos.x
    local dz = pos.z - discardPos.z
    return (dx * dx + dz * dz) <= (DISCARD_SLOT_THRESHOLD * DISCARD_SLOT_THRESHOLD)
end

local function posNearAnyPlaceholder(pos, guidList, threshold)
    if not pos or type(guidList) ~= "table" then return false end
    local r = tonumber(threshold) or 0
    if r <= 0 then return false end
    local r2 = r * r

    for _, guid in ipairs(guidList) do
        local ph = getObjectFromGUID(guid)
        if ph then
            local phPos = safeGetPosition(ph)
            if phPos then
                local dx = (pos.x or 0) - (phPos.x or 0)
                local dz = (pos.z or 0) - (phPos.z or 0)
                local d2 = (dx * dx) + (dz * dz)
                if d2 <= r2 then
                    return true
                end
            end
        end
    end

    return false
end

local function isPosInTechTuckExcludedArea(pos)
    if not pos then return true end

    if getMarketSlotIndexFromPosition and getMarketSlotIndexFromPosition(pos) then
        return true, "market-slot"
    end
    if getTalentRowSlotIndexFromPosition and getTalentRowSlotIndexFromPosition(pos) then
        return true, "talent-slot"
    end
    if posNearAnyPlaceholder(pos, MARKET_PLACEHOLDER_GUIDS, MARKET_SLOT_THRESHOLD + 0.35) then
        return true, "market-placeholder"
    end
    if posNearAnyPlaceholder(pos, TALENT_ROW_PLACEHOLDER_GUIDS, TALENT_ROW_SLOT_THRESHOLD + 0.35) then
        return true, "talent-placeholder"
    end
    if posNearTechMainDeckZone(pos) or posNearTechDiscardZone(pos) then
        return true, "deck-or-discard"
    end
    return false, nil
end

local function findNearbyTechCardForTuck(droppedCard)
    if not droppedCard or droppedCard.type ~= "Card" or not safeHasTag(droppedCard, "tech") then return nil end

    -- Never tuck cards while they are in a hand zone; in-hand rearrange should be inert.
    if objectIsCurrentlyInAnyHandZone(droppedCard) then
        return nil
    end

    local droppedGuid = droppedCard.getGUID()
    local droppedPos = safeGetPosition(droppedCard)
    local droppedExcluded, droppedReason = isPosInTechTuckExcludedArea(droppedPos)
    if not droppedPos or droppedExcluded then
        marketLog("tech tuck target-scan skipped guid=" .. tostring(droppedGuid)
            .. " reason=" .. tostring(droppedReason or "no-pos"))
        return nil
    end

    local best = nil
    local bestD2 = nil
    local MERGE_RADIUS_SQ = 1.2 * 1.2

    for _, other in ipairs(getAllObjects()) do
        local okOtherGuid, otherGuid = pcall(function() return other and other.getGUID() or nil end)
        if okOtherGuid and otherGuid and otherGuid ~= droppedGuid and other and (other.type == "Card" or other.type == "Deck") then
            if objectIsCurrentlyInAnyHandZone(other) then
                goto continue_tuck_scan
            end
            local isTechTarget = false
            if other.type == "Card" then
                isTechTarget = safeHasTag(other, "tech") or safeHasTag(other, "base")
            elseif other.type == "Deck" then
                local okObjs, deckObjs = pcall(function() return other.getObjects and other.getObjects() or {} end)
                if okObjs and type(deckObjs) == "table" then
                    for _, d in ipairs(deckObjs) do
                        if d and d.tags then
                            for _, t in ipairs(d.tags) do
                                if t == "tech" or t == "base" then
                                    isTechTarget = true
                                    break
                                end
                            end
                        end
                        if isTechTarget then break end
                    end
                end
            end

            if isTechTarget then
            local otherPos = safeGetPosition(other)
            local otherExcluded = false
            if otherPos then
                otherExcluded = isPosInTechTuckExcludedArea(otherPos)
            end
            if otherPos and not otherExcluded then
                local dx = droppedPos.x - otherPos.x
                local dz = droppedPos.z - otherPos.z
                local d2 = (dx * dx) + (dz * dz)
                if d2 <= MERGE_RADIUS_SQ and (not bestD2 or d2 < bestD2) then
                    best = other
                    bestD2 = d2
                end
            end
            end
        end
        ::continue_tuck_scan::
    end

    return best
end

local function tuckTechCardUnderTarget(droppedCard, targetObj)
    if not droppedCard or not targetObj then return end

    local droppedGuid = droppedCard.getGUID()
    local targetGuid = targetObj.getGUID()
    local targetPosAtDrop = safeGetPosition(targetObj)
    local TUCK_Y_OFFSET = 0.08
    local MERGE_Y_OFFSET = 0.02
    local RETRY_DELAYS = {1, 3, 8, 16, 32}
    local mergeRecoveryFired = false

    local targetSnapPoints = nil
    if targetObj and targetObj.type == "Card" and targetObj.getSnapPoints then
        local okSnap, snaps = pcall(function()
            return targetObj.getSnapPoints() or {}
        end)
        if okSnap and type(snaps) == "table" and #snaps > 0 then
            targetSnapPoints = JSON.decode(JSON.encode(snaps))
        end
    end

    local function findMergedDeck()
        local target = getObjectFromGUID(targetGuid)
        if target and target.type == "Deck" then
            return target
        end

        local dropped = getObjectFromGUID(droppedGuid)
        if dropped and dropped.type == "Deck" then
            return dropped
        end

        local anchor = targetPosAtDrop
        if not anchor then return nil end
        local SEARCH_RADIUS_SQ = 1.8 * 1.8

        for _, obj in ipairs(getAllObjects()) do
            if obj and obj.type == "Deck" then
                local pos = safeGetPosition(obj)
                if pos then
                    local dx = (pos.x or 0) - (anchor.x or 0)
                    local dz = (pos.z or 0) - (anchor.z or 0)
                    local d2 = (dx * dx) + (dz * dz)
                    if d2 <= SEARCH_RADIUS_SQ then
                        local okObjs, deckObjs = pcall(function() return obj.getObjects and obj.getObjects() or {} end)
                        if okObjs and type(deckObjs) == "table" then
                            for _, d in ipairs(deckObjs) do
                                local g = d and d.guid or nil
                                if g == droppedGuid or g == targetGuid then
                                    return obj
                                end
                            end
                        end
                    end
                end
            end
        end

        return nil
    end

    local function reapplySnapPointsToMergedDeck()
        if not targetSnapPoints then return end
        local deck = findMergedDeck()
        if not deck or not deck.setSnapPoints then return end
        pcall(function()
            deck.setSnapPoints(JSON.decode(JSON.encode(targetSnapPoints)))
        end)
    end

    -- If TTS merged the two cards into a deck, ensure it is grounded at the target surface Y.
    local function groundMergedDeck()
        local deck = findMergedDeck()
        if not deck then return end
        local anchor = targetPosAtDrop
        if not anchor then return end
        local pos = safeGetPosition(deck)
        if not pos then return end
        -- Only correct if the deck is noticeably above the expected surface.
        if math.abs((pos.y or 0) - (anchor.y or 0)) > 0.1 then
            pcall(function()
                deck.setPosition({x = pos.x, y = anchor.y, z = pos.z})
            end)
        end
    end

    -- Recovery for the fast-drop race: card physics caused a TTS deck merge before tuck could fire.
    -- Extracts the dropped card from the merged deck and re-tucks it at the bottom.
    local function recoverFromMerge()
        if mergeRecoveryFired then return end
        local deck = findMergedDeck()
        if not deck then return end
        local okObjs, deckObjs = pcall(function() return deck.getObjects() end)
        if not okObjs or type(deckObjs) ~= "table" or #deckObjs == 0 then return end
        local droppedInDeck = false
        for _, d in ipairs(deckObjs) do
            if d and d.guid == droppedGuid then droppedInDeck = true; break end
        end
        if not droppedInDeck then return end
        mergeRecoveryFired = true
        local deckPos = safeGetPosition(deck)
        if not deckPos then return end
        -- Stage above the deck so physics doesn't immediately re-merge during takeObject.
        local stagePos = {x = deckPos.x, y = deckPos.y + 3, z = deckPos.z}
        stackLog("tuckTechCard recoverFromMerge: extracting droppedGuid=" .. tostring(droppedGuid)
            .. " from merged deck guid=" .. tostring(deck.getGUID()))
        pcall(function()
            deck.takeObject({
                guid = droppedGuid,
                position = stagePos,
                smooth = false,
                callback_function = function(card)
                    if not card then
                        stackLog("tuckTechCard recoverFromMerge: takeObject returned nil")
                        return
                    end
                    Wait.frames(function()
                        local liveTarget = getObjectFromGUID(targetGuid)
                        local refObj = liveTarget or findMergedDeck()
                        local tPos = refObj and safeGetPosition(refObj) or targetPosAtDrop
                        if not tPos then return end
                        local tRot = nil
                        if refObj then
                            local okRot, rot = pcall(function() return refObj.getRotation() end)
                            if okRot then tRot = rot end
                        end
                        pcall(function()
                            if tRot then card.setRotation(tRot) end
                            card.setPosition({x = tPos.x, y = tPos.y - TUCK_Y_OFFSET, z = tPos.z})
                        end)
                        stackLog("tuckTechCard recoverFromMerge: re-tucked card guid=" .. tostring(card.getGUID()))
                    end, 1)
                end,
            })
        end)
    end

    local function applyTuck(yOffset)
        local liveDropped = getObjectFromGUID(droppedGuid)
        local liveTarget = getObjectFromGUID(targetGuid)
        -- Card may have already merged into a deck via fast physics; attempt one-shot recovery.
        if not liveDropped or liveDropped.type ~= "Card" then
            recoverFromMerge()
            return
        end
        if not liveTarget or (liveTarget.type ~= "Card" and liveTarget.type ~= "Deck") then
            return
        end

        local tPos = safeGetPosition(liveTarget)
        if not tPos then return end

        local tRot = nil
        local okRot, rot = pcall(function() return liveTarget.getRotation() end)
        if okRot then tRot = rot end

        pcall(function()
            if tRot then
                -- Use immediate transforms to reduce race windows where TTS stack order reverts.
                liveDropped.setRotation(tRot)
            end
            liveDropped.setPosition({x = tPos.x, y = tPos.y - (yOffset or TUCK_Y_OFFSET), z = tPos.z})
        end)
    end

    -- Initial tuck placement keeps the visible top card in place.
    applyTuck(TUCK_Y_OFFSET)

    -- Follow-up nudge helps TTS merge into a mini-deck (so tucked cards remain visible in hover stack)
    -- and avoids long-lived coplanar overlap that can cause render glitches.
    Wait.frames(function()
        applyTuck(MERGE_Y_OFFSET)
        reapplySnapPointsToMergedDeck()
        groundMergedDeck()
    end, 2)

    -- Additional delayed re-assertions harden against occasional late physics/merge reordering.
    for _, delay in ipairs(RETRY_DELAYS) do
        Wait.frames(function()
            applyTuck(MERGE_Y_OFFSET)
            reapplySnapPointsToMergedDeck()
            groundMergedDeck()
        end, delay)
    end
end

function onObjectDrop(player_color, obj)
    local droppedGuid = safeGetGuid(obj)
    local objType = safeGetType(obj)

    if droppedGuid == STARTING_PLAYER_TOKEN_GUID then
        Wait.frames(function()
            updatePassHud()
        end, 2)
    end

    if droppedGuid == ROUND_MARKER_GUID then
        local markerPos = safeGetPosition(obj)
        if markerPos and math.abs((markerPos.z or 0) - ROUND3_MARKER_Z) <= ROUND3_MARKER_Z_TOLERANCE then
            Wait.frames(function()
                collectRound3StartingBasesIfEligible()
            end, 1)
        end
    end

    -- Suppress side effects for cards auto-moved during game start setup.
    if START_GAME_SETUP_IN_PROGRESS then return end

    -- Suppress side effects for cards auto-moved by round-3 cleanup.
    if droppedGuid and (ROUND3_BASES_COLLECT_IN_PROGRESS or ROUND3_BASES_RECENTLY_MOVED_GUIDS[droppedGuid]) then
        return
    end

    -- Disabled: do not nudge money chips on drop during play (only onLoad).
    -- if isPossibleMoneyChipObject(obj) then
    --     queueMoneyChipRefreshAfterSettle(obj, {1, 6, 20})
    -- end

    local isImprovement = false
    local isBase = false
    local isProject = false
    local isDeveloper = false
    if obj and objType == "Card" then
        isImprovement = safeHasTag(obj, "improvement")
        isBase = safeHasTag(obj, "base")
        isProject = safeHasTag(obj, "project")
        isDeveloper = safeHasTag(obj, "developer")
    end

    -- Prevent improvement/tuck/convenience logic on tech/dev decks and discard piles
    local isTechDeck = (safeGetGuid(obj) == TECH_DECK_GUID)
    local isDevDeck = (safeGetGuid(obj) == DEVELOPER_DECK_GUID)
    local isTechDiscard = isObjectAtDiscardPile(obj)
    local isDevDiscard = isObjectAtDevDiscardPile(obj)

    if not (isTechDeck or isDevDeck or isTechDiscard or isDevDiscard) then
        if obj and objType == "Card" and isImprovement then
            handleImprovementDrop(obj)
            return  -- improvement cards must not fall through to tech-tuck or other paths
        end

        if obj and objType == "Card" and isBase then
            local guid = safeGetGuid(obj)
            if not guid then return end
            local baseOwner = player_color or "Neutral"
            stackLog("base card dropped guid=" .. tostring(guid) .. " by " .. tostring(player_color))

            for _, delay in ipairs({1, 10, 25}) do
                Wait.frames(function()
                    local liveObj = getObjectFromGUID(guid)
                    if liveObj then
                        handleBaseCardCounter(liveObj, baseOwner, delay == 25)
                    end
                end, delay)
            end
        end

        if obj and objType == "Card" and isProject and not isImprovement and not isBase then
            local guid = safeGetGuid(obj)
            if not guid then return end
            local projectOwner = player_color or "Neutral"
            stackLog("project card dropped guid=" .. tostring(guid) .. " by " .. tostring(player_color))

            for _, delay in ipairs({1, 10, 25}) do
                Wait.frames(function()
                    local liveObj = getObjectFromGUID(guid)
                    if liveObj then
                        -- Suppress marker placement if card was just dragged from deck or hand
                        local suppressMarker = false
                        -- Suppress if card was just in a hand zone
                        if HAND_REARRANGE_GUIDS[guid] or objectIsCurrentlyInAnyHandZone(liveObj) then
                            suppressMarker = true
                        end
                        if delay == 25 and not suppressMarker then
                            tryPlaceMarkerOnProjectCard(liveObj, projectOwner, 30)
                        end
                    end
                end, delay)
            end
        end
    end

    if obj and (objType == "Card" or objType == "Deck") and (isDeveloper or safeHasTag(obj, "developer")) then
        local guid = safeGetGuid(obj)
        if not guid then return end
        -- Record drop position for post-merge direction detection.
        local dropPos = safeGetPosition(obj)
        DEV_LAST_DRAG_INFO = {guid = guid, dropX = (dropPos and dropPos.x) or 0}
        local sourceSlot = TALENT_ROW_PICKUP_SLOT_BY_GUID[guid]
        local fromHand = DEV_RECENTLY_LEFT_HAND[guid] or false
        DEV_RECENTLY_LEFT_HAND[guid] = nil
        local droppedOnDevDeck = handleDevMainDeckDrop(obj)
        local droppedOnDevDiscard = false

        if not droppedOnDevDeck then
            droppedOnDevDiscard = handleDevDiscardDrop(obj)
        end

        local objPos = safeGetPosition(obj)
        local targetSlot = objPos and getTalentRowSlotIndexFromPosition(objPos) or nil

        if targetSlot then
            local occupant = getDeveloperCardAtTalentSlot(targetSlot, guid)
            if occupant then
                -- Slot occupied; do not stack. Leave face-up and refresh.
                TALENT_ROW_PICKUP_SLOT_BY_GUID[guid] = nil
                pcall(function()
                    if objType == "Card" then
                        local rot = obj.getRotation()
                        obj.setRotationSmooth({x = rot.x, y = rot.y, z = DEV_FACE_UP_Z}, false, true)
                    end
                end)
                marketLog("drop developer card blocked: talent slot " .. tostring(targetSlot) .. " occupied; card left face-up")
                Wait.frames(function()
                    refreshTalentRow(player_color)
                end, 20)
            else
                local targetPos, targetRot = getTalentRowSlotTransform(targetSlot)
                applyDeveloperCardRowPose(obj, targetPos, targetRot)
                ensureDeveloperCardFaceDown(obj)
                TALENT_ROW_PICKUP_SLOT_BY_GUID[guid] = targetSlot
                marketLog("drop developer card to talent slot " .. tostring(targetSlot) .. " (from " .. tostring(sourceSlot) .. ")")
            end
        else
            TALENT_ROW_PICKUP_SLOT_BY_GUID[guid] = nil

            -- Pre-merge nudge removed: fires after TTS has already merged (receives
            -- Deck not Card), so it caused a loop without preventing merges.
            -- Post-merge split in onObjectSpawn handles this instead.

            if (sourceSlot or fromHand) and not droppedOnDevDeck and not droppedOnDevDiscard then
                pcall(function()
                    if objType == "Card" then
                        local rot = obj.getRotation()
                        obj.setRotationSmooth({x = rot.x, y = rot.y, z = DEV_FACE_UP_Z}, false, true)
                    end
                end)

                Wait.frames(function()
                    refreshTalentRow(player_color)
                end, 20)
            end
        end
        return
    end

    droppedGuid = droppedGuid or nil
    local sourceMarketSlot = droppedGuid and MARKET_PICKUP_SLOT_BY_GUID[droppedGuid] or nil
    local targetMarketSlot = getMarketSlotIndexFromPosition(safeGetPosition(obj))
    local isMarketContextDrop = (sourceMarketSlot ~= nil) or (targetMarketSlot ~= nil)

    -- If this card left a hand zone (potential rearrange), schedule flag cleanup.
    -- onObjectEnterZone consumes the flag first if the card goes back to a hand;
    -- this 30-frame delayed clear handles the case where it was dropped on the table.
    if droppedGuid and HAND_REARRANGE_GUIDS[droppedGuid] then
        Wait.frames(function()
            HAND_REARRANGE_GUIDS[droppedGuid] = nil
        end, 30)
    end

    local pendingConvenienceTarget = nil

    -- Disable project convenience logic for cards dropped on/near discard piles (expanded radius)
    local function isNearDiscardPile(obj)
        local pos = safeGetPosition(obj)
        local dp = getDiscardPilePosition()
        if not pos or not dp then return false end
        local dx, dz = pos.x - dp.x, pos.z - dp.z
        return (dx * dx + dz * dz) <= ((DISCARD_SLOT_THRESHOLD * 2) * (DISCARD_SLOT_THRESHOLD * 2))
    end
    local function isNearDevDiscardPile(obj)
        local pos = safeGetPosition(obj)
        local dp = getDevDiscardPilePosition()
        if not pos or not dp then return false end
        local dx, dz = pos.x - dp.x, pos.z - dp.z
        return (dx * dx + dz * dz) <= ((DISCARD_SLOT_THRESHOLD * 2) * (DISCARD_SLOT_THRESHOLD * 2))
    end
    local isTechDiscard = isObjectAtDiscardPile(obj) or isNearDiscardPile(obj)
    local isDevDiscard = isObjectAtDevDiscardPile(obj) or isNearDevDiscardPile(obj)
    if obj and objType == "Card" and safeHasTag(obj, "project") and not safeHasTag(obj, "improvement") and not (isTechDiscard or isDevDiscard) then
        local isMarketRowReorder = (sourceMarketSlot ~= nil and targetMarketSlot ~= nil)

        -- Convenience should be low priority; defer it until tuck/deck/discard checks have a chance.
        -- Market-row drag/reorder must be handled by slot-swap logic below, never convenience.
        PROJECT_PICKUP_INTERSECTING_GUIDS_BY_GUID[droppedGuid] = nil
        if isMarketContextDrop then
            stackLog("project drop in/from market context; skipping convenience guid=" .. tostring(droppedGuid)
                .. " sourceSlot=" .. tostring(sourceMarketSlot)
                .. " targetSlot=" .. tostring(targetMarketSlot))
        elseif not isMarketRowReorder then
            pendingConvenienceTarget = findProjectConvenienceTarget(obj, player_color)
        else
            stackLog("project drop treated as market-row reorder guid=" .. tostring(droppedGuid)
                .. " sourceSlot=" .. tostring(sourceMarketSlot)
                .. " targetSlot=" .. tostring(targetMarketSlot))
        end
    elseif obj and objType == "Card" then
        local objGuid = safeGetGuid(obj)
        if objGuid then
            PROJECT_PICKUP_INTERSECTING_GUIDS_BY_GUID[objGuid] = nil
        end
    end

    if obj and objType == "Card" and safeHasTag(obj, "tech") and not targetMarketSlot then
        if objectIsCurrentlyInAnyHandZone(obj) then
            marketLog("tech tuck skipped: card in hand zone guid=" .. tostring(safeGetGuid(obj)))
        else
        local objPos = safeGetPosition(obj)
        local excluded, reason = isPosInTechTuckExcludedArea(objPos)
        if excluded then
            marketLog("tech tuck skipped: excluded area=" .. tostring(reason) .. " guid=" .. tostring(safeGetGuid(obj)))
        else
            local tuckTarget = findNearbyTechCardForTuck(obj)
            if tuckTarget then
                marketLog("tech tuck-under drop guid=" .. tostring(safeGetGuid(obj)) .. " target=" .. tostring(safeGetGuid(tuckTarget)))
                tuckTechCardUnderTarget(obj, tuckTarget)
                return
            end
        end
        end
    end

    if pendingConvenienceTarget then
        stackLog("project convenience drop guid=" .. tostring(safeGetGuid(obj))
            .. " target=" .. tostring(safeGetGuid(pendingConvenienceTarget)))
        applyProjectConvenienceDrop(obj, pendingConvenienceTarget, player_color)
        return
    end

    local handledMainDeck = false
    if obj and (objType == "Card" or objType == "Deck") and not safeHasTag(obj, "developer") then
        handledMainDeck = handleMainDeckDrop(obj)
    end

    if obj and not handledMainDeck and (objType == "Card" or objType == "Deck") and not safeHasTag(obj, "developer") then
        local guid = safeGetGuid(obj)
        if not guid then return end
        print("discard: about to call handleDiscardDrop for guid=" .. tostring(guid) .. " type=" .. tostring(objType))
        Wait.frames(function()
            local liveObj = getObjectFromGUID(guid)
            if liveObj then
                print("discard: handleDiscardDrop entry for guid=" .. tostring(guid))
                handleDiscardDrop(liveObj)
            else
                local discardObj = getDiscardDeckObject()
                if discardObj then
                    print("discard: handleDiscardDrop fallback for discard deck object")
                    handleDiscardDrop(discardObj)
                end
            end
        end, 1)
    end

    if not obj or not safeHasTag(obj, "tech") then return end

    local guid = safeGetGuid(obj)
    if not guid then return end
    local sourceSlot = MARKET_PICKUP_SLOT_BY_GUID[guid]
    local targetSlot = getMarketSlotIndexFromPosition(safeGetPosition(obj))
    if not targetSlot then
        marketLog("drop tech card outside market by " .. tostring(player_color) .. "; row left unchanged")
        return
    end

    local targetPos = getMarketSlotPosition(targetSlot)

    if not targetPos then
        MARKET_PICKUP_SLOT_BY_GUID[guid] = nil
        marketLog("drop aborted: no targetPos for slot " .. tostring(targetSlot))
        return
    end

    marketLog("drop tech card to slot " .. tostring(targetSlot) .. " (from " .. tostring(sourceSlot) .. ")")

    if sourceSlot and sourceSlot ~= targetSlot then
        local other = getCardAtMarketSlot(targetSlot, guid)
        if other then
            local sourcePos = getMarketSlotPosition(sourceSlot)
            if sourcePos then
                other.setPositionSmooth(sourcePos, false, true)
                applyTechCardRotation(other)
            end
        end
    end

    pcall(function()
        obj.setPositionSmooth(targetPos, false, true)
    end)
    applyTechCardRotation(obj)
end

function onObjectSpawn(obj)
    local objGuid = safeGetGuid(obj)

    Wait.frames(function()
        local okSpawnMenus, spawnMenusErr = pcall(function()
            local liveObj = objGuid and getObjectFromGUID(objGuid) or nil
            if not liveObj then return end

            if isSnapPatternEligible(liveObj) then
                attachSnapPatternMenus(liveObj)
            end
            attachFixImprovementsMenus(liveObj)
        end)
        if not okSpawnMenus then
            stackLog("onObjectSpawn menu attach failed guid=" .. tostring(objGuid) .. " err=" .. tostring(spawnMenusErr))
        end
    end, 1)

    -- Disabled: do not nudge money chips on spawn during play (only onLoad).
    -- if objGuid then
    --     local liveObjNow = getObjectFromGUID(objGuid)
    --     if liveObjNow and isPossibleMoneyChipObject(liveObjNow) then
    --         queueMoneyChipRefreshAfterSettle(liveObjNow, {1, 6, 20})
    --     end
    -- end

    -- Post-merge directional split: when TTS merges dev cards into a deck outside
    -- allowed zones, extract the dragged card and offset it by DEV_ANTI_MERGE_DX
    -- (safely beyond TTS's merge radius) in the direction it was dragged from.
    -- DEV_RECENT_SPLITS debounce prevents the split from re-triggering if the
    -- offset still lands within merge range (breaks the infinite-loop case).
    local isDeck = false
    if objGuid then
        local liveForType = getObjectFromGUID(objGuid)
        if liveForType then
            local okType, objType = pcall(function() return liveForType.type end)
            isDeck = okType and objType == "Deck"
        end
    end

    if isDeck and DEV_LAST_DRAG_INFO then
        local deckGuid = objGuid
        local dragInfo = DEV_LAST_DRAG_INFO
        Wait.frames(function()
            local live = getObjectFromGUID(deckGuid)
            if not live or safeGetType(live) ~= "Deck" then return end
            if not deckContainsDeveloperCard(live) then return end
            local livePos = safeGetPosition(live)
            if not livePos then return end
            if posNearDevDeckZone(livePos) or posNearDevDiscardZone(livePos) then return end

            -- Debounce: skip if deck contains a card we just split out.
            local okObjs, liveObjs = pcall(function() return live.getObjects() end)
            if not okObjs or type(liveObjs) ~= "table" then return end
            for _, d in ipairs(liveObjs) do
                if DEV_RECENT_SPLITS[d.guid] then
                    marketLog("post-merge split skipped (debounce) for deckGuid=" .. deckGuid)
                    return
                end
            end

            local dp = safeGetPosition(live)
            if not dp then return end
            local direction = (dragInfo.dropX >= dp.x) and 1 or -1

            -- Find the dragged card's index in the deck (TTS index 0 = top).
            local takeIndex = 0
            for i, d in ipairs(liveObjs) do
                if d.guid == dragInfo.guid then
                    takeIndex = #liveObjs - i
                    break
                end
            end

            pcall(function()
                live.takeObject({
                    index    = takeIndex,
                    position = {x = dp.x + direction * DEV_ANTI_MERGE_DX,
                                y = dp.y + 0.3,
                                z = dp.z},
                    smooth   = false,
                    callback_function = function(card)
                        if card then
                            local cg = safeGetGuid(card)
                            if cg then
                                DEV_RECENT_SPLITS[cg] = true
                                Wait.time(function()
                                    DEV_RECENT_SPLITS[cg] = nil
                                end, 2)
                                marketLog("post-merge dev split complete cardGuid=" .. cg
                                    .. " direction=" .. tostring(direction))
                            end
                        end
                    end,
                })
            end)
        end, 1)
    end

    -- Attach dev snap menus to newly spawned developer cards in edit mode.
    if objGuid then
        Wait.frames(function()
            local live = getObjectFromGUID(objGuid)
            if live and safeHasTag(live, "developer") then
                local okType, objType = pcall(function() return live.type end)
                if okType and objType == "Card" then
                    attachDevSnapMenus(live)
                end
            end
        end, 1)
    end
end

function setupMarketRowPlaceholders()
    MARKET_PLACEHOLDER_SLOT_BY_GUID = {}
    if #MARKET_PLACEHOLDER_GUIDS == 0 then
        marketLog("No MARKET_PLACEHOLDER_GUIDS set. Row features disabled until GUIDs are added.")
        return
    end

    for i, guid in ipairs(MARKET_PLACEHOLDER_GUIDS) do
        local p = getObjectFromGUID(guid)
        if p then
            MARKET_PLACEHOLDER_SLOT_BY_GUID[guid] = i
            p.clearButtons()

            if not EDIT_MODE and isGameStartedWithRoster() then
                p.createButton({
                    click_function = "onMarketPlaceholderClick",
                    function_owner = Global,
                    label = "",
                    position = {0, 0.1, 0},
                    rotation = {0, 0, 0},
                    width = ROW_PLACEHOLDER_BUTTON_WIDTH,
                    height = ROW_PLACEHOLDER_BUTTON_HEIGHT,
                    font_size = 1,
                    color = {1, 1, 1, 0},
                    font_color = {1, 1, 1, 0},
                    tooltip = "Click open slot to refresh market"
                })
                marketLog("placeholder slot " .. tostring(i) .. " bound to GUID " .. guid)
            else
                marketLog("placeholder slot " .. tostring(i) .. " left clickable-free (edit mode or game not started)")
            end
        else
            marketLog("placeholder GUID not found: " .. tostring(guid))
        end
    end

    marketLog("placeholder setup done. active slots=" .. tostring(#MARKET_PLACEHOLDER_GUIDS))
end

function onMarketPlaceholderClick(obj, player_color, alt_click)
    if EDIT_MODE then
        return
    end
    if not isGameStartedWithRoster() then
        return
    end
    if not obj then return end
    local guid = obj.getGUID()
    local idx = MARKET_PLACEHOLDER_SLOT_BY_GUID[guid]
    if not idx then return end

    marketLog("placeholder clicked slot " .. tostring(idx) .. " by " .. tostring(player_color))

    if getCardAtMarketSlot(idx) then
        marketLog("slot " .. tostring(idx) .. " occupied; refresh not triggered")
        return
    end
    refreshMarket()
end

function setupTalentRowPlaceholders()
    TALENT_ROW_SLOT_BY_GUID = {}
    if #TALENT_ROW_PLACEHOLDER_GUIDS == 0 then
        marketLog("No TALENT_ROW_PLACEHOLDER_GUIDS set. Talent row disabled until GUIDs are added.")
        return
    end

    for i, guid in ipairs(TALENT_ROW_PLACEHOLDER_GUIDS) do
        local p = getObjectFromGUID(guid)
        if p then
            TALENT_ROW_SLOT_BY_GUID[guid] = i
            p.clearButtons()

            if not EDIT_MODE and isGameStartedWithRoster() then
                p.createButton({
                    click_function = "onTalentRowPlaceholderClick",
                    function_owner = Global,
                    label = "",
                    position = {0, 0.1, 0},
                    rotation = {0, 0, 0},
                    width = ROW_PLACEHOLDER_BUTTON_WIDTH,
                    height = ROW_PLACEHOLDER_BUTTON_HEIGHT,
                    font_size = 1,
                    color = {1, 1, 1, 0},
                    font_color = {1, 1, 1, 0},
                    tooltip = "Click open slot to refresh talent row"
                })
                marketLog("talent row slot " .. tostring(i) .. " bound to GUID " .. guid)
            else
                marketLog("talent row slot " .. tostring(i) .. " left clickable-free (edit mode or game not started)")
            end
        else
            marketLog("talent row placeholder GUID not found: " .. tostring(guid))
        end
    end
end

function onTalentRowPlaceholderClick(obj, player_color, alt_click)
    if EDIT_MODE then
        return
    end
    if not isGameStartedWithRoster() then
        return
    end
    if not obj then return end
    local guid = obj.getGUID()
    local idx = TALENT_ROW_SLOT_BY_GUID[guid]
    if not idx then return end

    marketLog("talent row placeholder clicked slot " .. tostring(idx) .. " by " .. tostring(player_color))

    if getDeveloperCardAtTalentSlot(idx) then
        marketLog("talent row slot " .. tostring(idx) .. " occupied; refresh not triggered")
        return
    end
    refreshTalentRow(player_color)
end

function getMarketSlotPosition(index)
    local guid = MARKET_PLACEHOLDER_GUIDS[index]
    if not guid then return nil end
    local p = getObjectFromGUID(guid)
    if not p then return nil end
    local okPos, pos = pcall(function() return p.getPosition() end)
    if not okPos or not pos then return nil end
    return {x = pos.x, y = pos.y + 0.25, z = pos.z}
end

function getTalentRowSlotTransform(index)
    local guid = TALENT_ROW_PLACEHOLDER_GUIDS[index]
    if not guid then return nil, nil end
    local p = getObjectFromGUID(guid)
    if not p then return nil, nil end
    local okPos, pos = pcall(function() return p.getPosition() end)
    if not okPos or not pos then return nil, nil end
    local okRot, rot = pcall(function() return p.getRotation() end)
    if not okRot then rot = nil end
    return {x = pos.x, y = pos.y + 0.25, z = pos.z}, rot
end

function getMarketSlotIndexFromPosition(pos)
    if not pos then return nil end
    local bestIndex = nil
    local bestDist = nil

    for i = 1, #MARKET_PLACEHOLDER_GUIDS do
        local slotPos = getMarketSlotPosition(i)
        if slotPos then
            local dx = pos.x - slotPos.x
            local dz = pos.z - slotPos.z
            local d2 = dx * dx + dz * dz
            if d2 <= (MARKET_SLOT_THRESHOLD * MARKET_SLOT_THRESHOLD) then
                if not bestDist or d2 < bestDist then
                    bestDist = d2
                    bestIndex = i
                end
            end
        end
    end

    return bestIndex
end

function getTalentRowSlotIndexFromPosition(pos)
    if not pos then return nil end
    local bestIndex = nil
    local bestDist = nil

    for i = 1, #TALENT_ROW_PLACEHOLDER_GUIDS do
        local slotPos = select(1, getTalentRowSlotTransform(i))
        if slotPos then
            local dx = pos.x - slotPos.x
            local dz = pos.z - slotPos.z
            local d2 = dx * dx + dz * dz
            if d2 <= (TALENT_ROW_SLOT_THRESHOLD * TALENT_ROW_SLOT_THRESHOLD) then
                if not bestDist or d2 < bestDist then
                    bestDist = d2
                    bestIndex = i
                end
            end
        end
    end

    return bestIndex
end

function getCardAtMarketSlot(slotIndex, ignoreGuid)
    local slotPos = getMarketSlotPosition(slotIndex)
    if not slotPos then return nil end

    for _, o in ipairs(getAllObjects()) do
        if o.type == "Card" and o.hasTag("tech") then
            local g = o.getGUID()
            if not ignoreGuid or g ~= ignoreGuid then
                local p = o.getPosition()
                local dx = p.x - slotPos.x
                local dz = p.z - slotPos.z
                if (dx * dx + dz * dz) <= (MARKET_SLOT_THRESHOLD * MARKET_SLOT_THRESHOLD) then
                    return o
                end
            end
        end
    end
    return nil
end

function getDeveloperCardAtTalentSlot(slotIndex, ignoreGuid)
    local slotPos = select(1, getTalentRowSlotTransform(slotIndex))
    if not slotPos then return nil end

    for _, o in ipairs(getAllObjects()) do
        if o.type == "Card" and o.hasTag("developer") then
            local g = o.getGUID()
            if not ignoreGuid or g ~= ignoreGuid then
                local p = o.getPosition()
                local dx = p.x - slotPos.x
                local dz = p.z - slotPos.z
                if (dx * dx + dz * dz) <= (TALENT_ROW_SLOT_THRESHOLD * TALENT_ROW_SLOT_THRESHOLD) then
                    return o
                end
            end
        end
    end
    return nil
end

function ensureDeveloperCardFaceDown(card)
    if not card or card.type ~= "Card" then return end

    local guid = card.getGUID()

    local function enforce(target)
        if not target or target.type ~= "Card" then return end

        pcall(function()
            local rot = target.getRotation()
            target.setRotationSmooth({x = rot.x, y = rot.y, z = DEV_FACE_DOWN_Z}, false, true)
        end)
    end

    enforce(card)

    for _, delay in ipairs({1, 6, 15}) do
        Wait.frames(function()
            enforce(getLiveObjectByGUID(guid))
        end, delay)
    end
end

function applyDeveloperCardRowPose(card, targetPos, targetRot)
    if not card then return end

    pcall(function()
        local rot = targetRot or card.getRotation()
        card.setRotationSmooth({x = rot.x, y = rot.y, z = DEV_FACE_DOWN_Z}, false, true)
        if targetPos then
            card.setPositionSmooth(targetPos, false, true)
        end
    end)
end

function applyTechCardRotation(card)
    if not card then return end
    if card.hasTag("industry") then
        card.setRotationSmooth({0, 90, 0}, false, true)
    elseif card.hasTag("project") then
        card.setRotationSmooth({0, 180, 0}, false, true)
    end
end

function refreshMarket(player_color)
    local slotCount = #MARKET_PLACEHOLDER_GUIDS
    if slotCount == 0 then
        marketLog("refreshMarket skipped: no placeholder GUIDs configured")
        return
    end

    marketLog("refreshMarket start, slotCount=" .. tostring(slotCount))

    local rowCards = {}
    for i = 1, slotCount do
        rowCards[i] = getCardAtMarketSlot(i)
    end

    local compact = {}
    for i = 1, slotCount do
        if rowCards[i] then
            table.insert(compact, {card = rowCards[i], sourceSlot = i})
        end
    end

    for i, entry in ipairs(compact) do
        local c = entry.card
        if c and entry.sourceSlot ~= i then
            local pos = getMarketSlotPosition(i)
            if pos then
                pcall(function()
                    c.setPositionSmooth(pos, false, true)
                    applyTechCardRotation(c)
                end)
            end
        end
    end

    local needed = slotCount - #compact
    marketLog("refreshMarket compacted cards=" .. tostring(#compact) .. ", needed=" .. tostring(needed))
    if needed <= 0 then return end

    for n = 1, needed do
        local slotIndex = #compact + n
        local pos = getMarketSlotPosition(slotIndex)

        if pos then
            local deck = getObjectFromGUID(TECH_DECK_GUID)
            if not deck then
                marketLog("refreshMarket ran out of cards before slot " .. tostring(slotIndex) .. "; attempting reshuffle")
                if reshuffleDiscardIntoMainDeck(player_color, true) then
                    Wait.frames(function()
                        local okRefresh, refreshErr = pcall(function()
                            marketLog("refreshMarket delayed refill callback")
                            refreshMarket(player_color)
                        end)
                        if not okRefresh then
                            startLog("error refreshMarket delayed refill err=" .. tostring(refreshErr))
                        end
                    end, 15)
                end
                return
            end

            if deck.type == "Deck" then
                local okTake = pcall(function()
                    deck.takeObject({
                    index = 0,
                    position = pos,
                    smooth = false,
                    callback_function = function(card)
                        if card then
                            marketLog("dealt card into slot " .. tostring(slotIndex))
                            pcall(function() applyTechCardRotation(card) end)
                        else
                            marketLog("deal callback returned nil for slot " .. tostring(slotIndex))
                        end
                    end
                })
                end)
                if not okTake then
                    marketLog("refreshMarket takeObject failed at slot " .. tostring(slotIndex))
                end
            elseif deck.type == "Card" then
                pcall(function()
                    deck.setPositionSmooth(pos, false, true)
                    applyTechCardRotation(deck)
                end)
                marketLog("single card deck moved to slot " .. tostring(slotIndex) .. "; deck exhausted")

                if slotIndex < slotCount then
                    Wait.frames(function()
                        marketLog("market still needs cards after final draw; attempting reshuffle")
                        if reshuffleDiscardIntoMainDeck(player_color, true) then
                            Wait.frames(function()
                                local okRefresh, refreshErr = pcall(function()
                                    marketLog("refreshMarket delayed final-card refill callback")
                                    refreshMarket(player_color)
                                end)
                                if not okRefresh then
                                    startLog("error refreshMarket delayed final-card refill err=" .. tostring(refreshErr))
                                end
                            end, 15)
                        end
                    end, 10)
                end
                break
            else
                marketLog("refreshMarket stopped: unsupported deck.type=" .. tostring(deck.type))
                break
            end
        end
    end
end

function refreshTalentRow(player_color, didSettle)
    local slotCount = #TALENT_ROW_PLACEHOLDER_GUIDS
    if slotCount == 0 then
        marketLog("refreshTalentRow skipped: no talent row placeholder GUIDs configured")
        return
    end

    marketLog("refreshTalentRow start, slotCount=" .. tostring(slotCount))

    local rowCards = {}
    for i = 1, slotCount do
        rowCards[i] = getDeveloperCardAtTalentSlot(i)
    end

    local compact = {}
    for i = 1, slotCount do
        if rowCards[i] then
            table.insert(compact, {card = rowCards[i], sourceSlot = i})
        end
    end

    for i, entry in ipairs(compact) do
        local c = entry.card
        if c and entry.sourceSlot ~= i then
            local pos, rot = getTalentRowSlotTransform(i)
            if pos then
                pcall(function()
                    applyDeveloperCardRowPose(c, pos, rot)
                    ensureDeveloperCardFaceDown(c)
                end)
            end
        end
    end

    local needed = slotCount - #compact
    marketLog("refreshTalentRow compacted cards=" .. tostring(#compact) .. ", needed=" .. tostring(needed))
    if needed <= 0 then return end

    if #compact > 0 and not didSettle then
        Wait.frames(function()
            local okRefresh, refreshErr = pcall(function()
                marketLog("refreshTalentRow delayed settle callback")
                refreshTalentRow(player_color, true)
            end)
            if not okRefresh then
                startLog("error refreshTalentRow delayed settle err=" .. tostring(refreshErr))
            end
        end, 25)
        return
    end

    for n = 1, needed do
        local slotIndex = #compact + n
        local pos, rot = getTalentRowSlotTransform(slotIndex)

        if pos and not getDeveloperCardAtTalentSlot(slotIndex) then
            local deck = getObjectFromGUID(DEVELOPER_DECK_GUID)
            if not deck then
                marketLog("refreshTalentRow ran out of cards before slot " .. tostring(slotIndex) .. "; attempting reshuffle")
                if reshuffleDevDiscardIntoDevDeck(player_color, true) then
                    Wait.frames(function()
                        local okRefresh, refreshErr = pcall(function()
                            marketLog("refreshTalentRow delayed refill callback")
                            refreshTalentRow(player_color)
                        end)
                        if not okRefresh then
                            startLog("error refreshTalentRow delayed refill err=" .. tostring(refreshErr))
                        end
                    end, 15)
                end
                return
            end

            if deck.type == "Deck" then
                local okTake = pcall(function()
                    deck.takeObject({
                    index = 0,
                    position = pos,
                    smooth = false,
                    callback_function = function(card)
                        if card then
                            marketLog("dealt developer card into talent slot " .. tostring(slotIndex))
                            pcall(function()
                                applyDeveloperCardRowPose(card, pos, rot)
                                ensureDeveloperCardFaceDown(card)
                            end)
                        else
                            marketLog("developer deal callback returned nil for talent slot " .. tostring(slotIndex))
                        end
                    end
                })
                end)
                if not okTake then
                    marketLog("refreshTalentRow takeObject failed at slot " .. tostring(slotIndex))
                end
            elseif deck.type == "Card" then
                pcall(function()
                    applyDeveloperCardRowPose(deck, pos, rot)
                    ensureDeveloperCardFaceDown(deck)
                end)
                marketLog("single developer card deck moved to talent slot " .. tostring(slotIndex) .. "; developer deck exhausted")

                if slotIndex < slotCount then
                    Wait.frames(function()
                        marketLog("talent row still needs cards after final draw; attempting developer reshuffle")
                        if reshuffleDevDiscardIntoDevDeck(player_color, true) then
                            Wait.frames(function()
                                local okRefresh, refreshErr = pcall(function()
                                    marketLog("refreshTalentRow delayed final-card refill callback")
                                    refreshTalentRow(player_color)
                                end)
                                if not okRefresh then
                                    startLog("error refreshTalentRow delayed final-card refill err=" .. tostring(refreshErr))
                                end
                            end, 15)
                        end
                    end, 10)
                end
                break
            else
                marketLog("refreshTalentRow stopped: unsupported developer deck.type=" .. tostring(deck.type))
                break
            end
        end
    end
end




-- ============================================================
-- SECTION: Development/Rebuild utilities
-- utilities for mod rebuild and importing updated card decks
-- ============================================================

-- ***** for deck import – import cards, save state, check deck GUIDs, enter guids here, save & play
--       ...then the deck will have a context menu for tagging
-- TODO: simpler if the utility tagging menus are just always available on decks in edit mode, similar to snap-applying utilities
PROJECT_DECK_GUID = "xxxxxx" -- only relevant for utility functions when importing a new version of the deck
INDUSTRY_DECK_GUID = "zzzzzz" -- only relevant for utility functions when importing a new version of the deck

local SNAP_PATTERN_GUIDS = {
    industrymarker = "06acdd",
    industryaction = "2cfd00",
    base = "8acc6e",
    upgradeable = "e5d0ed",
    action = "05eacd",
    actionhigh = "f20954",
    newplatform = "b12320"
}

local SNAP_PATTERN_COMBINATIONS = {
    newplataction = {"actionhigh", "newplatform"}
}

local SNAP_PATTERN_ORDER = {
    "industrymarker",
    "industryaction",
    "base",
    "upgradeable",
    "action",
    "actionhigh",
    "newplatform",
    "newplataction"
}

local function getStackGridRowCount()
    return ((STACK_ROWS - 1) * STACK_DZ_MULTIPLE) + 1
end

local function isWorldPositionInStackArea(pos)
    if not pos then return false end

    local minX = STACK_TOPLEFT_POSITION.x - STACK_POSITION_TOLERANCE
    local maxX = STACK_TOPLEFT_POSITION.x + ((STACK_COLUMNS - 1) * STACK_LAYOUT_DX) + STACK_POSITION_TOLERANCE
    local maxZ = STACK_TOPLEFT_POSITION.z + STACK_POSITION_TOLERANCE
    local minZ = (STACK_TOPLEFT_POSITION.z - (STACK_DZ_MULTIPLE * STACK_LAYOUT_DZ)) - ((getStackGridRowCount() - 1) * STACK_LAYOUT_DZ) - STACK_POSITION_TOLERANCE

    return pos.x >= minX and pos.x <= maxX and pos.z <= maxZ and pos.z >= minZ
end

local function makeProjectStackSnapPoint(hostObj, worldX, worldY, worldZ, label)
    local worldPos = {x = worldX, y = worldY, z = worldZ}
    local localPos = worldPos

    if hostObj and hostObj.positionToLocal then
        localPos = hostObj.positionToLocal(worldPos)
    else
        stackLog("Warning: target object does not support positionToLocal; using world coordinates directly")
    end

    stackLog((label or "snap point") .. " world=" .. string.format("(%.2f, %.2f, %.2f)", worldPos.x, worldPos.y, worldPos.z) .. " local=" .. string.format("(%.2f, %.2f, %.2f)", localPos.x, localPos.y, localPos.z))

    return {
        position = localPos,
        rotation = {
            x = STACK_PROJECT_SNAP_ROTATION.x,
            y = STACK_PROJECT_SNAP_ROTATION.y,
            z = STACK_PROJECT_SNAP_ROTATION.z
        },
        rotation_snap = true,
        tags = {"project"}
    }
end

local function findProjectCardNearPosition(targetX, targetZ, ignoreGuid)
    local best = nil
    local bestDist = nil

    for _, obj in ipairs(getAllObjects()) do
        if obj and obj.type == "Card" and obj.hasTag("project") then
            local guid = obj.getGUID()
            if not ignoreGuid or guid ~= ignoreGuid then
                local pos = obj.getPosition()
                local dx = pos.x - targetX
                local dz = pos.z - targetZ
                local d2 = (dx * dx) + (dz * dz)

                if math.abs(dx) <= STACK_POSITION_TOLERANCE and math.abs(dz) <= STACK_POSITION_TOLERANCE then
                    if not bestDist or d2 < bestDist then
                        best = obj
                        bestDist = d2
                    end
                end
            end
        end
    end

    return best
end

local function findImprovementCardNearPosition(targetX, targetZ, ignoreGuid)
    local best = nil
    local bestDist = nil

    for _, obj in ipairs(getAllObjects()) do
        if obj and obj.type == "Card" and obj.hasTag("improvement") then
            local guid = obj.getGUID()
            if not ignoreGuid or guid ~= ignoreGuid then
                local pos = obj.getPosition()
                local dx = pos.x - targetX
                local dz = pos.z - targetZ
                local d2 = (dx * dx) + (dz * dz)

                if math.abs(dx) <= STACK_POSITION_TOLERANCE and math.abs(dz) <= STACK_POSITION_TOLERANCE then
                    if not bestDist or d2 < bestDist then
                        best = obj
                        bestDist = d2
                    end
                end
            end
        end
    end

    return best
end

local function findBaseCardNearObject(obj)
    if not obj then return nil end

    local pos = obj.getPosition()
    local best = nil
    local bestDist = nil

    for _, candidate in ipairs(getAllObjects()) do
        if candidate and candidate ~= obj and candidate.type == "Card" and candidate.hasTag("base") then
            local cpos = candidate.getPosition()
            local dx = pos.x - cpos.x
            local dz = pos.z - cpos.z
            local d2 = (dx * dx) + (dz * dz)

            if d2 <= (STACK_BASE_DETECT_RADIUS * STACK_BASE_DETECT_RADIUS) then
                if not bestDist or d2 < bestDist then
                    best = candidate
                    bestDist = d2
                end
            end
        end
    end

    return best
end

local function getStackCounterOwnerGuid(obj)
    if not obj or not obj.getGMNotes then return nil end
    return string.match(obj.getGMNotes() or "", "^base_guid:(%w+)$")
end

local function getStackMarkerOwnerGuid(obj)
    if not obj or not obj.getGMNotes then return nil end
    return string.match(obj.getGMNotes() or "", "^base_marker_guid:(%w+)$")
end

local function vecComponent(v, axis)
    if not v then return nil end
    if axis == "x" then return v.x or v[1] end
    if axis == "y" then return v.y or v[2] end
    if axis == "z" then return v.z or v[3] end
    return nil
end

-- Places one marker per player onto the morale and brand track starting positions.
function initializeTrackMarkers()
    local colors = STARTED_PLAYER_COLORS
    if not colors or #colors == 0 then
        stackLog("initializeTrackMarkers: no started players, skipping")
        return
    end

    local function findTrackMarkerNearPosition(targetPos, excludeGuid)
        if not targetPos then return nil end

        local MAX_DX = 0.25
        local MAX_DZ = 0.25
        local MAX_DY = 1.2

        for _, obj in ipairs(getAllObjects()) do
            if obj then
                local guid = safeGetGuid(obj)
                if guid and guid ~= excludeGuid then
                    local pos = safeGetPosition(obj)
                    if pos then
                        local dx = math.abs((pos.x or 0) - (targetPos.x or 0))
                        local dz = math.abs((pos.z or 0) - (targetPos.z or 0))
                        local dy = math.abs((pos.y or 0) - (targetPos.y or 0))
                        if dx <= MAX_DX and dz <= MAX_DZ and dy <= MAX_DY then
                            if safeHasTag(obj, "trackmarkerauto") or safeHasTag(obj, "marker") then
                                return obj
                            end
                            local n = string.lower(safeGetName(obj))
                            if string.find(n, "morale", 1, true) or string.find(n, "brand", 1, true) then
                                return obj
                            end
                        end
                    end
                end
            end
        end

        return nil
    end

    local function placeMarkerAt(ownerLabel, targetPos, markerName, attemptsLeft)
        local existingMarkerNow = findTrackMarkerNearPosition(targetPos, nil)
        if not existingMarkerNow then
            spawnDirectMarkerForOwner(ownerLabel, targetPos, markerName, nil, "trackmarkerauto")
        end
    end

    for i, color in ipairs(colors) do
        if i > 4 then break end
        local moralePos = MORALE_TRACK_START_POSITIONS[i]
        local brandPos  = BRAND_TRACK_START_POSITIONS[i]
        local ownerKey = string.lower(tostring(color or "player"))
        if moralePos then
            placeMarkerAt(color, moralePos, ownerKey .. " morale", 120)
        end
        if brandPos then
            placeMarkerAt(color, brandPos, ownerKey .. " brand", 120)
        end
    end
end

local function getLeftmostSnapWorldPosition(cardObj)
    if not cardObj or not cardObj.getSnapPoints then return nil end
    local okPoints, points = pcall(function()
        return cardObj.getSnapPoints() or {}
    end)
    if not okPoints or type(points) ~= "table" then return nil end
    local bestWorld = nil
    local bestX = nil

    for _, p in ipairs(points) do
        if p and p.position then
            local worldPos = cardObj.positionToWorld and cardObj.positionToWorld(p.position) or p.position
            local wx = vecComponent(worldPos, "x")
            if worldPos and wx and (bestX == nil or wx < bestX) then
                bestWorld = worldPos
                bestX = wx
            end
        end
    end

    return bestWorld
end

local function getSecondLeftmostSnapWorldPosition(cardObj)
    if not cardObj or not cardObj.getSnapPoints then return nil end
    local okPoints, points = pcall(function()
        return cardObj.getSnapPoints() or {}
    end)
    if not okPoints or type(points) ~= "table" then return nil end
    
    -- Collect all snaps sorted by X position (left to right)
    local sortedSnaps = {}
    for _, p in ipairs(points) do
        if p and p.position then
            local worldPos = cardObj.positionToWorld and cardObj.positionToWorld(p.position) or p.position
            if worldPos then
                table.insert(sortedSnaps, {pos = worldPos, x = vecComponent(worldPos, "x") or 0})
            end
        end
    end
    
    if #sortedSnaps < 2 then return nil end
    
    table.sort(sortedSnaps, function(a, b) return a.x < b.x end)
    return sortedSnaps[2].pos
end

local function isCardSnappedForAutoMarker(cardObj)
    if not cardObj then return false end
    if not cardObj.getRotation then return false end

    local okRot, rot = pcall(function()
        return cardObj.getRotation()
    end)
    if not okRot or not rot then return false end

    local yaw = rot.y or 0
    local normalizedYaw = yaw % 360
    if normalizedYaw < 0 then normalizedYaw = normalizedYaw + 360 end

    local delta = math.abs(normalizedYaw - STACK_AUTOMARKER_SNAP_ROT_Y)
    if delta > 180 then
        delta = 360 - delta
    end

    return delta <= STACK_AUTOMARKER_SNAP_ROT_Y_TOLERANCE
end

function tryPlaceMarkerOnProjectCard(projectObj, ownerLabel, attemptsLeft)
    if not projectObj or not ownerLabel then return end

    -- Guard: must be a project card that is NOT an improvement
    if safeGetType(projectObj) ~= "Card" or not safeHasTag(projectObj, "project") or safeHasTag(projectObj, "improvement") then
        return
    end

    local projectGuid = projectObj.getGUID()
    stackLog("tryPlaceMarkerOnProjectCard: checking guid=" .. tostring(projectGuid) .. " owner=" .. tostring(ownerLabel))

    -- Condition (b): Check if card already has any markers attached or sitting on/near it
    if hasAnyMarkerOnOrNearCard(projectObj) then
        stackLog("tryPlaceMarkerOnProjectCard: card already has marker on/near guid=" .. tostring(projectGuid))
        return
    end

    -- Check if card is in stack area
    local projectPos = safeGetPosition(projectObj)

    -- Skip auto-marker at lower stack end for non-base cards.
    if projectPos and not safeHasTag(projectObj, "base") and projectPos.z < AUTOMARKER_BOUNDARY_Z then
        stackLog("tryPlaceMarkerOnProjectCard: skipped by automarker boundary guid=" .. tostring(projectGuid)
            .. " z=" .. string.format("%.3f", projectPos.z)
            .. " boundary=" .. string.format("%.3f", AUTOMARKER_BOUNDARY_Z))
        return
    end

    if not projectPos or not isWorldPositionInStackArea(projectPos) then
        stackLog("tryPlaceMarkerOnProjectCard: card not in stack area guid=" .. tostring(projectGuid))
        return
    end

    if not isCardSnappedForAutoMarker(projectObj) then
        local rot = projectObj.getRotation and projectObj.getRotation() or nil
        stackLog("tryPlaceMarkerOnProjectCard: skipped unsnapped card guid=" .. tostring(projectGuid)
            .. " rotY=" .. string.format("%.1f", rot and rot.y or -999))
        return
    end

    -- Condition (a): Check if card intersects other cards
    if cardIntersectsOtherCards(projectObj) then
        stackLog("tryPlaceMarkerOnProjectCard: card intersects other cards guid=" .. tostring(projectGuid))
        return
    end

    -- Condition (c): Check if card has snap points
    local okSnap, snapPoints = pcall(function()
        return projectObj.getSnapPoints and projectObj.getSnapPoints() or {}
    end)
    if not okSnap or type(snapPoints) ~= "table" or #snapPoints == 0 then
        stackLog("tryPlaceMarkerOnProjectCard: card has no snap points guid=" .. tostring(projectGuid))
        return
    end

    -- All conditions met; attempt to place marker
    local function tryPlace(triesLeft)
        local liveCard = getObjectFromGUID(projectGuid)
        if not liveCard then
            stackLog("tryPlaceMarkerOnProjectCard aborted: card missing guid=" .. tostring(projectGuid))
            return
        end

        if not isCardSnappedForAutoMarker(liveCard) then
            local liveRot = liveCard.getRotation and liveCard.getRotation() or nil
            stackLog("tryPlaceMarkerOnProjectCard: placement-time skip unsnapped card guid=" .. tostring(projectGuid)
                .. " rotY=" .. string.format("%.1f", liveRot and liveRot.y or -999))
            return
        end

        -- Re-check at placement time; another delayed pass may have already placed one.
        if hasAnyMarkerOnOrNearCard(liveCard) then
            stackLog("tryPlaceMarkerOnProjectCard: marker detected at placement-time, skipping guid=" .. tostring(projectGuid))
            return
        end

        local cardPos = liveCard.getPosition()
        local snapPos = getLeftmostSnapWorldPosition(liveCard)
        local targetPos = makeVec3(
            vecComponent(snapPos, "x") or vecComponent(cardPos, "x") or 0,
            (vecComponent(cardPos, "y") or 1) + 0.35,
            vecComponent(snapPos, "z") or vecComponent(cardPos, "z") or 0
        )

        if spawnDirectMarkerForOwner(ownerLabel, targetPos, nil, "project_marker_guid:" .. tostring(projectGuid), STACK_BASE_MARKER_TAG) then
            stackLog("tryPlaceMarkerOnProjectCard: direct marker mode owner=" .. tostring(ownerLabel) .. " card=" .. tostring(projectGuid))
        end
    end

    tryPlace(attemptsLeft or 30)
end

local function placeOwnerMarkerOnBase(baseObj, ownerLabel)
    if not baseObj or not ownerLabel then return end

    local okBaseGuid, baseGuid = pcall(function()
        return baseObj.getGUID()
    end)
    if not okBaseGuid or not baseGuid then
        stackLog("owner marker aborted: failed to read base guid owner=" .. tostring(ownerLabel))
        return
    end

    local function tryPlaceMarker(attemptsLeft)
        local liveBase = getObjectFromGUID(baseGuid)
        if not liveBase then
            stackLog("owner marker aborted: base missing guid=" .. tostring(baseGuid))
            return
        end

        if not isCardSnappedForAutoMarker(liveBase) then
            local liveRot = liveBase.getRotation and liveBase.getRotation() or nil
            stackLog("owner marker skipped: base unsnapped guid=" .. tostring(baseGuid)
                .. " rotY=" .. string.format("%.1f", liveRot and liveRot.y or -999))
            return
        end

        -- If any marker is already attached or sitting on/near this base, do not place another.
        if hasAnyMarkerOnOrNearCard(liveBase) then
            stackLog("owner marker skipped: marker already on/near base=" .. tostring(baseGuid))
            return
        end

        local basePos = safeGetPosition(liveBase)
        if not basePos then
            if attemptsLeft > 0 then
                Wait.frames(function() tryPlaceMarker(attemptsLeft - 1) end, 10)
            else
                stackLog("owner marker skipped: base position unavailable owner=" .. tostring(ownerLabel) .. " base=" .. tostring(baseGuid))
            end
            return
        end
        -- Exception: base+tech cards use second leftmost snap point
        local snapPos = nil
        if liveBase.hasTag and liveBase.hasTag("base") and liveBase.hasTag("tech") then
            snapPos = getSecondLeftmostSnapWorldPosition(liveBase)
        end
        if not snapPos then
            snapPos = getLeftmostSnapWorldPosition(liveBase)
        end
        local targetPos = makeVec3(
            vecComponent(snapPos, "x") or vecComponent(basePos, "x") or 0,
            (vecComponent(basePos, "y") or 1) + 0.35,
            vecComponent(snapPos, "z") or vecComponent(basePos, "z") or 0
        )

        if spawnDirectMarkerForOwner(ownerLabel, targetPos, nil, "base_marker_guid:" .. tostring(baseGuid), STACK_BASE_MARKER_TAG) then
            stackLog("owner marker direct mode owner=" .. tostring(ownerLabel) .. " base=" .. tostring(baseGuid))
        end
    end

    tryPlaceMarker(120)
end

local function getTuckedImprovementY(baseY)
    local targetY = baseY - STACK_IMPROVEMENT_DY
    stackLog("tuck improvement baseY=" .. string.format("%.3f", baseY) .. " targetY=" .. string.format("%.3f", targetY))
    return targetY
end

local function finalizeStackCounter(counter, baseGuid, targetPos, targetRot)
    if not counter then
        stackLog("finalizeStackCounter received nil counter")
        return
    end

    counter.setName("stack level")
    counter.setLock(false)
    counter.addTag(STACK_COUNTER_TAG)

    if counter.setGMNotes then
        counter.setGMNotes("base_guid:" .. baseGuid)
    end

    local okValue, errValue = pcall(function()
        counter.setValue(1)
    end)
    if okValue then
        stackLog("initialized stack counter value to 1")
    else
        stackLog("could not set stack counter value: " .. tostring(errValue))
    end

    if targetRot then
        counter.setRotation(targetRot)
    end

    counter.setPosition(targetPos)

    -- Ensure correct orientation and lock after physics settle
    Wait.frames(function()
        if counter then
            counter.setLock(false)
            if targetRot then
                counter.setRotation(targetRot)
            end
            counter.setPosition(targetPos)
            counter.setLock(true)
            stackLog("finalized stack counter at " .. string.format("(%.2f, %.2f, %.2f)", targetPos.x, targetPos.y, targetPos.z))
        end
    end, 1)
end

function removeStackCounterForBase(baseObj, removeMarkers)
    if not baseObj then return end
    if removeMarkers == nil then removeMarkers = true end

    local baseGuid = baseObj.getGUID()
    for _, obj in ipairs(getAllObjects()) do
        if obj and obj.type ~= "Card" and safeHasTag(obj, STACK_COUNTER_TAG) then
            if getStackCounterOwnerGuid(obj) == baseGuid then
                obj.destruct()
            end
        end
        if removeMarkers and obj and safeHasTag(obj, STACK_BASE_MARKER_TAG) then
            if getStackMarkerOwnerGuid(obj) == baseGuid then
                obj.destruct()
            end
        end
    end
end

function handleBaseCardCounter(baseObj, ownerLabel, placeMarker)
    if not baseObj or baseObj.type ~= "Card" or not safeHasTag(baseObj, "base") then return end

    if placeMarker == nil then placeMarker = true end

    local okBaseGuid, baseGuid = pcall(function()
        return baseObj.getGUID and baseObj.getGUID() or nil
    end)
    if not okBaseGuid or not baseGuid then
        stackLog("handleBaseCardCounter: base guid unavailable")
        return
    end

    -- Preserve existing markers on the card during counter refresh.
    removeStackCounterForBase(baseObj, false)

    local basePos = safeGetPosition(baseObj)
    if not basePos then return end
    stackLog("handleBaseCardCounter guid=" .. tostring(baseGuid) .. " pos=" .. string.format("(%.2f, %.2f, %.2f)", basePos.x, basePos.y, basePos.z))

    -- Determine the stack column x and top-row slot this base card aligns with.
    -- We allow a counter if the card is at the top row OR if there are no cards
    -- above it within STACK_DZ_MULTIPLE * STACK_LAYOUT_DZ in the same column.
    local slotX = nil
    local nearestColX = nil
    local nearestColDx = nil
    for col = 0, STACK_COLUMNS - 1 do
        local cx = STACK_TOPLEFT_POSITION.x + (col * STACK_LAYOUT_DX)
        local dx = math.abs(basePos.x - cx)
        if not nearestColDx or dx < nearestColDx then
            nearestColDx = dx
            nearestColX = cx
        end
        if math.abs(basePos.x - cx) <= STACK_POSITION_TOLERANCE then
            slotX = cx
            break
        end
    end

    if not slotX then
        if nearestColX and nearestColDx and nearestColDx <= STACK_COLUMN_FALLBACK_TOLERANCE then
            slotX = nearestColX
            stackLog("handleBaseCardCounter: using nearest column fallback guid=" .. tostring(baseGuid)
                .. " dx=" .. string.format("%.3f", nearestColDx)
                .. " slotX=" .. string.format("%.3f", slotX))
        else
            stackLog("handleBaseCardCounter: base card x not in any stack column; counter not created")
            return
        end
    end

    if not isWorldPositionInStackArea(basePos) then
        stackLog("handleBaseCardCounter: base card not in stack area; counter not created")
        return
    end

    -- Check whether any card (project or base) occupies a z-position above this base
    -- such that there is no complete blank row above. A blank row is one full STACK_DZ_MULTIPLE * STACK_LAYOUT_DZ
    -- of unoccupied space. So we require the next card to be at least 2 full rows away.
    local gapThreshold = (2 * STACK_DZ_MULTIPLE * STACK_LAYOUT_DZ) + STACK_POSITION_TOLERANCE
    local hasCardAbove = false
    stackLog("handleBaseCardCounter GAP CHECK: basePos.z=" .. string.format("%.3f", basePos.z) 
        .. " slotX=" .. string.format("%.3f", slotX)
        .. " gapThreshold=" .. string.format("%.3f", gapThreshold)
        .. " (requires 2 full rows = 10*STACK_LAYOUT_DZ)")
    for _, obj in ipairs(getAllObjects()) do
        local okCandidate, isCandidate = pcall(function()
            return obj and obj ~= baseObj and obj.type == "Card"
                and (safeHasTag(obj, "project") or safeHasTag(obj, "base"))
        end)

        if okCandidate and isCandidate then
            local opos = safeGetPosition(obj)
            if opos then
                local dx = math.abs(opos.x - slotX)
                local dz = opos.z - basePos.z
                if dx <= STACK_POSITION_TOLERANCE then
                    -- "above" means closer to top row (larger z in this layout)
                    if dz > 0 and dz <= gapThreshold then
                        hasCardAbove = true
                        local okOtherGuid, otherGuid = pcall(function()
                            return obj.getGUID and obj.getGUID() or "?"
                        end)
                        if not okOtherGuid then otherGuid = "?" end
                        stackLog("handleBaseCardCounter: SUPPRESSED by card guid=" .. tostring(otherGuid)
                            .. " dz=" .. string.format("%.3f", dz))
                        break
                    end
                end
            end
        elseif not okCandidate then
            stackLog("handleBaseCardCounter: scan candidate read failed; skipping object")
        end
    end

    if hasCardAbove then
        stackLog("handleBaseCardCounter: card(s) exist above base within gap threshold; counter not created")

        -- Base+tech cards should still receive auto-markers even when counter generation is suppressed.
        if placeMarker and safeHasTag(baseObj, "tech") then
            local markerOwner = ownerLabel or "Neutral"
            stackLog("handleBaseCardCounter: suppressed-counter fallback marker for base+tech guid=" .. tostring(baseGuid))
            placeOwnerMarkerOnBase(baseObj, markerOwner)
        end

        return
    end

    -- Place counter above the base card's actual position (snapped to column x).
    local targetPos = {
        x = slotX + STACK_COUNTER_DX,
        y = STACK_COUNTER_Y,
        z = basePos.z + STACK_COUNTER_DZ
    }

    local template = resolveStackCounterTemplate()
    if not template then
        debugPrint("⚠️ Stack counter template not found from candidates: " .. table.concat(STACK_COUNTER_TEMPLATE_GUIDS or {}, ", "))
        if placeMarker then
            local markerOwner = ownerLabel or "Neutral"
            stackLog("handleBaseCardCounter: counter template missing; marker-only fallback base=" .. tostring(baseGuid))
            placeOwnerMarkerOnBase(baseObj, markerOwner)
        end
        return
    end

    -- Stack counters always spawn upright (y=0), even if base card is y=180
    local targetRot = {x = 0, y = 0, z = 0}

    local counter, cloneErr = cloneStackCounterFromTemplate(template, targetPos, targetRot)
    if not counter then
        -- If cached template became invalid for cloning, clear and retry once from candidates.
        STACK_COUNTER_TEMPLATE_GUID_CACHE = nil
        local retryTemplate = resolveStackCounterTemplate()
        if retryTemplate and retryTemplate ~= template then
            counter, cloneErr = cloneStackCounterFromTemplate(retryTemplate, targetPos, targetRot)
            if counter then
                stackLog("handleBaseCardCounter: clone retry succeeded using fallback template")
            end
        end
    end

    if counter then
        finalizeStackCounter(counter, baseGuid, targetPos, targetRot)
        stackLog("spawned stack counter for base guid=" .. tostring(baseGuid) .. " targeting " .. string.format("(%.2f, %.2f, %.2f)", targetPos.x, targetPos.y, targetPos.z))
        if placeMarker then
            local markerOwner = ownerLabel or "Neutral"
            placeOwnerMarkerOnBase(baseObj, markerOwner)
        end
    else
        stackLog("template clone failed for base guid=" .. tostring(baseGuid) .. " err=" .. tostring(cloneErr))
        if placeMarker then
            local markerOwner = ownerLabel or "Neutral"
            stackLog("handleBaseCardCounter: counter clone failed; marker-only fallback base=" .. tostring(baseGuid))
            placeOwnerMarkerOnBase(baseObj, markerOwner)
        end
    end
end

function CreateStackGrid(player_color)
    stackLog("CreateStackGrid called by " .. tostring(player_color))

    if not EDIT_MODE then
        stackLog("Aborted: EDIT_MODE is false")
        broadcastToColor("Enable EDIT_MODE before running createstack", player_color or "White")
        return
    end

    local targets = {}
    if player_color and Player[player_color] then
        targets = Player[player_color].getSelectedObjects()
        stackLog("Selected target count = " .. tostring(#targets))
    end

    if not targets or #targets == 0 then
        local mat = getObjectFromGUID(STACK_MAT_GUID)
        if mat then
            targets = {mat}
            stackLog("Using fallback stack mat target GUID " .. tostring(STACK_MAT_GUID) .. " name='" .. tostring(mat.getName()) .. "'")
        else
            stackLog("Error: stack mat not found for GUID " .. tostring(STACK_MAT_GUID))
            broadcastToColor("Could not find the stack mat by GUID: " .. tostring(STACK_MAT_GUID), player_color or "White")
            return
        end
    end

    local totalGenerated = 0

    for _, obj in ipairs(targets) do
        if not obj then
            stackLog("Skipping nil target object")
        elseif not obj.setSnapPoints then
            stackLog("Target object does not support setSnapPoints: " .. tostring(obj.getGUID()))
        else
            local merged = {}
            local existing = obj.getSnapPoints() or {}
            local removedExisting = 0

            stackLog("Preparing target '" .. tostring(obj.getName()) .. "' guid=" .. tostring(obj.getGUID()) .. " existing_snap_points=" .. tostring(#existing))

            for _, point in ipairs(existing) do
                local worldPos = nil
                if point and point.position then
                    if obj.positionToWorld then
                        worldPos = obj.positionToWorld(point.position)
                    else
                        worldPos = point.position
                    end
                end

                if not (point and worldPos and isWorldPositionInStackArea(worldPos)) then
                    table.insert(merged, JSON.decode(JSON.encode(point)))
                else
                    removedExisting = removedExisting + 1
                    stackLog("Removing previous stack snap point at world=" .. string.format("(%.2f, %.2f, %.2f)", worldPos.x, worldPos.y, worldPos.z))
                end
            end

            for col = 0, STACK_COLUMNS - 1 do
                table.insert(merged, makeProjectStackSnapPoint(
                    obj,
                    STACK_TOPLEFT_POSITION.x + (col * STACK_LAYOUT_DX),
                    STACK_TOPLEFT_POSITION.y,
                    STACK_TOPLEFT_POSITION.z,
                    "top row col " .. tostring(col + 1)
                ))
                totalGenerated = totalGenerated + 1
            end

            local gridStartZ = STACK_TOPLEFT_POSITION.z - (STACK_DZ_MULTIPLE * STACK_LAYOUT_DZ)
            local rowCount = getStackGridRowCount()
            stackLog("Generating lower grid rows=" .. tostring(rowCount) .. " columns=" .. tostring(STACK_COLUMNS) .. " for target guid=" .. tostring(obj.getGUID()))

            for row = 0, rowCount - 1 do
                local z = gridStartZ - (row * STACK_LAYOUT_DZ)
                for col = 0, STACK_COLUMNS - 1 do
                    table.insert(merged, makeProjectStackSnapPoint(
                        obj,
                        STACK_TOPLEFT_POSITION.x + (col * STACK_LAYOUT_DX),
                        STACK_TOPLEFT_POSITION.y,
                        z,
                        "grid row " .. tostring(row + 1) .. " col " .. tostring(col + 1)
                    ))
                    totalGenerated = totalGenerated + 1
                end
            end

            obj.setSnapPoints(merged)
            local finalCount = #(obj.getSnapPoints() or {})
            stackLog("Applied stack grid to guid=" .. tostring(obj.getGUID()) .. "; removed_existing=" .. tostring(removedExisting) .. "; final_snap_points=" .. tostring(finalCount))
        end
    end

    stackLog("CreateStackGrid finished; total new stack snap points generated=" .. tostring(totalGenerated))
    broadcastToColor("Created stack grid on " .. tostring(#targets) .. " object(s)", player_color or "White")
end

function onChat(message, player)
    local msg = string.lower((message or ""):gsub("^%s+", ""):gsub("%s+$", ""))

    if msg == "help" then
        local helpMessage = "Available chat commands:\n'cam <1-4>/market/stack' for camera presets\n'pass' to show as passed in HUD\n'unpass' to show as active in HUD\n'pass reset' to reset all players to active in HUD"
        broadcastToColor(helpMessage, (player and player.color) or "White")
        return false
    end

    if msg == "pass reset" then
        PASSED_BY_COLOR = {}
        updatePassHud()
        broadcastToAll("All players in", {0.8, 0.95, 0.8})
        return false
    end

    if msg == "pass" then
        local color = player and player.color or nil
        if color then
            PASSED_BY_COLOR[color] = true
            updatePassHud()
            broadcastToAll(color .. " has passed", {0.9, 0.9, 0.9})
        end
        return false
    end

    if msg == "unpass" then
        local color = player and player.color or nil
        if color then
            PASSED_BY_COLOR[color] = nil
            updatePassHud()
            broadcastToAll(color .. " has unpassed", {0.9, 0.9, 0.9})
        end
        return false
    end

    if msg == "editmode" or msg == "!editmode" or msg == "/editmode" then
        toggleEditMode(player and player.color or nil)
        return false
    end

    if msg == "createstack" or msg == "!createstack" or msg == "/createstack" then
        CreateStackGrid(player.color)
        return false
    end

    if msg == "printguids" or msg == "!printguids" or msg == "/printguids" then
        if not EDIT_MODE then
            broadcastToColor("Enable EDIT_MODE before running printguids", player and player.color or "White")
            return false
        end

        local PRINTGUIDS_EXCLUDED_GUIDS = {
            ["c2221a"] = true,
        }

        local selected = Player[player.color].getSelectedObjects()
        if not selected or #selected == 0 then
            broadcastToColor("No objects selected", player.color)
            return false
        end

        -- Find x,z bounding box from selected objects
        local minX, maxX, minZ, maxZ = nil, nil, nil, nil
        for _, obj in ipairs(selected) do
            local pos = obj.getPosition()
            local x, z = pos.x, pos.z
            if minX == nil or x < minX then minX = x end
            if maxX == nil or x > maxX then maxX = x end
            if minZ == nil or z < minZ then minZ = z end
            if maxZ == nil or z > maxZ then maxZ = z end
        end

        -- Collect selected GUIDs + any objects within x,z frame
        local collectedGuids = {}
        local seen = {}
        for _, obj in ipairs(selected) do
            local guid = obj.getGUID()
            if guid and not seen[guid] and not PRINTGUIDS_EXCLUDED_GUIDS[string.lower(guid)] then
                table.insert(collectedGuids, guid)
                seen[guid] = true
            end
        end

        -- Expand search to include locked objects in same x,z frame.
        -- Use both pivot and object bounds so odd pivots do not get missed.
        local framePadding = 0.9
        local frameMinX = minX - framePadding
        local frameMaxX = maxX + framePadding
        local frameMinZ = minZ - framePadding
        local frameMaxZ = maxZ + framePadding

        local function intersectsFrame(obj)
            if not obj then return false end

            local pos = obj.getPosition and obj.getPosition() or nil
            if pos and pos.x >= frameMinX and pos.x <= frameMaxX and pos.z >= frameMinZ and pos.z <= frameMaxZ then
                return true
            end

            local ok, bounds = pcall(function()
                if obj.getBoundsNormalized then
                    return obj.getBoundsNormalized()
                end
                if obj.getBounds then
                    return obj.getBounds()
                end
                return nil
            end)

            if not ok or not bounds then return false end
            local center = bounds.center
            local size = bounds.size
            if not center or not size then return false end

            local halfX = (size.x or 0) * 0.5
            local halfZ = (size.z or 0) * 0.5
            local objMinX = (center.x or 0) - halfX
            local objMaxX = (center.x or 0) + halfX
            local objMinZ = (center.z or 0) - halfZ
            local objMaxZ = (center.z or 0) + halfZ

            local xOverlaps = objMaxX >= frameMinX and objMinX <= frameMaxX
            local zOverlaps = objMaxZ >= frameMinZ and objMinZ <= frameMaxZ
            return xOverlaps and zOverlaps
        end

        for _, obj in ipairs(getAllObjects()) do
            local guid = obj.getGUID()
            if guid and not seen[guid] then
                if (not PRINTGUIDS_EXCLUDED_GUIDS[string.lower(guid)]) and intersectsFrame(obj) then
                    table.insert(collectedGuids, guid)
                    seen[guid] = true
                end
            end
        end

        local guidsStr = table.concat(collectedGuids, ", ")
        broadcastToColor("GUIDs (" .. #collectedGuids .. "): " .. guidsStr, player.color)
        return false
    end

    if msg == "freejoins" or msg == "!freejoins" or msg == "/freejoins" then
        if not EDIT_MODE then
            broadcastToColor("Enable EDIT_MODE before running freejoins", player and player.color or "White")
            return false
        end

        FREE_JOINS = true
        broadcastToAll("Free joins enabled: Black reservation and started-color reassignment are disabled", {0.95, 0.9, 0.6})
        return false
    end

    if msg == "unfreejoins" or msg == "!unfreejoins" or msg == "/unfreejoins" then
        if not EDIT_MODE then
            broadcastToColor("Enable EDIT_MODE before running unfreejoins", player and player.color or "White")
            return false
        end

        FREE_JOINS = false
        broadcastToAll("Free joins disabled: Black reservation and started-color reassignment are active", {0.8, 0.95, 0.8})
        return false
    end

    local camPreset = string.match(msg, "^!cam%s+(.+)$")
        or string.match(msg, "^/cam%s+(.+)$")
        or string.match(msg, "^cam%s+(.+)$")

    if camPreset then
        focusCameraPreset(player and player.color or nil, camPreset)
        return false
    end
end

function handleImprovementDrop(obj)
    if not obj or obj.type ~= "Card" or not obj.hasTag("improvement") then return end

    local dropPos = obj.getPosition()
    local base = findBaseCardNearObject(obj)
    if not base then return end

    local basePos = base.getPosition()
    local objGuid = obj.getGUID()
    local baseGuid = base.getGUID()
    local tuckedY = getTuckedImprovementY(basePos.y)
    stackLog("DROP obj=" .. objGuid
        .. " dropPos x=" .. string.format("%.3f", dropPos.x)
        .. " y=" .. string.format("%.3f", dropPos.y)
        .. " z=" .. string.format("%.3f", dropPos.z)
        .. " -> base=" .. baseGuid
        .. " basePos x=" .. string.format("%.3f", basePos.x)
        .. " y=" .. string.format("%.3f", basePos.y)
        .. " z=" .. string.format("%.3f", basePos.z)
        .. " dx=" .. string.format("%.3f", math.abs(dropPos.x - basePos.x))
        .. " dz=" .. string.format("%.3f", math.abs(dropPos.z - basePos.z)))

    -- Hard gate: only cards with the explicit improvement tag are ever treated
    -- as improvements for Y-axis tuck decisions (STACK_IMPROVEMENT_DY offset).
    local function isTaggedImprovement(o)
        return o
            and o.type == "Card"
            and o.hasTag
            and o.hasTag("improvement")
    end

    -- Park the dropped card high in Y immediately (same Lua frame as the drop event,
    -- before TTS physics resolves collisions). +3 in Y puts it well above the table
    -- surface so TTS cannot merge it into any nearby card or deck during the wait.
    obj.setPosition({x = basePos.x, y = basePos.y + 3, z = basePos.z})
    stackLog("PARK dropped=" .. objGuid .. " parkedAt y=" .. string.format("%.3f", basePos.y + 3)
        .. " x=" .. string.format("%.3f", basePos.x)
        .. " z=" .. string.format("%.3f", basePos.z))

    -- Wait for TTS drop physics to finish settling before we apply the authoritative
    -- layout. The dropped card is isolated at y+3 so no merging can occur.
    Wait.frames(function()
        local liveBase = getObjectFromGUID(baseGuid)
        if not liveBase then
            stackLog("LAYOUT ABORT: base gone guid=" .. baseGuid)
            return
        end

        local liveBasePos = liveBase.getPosition()
        local liveTuckedY = getTuckedImprovementY(liveBasePos.y)
        stackLog("LAYOUT START base=" .. baseGuid
            .. " basePos x=" .. string.format("%.3f", liveBasePos.x)
            .. " y=" .. string.format("%.3f", liveBasePos.y)
            .. " z=" .. string.format("%.3f", liveBasePos.z)
            .. " tolerance=" .. tostring(STACK_POSITION_TOLERANCE))

        -- Compute z-position slot index from a world position.
        local function getDepth(pos)
            local dz = liveBasePos.z - pos.z
            if dz <= 0 then return 0 end
            local d = math.floor((dz / STACK_LAYOUT_DZ) + 0.5)
            return d < 1 and 1 or d
        end

        local taggedImprovements = {}
        local nonImprovements = {}
        local targetByGuid = {}
        local slotOccupants = {}
        local BASE_ROW_DEPTH = STACK_DZ_MULTIPLE
        -- Treat cards as part of the same stack segment unless there are at least
        -- 5 empty slots between occupied depths (depth delta >= 6).
        local BREAK_DEPTH_GAP = STACK_DZ_MULTIPLE + 1
        local allCandidates = {}

        -- Keep diagnostics compact so they remain visible in TTS console.
        for _, o in ipairs(getAllObjects()) do
            if o and (o.type == "Card" or o.type == "Deck") then
                local guid = o.getGUID()
                local pos = o.getPosition()
                local dx = math.abs(pos.x - liveBasePos.x)
                local inColX = dx <= STACK_POSITION_TOLERANCE
                local inColZ = pos.z <= (liveBasePos.z + STACK_POSITION_TOLERANCE)
                local depth = getDepth(pos)
                local isImp = isTaggedImprovement(o)

                local skipReason = ""
                if guid == baseGuid then
                    skipReason = "IS_BASE"
                elseif guid == objGuid then
                    skipReason = "IS_DROPPED"
                elseif not inColX then
                    skipReason = "OUT_OF_COL_X dx=" .. string.format("%.3f", dx)
                elseif not inColZ then
                    skipReason = "OUT_OF_COL_Z"
                elseif depth < 1 then
                    skipReason = "DEPTH<1 depth=" .. tostring(depth)
                end

                if skipReason == "" then
                    table.insert(allCandidates, {obj = o, depth = depth, isImp = isImp, y = pos.y})
                    stackLog("SCAN_INITIAL_FOUND: type=" .. o.type .. " guid=" .. guid .. " depth=" .. tostring(depth) .. " isImp=" .. tostring(isImp) .. " y=" .. string.format("%.3f", pos.y))
                else
                    if depth >= 1 and depth <= 8 then
                        stackLog("SCAN_INITIAL_SKIP: type=" .. o.type .. " guid=" .. guid .. " depth=" .. tostring(depth) .. " reason=" .. skipReason)
                    end
                end
            end
        end

        -- Sort candidates by depth and walk forward from the base card row depth.
        -- If there is ever a depth jump >= BREAK_DEPTH_GAP, that implies at least
        -- 5 empty slots and therefore a separate stack segment below.
        table.sort(allCandidates, function(a, b) return a.depth < b.depth end)
        local lastDepth = BASE_ROW_DEPTH
        stackLog("GAP_WALK start: totalCandidates=" .. tostring(#allCandidates) 
            .. " lastDepth=" .. tostring(lastDepth) .. " BREAK_DEPTH_GAP=" .. tostring(BREAK_DEPTH_GAP))
        for _, c in ipairs(allCandidates) do
            local gap = c.depth - lastDepth
            if gap >= BREAK_DEPTH_GAP then
                stackLog("GAP_WALK reject: depth=" .. tostring(c.depth) 
                    .. " guid=" .. c.obj.getGUID() 
                    .. " gap=" .. tostring(gap) .. " >= " .. tostring(BREAK_DEPTH_GAP))
                break  -- separate stack segment: stop here, ignore rest
            end
            stackLog("GAP_WALK accept: depth=" .. tostring(c.depth) 
                .. " guid=" .. c.obj.getGUID() 
                .. " isImp=" .. tostring(c.isImp) 
                .. " gap=" .. tostring(gap))
            if c.depth > lastDepth then lastDepth = c.depth end
            local occ = c.obj.type .. ":" .. c.obj.getGUID()
            if c.isImp then occ = occ .. ":imp" end
            if not slotOccupants[c.depth] then
                slotOccupants[c.depth] = occ
            else
                slotOccupants[c.depth] = slotOccupants[c.depth] .. "|" .. occ
            end
            if c.isImp then
                table.insert(taggedImprovements, {obj = c.obj, depth = c.depth, isDropped = false})
            else
                table.insert(nonImprovements, {obj = c.obj, depth = c.depth, y = c.y})
            end
        end
        local slotSummary = {}
        for d = 1, 8 do
            table.insert(slotSummary, "d" .. tostring(d) .. "=" .. (slotOccupants[d] or "-"))
        end
        stackLog("SLOTS " .. table.concat(slotSummary, " "))
        stackLog("SCAN end: taggedImprovements=" .. tostring(#taggedImprovements)
            .. " nonImprovements=" .. tostring(#nonImprovements))

        -- Add the dropped improvement explicitly; force it to the deepest slot.
        -- GUARDRAIL: Verify the dropped card is actually tagged as improvement.
        local droppedObj = getObjectFromGUID(objGuid)
        if not droppedObj then
            stackLog("LAYOUT ABORT: dropped card gone guid=" .. objGuid)
            return
        end
        if not isTaggedImprovement(droppedObj) then
            stackLog("CRITICAL: dropped card is NOT tagged as improvement! guid=" .. objGuid 
                .. " treating as non-improvement instead")
            table.insert(nonImprovements, {obj = droppedObj, depth = math.huge, y = droppedObj.getPosition().y})
        else
            table.insert(taggedImprovements, {obj = droppedObj, depth = math.huge, isDropped = true})
        end

        -- Sort improvements: existing by z-position slot (shallowest first),
        -- dropped improvement last (forced to deepest slot in the block).
        table.sort(taggedImprovements, function(a, b)
            if a.isDropped ~= b.isDropped then
                return (not a.isDropped) and b.isDropped
            end
            return a.depth < b.depth
        end)

        -- Lay improvements into contiguous z-position slots 1..N (each with Y-axis tuck).
        -- GUARDRAIL: Verify each card is actually tagged as improvement before tucking.
        -- Rule: deeper south slot => lower Y (closer to table); base card remains highest.
        local nextDepth = 1
        local improvementCount = #taggedImprovements
        for _, entry in ipairs(taggedImprovements) do
            if not entry.isDropped and not isTaggedImprovement(entry.obj) then
                stackLog("CRITICAL: non-improvement in taggedImprovements! guid=" .. entry.obj.getGUID() 
                    .. " moving to nonImprovements instead")
                table.insert(nonImprovements, {obj = entry.obj, depth = entry.depth, y = entry.obj.getPosition().y})
            else
                local tz = liveBasePos.z - (nextDepth * STACK_LAYOUT_DZ)
                -- Slot 1 sits closest to the base card; deeper slots layer farther down.
                local distanceFromTop = nextDepth - 1
                local iy = liveTuckedY - (distanceFromTop * STACK_IMPROVEMENT_LAYER_DY)
                local guid = entry.obj.getGUID()
                stackLog("PLACE improvement guid=" .. entry.obj.getGUID()
                    .. " isDropped=" .. tostring(entry.isDropped)
                    .. " -> slot=" .. tostring(nextDepth)
                    .. " y=" .. string.format("%.3f", iy)
                    .. " z=" .. string.format("%.3f", tz))
                entry.obj.setPosition({x = liveBasePos.x, y = iy, z = tz})
                if entry.obj.type == "Card" then applyTechCardRotation(entry.obj) end
                targetByGuid[guid] = {
                    x = liveBasePos.x,
                    y = iy,
                    z = tz,
                    isCard = (entry.obj.type == "Card"),
                    lockBefore = (entry.obj.getLock and entry.obj.getLock() or false)
                }
                if entry.obj.setLock then entry.obj.setLock(true) end
                nextDepth = nextDepth + 1
            end
        end

        -- Sort non-improvements by z-position slot (shallowest first).
        table.sort(nonImprovements, function(a, b) return a.depth < b.depth end)

        -- Shift all non-improvements in this segment by exactly one slot per drop.
        -- Existing improvements were already accounted for in prior layouts.
        -- Capture marker positions before shifting to restore them after.
        -- Markers are NOT attached objects; they sit freely on top of cards.
        -- We identify them by marker-related tags and card bounds overlap.
        local markerDataByCardGuid = {}  -- [cardGuid] = {{pos, marker, relOffset}, ...}

        -- Build a list of all free markers in the scene once (avoid repeated getAllObjects calls).
        local allFreeMarkers = {}
        for _, obj in ipairs(getAllObjects()) do
            if obj and obj ~= droppedObj and (safeHasTag(obj, "marker") or safeHasTag(obj, STACK_BASE_MARKER_TAG)) then
                local mPos = safeGetPosition(obj)
                if mPos then
                    table.insert(allFreeMarkers, {obj = obj, pos = mPos})
                end
            end
        end

        for _, entry in ipairs(nonImprovements) do
            local cardGuid = entry.obj.getGUID()
            if entry.obj.type == "Card" then
                local cardPos = safeGetPosition(entry.obj)
                local cardBounds = getCardBoundsXZ(entry.obj)
                if cardPos and cardBounds then
                    for _, mEntry in ipairs(allFreeMarkers) do
                        local mPos = mEntry.pos
                        local pad = 0.18
                        local withinXZ = mPos.x >= (cardBounds.minX - pad) and mPos.x <= (cardBounds.maxX + pad)
                            and mPos.z >= (cardBounds.minZ - pad) and mPos.z <= (cardBounds.maxZ + pad)
                        local withinY = math.abs((mPos.y or 0) - (cardPos.y or 0)) <= 1.2
                        if withinXZ and withinY then
                            if not markerDataByCardGuid[cardGuid] then
                                markerDataByCardGuid[cardGuid] = {}
                            end
                            -- Store offset relative to card so we can shift it with the card
                            table.insert(markerDataByCardGuid[cardGuid], {
                                marker = mEntry.obj,
                                relX = mPos.x - cardPos.x,
                                relY = mPos.y - cardPos.y,
                                relZ = mPos.z - cardPos.z,
                            })
                        end
                    end
                end
            end
        end

        local shiftDelta = 1
        local improvementCount = nextDepth - 1
        local maxPlacedDepth = nextDepth - 1

        for _, entry in ipairs(nonImprovements) do
            local slot = entry.depth + shiftDelta
            local tz = liveBasePos.z - (slot * STACK_LAYOUT_DZ)
            local guid = entry.obj.getGUID()
            local reason = "SHIFT_BY_DROP"
            stackLog("PLACE non-improvement guid=" .. entry.obj.getGUID()
                .. " type=" .. entry.obj.type
                .. " origDepth=" .. tostring(entry.depth)
                .. " nextDepth=" .. tostring(nextDepth)
                .. " improvementCount=" .. tostring(improvementCount)
                .. " shiftDelta=" .. tostring(shiftDelta)
                .. " reason=" .. reason
                .. " -> slot=" .. tostring(slot)
                .. " y=" .. string.format("%.3f", entry.y)
                .. " z=" .. string.format("%.3f", tz))
            entry.obj.setPosition({x = liveBasePos.x, y = entry.y, z = tz})
            if entry.obj.type == "Card" then applyTechCardRotation(entry.obj) end
            -- Move any free-floating markers that sit on this card along with it.
            local cardMarkers = markerDataByCardGuid[guid]
            if cardMarkers then
                for _, mData in ipairs(cardMarkers) do
                    if mData.marker then
                        pcall(function()
                            mData.marker.setPosition({
                                x = liveBasePos.x + mData.relX,
                                y = entry.y + mData.relY,
                                z = tz + mData.relZ,
                            })
                        end)
                    end
                end
            end
            targetByGuid[guid] = {
                x = liveBasePos.x,
                y = entry.y,
                z = tz,
                isCard = (entry.obj.type == "Card"),
                lockBefore = (entry.obj.getLock and entry.obj.getLock() or false),
                markers = markerDataByCardGuid[guid]  -- store marker data for later restoration
            }
            if entry.obj.setLock then entry.obj.setLock(true) end
            if slot > maxPlacedDepth then
                maxPlacedDepth = slot
            end
        end
        nextDepth = maxPlacedDepth + 1
        stackLog("LAYOUT DONE nextDepth=" .. tostring(nextDepth))

        -- Re-assert authoritative positions in delayed passes to counter physics settling.
        -- Also restore marker positions that may have drifted or been displaced.
        local function verifyAndReapply(passLabel, unlockAfter)
            local corrected = 0
            local missing = 0
            local markerRestored = 0
            for guid, target in pairs(targetByGuid) do
                local liveObj = getObjectFromGUID(guid)
                if liveObj then
                    if liveObj.setLock then
                        liveObj.setLock(true)
                    end
                    local pos = liveObj.getPosition()
                    local offX = math.abs(pos.x - target.x)
                    local offY = math.abs(pos.y - target.y)
                    local offZ = math.abs(pos.z - target.z)
                    if offX > 0.02 or offY > 0.02 or offZ > 0.02 then
                        liveObj.setPosition({x = target.x, y = target.y, z = target.z})
                        if target.isCard and liveObj.type == "Card" then
                            applyTechCardRotation(liveObj)
                        end
                        corrected = corrected + 1
                    end
                    
                    -- Restore marker positions relative to the card's target position.
                    -- Markers are free-floating (not attached), so we track them by relative offset.
                    if target.markers and target.isCard then
                        for _, markerData in ipairs(target.markers) do
                            if markerData.marker then
                                local destX = target.x + markerData.relX
                                local destY = target.y + markerData.relY
                                local destZ = target.z + markerData.relZ
                                local mPos = safeGetPosition(markerData.marker)
                                if mPos then
                                    local mOffX = math.abs(mPos.x - destX)
                                    local mOffY = math.abs(mPos.y - destY)
                                    local mOffZ = math.abs(mPos.z - destZ)
                                    if mOffX > 0.05 or mOffY > 0.05 or mOffZ > 0.05 then
                                        pcall(function()
                                            markerData.marker.setPosition({x = destX, y = destY, z = destZ})
                                        end)
                                        markerRestored = markerRestored + 1
                                    end
                                end
                            end
                        end
                    end
                    
                    if unlockAfter and liveObj.setLock then
                        liveObj.setLock(target.lockBefore == true)
                    end
                else
                    missing = missing + 1
                end
            end
            local markerLog = (markerRestored > 0) and (" markerRestored=" .. tostring(markerRestored)) or ""
            stackLog("VERIFY " .. passLabel .. " corrected=" .. tostring(corrected)
                .. " missing=" .. tostring(missing) .. markerLog)
        end

        Wait.frames(function()
            verifyAndReapply("pass1", false)
        end, 2)

        Wait.frames(function()
            verifyAndReapply("pass2", false)
        end, 8)

        Wait.frames(function()
            verifyAndReapply("pass3", false)
        end, 16)

        Wait.frames(function()
            verifyAndReapply("pass4", true)
        end, 32)
    end, 6)
end

function fixImprovementsOnBaseCard(baseCard)
    if not baseCard or not baseCard.hasTag("base") then return end
    
    local basePos = baseCard.getPosition()
    if not basePos then return end
    
    -- Find all improvement cards nearby (within reasonable depth tolerance)
    local improvements = {}
    local maxSearchDepth = 8
    for d = 1, maxSearchDepth do
        local searchZ = basePos.z - (d * STACK_LAYOUT_DZ)
        local margin = 0.35
        for _, obj in ipairs(getAllObjects()) do
            if obj and obj.type == "Card" and obj.hasTag("improvement") then
                local opos = obj.getPosition()
                if opos and math.abs(opos.x - basePos.x) < 0.4 
                    and math.abs(opos.z - searchZ) < margin then
                    table.insert(improvements, {obj = obj, depth = d})
                    break
                end
            end
        end
    end
    
    if #improvements == 0 then
        broadcastToAll("No improvements found near base card.", "White")
        return
    end
    
    -- Sort by depth (descending: deepest/furthest away first)
    table.sort(improvements, function(a, b) return a.depth > b.depth end)
    
    stackLog("fixImprovementsOnBaseCard: found " .. tostring(#improvements) .. " improvements")
    
    -- Re-layer improvements using the same formula as drop handler:
    -- Deeper south slot/depth = lower Y (closer to table), base remains highest.
    local improvementCount = #improvements
    for _, entry in ipairs(improvements) do
        if entry.obj and entry.obj.getPosition then
            -- entry.depth is the slot number (1, 2, 3, ...)
            -- distanceFromTop: slot 1 gets 0 (highest improvement), deeper slots get lower.
            local slotNumber = entry.depth
            local distanceFromTop = slotNumber - 1
            local targetY = basePos.y - STACK_IMPROVEMENT_DY - (distanceFromTop * STACK_IMPROVEMENT_LAYER_DY)
            local targetZ = basePos.z - (entry.depth * STACK_LAYOUT_DZ)
            entry.obj.setPosition({
                x = basePos.x,
                y = targetY,
                z = targetZ
            })
            if entry.obj.type == "Card" then
                applyTechCardRotation(entry.obj)
            end
            stackLog("  improvement slot " .. tostring(entry.depth) 
                .. " (index " .. tostring(slotNumber) .. "/" .. tostring(improvementCount)
                .. ") -> y=" .. string.format("%.3f", targetY))
        end
    end
    
    -- Ensure base card is on top
    Wait.frames(function()
        if baseCard and baseCard.getPosition then
            baseCard.setPosition({
                x = basePos.x,
                y = basePos.y,
                z = basePos.z
            })
            if baseCard.type == "Card" then
                applyTechCardRotation(baseCard)
            end
        end
    end, 2)
    
    broadcastToAll("Fixed " .. tostring(#improvements) .. " improvement(s) on base card.", "White")
end

-- Recovery when a base card was accidentally merged into a deck with improvements.
-- Extracts all cards, places base at the deck position, and re-runs improvement layering.
function fixImprovementsOnDeck(deckObj)
    if not deckObj or deckObj.type ~= "Deck" then return end

    local deckPos = safeGetPosition(deckObj)
    if not deckPos then return end

    local okObjs, deckObjs = pcall(function() return deckObj.getObjects() end)
    if not okObjs or type(deckObjs) ~= "table" or #deckObjs == 0 then return end

    local function hasTagInList(objData, tag)
        if not objData or not objData.tags then return false end
        for _, t in ipairs(objData.tags) do
            if t == tag then return true end
        end
        return false
    end

    -- Build extraction plan: all improvement cards + the base card.
    local plan = {}
    local baseCount = 0
    local improvementCount = 0
    for i, d in ipairs(deckObjs) do
        local isBase = hasTagInList(d, "base")
        local isImprovement = hasTagInList(d, "improvement")
        if isBase or isImprovement then
            if isBase then baseCount = baseCount + 1 end
            if isImprovement then improvementCount = improvementCount + 1 end
            table.insert(plan, {
                tableIndex = i,
                ttsIndex = #deckObjs - i, -- TTS takeObject index is 0-based from top
                isBase = isBase,
                isImprovement = isImprovement,
            })
        end
    end

    if baseCount == 0 then
        stackLog("fixImprovementsOnDeck: no base card found in deck guid=" .. tostring(deckObj.getGUID()))
        broadcastToAll("Could not find base card in deck.", "White")
        return
    end
    if improvementCount == 0 then
        -- No improvements inside the deck, but base is merged in (e.g. improvement sitting
        -- coplanar on top outside the deck). Extract the base and let fixImprovementsOnBaseCard
        -- handle any coplanar/surface improvements around it.
        stackLog("fixImprovementsOnDeck: no improvements in deck, extracting base and delegating guid=" .. tostring(deckObj.getGUID()))
        local baseEntry = nil
        for _, entry in ipairs(plan) do
            if entry.isBase then baseEntry = entry; break end
        end
        if not baseEntry then
            broadcastToAll("Could not locate base card entry in deck.", "White")
            return
        end
        local liveDeck = getObjectFromGUID(deckObj.getGUID())
        if not liveDeck or liveDeck.type ~= "Deck" then
            broadcastToAll("Deck no longer present.", "White")
            return
        end
        pcall(function()
            liveDeck.takeObject({
                index = baseEntry.ttsIndex,
                position = {x = deckPos.x, y = deckPos.y + 0.4, z = deckPos.z},
                smooth = false,
                callback_function = function(card)
                    if not card then
                        broadcastToAll("Could not extract base card from deck.", "White")
                        return
                    end
                    applyTechCardRotation(card)
                    Wait.frames(function()
                        fixImprovementsOnBaseCard(card)
                    end, 4)
                end,
            })
        end)
        return
    end

    -- Take from topmost first to keep ttsIndex stable as the deck shrinks.
    table.sort(plan, function(a, b) return a.ttsIndex > b.ttsIndex end)

    stackLog("fixImprovementsOnDeck: deck=" .. tostring(deckObj.getGUID())
        .. " size=" .. tostring(#deckObjs)
        .. " extracting=" .. tostring(#plan)
        .. " (base=" .. tostring(baseCount) .. ", improvements=" .. tostring(improvementCount) .. ")")

    local extractedBase = nil
    local extractedImprovements = {}
    local stageX = deckPos.x + 2.2
    local stageZ = deckPos.z - 1.8

    local function placeExtractedCards()
        if not extractedBase then
            stackLog("fixImprovementsOnDeck: extraction finished but no base card object returned")
            broadcastToAll("Could not extract base card from deck.", "White")
            return
        end

        -- Place base first, then improvements underneath with strong anti-remerge spacing.
        local baseTarget = {x = deckPos.x, y = deckPos.y + 0.25, z = deckPos.z}
        pcall(function()
            extractedBase.setLock(true)
            extractedBase.setPosition(baseTarget)
            applyTechCardRotation(extractedBase)
        end)

        Wait.frames(function()
            if not extractedBase then return end
            local liveBasePos = safeGetPosition(extractedBase) or baseTarget
            local liveTuckedY = getTuckedImprovementY(liveBasePos.y)
            table.sort(extractedImprovements, function(a, b)
                return a.originalTableIndex < b.originalTableIndex
            end)

            for slot, info in ipairs(extractedImprovements) do
                local card = info.obj
                if card then
                    local targetZ = liveBasePos.z - (slot * STACK_LAYOUT_DZ)
                    local targetY = liveTuckedY - ((slot - 1) * STACK_IMPROVEMENT_LAYER_DY)
                    pcall(function()
                        card.setLock(true)
                        card.setPosition({x = liveBasePos.x, y = targetY, z = targetZ})
                        applyTechCardRotation(card)
                    end)
                    stackLog("fixImprovementsOnDeck: placed extracted improvement guid=" .. tostring(card.getGUID and card.getGUID() or "?")
                        .. " slot=" .. tostring(slot)
                        .. " y=" .. string.format("%.3f", targetY)
                        .. " z=" .. string.format("%.3f", targetZ))
                end
            end

            -- Verify after physics settles; unlock afterwards.
            Wait.frames(function()
                pcall(function()
                    extractedBase.setPosition({x = liveBasePos.x, y = liveBasePos.y, z = liveBasePos.z})
                    applyTechCardRotation(extractedBase)
                    extractedBase.setLock(false)
                end)
                for slot, info in ipairs(extractedImprovements) do
                    local card = info.obj
                    if card then
                        local targetZ = liveBasePos.z - (slot * STACK_LAYOUT_DZ)
                        local targetY = liveTuckedY - ((slot - 1) * STACK_IMPROVEMENT_LAYER_DY)
                        pcall(function()
                            card.setPosition({x = liveBasePos.x, y = targetY, z = targetZ})
                            applyTechCardRotation(card)
                            card.setLock(false)
                        end)
                    end
                end

                Wait.frames(function()
                    fixImprovementsOnBaseCard(extractedBase)
                end, 6)
            end, 12)
        end, 2)
    end

    local function extractPlanAt(planIdx)
        if planIdx > #plan then
            placeExtractedCards()
            return
        end

        local spec = plan[planIdx]
        local liveDeck = getObjectFromGUID(deckObj.getGUID())
        if not liveDeck or liveDeck.type ~= "Deck" then
            stackLog("fixImprovementsOnDeck: deck disappeared during extraction at step=" .. tostring(planIdx))
            placeExtractedCards()
            return
        end

        local stageY = deckPos.y + 2.2 + (planIdx * 0.25)
        local takePos = {x = stageX, y = stageY, z = stageZ}
        local okTake, errTake = pcall(function()
            liveDeck.takeObject({
                index = spec.ttsIndex,
                position = takePos,
                smooth = false,
                callback_function = function(card)
                    if card then
                        pcall(function() card.setPosition(takePos) end)
                        if spec.isBase then
                            extractedBase = card
                            stackLog("fixImprovementsOnDeck: extracted base guid=" .. tostring(card.getGUID and card.getGUID() or "?"))
                        elseif spec.isImprovement then
                            table.insert(extractedImprovements, {
                                obj = card,
                                originalTableIndex = spec.tableIndex,
                            })
                            stackLog("fixImprovementsOnDeck: extracted improvement guid=" .. tostring(card.getGUID and card.getGUID() or "?")
                                .. " from tableIndex=" .. tostring(spec.tableIndex))
                        end
                    else
                        stackLog("fixImprovementsOnDeck: takeObject callback returned nil at step=" .. tostring(planIdx))
                    end

                    Wait.frames(function()
                        extractPlanAt(planIdx + 1)
                    end, 2)
                end,
            })
        end)

        if not okTake then
            stackLog("fixImprovementsOnDeck: takeObject failed step=" .. tostring(planIdx) .. " err=" .. tostring(errTake))
            Wait.frames(function()
                extractPlanAt(planIdx + 1)
            end, 2)
        end
    end

    Wait.frames(function()
        extractPlanAt(1)
    end, 1)
end

-- Attach "Fix improvements" context menu to a base Card or to a Deck containing a base card.
-- Safe to call multiple times; TTS silently ignores duplicate identical menu items.
attachFixImprovementsMenus = function(obj)
    if not obj then return end
    local objType = safeGetType(obj)
    if objType == "Card" and safeHasTag(obj, "base") then
        obj.addContextMenuItem("Fix improvements", function(player_color)
            fixImprovementsOnBaseCard(obj)
        end)
    elseif objType == "Deck" then
        local deckGuid = safeGetGuid(obj)
        local isSystemDeck = (deckGuid == TECH_DECK_GUID
            or deckGuid == DEVELOPER_DECK_GUID
            or deckGuid == STARTER_DEVELOPER_DECK_GUID)
        local deckPos = safeGetPosition(obj)
        local isInDiscardZone = (deckPos and (posNearTechDiscardZone(deckPos) or posNearDevDiscardZone(deckPos)))
        if isSystemDeck or isInDiscardZone then return end
        local okObjs, deckObjs = pcall(function() return obj.getObjects() end)
        if not okObjs or type(deckObjs) ~= "table" or #deckObjs == 0 then return end
        local hasBase = false
        for _, d in ipairs(deckObjs) do
            if d and d.tags then
                for _, t in ipairs(d.tags) do
                    if t == "base" then hasBase = true; break end
                end
            end
            if hasBase then break end
        end
        if hasBase then
            obj.addContextMenuItem("Fix improvements", function(player_color)
                fixImprovementsOnDeck(obj)
            end)
        end
    end
end

local function hideReferencePanelsForPlayer(player_color)
    local function resolveUiPlayerColor(arg)
        if type(arg) == "string" then
            return normalizePlayerColorLabel(arg) or arg
        end
        if arg ~= nil then
            local okColor, raw = pcall(function()
                return arg.color or arg.player_color or arg.steam_color
            end)
            if okColor and raw then
                return normalizePlayerColorLabel(raw) or tostring(raw)
            end

            local asText = tostring(arg)
            local normalizedText = normalizePlayerColorLabel(asText)
            if normalizedText then
                return normalizedText
            end
        end
        return nil
    end

    local viewerColor = resolveUiPlayerColor(player_color)
    if not viewerColor or viewerColor == "" then return end

    local function removeViewerFromPanel(panelId, viewerColor)
        local okVis, visibility = pcall(function()
            return UI.getAttribute(panelId, "visibility")
        end)
        local current = {}
        local seen = {}
        if okVis and visibility and visibility ~= "" then
            for token in string.gmatch(visibility, "[^|]+") do
                local normalized = normalizePlayerColorLabel(token)
                if normalized and not seen[normalized] then
                    table.insert(current, normalized)
                    seen[normalized] = true
                end
            end
        end

        local wanted = normalizePlayerColorLabel(viewerColor)
        local filtered = {}
        for _, c in ipairs(current) do
            if c ~= wanted then
                table.insert(filtered, c)
            end
        end

        local nextVisibility = table.concat(filtered, "|")
        UI.setAttribute(panelId, "visibility", nextVisibility)
        UI.setAttribute(panelId, "active", (#filtered > 0) and "true" or "false")
    end

    removeViewerFromPanel(REFERENCE_ROUND_PANEL_ID, viewerColor)
    removeViewerFromPanel(REFERENCE_CARD_ICON_PANEL_ID, viewerColor)
end

local function forceHideAllReferencePanels()
    UI.setAttribute(REFERENCE_ROUND_PANEL_ID, "visibility", "")
    UI.setAttribute(REFERENCE_ROUND_PANEL_ID, "active", "false")
    UI.setAttribute(REFERENCE_CARD_ICON_PANEL_ID, "visibility", "")
    UI.setAttribute(REFERENCE_CARD_ICON_PANEL_ID, "active", "false")
end

local function showReferencePanelForPlayer(panelId, player_color)
    if not player_color then return end
    hideReferencePanelsForPlayer(player_color)

    local okVis, visibility = pcall(function()
        return UI.getAttribute(panelId, "visibility")
    end)
    local merged = {}
    local seen = {}

    if okVis and visibility and visibility ~= "" then
        for token in string.gmatch(visibility, "[^|]+") do
            local normalized = normalizePlayerColorLabel(token)
            if normalized and not seen[normalized] then
                table.insert(merged, normalized)
                seen[normalized] = true
            end
        end
    end

    local wanted = normalizePlayerColorLabel(player_color) or player_color
    if wanted and wanted ~= "" and not seen[wanted] then
        table.insert(merged, wanted)
    end

    UI.setAttribute(panelId, "visibility", table.concat(merged, "|"))
    UI.setAttribute(panelId, "active", "true")
end

function showRoundGuideReference(player_color)
    showReferencePanelForPlayer(REFERENCE_ROUND_PANEL_ID, player_color)
end

function showCardIconReference(player_color)
    showReferencePanelForPlayer(REFERENCE_CARD_ICON_PANEL_ID, player_color)
end

function hideReferencePanel(player, value, id)
    local okColor, resolved = pcall(function()
        if type(player) == "string" then
            return normalizePlayerColorLabel(player) or player
        end
        if player ~= nil then
            local raw = player.color or player.player_color or player.steam_color
            if raw then
                return normalizePlayerColorLabel(raw) or tostring(raw)
            end
        end
        return nil
    end)

    if okColor and resolved and resolved ~= "" then
        hideReferencePanelsForPlayer(resolved)
    else
        -- Fallback: avoid a stuck full-screen overlay if callback player identity is missing.
        forceHideAllReferencePanels()
    end
end

local function buildReferencePanelsXml()
    return [[
<Panel id="ref_root" active="true" width="100%" height="100%" color="#00000000" allowDragging="false" returnToOriginalPositionWhenReleased="false">
    <Panel id="ref_panel_round_guide" active="false" width="100%" height="100%" color="#000000AA" allowDragging="false" returnToOriginalPositionWhenReleased="false">
        <Button id="ref_backdrop_round_close" text="" onClick="hideReferencePanel" width="100%" height="100%" rectAlignment="MiddleCenter" offsetXY="0 0" colors="#00000000|#00000000|#00000000|#00000000" />
        <Panel width="1700" height="980" rectAlignment="MiddleCenter" color="#101010F0" outline="#FFFFFF33" outlineSize="2 2">
            <Text text="Round Guide" fontSize="44" color="#F2F2F2" alignment="UpperCenter" rectAlignment="UpperCenter" offsetXY="0 -20" />
            <Image image="ref_round_guide_image" preserveAspect="true" width="1600" height="860" rectAlignment="MiddleCenter" offsetXY="0 -20" />
        </Panel>
    </Panel>

    <Panel id="ref_panel_card_icon" active="false" width="100%" height="100%" color="#000000AA" allowDragging="false" returnToOriginalPositionWhenReleased="false">
        <Button id="ref_backdrop_card_icon_close" text="" onClick="hideReferencePanel" width="100%" height="100%" rectAlignment="MiddleCenter" offsetXY="0 0" colors="#00000000|#00000000|#00000000|#00000000" />
        <Panel width="1700" height="980" rectAlignment="MiddleCenter" color="#101010F0" outline="#FFFFFF33" outlineSize="2 2">
            <Text text="Card + Icon Reference" fontSize="44" color="#F2F2F2" alignment="UpperCenter" rectAlignment="UpperCenter" offsetXY="0 -20" />
            <Image image="ref_card_icon_image" preserveAspect="true" width="1600" height="860" rectAlignment="MiddleCenter" offsetXY="0 -20" />
        </Panel>
    </Panel>

    <Panel id="pass_hud_panel" active="true" width="198" height="132" rectAlignment="LowerRight" offsetXY="-20 70" color="#00000066" outline="#FFFFFF22" outlineSize="1 1" allowDragging="false" returnToOriginalPositionWhenReleased="false">
        <Text id="pass_hud_line_1" text="" fontSize="16" color="#FFFFFF" alignment="UpperRight" rectAlignment="UpperRight" offsetXY="-8 -10" />
        <Text id="pass_hud_line_2" text="" fontSize="16" color="#FFFFFF" alignment="UpperRight" rectAlignment="UpperRight" offsetXY="-8 -38" />
        <Text id="pass_hud_line_3" text="" fontSize="16" color="#FFFFFF" alignment="UpperRight" rectAlignment="UpperRight" offsetXY="-8 -66" />
        <Text id="pass_hud_line_4" text="" fontSize="16" color="#FFFFFF" alignment="UpperRight" rectAlignment="UpperRight" offsetXY="-8 -94" />
    </Panel>
</Panel>
]]
end

function initializeReferenceSystem()
    local okPanels, errPanels = pcall(function()
        setupReferencePanels()
    end)
    if not okPanels then
        debugPrint("⚠️ Reference panel setup failed: " .. tostring(errPanels))
    end

    local okMenu, errMenu = pcall(function()
        attachReferenceMenu()
    end)
    if not okMenu then
        debugPrint("⚠️ Reference menu setup failed: " .. tostring(errMenu))
    end
end

function setupReferencePanels()
    if not UI then
        debugPrint("⚠️ UI API unavailable; reference panels disabled")
        return
    end
    if not UI.getCustomAssets or not UI.setCustomAssets or not UI.getXml or not UI.setXml then
        debugPrint("⚠️ UI API incomplete; reference panels disabled")
        return
    end

    local customAssets = UI.getCustomAssets() or {}
    local assetByName = {}

    for _, asset in ipairs(customAssets) do
        if asset and asset.name then
            assetByName[asset.name] = true
        end
    end

    if not assetByName["ref_round_guide_image"] then
        table.insert(customAssets, {
            name = "ref_round_guide_image",
            url  = REFERENCE_ROUND_GUIDE_URL,
        })
    end
    if not assetByName["ref_card_icon_image"] then
        table.insert(customAssets, {
            name = "ref_card_icon_image",
            url  = REFERENCE_CARD_ICON_URL,
        })
    end
    UI.setCustomAssets(customAssets)

    local currentXml = UI.getXml() or ""
    if string.find(currentXml, REFERENCE_ROUND_PANEL_ID, 1, true)
        and string.find(currentXml, REFERENCE_CARD_ICON_PANEL_ID, 1, true)
        and string.find(currentXml, PASS_HUD_PANEL_ID, 1, true) then
        return
    end

    local referenceXml = buildReferencePanelsXml()
    UI.setXml(referenceXml)
end

function attachReferenceMenu()
    if REFERENCE_MENU_ATTACHED then return end

    local mat = getObjectFromGUID(STACK_MAT_GUID)
    if not mat then
        debugPrint("⚠️ Reference menu: stack mat not found (GUID " .. tostring(STACK_MAT_GUID) .. "), will retry next frame")
        Wait.frames(function() attachReferenceMenu() end, 60)
        return
    end

    mat.addContextMenuItem("Round Guide", function(player_color)
        showRoundGuideReference(player_color)
    end)
    mat.addContextMenuItem("Card + Icon Reference", function(player_color)
        showCardIconReference(player_color)
    end)

    mat.addContextMenuItem("Pass", function(player_color)
        local p = getPlayerByColorSafe(player_color)
        onChat("pass", p)
    end)
    mat.addContextMenuItem("Unpass", function(player_color)
        local p = getPlayerByColorSafe(player_color)
        onChat("unpass", p)
    end)
    mat.addContextMenuItem("Pass reset", function(player_color)
        local p = getPlayerByColorSafe(player_color)
        onChat("pass reset", p)
    end)
    mat.addContextMenuItem("────────", function(player_color)
        -- Visual divider before camera view options.
    end)

    REFERENCE_MENU_ATTACHED = true
    debugPrint("✅ Reference menu attached to stack mat")
end

function attachCameraPresetMenu()
    if CAMERA_MENU_ATTACHED then return end

    local mat = getObjectFromGUID(STACK_MAT_GUID)
    if not mat then
        debugPrint("⚠️ Camera menu: stack mat not found (GUID " .. tostring(STACK_MAT_GUID) .. "), will retry next frame")
        Wait.frames(function() attachCameraPresetMenu() end, 60)
        return
    end

    mat.addContextMenuItem("View: Board 1 (South)", function(player_color)
        focusCameraPreset(player_color, "1")
    end)
    mat.addContextMenuItem("View: Board 2 (West)", function(player_color)
        focusCameraPreset(player_color, "2")
    end)
    mat.addContextMenuItem("View: Board 3 (North)", function(player_color)
        focusCameraPreset(player_color, "3")
    end)
    mat.addContextMenuItem("View: Board 4 (East)", function(player_color)
        focusCameraPreset(player_color, "4")
    end)
    mat.addContextMenuItem("View: Market", function(player_color)
        focusCameraPreset(player_color, "market")
    end)
    mat.addContextMenuItem("View: Stack", function(player_color)
        focusCameraPreset(player_color, "stack")
    end)

    attachMarkerSpawnMenu()

    CAMERA_MENU_ATTACHED = true
    debugPrint("✅ Camera menu attached to stack mat")
end

function attachSnapPatternMenusToTechObjects()
    for _, obj in ipairs(getAllObjects()) do
        if isSnapPatternEligible(obj) then
            attachSnapPatternMenus(obj)
        end
    end
end

function attachSnapPatternMenus(obj)
    if not EDIT_MODE then return end

    for _, patternName in ipairs(SNAP_PATTERN_ORDER) do
        obj.addContextMenuItem("Apply snap: " .. patternName, function(player_color)
            applyPatternToSelectionOrHost(player_color, obj, patternName)
        end)
    end

    obj.addContextMenuItem("Apply snap: owner", function(player_color)
        applyPatternToSelectionOrHost(player_color, obj, "owner")
    end)
end

function applyPatternToSelectionOrHost(player_color, hostObj, patternName)
    local selected = Player[player_color].getSelectedObjects()
    if #selected == 0 then
        applyPatternToObjects(player_color, {hostObj}, patternName)
    else
        applyPatternToObjects(player_color, selected, patternName)
    end
end

local function isOwnerSnapEligibleTags(tags)
    local hasProject = false
    local hasImprovement = false

    for _, tag in ipairs(tags or {}) do
        if tag == "project" then
            hasProject = true
        elseif tag == "improvement" then
            hasImprovement = true
        end
    end

    return hasProject and not hasImprovement
end

local function isOwnerSnapEligibleCount(snapCount)
    return snapCount ~= 1 and snapCount ~= 2 and snapCount ~= 4 and snapCount ~= 5 and snapCount ~= 7
end

local function getContainedCardTags(cardData)
    return (cardData and (cardData.Tags or cardData.tags)) or {}
end

local function getContainedCardSnapPoints(cardData)
    return (cardData and (cardData.AttachedSnapPoints or cardData.attachedSnapPoints)) or {}
end

local function setContainedCardSnapPoints(cardData, snapPoints)
    if not cardData then return end
    cardData.AttachedSnapPoints = snapPoints
    cardData.attachedSnapPoints = nil
end

local function getOwnerTemplateSnapPoint()
    local templatePoint = JSON.decode(JSON.encode(OWNER_SNAP_POINT))
    local pos = templatePoint.position or {}
    print(string.format(
        "[OWNER SNAP TEMPLATE] source=script local_position={x=%.5f, y=%.5f, z=%.5f}",
        tonumber(pos.x or pos[1]) or 0,
        tonumber(pos.y or pos[2]) or 0,
        tonumber(pos.z or pos[3]) or 0
    ))

    return templatePoint, nil
end

local function appendOwnerSnapPointToCard(cardObj, templatePoint)
    if not cardObj or cardObj.type ~= "Card" then return false, false end
    if not cardObj.hasTag or not cardObj.hasTag("project") or cardObj.hasTag("improvement") then
        return false, false
    end

    local existing = cardObj.getSnapPoints() or {}
    if not isOwnerSnapEligibleCount(#existing) then
        return false, false
    end

    local merged = JSON.decode(JSON.encode(existing))
    table.insert(merged, JSON.decode(JSON.encode(templatePoint)))
    cardObj.setSnapPoints(merged)
    return true, true 
end

local function appendOwnerSnapPointToDeck(deck, templatePoint)
    local data = JSON.decode(deck.getJSON())
    if not data or not data.ContainedObjects then return false, 0, 0 end

    local changed = false
    local updated = 0
    local skipped = 0

    for _, card in ipairs(data.ContainedObjects) do
        local existing = getContainedCardSnapPoints(card)
        if isOwnerSnapEligibleTags(getContainedCardTags(card)) and isOwnerSnapEligibleCount(#existing) then
            local merged = JSON.decode(JSON.encode(existing))
            table.insert(merged, JSON.decode(JSON.encode(templatePoint)))
            setContainedCardSnapPoints(card, merged)
            changed = true
            updated = updated + 1
        else
            skipped = skipped + 1
        end
    end

    if not changed then
        return false, updated, skipped
    end

    local pos = deck.getPosition()
    local rot = deck.getRotation()

    deck.destruct()
    Wait.frames(function()
        spawnObjectJSON({
            json = JSON.encode(data),
            position = pos,
            rotation = rot
        })
    end, 1)

    return true, updated, skipped
end

function getPatternSnapPoints(patternName)
    local combo = SNAP_PATTERN_COMBINATIONS[patternName]
    if combo then
        local merged = {}

        for _, childPattern in ipairs(combo) do
            local childPoints, err = getPatternSnapPoints(childPattern)
            if not childPoints then
                return nil, err
            end

            for _, point in ipairs(childPoints) do
                table.insert(merged, JSON.decode(JSON.encode(point)))
            end
        end

        return merged, nil
    end

    local guid = SNAP_PATTERN_GUIDS[patternName]
    if not guid or guid == "" then
        return nil, "No GUID set for pattern: " .. patternName
    end

    local ref = getObjectFromGUID(guid)
    if not ref then
        return nil, "Could not find reference object for pattern: " .. patternName
    end

    local snapPoints = ref.getSnapPoints()
    if not snapPoints or #snapPoints == 0 then
        return nil, "Reference object has no snap points: " .. patternName
    end

    return JSON.decode(JSON.encode(snapPoints)), nil
end

function applyPatternToObjects(player_color, objects, patternName)
    if patternName == "owner" then
        local templatePoint, err = getOwnerTemplateSnapPoint()
        if not templatePoint then
            debugBroadcastToColor(err, player_color)
            return
        end

        local cardsUpdated = 0
        local decksUpdated = 0
        local deckCardsUpdated = 0
        local skipped = 0

        for _, obj in ipairs(objects) do
            if obj and obj.type == "Card" then
                local changed, eligible = appendOwnerSnapPointToCard(obj, templatePoint)
                if changed then
                    cardsUpdated = cardsUpdated + 1
                elseif not eligible then
                    skipped = skipped + 1
                end
            elseif obj and obj.type == "Deck" then
                local changed, updatedInDeck, skippedInDeck = appendOwnerSnapPointToDeck(obj, templatePoint)
                if changed then
                    decksUpdated = decksUpdated + 1
                end
                deckCardsUpdated = deckCardsUpdated + updatedInDeck
                skipped = skipped + skippedInDeck
            else
                skipped = skipped + 1
            end
        end

        debugBroadcastToColor(
            "Applied 'owner': cards=" .. tostring(cardsUpdated)
                .. ", deck_cards=" .. tostring(deckCardsUpdated)
                .. ", decks=" .. tostring(decksUpdated)
                .. ", skipped=" .. tostring(skipped),
            player_color
        )
        return
    end

    local snapPoints, err = getPatternSnapPoints(patternName)
    if not snapPoints then
        debugBroadcastToColor(err, player_color)
        return
    end

    local cardsUpdated = 0
    local decksUpdated = 0
    local skipped = 0

    for _, obj in ipairs(objects) do
        if obj and obj.type == "Card" then
            obj.setSnapPoints(snapPoints)
            cardsUpdated = cardsUpdated + 1
        elseif obj and obj.type == "Deck" then
            local ok = applyPatternToDeck(obj, snapPoints)
            if ok then
                decksUpdated = decksUpdated + 1
            else
                skipped = skipped + 1
            end
        else
            skipped = skipped + 1
        end
    end

    debugBroadcastToColor(
        "Applied '" .. patternName .. "': cards=" .. cardsUpdated .. ", decks=" .. decksUpdated .. ", skipped=" .. skipped,
        player_color
    )
end

function applyPatternToDeck(deck, snapPoints)
    local data = JSON.decode(deck.getJSON())
    if not data or not data.ContainedObjects then return false end

    for _, card in ipairs(data.ContainedObjects) do
        card.AttachedSnapPoints = JSON.decode(JSON.encode(snapPoints))
    end

    local pos = deck.getPosition()
    local rot = deck.getRotation()

    deck.destruct()
    Wait.frames(function()
        spawnObjectJSON({
            json = JSON.encode(data),
            position = pos,
            rotation = rot
        })
    end, 1)

    return true
end

-- Attaches "Add dev snaps left/right" context menu items to a developer card
-- when in EDIT_MODE. Safe to call multiple times (TTS deduplicates menu items).
function attachDevSnapMenus(obj)
    if not EDIT_MODE then return end
    if not obj or obj.type ~= "Card" then return end
    if not obj.hasTag or not obj.hasTag("developer") then return end

    obj.addContextMenuItem("Add dev snaps left", function(player_color)
        addDevSnapsInDirection(obj, -1, player_color)
    end)
    obj.addContextMenuItem("Add dev snaps right", function(player_color)
        addDevSnapsInDirection(obj, 1, player_color)
    end)
end

-- Scans all objects and attaches dev snap menus to every developer card.
function attachDevSnapMenusToDevObjects()
    for _, obj in ipairs(getAllObjects()) do
        if obj and obj.type == "Card" and obj.hasTag and obj.hasTag("developer") then
            attachDevSnapMenus(obj)
        end
    end
end

function tagDeck(deck, tagString)
    local tags = {}
    debugPrint("Tagging deck with " .. tagString)

    for tag in tagString:gmatch("%S+") do
        table.insert(tags, tag)
    end

    local data = JSON.decode(deck.getJSON())
    for _, obj in ipairs(data.ContainedObjects) do
        obj.Tags = tags
    end

    local pos = deck.getPosition()
    local rot = deck.getRotation()

    deck.destruct()

    Wait.frames(function()
        spawnObjectJSON({
            json = JSON.encode(data),
            position = pos,
            rotation = rot
        })
    end, 10)

    debugPrint("done tagging deck")
end

-- ---------------------------------------------------------------------------
-- Developer card snap-point utilities
-- ---------------------------------------------------------------------------
-- Returns the card's local +X (right) direction projected onto the table (XZ).
local function getCardRightVectorXZ(cardObj)
    local c = cardObj.getPosition()
    local p = cardObj.positionToWorld({x = 1, y = 0, z = 0})
    local dx = p.x - c.x
    local dz = p.z - c.z
    local len = math.sqrt(dx * dx + dz * dz)

    if len < 0.0001 then
        return {x = 1, z = 0}
    end

    return {x = dx / len, z = dz / len}
end

-- Returns a snap-point rotation that matches cardObj's facing, converted into
-- the mat's local rotation space (snap point rotations are local to the host).
local function getCardSnapRotationOnMat(cardObj, matObj)
    local cardRot = cardObj.getRotation()
    local matRot = matObj.getRotation()
    return {
        x = 0,
        y = (cardRot.y - matRot.y),
        z = 0,
    }
end

-- Creates 13 evenly-spaced snap points on the stack mat starting at the
-- centre of cardObj and stepping DEV_SNAP_DX units in `direction` (+1 right,
-- -1 left). Existing snap points on the mat are preserved.
function addDevSnapsInDirection(cardObj, direction, player_color)
    if not cardObj then return end

    local mat = getObjectFromGUID(STACK_MAT_GUID)
    if not mat then
        debugBroadcastToColor("Stack mat not found (GUID: " .. tostring(STACK_MAT_GUID) .. "),",
            player_color or "White")
        return
    end

    local cardPos = cardObj.getPosition()
    local rightVec = getCardRightVectorXZ(cardObj)
    local snapRot = getCardSnapRotationOnMat(cardObj, mat)
    local existing = mat.getSnapPoints() or {}
    local added = {}

    for i = 0, 12 do
        local step = direction * i * DEV_SNAP_DX
        local worldPos = {
            x = cardPos.x + (rightVec.x * step),
            y = cardPos.y,
            z = cardPos.z + (rightVec.z * step)
        }
        local localPos = mat.positionToLocal(worldPos)
        table.insert(added, {
            position      = localPos,
            rotation      = snapRot,
            rotation_snap = true,
            tags          = {"developer"},
        })
    end

    local merged = {}
    for _, p in ipairs(existing) do
        table.insert(merged, JSON.decode(JSON.encode(p)))
    end
    for _, p in ipairs(added) do
        table.insert(merged, p)
    end

    mat.setSnapPoints(merged)

    local dirLabel = direction > 0 and "right" or "left"
    debugBroadcastToColor("Added " .. #added .. " dev snap points " .. dirLabel,
        player_color or "White")
end

function addDevSnapsLeft(cardObj, player_color)
    addDevSnapsInDirection(cardObj, -1, player_color)
end

function addDevSnapsRight(cardObj, player_color)
    addDevSnapsInDirection(cardObj, 1, player_color)
end

local function syncBoardSnapPointsFromSource(sourceGuid, player_color)
    local srcGuid = tostring(sourceGuid or "")
    if srcGuid == "" then
        debugBroadcastToColor("Source GUID is required for board snap sync", player_color or "White")
        return false
    end

    local srcObj = getObjectFromGUID(srcGuid)
    if not srcObj then
        debugBroadcastToColor("Source board not found: " .. srcGuid, player_color or "White")
        return false
    end

    local srcSnapPoints = srcObj.getSnapPoints() or {}
    local updated = 0
    local skipped = 0
    local missing = 0
    local seen = {}

    for _, boardSpec in pairs(BOARD_CAMERA_BY_PRESET) do
        local guid = boardSpec and boardSpec.guid or nil
        if guid and not seen[guid] then
            seen[guid] = true

            if guid == srcGuid then
                skipped = skipped + 1
            else
                local boardObj = getObjectFromGUID(guid)
                if boardObj and boardObj.setSnapPoints then
                    boardObj.setSnapPoints(JSON.decode(JSON.encode(srcSnapPoints)))
                    updated = updated + 1
                else
                    missing = missing + 1
                    debugPrint("[BOARD] snap sync target missing or unsupported guid=" .. tostring(guid))
                end
            end
        end
    end

    debugBroadcastToColor(
        "Board snap sync complete from " .. srcGuid .. ": updated=" .. tostring(updated) .. ", skipped=" .. tostring(skipped) .. ", missing=" .. tostring(missing),
        player_color or "White"
    )

    return true
end

function applyBoardSnapPointsFromBoard1(player_color)
    if not EDIT_MODE then
        broadcastToColor("Enable EDIT_MODE before syncing board snap points", player_color or "White")
        return
    end

    syncBoardSnapPointsFromSource("7f0dd5", player_color)
end

function attachBoardSnapSyncMenus()
    for _, boardSpec in pairs(BOARD_CAMERA_BY_PRESET) do
        local guid = boardSpec and boardSpec.guid or nil
        if guid and not BOARD_SNAP_MENU_ATTACHED_BY_GUID[guid] then
            local boardObj = getObjectFromGUID(guid)
            if boardObj then
                boardObj.addContextMenuItem("Sync board snaps from source (7f0dd5)", function(player_color)
                    applyBoardSnapPointsFromBoard1(player_color)
                end)
                BOARD_SNAP_MENU_ATTACHED_BY_GUID[guid] = true
            end
        end
    end
end

