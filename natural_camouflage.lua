local NATURAL_CAMOUFLAGE_ID = FourCC('NCon') -- ID da sua habilidade custom
local BUFF_ID     = FourCC('NCbf') -- ID do BUFF do Immolation (aba Buffs, não a habilidade)
local NC_INVISIBILITY   = FourCC('NCps') -- Permanent Invisibility
 
local CHECK_RADIUS = 250.0 -- distância até a árvore pra considerar "camuflado"

local activeUnits = CreateGroup()
local checkTimer = nil
local nearTreeTime = {} -- [GetHandleId(unit)] = segundos acumulados perto de árvore

local CHECK_INTERVAL = 0.


--- Chave nível - Valor delay.
local cammouflageDelay = {
    [1] = 3.000,
    [2] = 1.500,
    [3] = 0.200,
}

local trees = {
  [FourCC('ATtr')] = true, -- Ashenvale Tree Wall
  [FourCC('BTtw')] = true, -- Barrens Tree Wall
  [FourCC('KTtw')] = true, -- Black Citadel Tree Wall
  [FourCC('YTft')] = true, -- Cityscape Fall Tree Wall
  [FourCC('JTct')] = true, -- Cityscape Ruined Tree Wall
  [FourCC('YTst')] = true, -- Cityscape Snowy Tree Wall
  [FourCC('YTct')] = true, -- Cityscape Summer Tree Wall
  [FourCC('YTwt')] = true, -- Cityscape Winter Tree Wall
  [FourCC('JTtw')] = true, -- Dalaran Ruins Tree Wall
  [FourCC('DTsh')] = true, -- Dungeon Tree Wall
  [FourCC('FTtw')] = true, -- Fall Tree Wall
  [FourCC('CTtr')] = true, -- Felwood Tree Wall
  [FourCC('ITtw')] = true, -- Icecrown Tree Wall
  [FourCC('NTiw')] = true, -- Northrend Icy Tree Wall
  [FourCC('NTtw')] = true, -- Northrend Tree Wall
  [FourCC('OTtw')] = true, -- Outland Tree Wall
  [FourCC('ZTtw')] = true, -- Ruins Tree Wall
  [FourCC('Ytsc')] = true, -- Scorched Tree Wall
  [FourCC('Yts1')] = true, -- Silvermoon Tree
  [FourCC('WTst')] = true, -- Snowy Tree Wall
  [FourCC('LTlt')] = true, -- Summer Tree Wall
  [FourCC('GTsh')] = true, -- Underground Tree Wall
  [FourCC('VTlt')] = true, -- Village Tree Wall
  [FourCC('WTtw')] = true, -- Winter Tree Wall
  [FourCC('ATtc')] = true, -- Ashenvale Canopy Tree
  [FourCC('BTtc')] = true, -- Barrens Canopy Tree
  [FourCC('CTtc')] = true, -- Felwood Canopy Tree
  [FourCC('ITtc')] = true, -- Icecrown Canopy Tree
  [FourCC('NTtc')] = true, -- Northrend Canopy Tree
  [FourCC('ZTtc')] = true, -- Ruins Canopy Tree
}

---@param d destructable
---return boolean
local function isTree(d)
    return trees[GetDestructableTypeId(d)] or false
end

-- Verifica árvores perto da unidade e liga/desliga a invisibilidade conforme o resultado
local function UpdateCamouflage(u)
    local x = GetUnitX(u)
    local y = GetUnitY(u)
    local treeFound = false
 
    local r = Rect(x - CHECK_RADIUS, y - CHECK_RADIUS, x + CHECK_RADIUS, y + CHECK_RADIUS)
    EnumDestructablesInRect(r, nil, function()
        local d = GetEnumDestructable()
        print("Detectado árvore - " .. GetDestructableTypeId(d) .. " - x: " .. GetDestructableX(d) .. "y:" .. GetDestructableY(d))

        if isTree(d) and GetDestructableLife(d) > 0 then
            treeFound = true
            print('Live tree found!')
            print("Vida: " .. GetDestructableLife(d))
        end
    end)

    RemoveRect(r)
 
    if treeFound then
        local timeNow = TimerGetElapsed(checkTimer)
        local uHandleId = GetHandleId(u)

        nearTreeTime[uHandleId] = (nearTreeTime[uHandleId] or 0) + CHECK_INTERVAL
        print("nearTreeTime[u]: " .. nearTreeTime[uHandleId])

        local nCLevel = GetUnitAbilityLevel(u, NATURAL_CAMOUFLAGE_ID)
        local delay = cammouflageDelay[nCLevel]
        if delay == nil then -- debug print
            print("Delay é nulo! Não deveria acontecer.")
            delay = 0
        end
        if nearTreeTime[uHandleId] >= delay  and GetUnitAbilityLevel(u, NC_INVISIBILITY) == 0 then
            UnitAddAbility(u, NC_INVISIBILITY)
            UnitMakeAbilityPermanent(u, true, NC_INVISIBILITY)
        elseif nearTreeTime[uHandleId] < delay then
            print("Delay de " .. delay .."  para nível " .. nCLevel .. "não ultrapassado para ficar invisível.")
        end

    else
        print('No live tree found!')
        nearTreeTime[GetHandleId(u)] = 0
        if GetUnitAbilityLevel(u, NC_INVISIBILITY) > 0 then
            UnitRemoveAbility(u, NC_INVISIBILITY)
        end
    end
