-- selab_dashboard — Luanti/Minetest opdracht6 Dashboard
-- Wall layout: sections = columns (X axis), checks stacked vertically (Y axis)
-- Player stands south of wall looking north.
-- Green = pass, Red = fail, Yellow = skip, Grey = unknown
--
-- minetest.conf: secure.http_mods = selab_dashboard
-- Commands: /dashboard build | rebuild | refresh | clear | info

local MODNAME       = minetest.get_current_modname()
local ENDPOINT      = "http://192.168.122.1:8080/api/status"
local RUN_BASE      = "http://192.168.122.1:8080/api/run"
local POLL_INTERVAL = 30

local SEC_STRIDE   = 4
local CHECK_HEIGHT = 2
local VIEW_DIST    = 10

local dash = { origin = nil, positions = {}, polling = false }
local http = minetest.request_http_api()

--  Helpers 
local function trunc(s, n)
    s = tostring(s or "")
    return #s <= n and s or s:sub(1,n-2)..".."
end

local function set_info(pos, text)
    minetest.get_meta(pos):set_string("infotext", text)
end

local function status_node(s)
    if s == "pass"  then return "wool:green"
    elseif s == "fail"  then return "wool:red"
    elseif s == "skip"  then return "wool:yellow"
    else                     return "wool:grey" end
end

local function place_sign(pos, text)
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

--  Forward declarations 
local fetch_and_update   -- defined later, referenced by run_lever

--  Lever node 
-- Looks like a wall-mounted lever. Left-click OR right-click triggers run.
-- Stores run_url and label in metadata.

minetest.register_node("selab_dashboard:lever", {
    description = "SELab Run Lever",
    tiles = {
        "default_cobble.png",
        "default_cobble.png",
        "default_cobble.png",
        "default_cobble.png",
        "default_cobble.png",
        "default_cobble.png",
    },
    drawtype = "nodebox",
    paramtype = "light",
    node_box = {
        type = "fixed",
        fixed = {
            {-0.2, -0.4, -0.1,  0.2,  0.4,  0.1},   -- cobble base
            {-0.04,-0.28,-0.28, 0.04, 0.22, -0.1},   -- wood stick (toward player)
            {-0.09, 0.14,-0.26, 0.09, 0.30, -0.08},  -- wood knob
        },
    },
    groups = {not_in_creative_inventory=1},
    can_dig      = function() return false end,
    on_rightclick = function(pos, node, clicker)
        if not clicker then return end
        local m    = minetest.get_meta(pos)
        local url  = m:get_string("run_url")
        local lbl  = m:get_string("label")
        if url == "" then return end
        local name = clicker:get_player_name()
        minetest.chat_send_player(name, "[SELab] ► Running: " .. lbl)
        if not http then
            minetest.chat_send_player(name, "[SELab] ERROR: HTTP API not available")
            return
        end
        http.fetch({url=url, method="GET", timeout=60}, function(res)
            minetest.after(0, function()
                if not res.succeeded or res.code ~= 200 then
                    minetest.chat_send_player(name,
                        "[SELab] Run failed (HTTP "..tostring(res.code)..")")
                    return
                end
                minetest.chat_send_player(name, "[SELab] ✓ Done — refreshing display...")
                -- Try to parse run response as status data directly
                local ok, data = pcall(minetest.parse_json, res.data)
                if ok and data and data.sections then
                    update_dashboard(data)
                end
                -- Also fetch fresh /api/status after a short delay as backup
                minetest.after(2, function()
                    fetch_and_update(false)
                end)
            end)
        end)
    end,
    on_punch = function(pos, node, puncher)
        -- Trigger same as right-click so both mouse buttons work
        local node_def = minetest.registered_nodes["selab_dashboard:lever"]
        if node_def and node_def.on_rightclick then
            node_def.on_rightclick(pos, node, puncher)
        end
    end,
})

--  Section label nodes 
-- Flat wide nodebox with a pre-generated texture showing section name.
-- One node per section id, texture = selab_label_<id>.png

local SECTION_IDS = {
    "network","ssh","apache","sftp","mysql",
    "portainer","vaultwarden","planka","wordpress","docker","minetest"
}

for _, sid in ipairs(SECTION_IDS) do
    local tex = "selab_label_"..sid..".png"
    minetest.register_node("selab_dashboard:label_"..sid, {
        description = "SELab Label: "..sid,
        tiles = { "default_stone.png", "default_stone.png",
                  tex, tex, "default_stone.png", tex },
        drawtype = "nodebox",
        paramtype = "light",
        node_box = {
            type = "fixed",
            -- vertical panel, thin, sits against the wall (+Z side)
            fixed = {-0.5, -0.5, 0.3,  0.5, 0.5, 0.5},
        },
        groups = {not_in_creative_inventory=1},
        can_dig = function() return false end,
    })
