-- selab_dashboard — Luanti/Minetest Infrastructure Dashboard
-- Wall layout: sections = columns (X axis), checks stacked vertically (Y axis)
-- Player stands south of wall looking north.
-- Green = pass, Red = fail, Yellow = skip, Grey = unknown
--
-- minetest.conf: secure.http_mods = selab_dashboard
-- Commands: /dashboard build | rebuild | refresh | clear | info

local MODNAME       = minetest.get_current_modname()
local ENDPOINT      = "http://192.168.122.1:8080/api/status"
local POLL_INTERVAL = 30

-- Wall layout constants
local SEC_STRIDE   = 4   -- X blocks between section columns
local CHECK_HEIGHT = 2   -- Y blocks per check row (block + gap)
local WALL_Z       = 0   -- relative Z of the wall face
local VIEW_DIST    = 10  -- how far south the player stands

local dash = { origin = nil, positions = {}, polling = false }

local http = minetest.request_http_api()

local function trunc(s, n)
    s = tostring(s or "")
    return #s <= n and s or s:sub(1,n-2)..".."
end

local function set_info(pos, text)
    minetest.get_meta(pos):set_string("infotext", text)
end

local function status_node(s)
    if s == "pass" then return "wool:green"
    elseif s == "fail" then return "wool:red"
    elseif s == "skip" then return "wool:yellow"
    else return "wool:grey" end
end

local function place_sign(pos, text)
    -- param2=3: sign faces -Z (north), readable by player standing south of wall
    minetest.set_node(pos, {name="default:sign_wall_wood", param2=3})
    local m = minetest.get_meta(pos)
    m:set_string("text", text)
    m:set_string("infotext", text)
end

local function burst(pos, pass)
    minetest.add_particlespawner({
        amount=12, time=0.6,
        minpos={x=pos.x-.4,y=pos.y+.5,z=pos.z-.4},
        maxpos={x=pos.x+.4,y=pos.y+.5,z=pos.z+.4},
        minvel={x=-.3,y=.8,z=-.3}, maxvel={x=.3,y=1.5,z=.3},
        minacc={x=0,y=-2,z=0}, maxacc={x=0,y=-2,z=0},
        minexptime=0.4, maxexptime=0.9,
        minsize=2, maxsize=4, glow=pass and 10 or 0,
    })
end

local function build_dashboard(data)
    local o = dash.origin
    dash.positions = {}

    local n_sec = #data.sections
    local max_chk = 0
    for _, s in ipairs(data.sections) do
        if #s.checks > max_chk then max_chk = #s.checks end
    end

    -- Wall dimensions
    local wall_w = n_sec * SEC_STRIDE + 2
    local wall_h = max_chk * CHECK_HEIGHT + 4  -- +4 for header + roof

    --  Clear area 
    for dz = -VIEW_DIST - 1, 3 do
        for dx = -2, wall_w + 1 do
            -- Floor
            minetest.set_node({x=o.x+dx, y=o.y-1, z=o.z+dz},
                {name="default:stone_block"})
            -- Air above
            for dy = 0, wall_h + 2 do
                minetest.set_node({x=o.x+dx, y=o.y+dy, z=o.z+dz},
                    {name="air"})
            end
        end
    end

    --  Stone wall background 
    for dx = -1, wall_w do
        for dy = 0, wall_h do
            minetest.set_node({x=o.x+dx, y=o.y+dy, z=o.z},
                {name="default:stone"})
        end
    end

    --  Roof with meselamp lighting strip 
    for dx = -1, wall_w do
        minetest.set_node({x=o.x+dx, y=o.y+wall_h+1, z=o.z},
            {name="default:stone_block"})
        -- Meselamp every 3 blocks for lighting
        if dx % 3 == 0 then
            minetest.set_node({x=o.x+dx, y=o.y+wall_h, z=o.z-1},
                {name="default:meselamp"})
        end
    end

    --  Summary sign 
    local spos = {x=o.x-1, y=o.y+wall_h-1, z=o.z}
    minetest.set_node(spos, {name="default:mese"})
    set_info(spos, string.format(
        "SELab Dashboard\n%d/%d pass | %d fail",
        data.passed, data.total, data.failed))
    place_sign({x=o.x-1, y=o.y+wall_h-1, z=o.z-1},
        string.format("SELab\n%d/%d pass", data.passed, data.total))

    --  Sections 
    for s_idx, section in ipairs(data.sections) do
        local x = (s_idx - 1) * SEC_STRIDE

        -- Section header: meselamp at top of column
        local hy = o.y + max_chk * CHECK_HEIGHT + 1
        local hpos = {x=o.x+x, y=hy, z=o.z}
        minetest.set_node(hpos, {name="default:meselamp"})
        set_info(hpos, section.name .. " [" .. section.status:upper() .. "]")

        -- Section name sign (in front of wall, 2 lines: name + status)
        place_sign({x=o.x+x, y=hy, z=o.z-1},
            trunc(section.name, 12) .. "\n" .. section.status:upper())

        --  Check blocks 
        for c_idx, check in ipairs(section.checks) do
            local y = o.y + (c_idx - 1) * CHECK_HEIGHT
            local pos = {x=o.x+x, y=y, z=o.z}

            -- Wool block (replaces stone in wall)
            minetest.set_node(pos, {name=status_node(check.status)})
            -- Second block above for 2-tall columns = more visible
            minetest.set_node({x=o.x+x, y=y+1, z=o.z},
                {name=status_node(check.status)})

            set_info(pos, string.format(
                "[%s] %s\n%s port %s  %dms",
                check.status:upper(), check.name,
                check.protocol or "?", check.port or "?",
                check.duration_ms or 0))

            -- Check name sign in front of block
            place_sign({x=o.x+x, y=y, z=o.z-1},
                trunc(check.name, 14))

            dash.positions[section.id.."."..check.id] =
                {x=o.x+x, y=y, z=o.z}
        end
    end

    minetest.log("action", string.format(
        "[%s] Wall built — %d sections, %d/%d pass",
        MODNAME, n_sec, data.passed, data.total))
