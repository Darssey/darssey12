-- Auto-Recoger v5 | Derrota al RNG Anime
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

-- Cierra versiones anteriores (incluido el script suelto del comerciante)
if getgenv then
    if getgenv().RNGAutoStop then pcall(getgenv().RNGAutoStop) end
    if getgenv().RNGMerchStop then pcall(getgenv().RNGMerchStop) end
end

local RARITIES = {
    {name = "Common",    alias = {"common", "comun"}},
    {name = "Uncommon",  alias = {"uncommon", "pococomun", "infrecuente"}},
    {name = "Rare",      alias = {"rare", "raro"}},
    {name = "Epic",      alias = {"epic", "spic", "epico"}},
    {name = "Legendary", alias = {"legendary", "legendario"}},
    {name = "Mythic",    alias = {"mythic", "mitico"}},
    {name = "Cosmic",    alias = {"cosmic", "cosmico"}},
    {name = "Divine",    alias = {"divine", "divino"}},
    {name = "Secret",    alias = {"secret", "secreto"}},
    {name = "Template",  alias = {"template", "plantilla"}},
}

local MUTATIONS = {
    {name = "Angelic",     alias = {"angelic", "angelico"}},
    {name = "Blossom",     alias = {"blossom", "florecer"}},
    {name = "Diamond",     alias = {"diamond", "diamante"}},
    {name = "Example",     alias = {"example", "ejemplo"}},
    {name = "Genius",      alias = {"genius", "genio"}},
    {name = "Gold",        alias = {"gold", "oro", "dorado"}},
    {name = "Honored",     alias = {"honored", "honor", "honores", "honrando", "honrado"}},
    {name = "No Mutation", alias = {"", "nomutation", "none", "ninguna", "nomutacion", "sinmutacion"}},
}

------------------------------------------------------------------
-- ESTADO Y CONFIGURACIÓN GUARDADA
------------------------------------------------------------------
local CONFIG_FILE = "RNGAuto_config_v5.json"
local canFile = type(writefile) == "function" and type(readfile) == "function"
    and type(isfile) == "function"

local selected, rules
local filterRarity, filterChars, useTeleport, merchAuto
local winPos = nil

local function defaults()
    selected = {Secret = true, Divine = true}
    rules = {}
    filterRarity, filterChars = true, false
    useTeleport, merchAuto = true, true
end
defaults()

local running, alive = false, true
local stationRef, origin
local pending = {}
local cooldown = setmetatable({}, {__mode = "k"})
local stable = setmetatable({}, {__mode = "k"})
local seenChars, seenList = {}, {}
local refreshSeen

local logLines, logLabel, statusLabel = {}, nil, nil
local function log(msg)
    print("[RNGAuto]", msg)
    table.insert(logLines, msg)
    if #logLines > 8 then table.remove(logLines, 1) end
    if logLabel then logLabel.Text = table.concat(logLines, "\n") end
    if statusLabel then statusLabel.Text = msg end
end

local function snapshot()
    local sel = {}
    for k in pairs(selected) do table.insert(sel, k) end
    local rl = {}
    for _, r in ipairs(rules) do
        local ms = {}
        for k in pairs(r.mutations) do table.insert(ms, k) end
        table.insert(rl, {label = r.label, key = r.key, mutations = ms})
    end
    return {
        version = 5, selected = sel, rules = rl,
        filterRarity = filterRarity, filterChars = filterChars,
        useTeleport = useTeleport, merchAuto = merchAuto, pos = winPos,
    }
end

local saveQueued = false
local function saveConfig(now)
    if not canFile then return end
    local function doSave()
        local ok, err = pcall(function()
            writefile(CONFIG_FILE, HttpService:JSONEncode(snapshot()))
        end)
        if not ok then log("No pude guardar: " .. tostring(err)) end
        return ok
    end
    if now then return doSave() end
    if saveQueued then return end
    saveQueued = true
    task.delay(0.6, function()
        saveQueued = false
        doSave()
    end)
end

local function validName(list, n)
    for _, item in ipairs(list) do
        if item.name == n then return true end
    end
    return false
end