end


-- Roda só enquanto houver unidades no grupo; verifica se o buff ainda está ativo
local function CheckActiveUnits()
    if BlzGroupGetSize(activeUnits) == 0 then
        PauseTimer(checkTimer)
        return
    end

    local toRemove = {}

    ForGroup(activeUnits, function()
        local u = GetEnumUnit()
        if not UnitAlive(u) or GetUnitAbilityLevel(u, BUFF_ID) == 0 then
            table.insert(toRemove, u)
            return
        end
        UpdateCamouflage(u)
    end)

    for _, u in ipairs(toRemove) do
        local uHandleId = GetHandleId(u)
        nearTreeTime[uHandleId] = nil
        UnitRemoveAbility(u, NC_INVISIBILITY)
        GroupRemoveUnit(activeUnits, u)
        print(GetUnitName(u) .. " saiu do grupo (buff sumiu ou morreu). Total: " .. BlzGroupGetSize(activeUnits))

        if BlzGroupGetSize(activeUnits) == 0 then
            PauseTimer(checkTimer)
        end
    end
end

local function OnAbilityOn()
    local ok, err = pcall(function()
        local u = GetTriggerUnit()
        local castId = GetSpellAbilityId()
        print("EVENTO OnAbilityOn: " .. GetUnitName(u) .. " castId=" .. castId .. " match=" .. tostring(castId == NATURAL_CAMOUFLAGE_ID) .. " jaNoGrupo=" .. tostring(IsUnitInGroup(u, activeUnits)))

        if GetSpellAbilityId() == NATURAL_CAMOUFLAGE_ID then
            nearTreeTime[GetHandleId(u)] = 0.0
            if not IsUnitInGroup(u, activeUnits) then
                GroupAddUnit(activeUnits, u)
                print(GetUnitName(u) .. " ativou. Total no grupo: " .. BlzGroupGetSize(activeUnits))

                if BlzGroupGetSize(activeUnits) == 1 then
                    TimerStart(checkTimer, CHECK_INTERVAL, true, CheckActiveUnits)
                end
            end
        end
    end)
    if not ok then
        print("|cffff0000ERRO:|r " .. tostring(err))
    end
end

local function OnAbilityOff()
    local ok, err = pcall(function()
        local u = GetTriggerUnit()
        local orderId = GetIssuedOrderId()
        print("EVENTO OnAbilityOff: " .. GetUnitName(u) .. " orderId=" .. orderId .. " match=" .. tostring(orderId == OrderId("unimmolation")))

        if GetIssuedOrderId() == OrderId("unimmolation") then
            nearTreeTime[GetHandleId(u)] = nil
            if IsUnitInGroup(u, activeUnits) then
                UnitRemoveAbility(u, NC_INVISIBILITY)
                GroupRemoveUnit(activeUnits, u)
                print(GetUnitName(u) .. " desativou manualmente. Total: " .. BlzGroupGetSize(activeUnits))

                if BlzGroupGetSize(activeUnits) == 0 then
                    PauseTimer(checkTimer)
                end
            end
        end
    end)
    if not ok then
        print("|cffff0000ERRO:|r " .. tostring(err))
    end
end

local function Init()
    checkTimer = CreateTimer()

    local castTrigger = CreateTrigger()
    TriggerRegisterAnyUnitEventBJ(castTrigger, EVENT_PLAYER_UNIT_SPELL_EFFECT)
    TriggerAddAction(castTrigger, OnAbilityOn)

    local orderTrigger = CreateTrigger()
    TriggerRegisterAnyUnitEventBJ(orderTrigger, EVENT_PLAYER_UNIT_ISSUED_ORDER)
    TriggerAddAction(orderTrigger, OnAbilityOff)
end

Init()