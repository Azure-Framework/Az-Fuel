Config = {}

-- Toggle debug prints
Config.Debug = true

-- Basic fuel / charge config
Config.MaxFuel = 100.0                 -- maximum fuel / charge level (0–100)
Config.MinFuelToStart = 1.0            -- minimum to allow engine to stay on

-- How fast fuel drains (per second) depending on speed
Config.FuelDrainIdle       = 0.003     -- not really moving
Config.FuelDrainDriving    = 0.025     -- normal driving
Config.FuelDrainHighSpeed  = 0.05      -- high speed / highway

-- How often we tick fuel drain (ms)
Config.FuelTickInterval = 1000

-- Refueling / charging
Config.FuelPerSecondAtPump   = 2.0     -- gas: how fast fuel goes up while fueling
Config.EVChargePerSecond     = 2.0     -- EV: how fast charge goes up while charging
Config.MaxPumpDistance       = 2.2     -- distance from pump to pick up / hang up nozzle
Config.MaxVehicleDistance    = 3.0     -- distance from vehicle to attach nozzle
Config.MaxHoseStretch        = 12.0    -- max distance between pump and car while fueling

-- Billing (Az-Framework integration in server.lua)
-- ON by default now – will charge money if Az-Framework is running.
Config.UseBilling            = true
Config.PricePerUnitFuel      = 2.0     -- gas price per 1.0 fuel (0-100 tank)
Config.PricePerUnitElectric  = 1.5     -- EV price per 1.0 charge

-- HUD
Config.EnableHUD = true
Config.HUD = {
    alignRight = true,     -- bottom-right by default
    offsetX    = 0.0,
    offsetY    = 0.0,
}


Config.HUD.offsetX = -0.050  -- left/right
Config.HUD.offsetY =  0.002  -- up/down

-- Visual hose (tow / cargobob style rope) between pump & nozzle
Config.DrawHoseRope = true

-- Hose model
Config.HoseModel = `prop_cs_fuel_nozle`  -- nozzle in player hand / attached to car

-- OPTIONAL: manual overrides for EV models (for addons where native might not flag it)
Config.ElectricModels = {
    -- `custom_ev_model`,
}

-- Pump / charger props we treat as valid stations (gas or EV)
Config.PumpModels = {
    -- Base-game gas pumps
    `prop_gas_pump_1a`,
    `prop_gas_pump_1b`,
    `prop_gas_pump_1c`,
    `prop_gas_pump_1d`,
    `prop_gas_pump_old2`,
    `prop_gas_pump_old3`,
    `prop_vintage_pump`,

    -- Example custom pumps / chargers (optional - use if your map has them)
    `denis3d_prop_gas_pump`,
    `amb_rox_caspump_pf`
    -- add custom EV charger props here too if you have them
}

-- OPTIONAL: legacy hand-picked pump locations (for blips etc, not used by logic)
Config.Pumps = {
    { coords = vector3(265.0, -1261.3, 29.2), heading = 90.0 },
    { coords = vector3(273.0, -1261.3, 29.2), heading = 90.0 },
    { coords = vector3(281.0, -1261.3, 29.2), heading = 90.0 },
    { coords = vector3(289.0, -1261.3, 29.2), heading = 90.0 },

    { coords = vector3(1179.1, -330.7, 69.1), heading = 100.0 },
    { coords = vector3(1184.8, -324.2, 69.1), heading = 100.0 },
    { coords = vector3(1190.7, -317.4, 69.1), heading = 100.0 },

    { coords = vector3(1180.5, -1400.7, 35.3), heading = 180.0 },
    { coords = vector3(1180.5, -1393.2, 35.3), heading = 180.0 },
    { coords = vector3(1180.5, -1385.7, 35.3), heading = 180.0 },

    { coords = vector3(2001.1, 3774.6, 32.4), heading = 119.0 },
    { coords = vector3(2005.8, 3779.9, 32.4), heading = 119.0 },
    { coords = vector3(2010.6, 3785.3, 32.4), heading = 119.0 },

    { coords = vector3(176.6, 6604.9, 31.8), heading = 180.0 },
    { coords = vector3(168.9, 6604.9, 31.8), heading = 180.0 },
    { coords = vector3(161.1, 6604.9, 31.8), heading = 180.0 },
}

-- Draw a marker at the nearest pump when you are close (for testing / debugging)
Config.ShowPumpMarkers = true
Config.PumpMarker = {
    type      = 1,
    scale     = vector3(0.4, 0.4, 0.4),
    rgba      = {0, 150, 255, 140},
}

-- Keybind labels
Config.Keys = {
    Use   = "~INPUT_CONTEXT~", -- E
    Start = "~INPUT_JUMP~",    -- SPACE
}
