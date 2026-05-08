local isMenuOpen          = false
local currentScale        = Config.DefaultScale
local savedScale          = Config.DefaultScale
local weaponNotifCooldown = false

-- ─────────────────────────────────────────────────────────────────────
--  SCALE NATIVE  –  resolved once at startup
-- ─────────────────────────────────────────────────────────────────────
--
--  SetEntityScale is a CFX-registered native added in newer FiveM artifacts.
--  Its internal hash is NOT the Jenkins/joaat hash of its name, so backtick
--  literals like `SET_ENTITY_SCALE` are wrong.  We probe the handful of
--  hashes that have actually been observed to work in the wild.
--
--  Crucially: GTA resets entity properties between ticks.  Scale MUST be
--  reapplied every frame in a persistent thread – applying it once then
--  moving on is why "nothing changes".

local _scaleHash   = nil    -- numeric hash that works, or false if none
local _scaleReady  = false  -- true once probe has finished

-- All known hashes for the entity-scale native across FiveM builds
local HASH_CANDIDATES = {
    { label = 'N_0xCAAFD5E9',            hash = 0xCAAFD5E9 },
    { label = 'N_0x025D59F9',            hash = 0x025D59F9 },
    { label = 'N_0x3F28DFB4',            hash = 0x3F28DFB4 },
    { label = 'N_0x0089EF3B',            hash = 0x0089EF3B },
    { label = 'SET_ENTITY_SCALE(joaat)', hash = `SET_ENTITY_SCALE` },
    { label = 'SET_PED_SCALE(joaat)',    hash = `SET_PED_SCALE`    },
}

-- Call the raw native (float must be explicit to avoid int truncation)
local function RawScale(ped, scale)
    if SetEntityScale then
        SetEntityScale(ped, scale)
    elseif _scaleHash then
        Citizen.InvokeNative(_scaleHash, ped, scale * 1.0)
    end
end

-- Probe: try each hash and verify with GetEntityScale; if that's also
-- missing, use a bone-position delta as an indirect signal instead.
local function ProbeScaleNative()
    if SetEntityScale then
        _scaleReady = true
        print('[ScaleM] Scale native: SetEntityScale (builtin) ✓')
        return
    end

    local ped = PlayerPedId()
    while not DoesEntityExist(ped) do Wait(500) ped = PlayerPedId() end

    -- Get a baseline bone position we can compare after applying test scale
    local boneIdx  = GetEntityBoneIndexByName(ped, 'IK_Head')
    local bx0, by0, bz0 = GetEntityBoneCoords(ped, boneIdx, false)

    local TEST = 1.35   -- obvious enough to detect a bone-position shift

    for _, c in ipairs(HASH_CANDIDATES) do
        -- Apply test scale
        pcall(Citizen.InvokeNative, c.hash, ped, TEST * 1.0)
        Wait(50)   -- let the game engine tick once

        -- Verify method 1: GetEntityScale (if it exists)
        if GetEntityScale then
            local actual = GetEntityScale(ped)
            if actual and math.abs(actual - TEST) < 0.05 then
                _scaleHash  = c.hash
                _scaleReady = true
                Citizen.InvokeNative(c.hash, ped, Config.DefaultScale * 1.0)
                print('[ScaleM] Scale native confirmed via GetEntityScale: ' .. c.label)
                return
            end
        end

        -- Verify method 2: head bone moved upward (ped is taller)
        local bx1, by1, bz1 = GetEntityBoneCoords(ped, boneIdx, false)
        if bz1 - bz0 > 0.05 then
            _scaleHash  = c.hash
            _scaleReady = true
            Citizen.InvokeNative(c.hash, ped, Config.DefaultScale * 1.0)
            print('[ScaleM] Scale native confirmed via bone delta: ' .. c.label)
            return
        end
    end

    -- Nothing verified – but we still cache the first non-erroring hash
    -- and rely on the per-tick thread to make it stick if any hash helps
    for _, c in ipairs(HASH_CANDIDATES) do
        local ok = pcall(Citizen.InvokeNative, c.hash, ped, TEST * 1.0)
        if ok then
            pcall(Citizen.InvokeNative, c.hash, ped, Config.DefaultScale * 1.0)
            _scaleHash  = c.hash
            _scaleReady = true
            print('[ScaleM] Scale native unverified, using best-effort: ' .. c.label)
            print('[ScaleM] If scale still does not change, update your FiveM server:')
            print('[ScaleM] https://runtime.fivem.net/artifacts/fivem/build_server_windows/master/')
            return
        end
    end

    _scaleHash  = false
    _scaleReady = true
    print('[ScaleM] !! No scale native found – server artifacts must be updated.')
    print('[ScaleM] https://runtime.fivem.net/artifacts/fivem/build_server_windows/master/')
end

-- ─────────────────────────────────────────────────────────────────────
--  PER-TICK SCALE ENFORCEMENT
--  GTA resets entity properties each simulation step.  Continuously
--  reapplying the scale on every frame is the only reliable approach.
-- ─────────────────────────────────────────────────────────────────────
CreateThread(function()
    while true do
        if _scaleReady and math.abs(currentScale - Config.DefaultScale) > 0.001 then
            local ped = PlayerPedId()
            if DoesEntityExist(ped) then
                RawScale(ped, currentScale)
            end
            Wait(0)
        else
            Wait(200)
        end
    end
end)

