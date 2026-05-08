local isMenuOpen          = false
local currentScale        = Config.DefaultScale
local savedScale          = Config.DefaultScale
local weaponNotifCooldown = false

-- ─────────────────────────────────────────────────────────────────────
--  SCALE APPLICATION
-- ─────────────────────────────────────────────────────────────────────
local function ApplyScale(ped, scale)
    if not DoesEntityExist(ped) then return end
    if SetEntityScale then
        SetEntityScale(ped, scale)
    else
        -- Backtick hash syntax is resolved by FiveM at compile time
        pcall(function()
            Citizen.InvokeNative(`SET_ENTITY_SCALE`, ped, scale)
        end)
    end
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
    -- Release focus and respond immediately so mouse is NEVER stuck
    isMenuOpen = false
    SetNuiFocus(false, false)
    cb({})

    local scale = tonumber(data.scale)
    if not scale then return end
    scale = math.max(Config.MinScale, math.min(Config.MaxScale, scale))
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
--  INITIAL SCALE RESTORE ON SPAWN
-- ─────────────────────────────────────────────────────────────────────
CreateThread(function()
    Wait(5000)
    TriggerServerEvent('ScaleM:RequestSavedScale')
end)