end

local function place_label(pos, sid)
    local name = "selab_dashboard:label_"..sid
    if minetest.registered_nodes[name] then
        minetest.set_node(pos, {name=name})
    end
end

local function place_lever(pos, url, label)
    minetest.set_node(pos, {name="selab_dashboard:lever"})
    local m = minetest.get_meta(pos)
    m:set_string("run_url",  url)
    m:set_string("label",    label)
    m:set_string("infotext", "Left/Right-click to run: " .. label)
end

--  Dashboard build 
local function build_dashboard(data)
    local o = dash.origin
    dash.positions = {}

    local n_sec   = #data.sections
    local max_chk = 0
    for _, s in ipairs(data.sections) do
        if #s.checks > max_chk then max_chk = #s.checks end
    end

    local wall_w = n_sec * SEC_STRIDE + 2
    local wall_h = max_chk * CHECK_HEIGHT + 4

    -- Clear area
    for dz = -VIEW_DIST - 1, 3 do
        for dx = -2, wall_w + 1 do
            minetest.set_node({x=o.x+dx, y=o.y-1, z=o.z+dz},
                {name="default:stone_block"})
            for dy = 0, wall_h + 2 do
                minetest.set_node({x=o.x+dx, y=o.y+dy, z=o.z+dz},
                    {name="air"})
            end
        end
    end

    -- Stone wall
    for dx = -1, wall_w do
        for dy = 0, wall_h do
            minetest.set_node({x=o.x+dx, y=o.y+dy, z=o.z},
                {name="default:stone"})
        end
    end

    -- Lit ceiling
    for dx = -1, wall_w do
        minetest.set_node({x=o.x+dx, y=o.y+wall_h+1, z=o.z},
            {name="default:stone_block"})
        if dx % 3 == 0 then
            minetest.set_node({x=o.x+dx, y=o.y+wall_h, z=o.z-1},
                {name="default:meselamp"})
        end
    end

    -- Summary beacon + Run All lever
    local spos = {x=o.x-1, y=o.y+wall_h-1, z=o.z}
    minetest.set_node(spos, {name="default:mese"})
    set_info(spos, string.format(
        "SELab Dashboard\n%d/%d pass | %d fail",
        data.passed, data.total, data.failed))
    place_sign({x=o.x-1, y=o.y+wall_h-1, z=o.z-1},
        string.format("SELab\n%d/%d pass", data.passed, data.total))
    place_lever({x=o.x-1, y=o.y+wall_h-2, z=o.z-1},
        RUN_BASE, "Run ALL checks")

    -- Sections
    for s_idx, section in ipairs(data.sections) do
        local x  = (s_idx - 1) * SEC_STRIDE
        local hy = o.y + max_chk * CHECK_HEIGHT + 1

        -- Section header meselamp
        local hpos = {x=o.x+x, y=hy, z=o.z}
        minetest.set_node(hpos, {name="default:meselamp"})
        set_info(hpos, section.name.." ["..section.status:upper().."]")

        -- Readable label above the header (vertical panel with texture)
        place_label({x=o.x+x, y=hy+2, z=o.z-1}, section.id)

        -- Section sign + lever
        place_sign({x=o.x+x, y=hy, z=o.z-1},
            trunc(section.name, 12).."\n"..section.status:upper())
        place_lever({x=o.x+x+1, y=hy+1, z=o.z-1},
            RUN_BASE.."/"..section.id, "Run section: "..section.name)

        -- Checks
        for c_idx, check in ipairs(section.checks) do
            local y   = o.y + (c_idx - 1) * CHECK_HEIGHT
            local pos = {x=o.x+x, y=y, z=o.z}

            minetest.set_node(pos,
                {name=status_node(check.status)})
            minetest.set_node({x=o.x+x, y=y+1, z=o.z},
                {name=status_node(check.status)})

            local info = string.format("[%s] %s\n%s port %s  %dms",
                check.status:upper(), check.name,
                check.protocol or "?", check.port or "?",
                check.duration_ms or 0)
            for _, r in ipairs(check.results or {}) do
                info = info .. "\n\n[" .. r.status:upper() .. "] " .. (r.message or "")
                if r.command and r.command ~= "" then
                    -- Show only the last/most relevant line of the command
                    local cmd = r.command:match("[^\n]+$") or r.command
                    info = info .. "\n$ " .. cmd:sub(1, 80)
                end
                if r.output and r.output ~= "" then
                    -- Show only last 2 lines of output
                    local lines = {}
                    for l in r.output:gmatch("[^\n]+") do lines[#lines+1] = l end
                    local out = table.concat(lines, " | ", math.max(1,#lines-1))
                    info = info .. "\n> " .. out:sub(1, 80)
                end
            end
            set_info(pos, info:sub(1, 500))

            -- Sign on wall face (z-1) and lever embedded in wall (z=0)
            place_sign({x=o.x+x, y=y, z=o.z-1},
                trunc(check.name, 14))
            place_lever({x=o.x+x+1, y=y+1, z=o.z-1},
                RUN_BASE.."/"..check.id, "Run: "..check.name)

            dash.positions[section.id.."."..check.id] =
                {x=o.x+x, y=y, z=o.z}
        end
    end

    minetest.log("action", string.format(
        "[%s] Wall built — %d sections, %d/%d pass",
        MODNAME, n_sec, data.passed, data.total))
end

--  Dashboard update (colours only) 
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
                    local c = check.status=="pass"
                        and "\27(c@#44FF44)" or "\27(c@#FF4444)"
                    minetest.chat_send_all(string.format(
                        "%s[SELab] %s → %s\27(c@#FFFFFF)",
                        c, check.name, check.status:upper()))
                end
                local info = string.format("[%s] %s\n%s port %s %dms",
                    check.status:upper(), check.name,
                    check.protocol or "?", check.port or "?",
                    check.duration_ms or 0)
                for _, r in ipairs(check.results or {}) do
                    info = info .. "\n\n[" .. r.status:upper() .. "] " .. (r.message or "")
                    if r.command and r.command ~= "" then
                        local cmd = r.command:match("[^\n]+$") or r.command
                        info = info .. "\n$ " .. cmd:sub(1, 80)
                    end
                    if r.output and r.output ~= "" then
                        local lines = {}
                        for l in r.output:gmatch("[^\n]+") do lines[#lines+1] = l end
                        local out = table.concat(lines, " | ", math.max(1,#lines-1))
                        info = info .. "\n> " .. out:sub(1, 80)
                    end
                end
                set_info(pos, info:sub(1, 500))
            end
        end
    end
end

--  Fetch & update (now defined, resolves forward reference) 
fetch_and_update = function(rebuild)
    if not http then
        minetest.log("error", "["..MODNAME.."] HTTP API unavailable")
        return
    end
    http.fetch({url=ENDPOINT, method="GET", timeout=10}, function(res)
        if not res.succeeded then
            minetest.log("error", string.format(
                "[%s] HTTP error (code %d)", MODNAME, res.code))
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

--  Poll loop 
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

--  Chat command 
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
                return false, "HTTP API unavailable — add '"
                    ..MODNAME.."' to secure.http_mods"
            end
            local pos = player:get_pos()
            dash.origin = {
                x = math.floor(pos.x) - 2,
                y = math.floor(pos.y),
                z = math.floor(pos.z) + VIEW_DIST,
            }
            local spawn_x = dash.origin.x + 16
            local spawn_y = dash.origin.y + 1
            local spawn_z = dash.origin.z - VIEW_DIST + 1
            minetest.setting_set("static_spawnpoint",
                spawn_x..","..spawn_y..","..spawn_z)
            player:set_pos({x=spawn_x, y=spawn_y, z=spawn_z})
            minetest.set_timeofday(0.5)
            minetest.chat_send_player(name,
                "[Dashboard] Fetching "..ENDPOINT.." ...")
            fetch_and_update(true)
            start_polling()
            return true, "Dashboard building. Auto-refresh every "
                ..POLL_INTERVAL.."s."

        elseif param == "refresh" then
            if not dash.origin then return false, "Run /dashboard build first" end
            fetch_and_update(false)
            return true, "Refreshing..."

        elseif param == "rebuild" then
            if not dash.origin then return false, "Run /dashboard build first" end
            fetch_and_update(true)
            return true, "Rebuilding..."

        elseif param == "clear" then
            dash.polling  = false
            dash.origin   = nil
            dash.positions = {}
            return true, "Stopped."

        elseif param == "info" then
            if not dash.origin then return true, "No active dashboard." end
            local n = 0
            for _ in pairs(dash.positions) do n = n + 1 end
            return true, string.format("Origin:%s | Checks:%d | Endpoint:%s",
                minetest.pos_to_string(dash.origin), n, ENDPOINT)

        else
            return false,
                "Usage: /dashboard <build|rebuild|refresh|clear|info>"
        end
    end
})

minetest.log("action", "["..MODNAME.."] loaded.")