local function loadConfig()
    if not canFile then return false end
    local ok, data = pcall(function()
        if isfile(CONFIG_FILE) then
            return HttpService:JSONDecode(readfile(CONFIG_FILE))
        end
    end)
    if not ok or type(data) ~= "table" then return false end
    if type(data.selected) == "table" then
        selected = {}
        for _, n in ipairs(data.selected) do
            if validName(RARITIES, n) then selected[n] = true end
        end
    end
    if type(data.rules) == "table" then
        rules = {}
        for _, r in ipairs(data.rules) do
            if type(r) == "table" and type(r.key) == "string" and r.key ~= "" then
                local muts = {}
                if type(r.mutations) == "table" then
                    for _, m in ipairs(r.mutations) do
                        if validName(MUTATIONS, m) then muts[m] = true end
                    end
                end
                table.insert(rules, {label = tostring(r.label or r.key), key = r.key, mutations = muts})
            end
        end
    end
    if type(data.filterRarity) == "boolean" then filterRarity = data.filterRarity end
    if type(data.filterChars) == "boolean" then filterChars = data.filterChars end
    if type(data.useTeleport) == "boolean" then useTeleport = data.useTeleport end
    if type(data.merchAuto) == "boolean" then merchAuto = data.merchAuto end
    if type(data.pos) == "table" and type(data.pos.x) == "number" and type(data.pos.y) == "number" then
        winPos = {x = data.pos.x, y = data.pos.y}
    end
    return true
end

local loaded = loadConfig()

------------------------------------------------------------------
-- LÓGICA DE RECOGIDA
------------------------------------------------------------------
local ACC = {["á"]="a",["é"]="e",["í"]="i",["ó"]="o",["ú"]="u",["ñ"]="n",
             ["Á"]="a",["É"]="e",["Í"]="i",["Ó"]="o",["Ú"]="u",["Ñ"]="n"}
local function normalize(s)
    s = tostring(s or "")
    s = s:gsub("<[^>]->", "")
    s = s:lower()
    for a, b in pairs(ACC) do s = s:gsub(a, b) end
    s = s:gsub("[%s%p]", "")
    return s
end

local function canon(list, text)
    local n = normalize(text)
    for _, item in ipairs(list) do
        for _, a in ipairs(item.alias) do
            if n == a then return item.name end
        end
    end
end

local function readDesc(model, name)
    local r = model:FindFirstChild(name, true)
    local d = r and (r:FindFirstChild("Desc") or r)
    if d and d:IsA("TextLabel") then return d.Text end
end

local function getInfo(prompt)
    local model = prompt.Parent and prompt.Parent.Parent
    if not model then return nil end
    local rText = readDesc(model, "Rarity")
    if not rText or rText == "" then return nil end
    local uText = readDesc(model, "UnitName") or ""
    local mText = readDesc(model, "Mutation") or ""
    return {
        model = model, rText = rText, uText = uText, mText = mText,
        sig = model.Name .. "|" .. rText .. "|" .. uText .. "|" .. mText,
    }
end

local function noteSeen(text)
    if not text or text == "" then return end
    local key = normalize(text)
    if key == "" or seenChars[key] then return end
    seenChars[key] = text
    table.insert(seenList, text)
    table.sort(seenList, function(a, b) return a:lower() < b:lower() end)
    if refreshSeen then refreshSeen() end
end

local function decide(info)
    local rname = canon(RARITIES, info.rText)
    local mut = canon(MUTATIONS, info.mText)
    if filterRarity and rname and selected[rname] then return true, rname, mut end
    if filterChars then
        local uKey = normalize(info.uText)
        local mKey = normalize(info.model.Name)
        for _, r in ipairs(rules) do
            local charOk = r.key == "*" or (uKey ~= "" and r.key == uKey) or r.key == mKey
            local mutOk = next(r.mutations) == nil or (mut ~= nil and r.mutations[mut])
            if charOk and mutOk then return true, rname, mut end
        end
    end
    return false, rname, mut
end

local function restore()
    if origin then
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.CFrame = origin end
        origin = nil
    end
end

