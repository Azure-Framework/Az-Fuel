local RESOURCE_NAME = GetCurrentResourceName()
local debug = Config.Debug

local function dprint(...)
    if not debug then return end
    local args = { ... }
    for i = 1, #args do
        args[i] = tostring(args[i])
    end
    print(("^3[%s C]^7 %s"):format(RESOURCE_NAME, table.concat(args, " ")))
end

---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------

local currentVehicle      = nil

local hoseObj             = nil      -- nozzle prop entity
local hosePumpPos         = nil      -- vector3 position of pump we grabbed from
local hosePumpEntity      = nil      -- actual pump entity (optional)
local hosePumpAnchorObj   = nil      -- hidden object we anchor rope to
local hoseRopeId          = nil      -- rope handle
local hoseVehicle         = nil      -- vehicle entity attached to
local hoseState           = "IDLE"   -- "IDLE" | "HELD" | "ATTACHED" | "FUELING"

local sessionCost         = 0.0      -- session cost ($)
local sessionLiters       = 0.0      -- session liters pumped

-- current hologram screen coords (0–1)
local uiSX                = 0.5
local uiSY                = 0.5

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------

local function distance(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function helpText(msg)
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

local function loadModel(hash)
    if not IsModelValid(hash) then
        dprint("Model invalid:", hash)
        return false
    end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then
            dprint("Model failed to load in time:", hash)
            return false
        end
        Wait(0)
    end
    return true
end

local function ensureFuelLevel(veh)
    if not DoesEntityExist(veh) then return end
    local fuel = GetVehicleFuelLevel(veh)
    if fuel <= 0.0 then
        fuel = 75.0
        SetVehicleFuelLevel(veh, fuel)
    end
end

-- EV detection – uses native _GET_IS_VEHICLE_ELECTRIC with optional fallback list
local function isElectricVehicle(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        return false
    end

    local model = GetEntityModel(veh)

    if GetIsVehicleElectric ~= nil then
        if GetIsVehicleElectric(model) then
            return true
        end
    end

    if Config.ElectricModels then
        for _, hash in ipairs(Config.ElectricModels) do
            if hash == model then
                return true
            end
        end
    end

    return false
end

---------------------------------------------------------------------
-- PUMP DETECTION (by PROP)
---------------------------------------------------------------------

local function findClosestPump(maxDist)
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    maxDist = maxDist or Config.MaxPumpDistance

    local bestPos, bestDist, bestEnt

    for _, model in ipairs(Config.PumpModels) do
        local obj = GetClosestObjectOfType(
            pCoords.x, pCoords.y, pCoords.z,
            maxDist + 5.0,
            model, false, false, false
        )
        if obj ~= 0 and DoesEntityExist(obj) then
            local oCoords = GetEntityCoords(obj)
            local dist = distance(pCoords, oCoords)
            if dist <= maxDist and (not bestDist or dist < bestDist) then
                bestPos  = oCoords
                bestDist = dist
                bestEnt  = obj
            end
        end
    end

    return bestPos, bestDist, bestEnt
end

---------------------------------------------------------------------
-- ROPE (tow / cargobob-style)
---------------------------------------------------------------------

local function deleteRope()
    if hoseRopeId and hoseRopeId ~= 0 then
        DeleteRope(hoseRopeId)
    end
    hoseRopeId = nil

    if hosePumpAnchorObj and DoesEntityExist(hosePumpAnchorObj) then
        DeleteObject(hosePumpAnchorObj)
    end
    hosePumpAnchorObj = nil
end

local function createRope()
    deleteRope()
    if not Config.DrawHoseRope then return end
    if not hosePumpPos or not hoseObj or not DoesEntityExist(hoseObj) then return end

    local anchorModel = `prop_weight_15k`
    if not loadModel(anchorModel) then return end

    local pumpAnchorPos = hosePumpPos + vector3(0.0, 0.0, 1.0)
    hosePumpAnchorObj = CreateObject(anchorModel, pumpAnchorPos.x, pumpAnchorPos.y, pumpAnchorPos.z, false, false, false)
    SetEntityVisible(hosePumpAnchorObj, false, false)
    FreezeEntityPosition(hosePumpAnchorObj, true)

    RopeLoadTextures()

    local hosePos = GetEntityCoords(hoseObj)
    local length  = distance(pumpAnchorPos, hosePos) + 1.0

    hoseRopeId = AddRope(
        pumpAnchorPos.x, pumpAnchorPos.y, pumpAnchorPos.z,
        0.0, 0.0, 0.0,
        length,
        4,
        length,
        0.5,
        false, false, true,
        1.0,
        false,
        0
    )

    if hoseRopeId and hoseRopeId ~= 0 then
        AttachEntitiesToRope(
            hoseRopeId,
            hosePumpAnchorObj, hoseObj,
            pumpAnchorPos.x, pumpAnchorPos.y, pumpAnchorPos.z,
            hosePos.x, hosePos.y, hosePos.z,
            length,
            false, false,
            nil, nil
        )
        dprint("Created hose rope with id", hoseRopeId)
    else
        dprint("Failed to create hose rope")
        deleteRope()
    end
end

---------------------------------------------------------------------
-- HOSE HANDLING
---------------------------------------------------------------------

local function deleteHose()
    if hoseObj and DoesEntityExist(hoseObj) then
        DeleteObject(hoseObj)
    end
    hoseObj        = nil
    hosePumpPos    = nil
    hosePumpEntity = nil
    hoseVehicle    = nil
    hoseState      = "IDLE"
    sessionCost    = 0.0
    sessionLiters  = 0.0
    deleteRope()
    SendNUIMessage({ action = "fuel_close" })
end

local function attachHoseToPlayer(pumpPos, pumpEnt)
    if hoseState ~= "IDLE" then return end
    local ped = PlayerPedId()
    if not loadModel(Config.HoseModel) then return end

    local spawnPos = pumpPos + vector3(0.0, 0.0, 1.0)
    local obj = CreateObject(Config.HoseModel, spawnPos.x, spawnPos.y, spawnPos.z, true, true, false)
    SetEntityCollision(obj, false, false)

    local handBone = GetPedBoneIndex(ped, 0x49D9) -- left hand
    AttachEntityToEntity(
        obj, ped, handBone,
        0.10, 0.02, 0.02,
        90.0, 40.0, 170.0,
        true, true, false, true, 1, true
    )

    hoseObj        = obj
    hosePumpPos    = pumpPos
    hosePumpEntity = pumpEnt
    hoseState      = "HELD"

    createRope()
    dprint("Hose picked up near pump", pumpPos.x, pumpPos.y, pumpPos.z)
end

local function attachHoseToVehicle(veh)
    if hoseState ~= "HELD" then return end
    if not hoseObj or not DoesEntityExist(hoseObj) then return end
    if not DoesEntityExist(veh) then return end

    DetachEntity(hoseObj, true, true)

    local capBone = GetEntityBoneIndexByName(veh, "petrolcap")
    if capBone == -1 then
        capBone = GetEntityBoneIndexByName(veh, "wheel_rr")
    end

    local offset = vector3(0.05, 0.0, 0.10)
    AttachEntityToEntity(
        hoseObj, veh, capBone,
        offset.x, offset.y, offset.z,
        0.0, 0.0, 0.0,
        true, true, false, true, 1, true
    )

    hoseVehicle = veh
    hoseState   = "ATTACHED"

    createRope()
    dprint("Hose attached to vehicle", veh)
end

local function returnHoseToPump()
    if hoseState ~= "HELD" then return end
    deleteHose()
    dprint("Hose returned to pump")
end

local function startFueling()
    if hoseState ~= "ATTACHED" then
        helpText("Attach the nozzle to the vehicle first.")
        return
    end
    if not hoseVehicle or not DoesEntityExist(hoseVehicle) then
        helpText("No vehicle to fuel/charge.")
        return
    end

    sessionCost   = 0.0
    sessionLiters = 0.0
    hoseState     = "FUELING"

    local fuel = GetVehicleFuelLevel(hoseVehicle)
    local ev   = isElectricVehicle(hoseVehicle)

    -- initial hologram position (will keep updating in a separate thread)
    local uiWorld = hosePumpPos + vector3(0.3, 0.0, 1.5)
    local onScreen; onScreen, uiSX, uiSY = GetScreenCoordFromWorldCoord(uiWorld.x, uiWorld.y, uiWorld.z)
    if not onScreen then
        uiSX, uiSY = 0.5, 0.5
    end

    SendNUIMessage({
        action = "fuel_open",
        fuel   = fuel,
        cost   = sessionCost,
        liters = sessionLiters,
        isEV   = ev,
        sx     = uiSX,
        sy     = uiSY
    })

    dprint("Fueling/charging started")
end

local function stopFueling()
    if hoseState ~= "FUELING" then return end

    local ped = PlayerPedId()

    if Config.UseBilling and sessionCost > 0.0 then
        local finalCost = math.floor(sessionCost + 0.5)
        TriggerServerEvent("az_fuelpump:chargeFuelFinal", finalCost)
        dprint(("Sent final fuel/charge cost to server: $%d"):format(finalCost))
    end
    sessionCost   = 0.0
    sessionLiters = 0.0

    SendNUIMessage({ action = "fuel_close" })

    if hoseObj and DoesEntityExist(hoseObj) and hoseVehicle and DoesEntityExist(hoseVehicle) then
        DetachEntity(hoseObj, true, true)

        local handBone = GetPedBoneIndex(ped, 0x49D9)
        AttachEntityToEntity(
            hoseObj, ped, handBone,
            0.10, 0.02, 0.02,
            90.0, 40.0, 170.0,
            true, true, false, true, 1, true
        )

        hoseState   = "HELD"
        hoseVehicle = nil
        createRope()
        dprint("Fueling/charging stopped, hose back in hand")
    else
        deleteHose()
    end
end

---------------------------------------------------------------------
-- NEAREST VEHICLE
---------------------------------------------------------------------

local function getClosestVehicle(maxDist)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    maxDist = maxDist or Config.MaxVehicleDistance

    local veh = GetClosestVehicle(pos.x, pos.y, pos.z, maxDist, 0, 70)
    if veh ~= 0 and DoesEntityExist(veh) then
        local dist = distance(pos, GetEntityCoords(veh))
        return veh, dist
    end

    return nil, -1.0
end

---------------------------------------------------------------------
-- FUEL TICK (driving)
---------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(Config.FuelTickInterval)

        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            if GetPedInVehicleSeat(veh, -1) == ped then
                currentVehicle = veh
                ensureFuelLevel(veh)

                local speed = GetEntitySpeed(veh) * 3.6 -- km/h
                local fuel  = GetVehicleFuelLevel(veh)

                local drain = Config.FuelDrainIdle
                if speed > 2.0 then
                    drain = Config.FuelDrainDriving
                end
                if speed > 80.0 then
                    drain = Config.FuelDrainHighSpeed
                end

                local seconds = Config.FuelTickInterval / 1000.0
                fuel = fuel - (drain * seconds)

                if fuel <= 0.0 then
                    fuel = 0.0
                    SetVehicleEngineOn(veh, false, false, true)
                end

                SetVehicleFuelLevel(veh, fuel)
            end
        else
            currentVehicle = nil
        end
    end
end)

---------------------------------------------------------------------
-- HUD (minimap fuel/charge bar)
---------------------------------------------------------------------

local function getHudVehicle()
    if hoseVehicle and DoesEntityExist(hoseVehicle) then
        return hoseVehicle
    end
    if currentVehicle and DoesEntityExist(currentVehicle) then
        return currentVehicle
    end
    return nil
end

local function drawFuelHud()
    if not Config.EnableHUD then return end
    if hoseState == "FUELING" then return end -- NUI handles fueling UI

    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return end

    local veh = getHudVehicle()
    if not veh then return end

    local fuel = GetVehicleFuelLevel(veh)
    if fuel < 0.0 then fuel = 0.0 end
    if fuel > Config.MaxFuel then fuel = Config.MaxFuel end

    local pct       = (fuel / Config.MaxFuel)
    local value     = math.floor(pct * 100.0 + 0.5)
    local isEV      = isElectricVehicle(veh)
    local labelName = isEV and "Charge" or "Fuel"

    -- 🔧 positioned further LEFT and DOWN under minimap
    local barW = 0.165
    local barH = 0.010
    local barX = 0.145 + (Config.HUD.offsetX or 0.0)  -- was 0.159
    local barY = 0.990 + (Config.HUD.offsetY or 0.0)  -- was ~0.982

    -- outer / inner bar
    DrawRect(barX, barY, barW + 0.006, barH + 0.006, 0, 0, 0, 180)
    DrawRect(barX, barY, barW,         barH,         20, 20, 20, 220)

    -- fill
    local fillW = barW * pct
    if fillW > 0.0 then
        local leftEdge = barX - barW / 2.0
        local fillX    = leftEdge + fillW / 2.0
        DrawRect(fillX, barY, fillW, barH, 90, 180, 255, 220)
    end

    -- centered label, no % sign
    local text = ("%s %d"):format(labelName, value)
    local textX = barX
    local textY = barY - 0.016

    SetTextFont(4)
    SetTextScale(0.28, 0.28)
    SetTextColour(255, 255, 255, 230)
    SetTextOutline()
    SetTextCentre(true)

    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(textX, textY)
end

CreateThread(function()
    while true do
        Wait(0)
        drawFuelHud()
    end
end)

---------------------------------------------------------------------
-- PUMP MARKERS + INTERACTION
---------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(0)

        local ped = PlayerPedId()
        local pedCoords = GetEntityCoords(ped)

        if Config.ShowPumpMarkers then
            local pumpPos, pumpDist = findClosestPump(30.0)
            if pumpPos and pumpDist < 30.0 then
                DrawMarker(
                    Config.PumpMarker.type,
                    pumpPos.x, pumpPos.y, pumpPos.z + 0.1,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    Config.PumpMarker.scale.x, Config.PumpMarker.scale.y, Config.PumpMarker.scale.z,
                    Config.PumpMarker.rgba[1], Config.PumpMarker.rgba[2],
                    Config.PumpMarker.rgba[3], Config.PumpMarker.rgba[4],
                    false, false, 2, false, nil, nil, false
                )
            end
        end

        if not IsPedInAnyVehicle(ped, false) then
            local pumpPos, _, pumpEnt = findClosestPump(Config.MaxPumpDistance)

            if hoseState == "IDLE" then
                if pumpPos then
                    helpText(("Press %s to pick up nozzle"):format(Config.Keys.Use))
                    if IsControlJustReleased(0, 38) then -- E
                        attachHoseToPlayer(pumpPos, pumpEnt)
                    end
                end

            elseif hoseState == "HELD" then
                if hosePumpPos and distance(pedCoords, hosePumpPos) <= Config.MaxPumpDistance then
                    helpText(("Press %s to hang up nozzle"):format(Config.Keys.Use))
                    if IsControlJustReleased(0, 38) then
                        returnHoseToPump()
                    end
                else
                    local veh, dist = getClosestVehicle(Config.MaxVehicleDistance)
                    if veh and dist <= Config.MaxVehicleDistance then
                        helpText(("Press %s to attach nozzle to vehicle"):format(Config.Keys.Use))
                        if IsControlJustReleased(0, 38) then
                            attachHoseToVehicle(veh)
                        end
                    else
                        helpText("Walk to a vehicle to attach the nozzle")
                    end
                end

            elseif hoseState == "ATTACHED" then
                local ev = hoseVehicle and isElectricVehicle(hoseVehicle)
                local action = ev and "start charging" or "start fueling"
                helpText(("Press %s to %s"):format(Config.Keys.Start, action))
                if IsControlJustReleased(0, 22) then -- SPACE
                    startFueling()
                end

            elseif hoseState == "FUELING" then
                local ev = hoseVehicle and isElectricVehicle(hoseVehicle)
                local action = ev and "stop charging" or "stop fueling"
                helpText(("Press %s to %s"):format(Config.Keys.Start, action))
                if IsControlJustReleased(0, 22) then
                    stopFueling()
                end
            end
        end
    end
end)

