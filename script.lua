-- Configuração: Substitua pelos IDs do seu Object Editor
local BUFF_ACTIVATOR  = FourCC('A000') -- ID do BUFF (aba "Buffs", NÃO a habilidade) do Immolation
local ABI_INVISIBILITY = FourCC('A001') -- ID da Invisibilidade Permanente
local CHECK_RADIUS     = 250.0          -- Distância até a árvore

-- Variáveis de controle do sistema
local activeUnits = CreateGroup()
local loopTimer = nil

local function dbg(msg)
    print("[Camuflagem] " .. msg)
end

-- Esta é a função periódica que verifica as árvores
local function TrackForestCamouflage()
    dbg("Tick do timer. Unidades no grupo: " .. BlzGroupGetSize(activeUnits))

    if BlzGroupGetSize(activeUnits) == 0 then
        dbg("Grupo vazio, pausando timer.")
        PauseTimer(loopTimer)
        return
    end

    ForGroup(activeUnits, function()
        local u = GetEnumUnit()
        local buffLevel = GetUnitAbilityLevel(u, BUFF_ACTIVATOR)
        dbg(GetUnitName(u) .. " -> nível do buff: " .. buffLevel)

        if not UnitAlive(u) or buffLevel == 0 then
            dbg(GetUnitName(u) .. " perdeu o buff ou morreu. Removendo do grupo.")
            UnitRemoveAbility(u, ABI_INVISIBILITY)
            GroupRemoveUnit(activeUnits, u)

            if BlzGroupGetSize(activeUnits) == 0 then
                PauseTimer(loopTimer)
            end
            return
        end

        local x = GetUnitX(u)
        local y = GetUnitY(u)
        local treeFound = false

        local r = Rect(x - CHECK_RADIUS, y - CHECK_RADIUS, x + CHECK_RADIUS, y + CHECK_RADIUS)
        EnumDestructablesInRect(r, nil, function()
            local d = GetEnumDestructable()
            if IsDestructableTree(d) and GetDestructableLife(d) > 0 then
                treeFound = true
            end
        end)
        RemoveRect(r)

        dbg(GetUnitName(u) .. " -> árvore encontrada perto? " .. tostring(treeFound))

        if treeFound then
            if GetUnitAbilityLevel(u, ABI_INVISIBILITY) == 0 then
                dbg(GetUnitName(u) .. " ficando invisível.")
                UnitAddAbility(u, ABI_INVISIBILITY)
                UnitMakeAbilityPermanent(u, true, ABI_INVISIBILITY)
            end
        else
            if GetUnitAbilityLevel(u, ABI_INVISIBILITY) > 0 then
                dbg(GetUnitName(u) .. " ficando visível de novo.")
                UnitRemoveAbility(u, ABI_INVISIBILITY)
            end
        end
    end)
end

-- Função disparada sempre que uma magia é conjurada
local function OnSpellCast()
    local u = GetTriggerUnit()
    dbg(GetUnitName(u) .. " conjurou algo: " .. GetSpellName())

    TimerStart(CreateTimer(), 0.0, false, function()
        local t = GetExpiredTimer()
        local buffLevel = GetUnitAbilityLevel(u, BUFF_ACTIVATOR)
        dbg("(pós-cast) " .. GetUnitName(u) .. " -> nível do buff: " .. buffLevel)

        if buffLevel > 0 then
            if not IsUnitInGroup(u, activeUnits) then
                dbg(GetUnitName(u) .. " adicionada ao grupo de rastreamento.")
                GroupAddUnit(activeUnits, u)

                if BlzGroupGetSize(activeUnits) == 1 then
                    dbg("Primeira unidade ativa, iniciando timer periódico.")
                    TimerStart(loopTimer, 0.50, true, TrackForestCamouflage)
                end
            end
        else
            if IsUnitInGroup(u, activeUnits) then
                dbg(GetUnitName(u) .. " removida do grupo (buff sumiu).")
                UnitRemoveAbility(u, ABI_INVISIBILITY)
                GroupRemoveUnit(activeUnits, u)

                if BlzGroupGetSize(activeUnits) == 0 then
                    PauseTimer(loopTimer)
                end
            end
        end

        DestroyTimer(t)
    end)
end

-- Inicialização do Script
function InitForestCamouflage()
    loopTimer = CreateTimer()

    local t = CreateTrigger()
    TriggerRegisterAnyUnitEventBJ(t, EVENT_PLAYER_UNIT_SPELL_EFFECT)
    TriggerAddAction(t, OnSpellCast)

    dbg("Sistema inicializado.")
end

function InitTrig_ForestCamouflage()
    InitForestCamouflage()
end