end

local function update_dashboard(data)
    if not dash.origin then return end
    for _, section in ipairs(data.sections) do
        for _, check in ipairs(section.checks) do
            local key = section.id.."."..check.id
            local pos = dash.positions[key]
            if pos then
                local new = status_node(check.status)
                if minetest.get_node(pos).name ~= new then
                    minetest.set_node(pos, {name=new})
                    minetest.set_node({x=pos.x,y=pos.y+1,z=pos.z},{name=new})
                    burst(pos, check.status=="pass")
                    local c = check.status=="pass" and "\27(c@#44FF44)" or "\27(c@#FF4444)"
                    minetest.chat_send_all(string.format(
                        "%s[SELab] %s → %s\27(c@#FFFFFF)",
                        c, check.name, check.status:upper()))
                end
                set_info(pos, string.format("[%s] %s\n%s port %s %dms",
                    check.status:upper(), check.name,
                    check.protocol or "?", check.port or "?",
                    check.duration_ms or 0))
            end
        end
    end
end

local function fetch_and_update(rebuild)
    if not http then
        minetest.log("error", "["..MODNAME.."] HTTP API unavailable — add to secure.http_mods")
        return
    end
    http.fetch({url=ENDPOINT, method="GET", timeout=10}, function(res)
        if not res.succeeded then
            minetest.log("error", string.format("[%s] HTTP error (code %d)", MODNAME, res.code))
            return
        end
        local ok, data = pcall(minetest.parse_json, res.data)
        if not ok or not data or not data.sections then
            minetest.log("error", "["..MODNAME.."] JSON parse failed")
            return
        end
        minetest.after(0, function()
            if rebuild or next(dash.positions) == nil then
                build_dashboard(data)
            else
                update_dashboard(data)
            end
        end)
    end)
end

local function start_polling()
    if dash.polling then return end
    dash.polling = true
    local function loop()
        if not dash.polling then return end
        if dash.origin then fetch_and_update(false) end
        minetest.after(POLL_INTERVAL, loop)
    end
    minetest.after(POLL_INTERVAL, loop)
end

minetest.register_chatcommand("dashboard", {
    params = "<build|rebuild|refresh|clear|info>",
    description = "SELab infra dashboard",
    privs = {interact=true},
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found" end
        param = param:match("^%s*(.-)%s*$")

        if param == "build" or param == "" then
            if not http then
                return false, "HTTP API unavailable — add '"..MODNAME.."' to secure.http_mods"
            end
            local pos = player:get_pos()
            -- Wall is placed in front of player (+Z), player views from -Z side
            dash.origin = {
                x = math.floor(pos.x) - 2,
                y = math.floor(pos.y),
                z = math.floor(pos.z) + VIEW_DIST,
            }

            -- Set spawn point in front of wall, facing wall
            local spawn_x = dash.origin.x + 16  -- center of 11-section wall
            local spawn_y = dash.origin.y + 1
            local spawn_z = dash.origin.z - VIEW_DIST + 1
            minetest.setting_set("static_spawnpoint",
                spawn_x..","..spawn_y..","..spawn_z)

            -- Teleport player to viewing position
            player:set_pos({x=spawn_x, y=spawn_y, z=spawn_z})

            -- Set daytime
            minetest.set_timeofday(0.5)

            minetest.chat_send_player(name,
                "[Dashboard] Fetching "..ENDPOINT.." ...")
            fetch_and_update(true)
            start_polling()
            return true, "Building wall dashboard. Spawn point set. Auto-refresh every "..POLL_INTERVAL.."s."

        elseif param == "refresh" then
            if not dash.origin then return false, "Run /dashboard build first" end
            fetch_and_update(false)
            return true, "Refreshing..."

        elseif param == "rebuild" then
            if not dash.origin then return false, "Run /dashboard build first" end
            fetch_and_update(true)
            return true, "Rebuilding..."

        elseif param == "clear" then
            dash.polling = false
            dash.origin = nil
            dash.positions = {}
            return true, "Stopped."

        elseif param == "info" then
            if not dash.origin then return true, "No active dashboard." end
            local n = 0
            for _ in pairs(dash.positions) do n = n + 1 end
            return true, string.format("Origin:%s | Checks:%d | Endpoint:%s",
                minetest.pos_to_string(dash.origin), n, ENDPOINT)

        else
            return false, "Usage: /dashboard <build|rebuild|refresh|clear|info>"
        end
    end
})

minetest.log("action", "["..MODNAME.."] loaded.")