---------------------------------------------------------------------
-- 3D HOLOGRAM POSITION UPDATER
---------------------------------------------------------------------
-- Runs every frame while ATTACHED/FUELING to keep the panel stuck to the pump

CreateThread(function()
    while true do
        Wait(0)

        if hoseState == "ATTACHED" or hoseState == "FUELING" then
            if hosePumpPos then
                local uiWorld = hosePumpPos + vector3(0.3, 0.0, 1.5)
                local onScreen, sx, sy = GetScreenCoordFromWorldCoord(uiWorld.x, uiWorld.y, uiWorld.z)
                if onScreen then
                    -- only send when moved a bit to avoid spam
                    if math.abs(sx - uiSX) > 0.0005 or math.abs(sy - uiSY) > 0.0005 then
                        uiSX, uiSY = sx, sy
                        SendNUIMessage({
                            action = "fuel_pos",
                            sx     = uiSX,
                            sy     = uiSY
                        })
                    end
                end
            end
        else
            -- small sleep when nothing to do
            Wait(150)
        end
    end
end)

---------------------------------------------------------------------
-- FUELING / CHARGING LOOP (SMOOTH)
---------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(100) -- 10x per second for smooth bar

        if hoseState ~= "FUELING" then
            goto continue
        end

        if not hoseVehicle or not DoesEntityExist(hoseVehicle) then
            dprint("Fueling aborted: vehicle gone")
            helpText("Stopped: vehicle moved.")
            stopFueling()
            goto continue
        end

        if not hosePumpPos then
            dprint("Fueling aborted: pump position lost")
            helpText("Stopped: pump lost.")
            stopFueling()
            goto continue
        end

        local vehPos  = GetEntityCoords(hoseVehicle)
        local stretch = distance(hosePumpPos, vehPos)

        if stretch > Config.MaxHoseStretch then
            dprint("Fueling aborted: hose stretched too far", stretch)
            helpText("Stopped: too far from pump.")
            stopFueling()
            goto continue
        end

        local fuel = GetVehicleFuelLevel(hoseVehicle)
        if fuel >= Config.MaxFuel then
            local ev = isElectricVehicle(hoseVehicle)
            dprint("Full, stopping fueling/charging")
            helpText(ev and "Battery is full." or "Tank is full.")
            stopFueling()
            goto continue
        end

        local ev        = isElectricVehicle(hoseVehicle)
        local perSecond = ev and Config.EVChargePerSecond or Config.FuelPerSecondAtPump
        local seconds   = 0.10
        local addedFuel = perSecond * seconds
        local newFuel   = fuel + addedFuel
        if newFuel > Config.MaxFuel then
            addedFuel = Config.MaxFuel - fuel
            newFuel   = Config.MaxFuel
        end

        local litersPerUnit = (Config.TankCapacityLiters or 60.0) / Config.MaxFuel
        local addedLiters   = addedFuel * litersPerUnit

        if Config.UseBilling then
            local price = ev and Config.PricePerUnitElectric or Config.PricePerUnitFuel
            local cost  = addedFuel * price
            if cost > 0.0 then
                sessionCost = sessionCost + cost
            end
        end

        sessionLiters = sessionLiters + addedLiters
        SetVehicleFuelLevel(hoseVehicle, newFuel)

        SendNUIMessage({
            action = "fuel_update",
            fuel   = newFuel,
            cost   = sessionCost,
            liters = sessionLiters,
            isEV   = ev
        })

        ::continue::
    end
end)

---------------------------------------------------------------------
-- CLEANUP
---------------------------------------------------------------------

AddEventHandler("onResourceStop", function(res)
    if res ~= RESOURCE_NAME then return end
    deleteHose()
end)