-- ─────────────────────────────────────────────────────────────────────
--  NOTIFICATION
-- ─────────────────────────────────────────────────────────────────────
local function Notify(msg, notifType)
    if Config.Framework == 'ESX' then
        local ESX = exports['es_extended']:getSharedObject()
        ESX.ShowNotification((notifType == 'error' and '~r~' or '~g~') .. msg)
    elseif Config.Framework == 'QB' then
        local QBCore = exports['qb-core']:GetCoreObject()
        QBCore.Functions.Notify(msg, notifType or 'primary')
    elseif Config.Framework == 'Qbox' then
        local QBX = exports['qbx_core']:GetCoreObject()
        QBX.Functions.Notify(msg, notifType or 'inform')
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(msg)
        EndTextCommandThefeedPostTicker(false, true)
    end
end

-- ─────────────────────────────────────────────────────────────────────
--  SERVER EVENTS
-- ─────────────────────────────────────────────────────────────────────

RegisterNetEvent('ScaleM:SyncScale', function(serverId, scale)
    local myServerId = GetPlayerServerId(PlayerId())

    for _, player in ipairs(GetActivePlayers()) do
        if GetPlayerServerId(player) == serverId then
            local ped = GetPlayerPed(player)
            if DoesEntityExist(ped) then RawScale(ped, scale) end
            break
        end
    end

    if serverId == myServerId then
        currentScale = scale
        savedScale   = scale
        RawScale(PlayerPedId(), scale)
    end
end)

RegisterNetEvent('ScaleM:Notify', function(msg, notifType)
    Notify(msg, notifType)
end)

RegisterNetEvent('ScaleM:OpenMenu', function(scale)
    if Config.GenderRestriction then
        local ped    = PlayerPedId()
        local isMale = IsPedMale(ped)
        if Config.GenderRestriction == 'male' and not isMale then
            Notify('Only male characters can use the Scale Menu.', 'error')
            return
        end
        if Config.GenderRestriction == 'female' and isMale then
            Notify('Only female characters can use the Scale Menu.', 'error')
            return
        end
    end

    currentScale = scale
    savedScale   = scale
    isMenuOpen   = true

    SetNuiFocus(true, true)
    SendNUIMessage({
        type         = 'openMenu',
        scale        = currentScale,
        minScale     = Config.MinScale,
        maxScale     = Config.MaxScale,
        defaultScale = Config.DefaultScale,
        themeColor   = Config.ThemeColor,
    })
end)

-- ─────────────────────────────────────────────────────────────────────
--  NUI CALLBACKS
-- ─────────────────────────────────────────────────────────────────────

RegisterNUICallback('confirm', function(data, cb)
    isMenuOpen = false
    SetNuiFocus(false, false)
    cb({})

    local scale = tonumber(data.scale)
    if not scale then return end
    scale = math.max(Config.MinScale, math.min(Config.MaxScale, scale))
    currentScale = scale
    savedScale   = scale

    RawScale(PlayerPedId(), scale)
    TriggerServerEvent('ScaleM:SaveScale', scale)
    print(('[ScaleM] confirm → scale=%.3f  hash=%s'):format(scale, tostring(_scaleHash)))
end)

RegisterNUICallback('reset', function(_, cb)
    isMenuOpen = false
    SetNuiFocus(false, false)
    cb({})

    currentScale = Config.DefaultScale
    savedScale   = Config.DefaultScale
    RawScale(PlayerPedId(), Config.DefaultScale)
    TriggerServerEvent('ScaleM:ResetScale')
end)

RegisterNUICallback('close', function(_, cb)
    isMenuOpen = false
    SetNuiFocus(false, false)
    cb({})

    currentScale = savedScale
    RawScale(PlayerPedId(), savedScale)
end)

-- ─────────────────────────────────────────────────────────────────────
--  COMMAND
-- ─────────────────────────────────────────────────────────────────────
RegisterCommand(Config.Command, function()
    if isMenuOpen then return end
    TriggerServerEvent('ScaleM:RequestOpen')
end, false)

-- ─────────────────────────────────────────────────────────────────────
--  WEAPON BLOCKING
-- ─────────────────────────────────────────────────────────────────────
if Config.BlockWeapons then
    CreateThread(function()
        while true do
            Wait(0)
            local ped = PlayerPedId()
            if math.abs(currentScale - Config.DefaultScale) > 0.005 then
                if GetSelectedPedWeapon(ped) ~= GetHashKey('WEAPON_UNARMED') then
                    SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
                    if not weaponNotifCooldown then
                        weaponNotifCooldown = true
                        Notify('Weapons are disabled while your character is scaled.', 'error')
                        SetTimeout(5000, function() weaponNotifCooldown = false end)
                    end
                end
            else
                Wait(500)
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────
--  PED CHANGE DETECTION  (respawn / model swap)
-- ─────────────────────────────────────────────────────────────────────
CreateThread(function()
    local lastPed = PlayerPedId()
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        if ped ~= lastPed then
            lastPed = ped
            Wait(800)
            RawScale(ped, currentScale)
        end
    end
end)

-- ─────────────────────────────────────────────────────────────────────
--  STARTUP
-- ─────────────────────────────────────────────────────────────────────
CreateThread(function()
    Wait(5000)
    ProbeScaleNative()
    Wait(100)
    TriggerServerEvent('ScaleM:RequestSavedScale')
end)
