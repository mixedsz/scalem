local isMenuOpen          = false
local currentScale        = Config.DefaultScale
local savedScale          = Config.DefaultScale
local weaponNotifCooldown = false

-- ─────────────────────────────────────────────────────────────────────
--  SCALE APPLICATION
--
--  FiveM uses its OWN hash scheme for CFX-registered natives, NOT the
--  standard Jenkins/joaat hash.  Backtick syntax (`SET_ENTITY_SCALE`)
--  gives the Jenkins hash, which is wrong → InvokeNative runs ok=true
--  but silently does nothing.  We probe every known possible hash/alias
--  at startup and cache whichever one actually verifies via GetEntityScale.
-- ─────────────────────────────────────────────────────────────────────

local _scaleNative = nil   -- cached working hash or false if none found

local function ProbeScaleNative()
    if SetEntityScale then
        _scaleNative = 'builtin'
        print('[ScaleM] Scale native: using SetEntityScale (builtin)')
        return
    end

    local ped       = PlayerPedId()
    local testScale = 1.05          -- small nudge to verify
    local restored  = false

    -- Every hash/alias ever documented or cited for this native
    local candidates = {
        { label = 'SET_ENTITY_SCALE (joaat)',  hash = `SET_ENTITY_SCALE`  },
        { label = 'SET_PED_SCALE (joaat)',     hash = `SET_PED_SCALE`     },
        { label = 'N_0x025D59F9',             hash = 0x025D59F9          },
        { label = 'N_0xCAAFD5E9',             hash = 0xCAAFD5E9          },
        { label = 'N_0x3F28DFB4',             hash = 0x3F28DFB4          },
        { label = 'N_0x0089EF3B',             hash = 0x0089EF3B          },
    }

    for _, c in ipairs(candidates) do
        -- Apply test scale
        pcall(Citizen.InvokeNative, c.hash, ped, testScale + 0.0)
        -- Verify via GetEntityScale if available
        if GetEntityScale then
            local actual = GetEntityScale(ped)
            if actual and math.abs(actual - testScale) < 0.01 then
                _scaleNative = c.hash
                print('[ScaleM] Scale native found: ' .. c.label)
                -- Restore default while we remember the working hash
                Citizen.InvokeNative(c.hash, ped, Config.DefaultScale + 0.0)
                restored = true
                break
            end
        end
    end

    if not _scaleNative then
        -- GetEntityScale unavailable — can't verify, try applying anyway
        -- and just use the first candidate that doesn't error
        for _, c in ipairs(candidates) do
            local ok = pcall(Citizen.InvokeNative, c.hash, ped, testScale + 0.0)
            if ok then
                _scaleNative = c.hash
                print('[ScaleM] Scale native unverified (GetEntityScale missing), using: ' .. c.label)
                pcall(Citizen.InvokeNative, c.hash, ped, Config.DefaultScale + 0.0)
                restored = true
                break
            end
        end
    end

    if not _scaleNative then
        _scaleNative = false
        print('[ScaleM] !! No scale native found on this server.')
        print('[ScaleM] !! Update FiveM server artifacts to fix: https://runtime.fivem.net/artifacts/fivem/build_server_windows/master/')
    end
end

local function ApplyScale(ped, scale)
    if not DoesEntityExist(ped) then return end

    if SetEntityScale then
        SetEntityScale(ped, scale)
        return
    end

    if _scaleNative == nil then
        -- probe not run yet (called too early), skip silently
        return
    end

    if _scaleNative == false then
        -- already determined nothing works
        return
    end

    pcall(Citizen.InvokeNative, _scaleNative, ped, scale + 0.0)
end

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

-- Apply a scale for any networked player (server-broadcast)
RegisterNetEvent('ScaleM:SyncScale', function(serverId, scale)
    local myServerId = GetPlayerServerId(PlayerId())

    for _, player in ipairs(GetActivePlayers()) do
        if GetPlayerServerId(player) == serverId then
            local ped = GetPlayerPed(player)
            if DoesEntityExist(ped) then ApplyScale(ped, scale) end
            break
        end
    end

    if serverId == myServerId then
        currentScale = scale
        savedScale   = scale
        ApplyScale(PlayerPedId(), scale)
    end
end)

-- Server notification relay
RegisterNetEvent('ScaleM:Notify', function(msg, notifType)
    Notify(msg, notifType)
end)

-- Server tells client to open NUI
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
    print(('[ScaleM] confirm: scale=%.3f  native=%s'):format(scale, tostring(_scaleNative)))
    currentScale = scale
    savedScale   = scale

    pcall(ApplyScale, PlayerPedId(), scale)
    TriggerServerEvent('ScaleM:SaveScale', scale)
end)

RegisterNUICallback('reset', function(_, cb)
    isMenuOpen = false
    SetNuiFocus(false, false)
    cb({})

    currentScale = Config.DefaultScale
    savedScale   = Config.DefaultScale
    pcall(ApplyScale, PlayerPedId(), Config.DefaultScale)
    TriggerServerEvent('ScaleM:ResetScale')
end)

RegisterNUICallback('close', function(_, cb)
    isMenuOpen = false
    SetNuiFocus(false, false)
    cb({})

    local revert = savedScale
    currentScale = revert
    pcall(ApplyScale, PlayerPedId(), revert)
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
                local weapon = GetSelectedPedWeapon(ped)
                if weapon ~= GetHashKey('WEAPON_UNARMED') then
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
--  PED CHANGE DETECTION  (respawn, model swap)
-- ─────────────────────────────────────────────────────────────────────
CreateThread(function()
    local lastPed = PlayerPedId()
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        if ped ~= lastPed then
            lastPed = ped
            Wait(800)
            ApplyScale(ped, currentScale)
        end
    end
end)

-- ─────────────────────────────────────────────────────────────────────
--  STARTUP — probe scale native then restore saved scale
-- ─────────────────────────────────────────────────────────────────────
CreateThread(function()
    Wait(5000)           -- wait for ped to fully load
    ProbeScaleNative()   -- find working hash once, cache it
    Wait(200)
    TriggerServerEvent('ScaleM:RequestSavedScale')
end)
