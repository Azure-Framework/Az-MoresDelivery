Config = Config or {}

--==========================================================
--  DB / Identifiers
--==========================================================
-- Your table:
--   testersz.user_vehicles
-- You can set DB_TABLE = 'testersz.user_vehicles' if needed.
Config.DB_TABLE = 'user_vehicles'

-- Column name used for the owner identifier
Config.DB_OWNER_COLUMN = 'discordid'

-- How to identify a player:
--   'discord'  -> uses identifier that starts with "discord:" (recommended for your schema)
--   'license'  -> uses "license:" identifier (fallback)
Config.IdentifierType = 'discord'

-- Which MySQL resource you run:
--   'oxmysql' (recommended)
--   'mysql-async'
--   'ghmattimysql'
Config.MySQL = 'oxmysql'

-- If true, server will attempt to add a `parked` column automatically if missing.
-- Requires ALTER permissions.
Config.AutoMigrateParkedColumn = true

--==========================================================
--  Delivery Settings
--==========================================================
-- Command to open the insurance UI
Config.Command = 'mors'
Config.Command2 = 'mors2'

-- Cooldown per player (seconds)
Config.CooldownSeconds = 60

-- Delivery "call" timing
Config.CallSeconds = 9

-- AI driving
Config.DriverPedModel = 's_m_y_valet_01'
Config.DriveSpeed = 20.0
Config.DrivingStyle = 786603 -- safe-ish
Config.StopDistance = 8.0

-- Spawn distance around player (meters)
Config.SpawnDistanceMin = 280.0
Config.SpawnDistanceMax = 520.0

-- If road-node spawn fails, use these fallback spots (anywhere on map).
Config.FallbackSpawnPoints = {
  { x = -46.5,  y = -1108.6, z = 26.4,  h = 70.0 },   -- PDM area
  { x = 247.3,  y = -779.2,  z = 30.6,  h = 160.0 },  -- Legion nearby
  { x = 1150.7, y = -332.6,  z = 68.9,  h = 10.0 },   -- Mirror Park-ish
  { x = -1033.2,y = -2733.0, z = 20.1,  h = 330.0 },  -- Airport
}

--==========================================================
--  Audio (in-game)
--==========================================================
-- These are GTA/FiveM frontend sounds. Some soundsets vary by build;
-- you can change names if you prefer different phone/dispatch sounds.
Config.Audio = {
  enable = true,
  sequence = {
    { name = 'Dial_and_Remote_Ring', set = 'Phone_SoundSet_Default', ms = 2100 },
    { name = 'Remote_Ring',          set = 'Phone_SoundSet_Default', ms = 2600 },
    { name = 'Remote_Ring',          set = 'Phone_SoundSet_Default', ms = 2600 },
    { name = 'Text_Arrive_Tone',     set = 'Phone_SoundSet_Default', ms = 600  },
  }
}

--==========================================================
--  NUI Theme
--==========================================================
Config.Theme = {
  accent = '#e63946'
}