local function scan()
    if not stationRef or not stationRef.Parent then return end
    for _, d in ipairs(stationRef:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            local info = getInfo(d)
            if info then
                local buy, rname, mut = decide(info)
                local st = stable[d]
                if not st or st.sig ~= info.sig then
                    st = {sig = info.sig, since = os.clock()}
                    stable[d] = st
                    noteSeen(info.uText)
                    local verb = running and (buy and "COMPRAR: " or "Ignorado: ") or "Visto: "
                    log(verb .. (info.uText ~= "" and info.uText or info.model.Name)
                        .. " [" .. (rname or ("?" .. info.rText)) .. "] ["
                        .. (mut or ("?" .. info.mText)) .. "]")
                end
                if running and buy and not pending[d]
                    and (cooldown[d] or 0) < os.clock()
                    and os.clock() - st.since >= 0.25 then
                    pending[d] = {
                        t = os.clock(), sig = info.sig,
                        name = info.uText ~= "" and info.uText or info.model.Name,
                    }
                end
            end
        end
    end
end

task.spawn(function()
    while alive do
        scan()
        if running then
            local any = false
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            for prompt, info in pairs(pending) do
                local cur = prompt:IsDescendantOf(workspace) and getInfo(prompt)
                if not cur or cur.sig ~= info.sig then
                    pending[prompt] = nil
                    cooldown[prompt] = os.clock() + 1.5
                    log("Listo: " .. info.name)
                elseif os.clock() - info.t > 2.5 then
                    pending[prompt] = nil
                    cooldown[prompt] = os.clock() + 4
                    log("No se pudo recoger: " .. info.name)
                else
                    any = true
                    local part = prompt.Parent
                    if useTeleport and hrp and part and part:IsA("BasePart") then
                        origin = origin or hrp.CFrame
                        hrp.CFrame = part.CFrame * CFrame.new(0, 0, 3)
                    end
                    pcall(function()
                        prompt.HoldDuration = 0
                        fireproximityprompt(prompt)
                    end)
                    task.wait(0.08)
                end
            end
            if not any then restore() end
        end
        task.wait(0.1)
    end
end)

local function stop()
    running = false
    table.clear(pending)
    restore()
end

-- Detección de tu base
local function posOf(inst)
    if inst:IsA("Model") then return inst:GetPivot().Position end
    local p = inst:FindFirstChildWhichIsA("BasePart", true)
    return p and p.Position
end

local function findMyBase()
    local bases = workspace:FindFirstChild("Bases")
    if not bases then return nil end
    local function match(v)
        v = tostring(v)
        return v == player.Name or v == player.DisplayName or v == tostring(player.UserId)
    end
    for _, base in ipairs(bases:GetChildren()) do
        for k, v in pairs(base:GetAttributes()) do
            if match(v) then return base, "atributo " .. k end
        end
        for _, d in ipairs(base:GetDescendants()) do
            if d:IsA("ValueBase") then
                if d.Value == player or match(d.Value) then
                    return base, "valor " .. d.Name
                end
            elseif d:IsA("TextLabel") then
                local t = d.Text
                if t:find(player.Name, 1, true) or t:find(player.DisplayName, 1, true) then
                    return base, "cartel con tu nombre"
                end
            end
        end
    end
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local best, bestD
    for _, base in ipairs(bases:GetChildren()) do
        local p = posOf(base)
        if p then
            local dist = (p - hrp.Position).Magnitude
            if not bestD or dist < bestD then best, bestD = base, dist end
        end
    end
    if best then return best, "cercanía (" .. math.floor(bestD) .. " studs)" end
end

------------------------------------------------------------------
-- COMERCIANTE
------------------------------------------------------------------
local mLines, mLabel = {}, nil
local function mlog(msg)
    print("[Tienda]", msg)
    table.insert(mLines, msg)
    if #mLines > 7 then table.remove(mLines, 1) end
    if mLabel then mLabel.Text = table.concat(mLines, "\n") end
    if statusLabel then statusLabel.Text = "Tienda: " .. msg end
end

local function ser(v, depth)
    depth = depth or 0
    if type(v) == "table" then
        if depth > 3 then return "{...}" end
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 30 then table.insert(parts, "...") break end
            table.insert(parts, tostring(k) .. "=" .. ser(val, depth + 1))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end

local function invoke(rf, ...)
    local args = table.pack(...)
    local done, ok, res = false, false, nil
    task.spawn(function()
        ok, res = pcall(function()
            return rf:InvokeServer(table.unpack(args, 1, args.n))
        end)
        done = true
    end)
    local t0 = os.clock()
    while not done and os.clock() - t0 < 5 do task.wait(0.05) end
    if not done then return false, "sin respuesta (5 s)" end
    return ok, res
end

local merch = {}
local merchBusy, merchLast = false, 0
local merchConn

local function buyMerchant(reason)
    if merchBusy then return end
    merchBusy = true
    mlog("Comprando todo (" .. reason .. ")")
    if merch.stock then
        local ok, res = invoke(merch.stock)
        mlog("Stock -> " .. (ok and ser(res):sub(1, 110) or tostring(res)))
    end
    if merch.buyAll then
        local ok, res = invoke(merch.buyAll)
        mlog("BuyAll -> " .. (ok and ser(res):sub(1, 110) or ("error: " .. tostring(res))))
    else
        mlog("No encontré BuyAllMerchantItemsRequestFunction")
    end
    merchBusy = false
end

task.spawn(function()
    local folder = RS:WaitForChild("RemoteEvents", 10)
    if not folder then mlog("No encontré RemoteEvents") return end
    merch.vis = folder:FindFirstChild("MerchantVisibilityEvent")
    merch.buyAll = folder:FindFirstChild("BuyAllMerchantItemsRequestFunction")
    merch.stock = folder:FindFirstChild("GetMerchantStockRequestFunction")
    if merch.vis and alive then
        merchConn = merch.vis.OnClientEvent:Connect(function(...)
            local args = {...}
            mlog("Evento: " .. ser(args):sub(1, 80))
            if merchAuto and args[1] ~= false and os.clock() - merchLast > 3 then
                merchLast = os.clock()
                task.wait(1)
                buyMerchant("apareció")
            end
        end)
    else
        mlog("No encontré MerchantVisibilityEvent")
    end
end)

------------------------------------------------------------------
-- INTERFAZ
------------------------------------------------------------------
local BG = Color3.fromRGB(24, 24, 30)
local CARD = Color3.fromRGB(38, 38, 48)
local CARD2 = Color3.fromRGB(52, 52, 66)
local TEXT = Color3.fromRGB(235, 235, 242)
local MUTED = Color3.fromRGB(140, 140, 156)
local ACCENT = Color3.fromRGB(88, 101, 242)
local GREEN = Color3.fromRGB(46, 160, 67)
local RED = Color3.fromRGB(200, 60, 60)
local WHITE = Color3.new(1, 1, 1)

local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local function corner(o, r)
    mk("UICorner", {CornerRadius = UDim.new(0, r)}, o)
end

local ord = 0
local function O() ord = ord + 1 return ord end

for _, holder in ipairs({function() return gethui() end,
                         function() return game:GetService("CoreGui") end,
                         function() return player.PlayerGui end}) do
    pcall(function()
        for _, n in ipairs({"RNGAutoUI", "RNGMerchantUI"}) do
            local old = holder():FindFirstChild(n)
            if old then old:Destroy() end
        end
    end)
end

local gui = Instance.new("ScreenGui")
gui.Name = "RNGAutoUI"
gui.ResetOnSpawn = false
local okParent = pcall(function()
    gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
end)
if not okParent or not gui.Parent then gui.Parent = player:WaitForChild("PlayerGui") end

-- Posición inicial (guardada o por defecto), dentro de la pantalla
local function clampPos(x, y)
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
    return math.clamp(x, 0, math.max(0, vp.X - 80)), math.clamp(y, 0, math.max(0, vp.Y - 60))
end
local px, py = clampPos(winPos and winPos.x or 20, winPos and winPos.y or 60)

local main = mk("Frame", {
    Size = UDim2.new(0, 300, 0, 470), Position = UDim2.new(0, px, 0, py),
    BackgroundColor3 = BG, BorderSizePixel = 0, ClipsDescendants = true,
}, gui)
corner(main, 12)

-- Cabecera
local header = mk("Frame", {Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1}, main)
local dot = mk("Frame", {
    Size = UDim2.new(0, 10, 0, 10), Position = UDim2.new(0, 14, 0, 14),
    BackgroundColor3 = MUTED, BorderSizePixel = 0,
}, header)
corner(dot, 5)
mk("TextLabel", {
    Size = UDim2.new(1, -110, 1, 0), Position = UDim2.new(0, 32, 0, 0),
    BackgroundTransparency = 1, Text = "Auto-Recoger", TextColor3 = TEXT,
    Font = Enum.Font.GothamBold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local function circleBtn(text, x, color)
    local b = mk("TextButton", {
        Size = UDim2.new(0, 24, 0, 24), Position = UDim2.new(1, x, 0, 7),
        Text = text, BackgroundColor3 = color, TextColor3 = WHITE,
        Font = Enum.Font.GothamBold, TextSize = 14, BorderSizePixel = 0,
    }, header)
    corner(b, 12)
    return b
end
local minBtn = circleBtn("–", -62, CARD2)
local closeBtn = circleBtn("×", -34, RED)

-- Cuerpo (se oculta al minimizar)
local body = mk("Frame", {
    Position = UDim2.new(0, 0, 0, 38), Size = UDim2.new(1, 0, 1, -38),
    BackgroundTransparency = 1,
}, main)

local tabBar = mk("Frame", {
    Size = UDim2.new(1, -20, 0, 28), Position = UDim2.new(0, 10, 0, 0),
    BackgroundTransparency = 1,
}, body)
mk("Frame", {
    Size = UDim2.new(1, -20, 0, 1), Position = UDim2.new(0, 10, 0, 29),
    BackgroundColor3 = CARD, BorderSizePixel = 0,
}, body)

local pageHolder = mk("Frame", {
    Position = UDim2.new(0, 0, 0, 34), Size = UDim2.new(1, 0, 1, -34 - 64),
    BackgroundTransparency = 1,
}, body)

local footer = mk("Frame", {
    Position = UDim2.new(0, 0, 1, -64), Size = UDim2.new(1, 0, 0, 64),
    BackgroundTransparency = 1,
}, body)
statusLabel = mk("TextLabel", {
    Size = UDim2.new(1, -20, 0, 16), Position = UDim2.new(0, 10, 0, 4),
    BackgroundTransparency = 1, Text = "Listo", TextColor3 = MUTED,
    Font = Enum.Font.Gotham, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
}, footer)
local startBtn = mk("TextButton", {
    Size = UDim2.new(1, -20, 0, 34), Position = UDim2.new(0, 10, 0, 24),
    Text = "INICIAR", BackgroundColor3 = GREEN, TextColor3 = WHITE,
    Font = Enum.Font.GothamBold, TextSize = 15, BorderSizePixel = 0,
}, footer)
corner(startBtn, 10)

local function setRunningUI(on)
    startBtn.Text = on and "DETENER" or "INICIAR"
    startBtn.BackgroundColor3 = on and RED or GREEN
    dot.BackgroundColor3 = on and GREEN or MUTED
end

-- Pestañas
local pages, tabs = {}, {}
local function showTab(name)
    for n, p in pairs(pages) do p.Visible = (n == name) end
    for n, t in pairs(tabs) do
        t.btn.TextColor3 = (n == name) and TEXT or MUTED
        t.line.Visible = (n == name)
    end
end

local TAB_NAMES = {"Control", "Rarezas", "Personajes", "Tienda"}
local function newPage(name, idx)
    local b = mk("TextButton", {
        Size = UDim2.new(0.25, 0, 1, 0), Position = UDim2.new((idx - 1) * 0.25, 0, 0, 0),
        BackgroundTransparency = 1, Text = name, TextColor3 = MUTED,
        Font = Enum.Font.GothamBold, TextSize = 12,
    }, tabBar)
    local line = mk("Frame", {
        Size = UDim2.new(0.7, 0, 0, 2), Position = UDim2.new(0.15, 0, 1, -2),
        BackgroundColor3 = ACCENT, BorderSizePixel = 0, Visible = false,
    }, b)
    tabs[name] = {btn = b, line = line}
    local p = mk("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
    }, pageHolder)
    mk("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, p)
    mk("UIPadding", {
        PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 12),
        PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
    }, p)
    pages[name] = p
    b.Activated:Connect(function() showTab(name) end)
    return p
end

local pControl = newPage("Control", 1)
local pRare = newPage("Rarezas", 2)
local pChars = newPage("Personajes", 3)
local pShop = newPage("Tienda", 4)

-- Componentes
local function section(parent, text)
    return mk("TextLabel", {
        Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Text = text,
        TextColor3 = MUTED, Font = Enum.Font.GothamBold, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = O(),
    }, parent)
end

local function note(parent, text, h)
    return mk("TextLabel", {
        Size = UDim2.new(1, 0, 0, h or 28), BackgroundTransparency = 1, Text = text,
        TextColor3 = MUTED, Font = Enum.Font.Gotham, TextSize = 11, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = O(),
    }, parent)
end

local function rowFrame(parent, h)
    return mk("Frame", {
        Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1, LayoutOrder = O(),
    }, parent)
end

local function btn(parent, text, color, props)
    local b = mk("TextButton", {
        Text = text, BackgroundColor3 = color, TextColor3 = WHITE,
        Font = Enum.Font.GothamBold, TextSize = 13, BorderSizePixel = 0,
    }, parent)
    corner(b, 8)
    if props then for k, v in pairs(props) do b[k] = v end end
    return b
end

local function logBox(parent, h)
    local l = mk("TextLabel", {
        Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = Color3.fromRGB(18, 18, 23),
        TextColor3 = Color3.fromRGB(200, 200, 210), Font = Enum.Font.Code, TextSize = 11,
        TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top, BorderSizePixel = 0, Text = "",
        LayoutOrder = O(),
    }, parent)
    corner(l, 8)
    mk("UIPadding", {
        PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
        PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
    }, l)
    return l
end

local refreshers = {}
local function toggleRow(parent, text, get, set)
    local row = mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = CARD, AutoButtonColor = false,
        Text = "", BorderSizePixel = 0, LayoutOrder = O(),
    }, parent)
    corner(row, 8)
    mk("TextLabel", {
        Size = UDim2.new(1, -64, 1, 0), Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1, Text = text, TextColor3 = TEXT,
        Font = Enum.Font.Gotham, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    local sw = mk("Frame", {
        Size = UDim2.new(0, 38, 0, 20), Position = UDim2.new(1, -50, 0.5, -10),
        BorderSizePixel = 0,
    }, row)
    corner(sw, 10)
    local knob = mk("Frame", {
        Size = UDim2.new(0, 16, 0, 16), BackgroundColor3 = WHITE, BorderSizePixel = 0,
    }, sw)
    corner(knob, 8)
    local function refresh()
        local on = get()
        sw.BackgroundColor3 = on and ACCENT or Color3.fromRGB(85, 85, 100)
        knob.Position = on and UDim2.new(1, -18, 0, 2) or UDim2.new(0, 2, 0, 2)
    end
    refresh()
    table.insert(refreshers, refresh)
    row.Activated:Connect(function()
        set(not get())
        refresh()
        saveConfig()
    end)
end

local repaints = {}
local function chip(parent, text, isOn, onClick, order)
    local b = mk("TextButton", {
        Text = text, Font = Enum.Font.GothamMedium, TextSize = 12,
        BorderSizePixel = 0, AutoButtonColor = false, LayoutOrder = order,
    }, parent)
    corner(b, 8)
    local function paint()
        local on = isOn()
        b.BackgroundColor3 = on and ACCENT or CARD
        b.TextColor3 = on and WHITE or Color3.fromRGB(190, 190, 205)
    end
    paint()
    b.Activated:Connect(function() onClick() paint() end)
    return paint
end

local function grid(parent, count, cellH)
    local rows = math.ceil(count / 2)
    local f = mk("Frame", {
        Size = UDim2.new(1, 0, 0, rows * cellH + (rows - 1) * 6),
        BackgroundTransparency = 1, LayoutOrder = O(),
    }, parent)
    mk("UIGridLayout", {
        CellSize = UDim2.new(0.5, -3, 0, cellH), CellPadding = UDim2.new(0, 6, 0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, f)
    return f
end

------------------------------ PESTAÑA CONTROL
section(pControl, "BASE")
local baseRow = rowFrame(pControl, 34)
local baseBox = mk("TextBox", {
    Size = UDim2.new(1, -92, 1, 0), BackgroundColor3 = CARD, Text = "auto",
    PlaceholderText = "auto", TextColor3 = TEXT, Font = Enum.Font.Gotham, TextSize = 13,
    ClearTextOnFocus = false, BorderSizePixel = 0,
}, baseRow)
corner(baseBox, 8)
local detectBtn = btn(baseRow, "Detectar", ACCENT, {
    Size = UDim2.new(0, 86, 1, 0), Position = UDim2.new(1, -86, 0, 0), TextSize = 12,
})

section(pControl, "FILTROS")
toggleRow(pControl, "Filtro por rareza",
    function() return filterRarity end, function(v) filterRarity = v end)
toggleRow(pControl, "Filtro por personaje",
    function() return filterChars end, function(v) filterChars = v end)

section(pControl, "OPCIONES")
toggleRow(pControl, "Ir hacia el personaje",
    function() return useTeleport end, function(v) useTeleport = v end)

section(pControl, "CONFIGURACIÓN")
local cfgRow = rowFrame(pControl, 32)
local saveBtn = btn(cfgRow, "Guardar ahora", CARD2, {Size = UDim2.new(0.5, -3, 1, 0), TextSize = 12})
local resetBtn = btn(cfgRow, "Restablecer", CARD2, {
    Size = UDim2.new(0.5, -3, 1, 0), Position = UDim2.new(0.5, 3, 0, 0), TextSize = 12,
})
note(pControl, canFile and "Se guarda solo cada vez que cambias algo."
    or "Este ejecutor no permite guardar archivos.", 16)

section(pControl, "REGISTRO")
logLabel = logBox(pControl, 110)

------------------------------ PESTAÑA RAREZAS
section(pRare, "RAREZAS A RECOGER")
local rareGrid = grid(pRare, #RARITIES, 32)
for i, r in ipairs(RARITIES) do
    table.insert(repaints, chip(rareGrid, r.name,
        function() return selected[r.name] end,
        function() selected[r.name] = not selected[r.name] or nil saveConfig() end, i))
end
local quickRow = rowFrame(pRare, 30)
local allBtn = btn(quickRow, "Marcar todas", CARD2, {Size = UDim2.new(0.5, -3, 1, 0), TextSize = 12})
local noneBtn = btn(quickRow, "Limpiar", CARD2, {
    Size = UDim2.new(0.5, -3, 1, 0), Position = UDim2.new(0.5, 3, 0, 0), TextSize = 12,
})
note(pRare, "Se recogen las rarezas marcadas, siempre que 'Filtro por rareza' esté activo en Control.", 34)

------------------------------ PESTAÑA PERSONAJES
section(pChars, "NUEVA REGLA")
local charBox = mk("TextBox", {
    Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = CARD, Text = "",
    PlaceholderText = "Personaje (o * para cualquiera)", PlaceholderColor3 = MUTED,
    TextColor3 = TEXT, Font = Enum.Font.Gotham, TextSize = 13,
    ClearTextOnFocus = false, BorderSizePixel = 0, LayoutOrder = O(),
}, pChars)
corner(charBox, 8)

section(pChars, "VISTOS (TOCA UNO PARA USARLO)")
local seenFrame = mk("ScrollingFrame", {
    Size = UDim2.new(1, 0, 0, 84), BackgroundColor3 = Color3.fromRGB(18, 18, 23),
    BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y, LayoutOrder = O(),
}, pChars)
corner(seenFrame, 8)
mk("UIListLayout", {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder}, seenFrame)
mk("UIPadding", {PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4)}, seenFrame)

section(pChars, "MUTACIONES (NINGUNA = CUALQUIERA)")
local newMuts, mutPaints = {}, {}
local muGrid = grid(pChars, #MUTATIONS, 28)
for i, m in ipairs(MUTATIONS) do
    table.insert(mutPaints, chip(muGrid, m.name,
        function() return newMuts[m.name] end,
        function() newMuts[m.name] = not newMuts[m.name] or nil end, i))
end

local addBtn = btn(pChars, "Agregar regla", ACCENT, {
    Size = UDim2.new(1, 0, 0, 34), LayoutOrder = O(),
})
local rulesTitle = section(pChars, "REGLAS ACTIVAS (0)")
local rulesFrame = mk("ScrollingFrame", {
    Size = UDim2.new(1, 0, 0, 110), BackgroundColor3 = Color3.fromRGB(18, 18, 23),
    BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y, LayoutOrder = O(),
}, pChars)
corner(rulesFrame, 8)
mk("UIListLayout", {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder}, rulesFrame)
mk("UIPadding", {PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4)}, rulesFrame)

refreshSeen = function()
    for _, c in ipairs(seenFrame:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    for i, name in ipairs(seenList) do
        local b = mk("TextButton", {
            Size = UDim2.new(1, -4, 0, 24), LayoutOrder = i, Text = name,
            BackgroundColor3 = CARD, TextColor3 = TEXT, Font = Enum.Font.Gotham,
            TextSize = 12, BorderSizePixel = 0,
        }, seenFrame)
        corner(b, 6)
        b.Activated:Connect(function() charBox.Text = name end)
    end
end

local function refreshRules()
    rulesTitle.Text = "REGLAS ACTIVAS (" .. #rules .. ")"
    for _, c in ipairs(rulesFrame:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    for i, r in ipairs(rules) do
        local names = {}
        for _, m in ipairs(MUTATIONS) do
            if r.mutations[m.name] then table.insert(names, m.name) end
        end
        local row = mk("Frame", {
            Size = UDim2.new(1, -4, 0, 26), LayoutOrder = i,
            BackgroundColor3 = CARD, BorderSizePixel = 0,
        }, rulesFrame)
        corner(row, 6)
        mk("TextLabel", {
            Size = UDim2.new(1, -34, 1, 0), Position = UDim2.new(0, 8, 0, 0),
            BackgroundTransparency = 1,
            Text = r.label .. "  +  " .. (#names > 0 and table.concat(names, " / ") or "cualquier mutación"),
            TextColor3 = TEXT, Font = Enum.Font.Gotham, TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
        }, row)
        local del = btn(row, "×", RED, {
            Size = UDim2.new(0, 22, 0, 20), Position = UDim2.new(1, -26, 0, 3), TextSize = 14,
        })
        del.Activated:Connect(function()
            table.remove(rules, i)
            refreshRules()
            saveConfig()
        end)
    end
end

------------------------------ PESTAÑA TIENDA
section(pShop, "COMERCIANTE")
toggleRow(pShop, "Comprar todo al aparecer",
    function() return merchAuto end, function(v) merchAuto = v end)
local nowBtn = btn(pShop, "Comprar ahora", ACCENT, {
    Size = UDim2.new(1, 0, 0, 34), LayoutOrder = O(),
})
note(pShop, "Funciona aunque el script esté detenido: no depende del botón INICIAR.", 30)
section(pShop, "ESTADO")
mLabel = logBox(pShop, 120)

------------------------------ ACCIONES
local function refreshAll()
    for _, f in ipairs(refreshers) do f() end
    for _, f in ipairs(repaints) do f() end
    refreshRules()
end

local function detect()
    local base, how = findMyBase()
    if base then
        baseBox.Text = base.Name
        stationRef = base:FindFirstChild("RollStation")
        log("Base: " .. base.Name .. " por " .. how)
        return base
    end
    log("No pude detectar la base. Escríbela a mano.")
end
detectBtn.Activated:Connect(detect)

startBtn.Activated:Connect(function()
    if running then
        stop()
        setRunningUI(false)
        log("Detenido")
        return
    end
    if not filterRarity and not filterChars then
        log("Activa al menos un filtro")
        return
    end

    local bases = workspace:FindFirstChild("Bases")
    local txt = baseBox.Text
    local base
    if txt == "" or txt:lower() == "auto" then
        base = detect()
    else
        base = bases and bases:FindFirstChild(txt)
    end
    local station = base and base:FindFirstChild("RollStation")
    if not station then
        log("No encontré la base o su RollStation")
        return
    end

    stationRef = station
    table.clear(pending)
    running = true
    setRunningUI(true)

    local names = {}
    for _, r in ipairs(RARITIES) do
        if selected[r.name] then table.insert(names, r.name) end
    end
    log("Activo en " .. base.Name
        .. " | Rareza: " .. (filterRarity and (#names > 0 and table.concat(names, ",") or "ninguna") or "OFF")
        .. " | Reglas: " .. (filterChars and #rules or "OFF"))
end)

addBtn.Activated:Connect(function()
    local txt = charBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
    if txt == "" then
        log("Escribe un personaje, o * para cualquiera")
        return
    end
    local key
    if txt == "*" then
        key = "*"
    else
        key = normalize(txt)
        if key == "" then
            log("Nombre no válido")
            return
        end
    end
    local muts = {}
    for k in pairs(newMuts) do muts[k] = true end
    table.insert(rules, {label = (key == "*") and "Cualquiera" or txt, key = key, mutations = muts})
    refreshRules()
    newMuts = {}
    for _, f in ipairs(mutPaints) do f() end
    charBox.Text = ""
    if not filterChars then
        filterChars = true
        for _, f in ipairs(refreshers) do f() end
        log("Regla agregada. Filtro por personaje ahora está activo")
    else
        log("Regla agregada")
    end
    saveConfig()
end)

allBtn.Activated:Connect(function()
    for _, r in ipairs(RARITIES) do selected[r.name] = true end
    for _, f in ipairs(repaints) do f() end
    saveConfig()
end)
noneBtn.Activated:Connect(function()
    selected = {}
    for _, f in ipairs(repaints) do f() end
    saveConfig()
end)

nowBtn.Activated:Connect(function() task.spawn(buyMerchant, "manual") end)

saveBtn.Activated:Connect(function()
    if not canFile then log("Este ejecutor no permite guardar archivos") return end
    if saveConfig(true) then log("Configuración guardada") end
end)
resetBtn.Activated:Connect(function()
    defaults()
    newMuts = {}
    refreshAll()
    saveConfig()
    log("Configuración restablecida")
end)

minBtn.Activated:Connect(function()
    body.Visible = not body.Visible
    main.Size = body.Visible and UDim2.new(0, 300, 0, 470) or UDim2.new(0, 300, 0, 38)
end)

local function closeAll()
    alive = false
    stop()
    if merchConn then merchConn:Disconnect() end
    saveConfig(true)
    gui:Destroy()
end
closeBtn.Activated:Connect(closeAll)
if getgenv then getgenv().RNGAutoStop = closeAll end

-- Arrastrar la ventana (se guarda la posición)
local dragging, dragStart, startPos
header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, startPos = true, i.Position, main.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                  startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch) then
        dragging = false
        winPos = {x = main.Position.X.Offset, y = main.Position.Y.Offset}
        saveConfig()
    end
end)

refreshRules()
setRunningUI(false)
showTab("Control")
if loaded then
    log("Configuración cargada")
elseif canFile then
    log("Sin configuración guardada. Usando valores por defecto")
else
    log("Este ejecutor no permite guardar archivos")
end
