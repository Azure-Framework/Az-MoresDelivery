-- nv_morsmutual/server.lua
-- Parked/unparked is determined ONLY by presence in testersz.user_vehicles:
--   - Parked  = row EXISTS in user_vehicles
--   - Unparked= row REMOVED from user_vehicles
-- No parked column. No new table.
--
-- We keep removed rows in memory while out so we can insert them back when "parked".

local RESOURCE = GetCurrentResourceName()

local function dbg(msg)
  print(('[%s] %s'):format(RESOURCE, tostring(msg)))
end

-- ----------------------------
-- MySQL wrapper (oxmysql/mysql-async/ghmattimysql)
-- ----------------------------
local function isOx() return (Config.MySQL or ''):lower() == 'oxmysql' end
local function isMyAsync() return (Config.MySQL or ''):lower() == 'mysql-async' end
local function isGH() return (Config.MySQL or ''):lower() == 'ghmattimysql' end

local function fetchAll(query, params)
  if isOx() then
    return exports.oxmysql:fetchSync(query, params or {})
  elseif isMyAsync() then
    local p = promise.new()
    exports['mysql-async']:fetchAll(query, params or {}, function(r) p:resolve(r) end)
    return Citizen.Await(p)
  elseif isGH() then
    local p = promise.new()
    exports.ghmattimysql:execute(query, params or {}, function(r) p:resolve(r) end)
    return Citizen.Await(p)
  else
    error('Config.MySQL must be one of: oxmysql, mysql-async, ghmattimysql')
  end
end

local function execute(query, params)
  if isOx() then
    return exports.oxmysql:executeSync(query, params or {})
  elseif isMyAsync() then
    local p = promise.new()
    exports['mysql-async']:execute(query, params or {}, function(r) p:resolve(r) end)
    return Citizen.Await(p)
  elseif isGH() then
    local p = promise.new()
    exports.ghmattimysql:execute(query, params or {}, function(r) p:resolve(r) end)
    return Citizen.Await(p)
  else
    error('Config.MySQL must be one of: oxmysql, mysql-async, ghmattimysql')
  end
end

-- ----------------------------
-- Identifier
-- ----------------------------
local function getIdentifier(src)
  local t = (Config.IdentifierType or 'discord'):lower()

  for _, id in ipairs(GetPlayerIdentifiers(src)) do
    if t == 'discord' and id:find('discord:', 1, true) == 1 then
      return id:gsub('discord:', '')
    elseif t == 'license' and id:find('license:', 1, true) == 1 then
      return id:gsub('license:', '')
    end
  end

  -- fallback to license if discord missing
  if t ~= 'license' then
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
      if id:find('license:', 1, true) == 1 then
        return id:gsub('license:', '')
      end
    end
  end
  return nil
end

-- ----------------------------
-- Cooldowns / locks
-- ----------------------------
local cooldowns = {}        -- [ownerId] = os.time()+seconds
local activeDeliveries = {} -- [ownerId] = plate

local function canUse(ownerId)
  local now = os.time()
  if cooldowns[ownerId] and cooldowns[ownerId] > now then
    return false, (cooldowns[ownerId] - now)
  end
  return true, 0
end

-- ----------------------------
-- "Out" memory store (NOT a DB table)
-- We store the removed DB row here so we can insert it back when parked.
-- outVehicles[ownerId][plate] = { row=<db row>, state='delivering'|'out', since=os.time() }
-- ----------------------------
local outVehicles = {}

local function ownerMap(ownerId)
  outVehicles[ownerId] = outVehicles[ownerId] or {}
  return outVehicles[ownerId]
end

local function isOut(ownerId, plate)
  local m = outVehicles[ownerId]
  return (m and m[plate]) ~= nil
end

local function setOut(ownerId, plate, row, state)
  local m = ownerMap(ownerId)
  m[plate] = {
    row = row, -- full db row
    state = state or 'out',
    since = os.time()
  }
end

local function clearOut(ownerId, plate)
  local m = outVehicles[ownerId]
  if not m then return end
  m[plate] = nil
end

-- ----------------------------
-- JSON helpers
-- ----------------------------
local function toJsonString(v)
  if v == nil then return nil end
  if type(v) == 'string' then return v end
  local ok, s = pcall(function() return json.encode(v) end)
  if ok then return s end
  return nil
end

local function upperPlate(p)
  return tostring(p or ''):upper()
end

-- ----------------------------
-- Queries (ONLY parked vehicles exist in table)
-- ----------------------------
local function getVehiclesForOwner(ownerId)
  local t = Config.DB_TABLE
  local ownerCol = Config.DB_OWNER_COLUMN

  -- Parked vehicles ONLY = what remains in the table
  local rows = fetchAll(([[
    SELECT id, plate, model, x, y, z, h, color1, color2, pearlescent, wheelColor, wheelType, windowTint, mods, extras
    FROM %s
    WHERE %s = ?
    ORDER BY id DESC
  ]]):format(t, ownerCol), { ownerId })

  return rows or {}
end

local function getVehicleByPlate(ownerId, plate)
  local t = Config.DB_TABLE
  local ownerCol = Config.DB_OWNER_COLUMN
  local rows = fetchAll(("SELECT * FROM %s WHERE %s = ? AND plate = ? LIMIT 1"):format(t, ownerCol), { ownerId, plate })
  return rows and rows[1] or nil
end

local function deleteVehicleRow(ownerId, plate)
  local t = Config.DB_TABLE
  local ownerCol = Config.DB_OWNER_COLUMN
  execute(("DELETE FROM %s WHERE %s = ? AND plate = ? LIMIT 1"):format(t, ownerCol), { ownerId, plate })
end

local function upsertVehicleRow(ownerId, row)
  -- Inserts the car back into user_vehicles (parked).
  -- Uses ON DUPLICATE KEY because you have UNIQUE(discordid,plate)
  local t = Config.DB_TABLE

  local discordid   = row.discordid or ownerId
  local plate       = row.plate
  local model       = row.model
  local x           = tonumber(row.x) or 0.0
  local y           = tonumber(row.y) or 0.0
  local z           = tonumber(row.z) or 0.0
  local h           = tonumber(row.h) or 0.0
  local color1      = tonumber(row.color1) or 0
  local color2      = tonumber(row.color2) or 0
  local pearlescent = tonumber(row.pearlescent) or 0
  local wheelColor  = tonumber(row.wheelColor) or 0
  local wheelType   = tonumber(row.wheelType) or 0
  local windowTint  = tonumber(row.windowTint) or 0
  local mods        = toJsonString(row.mods)
  local extras      = toJsonString(row.extras)

  execute(([[
    INSERT INTO %s
      (discordid, plate, model, x, y, z, h, color1, color2, pearlescent, wheelColor, wheelType, windowTint, mods, extras)
    VALUES
      (?,        ?,     ?,     ?, ?, ?, ?, ?,      ?,      ?,          ?,          ?,         ?,          ?,    ?)
    ON DUPLICATE KEY UPDATE
      model=VALUES(model),
      x=VALUES(x), y=VALUES(y), z=VALUES(z), h=VALUES(h),
      color1=VALUES(color1), color2=VALUES(color2),
      pearlescent=VALUES(pearlescent),
      wheelColor=VALUES(wheelColor),
      wheelType=VALUES(wheelType),
      windowTint=VALUES(windowTint),
      mods=VALUES(mods),
      extras=VALUES(extras)
  ]]):format(t), {
    discordid, plate, model, x, y, z, h, color1, color2, pearlescent, wheelColor, wheelType, windowTint, mods, extras
  })
end

-- ----------------------------
-- Events
-- ----------------------------

-- List vehicles: ONLY parked ones (because unparked are removed from table)
RegisterNetEvent('nv_morsmutual:sv_list', function()
  local src = source
  local ownerId = getIdentifier(src)
  if not ownerId then
    TriggerClientEvent('nv_morsmutual:cl_notify', src, 'No identifier found (discord/license).')
    return
  end

  local ok, remaining = canUse(ownerId)
  local vehicles = getVehiclesForOwner(ownerId)

  -- Optional: make UI show them as parked (if your UI expects this field)
  for _, v in ipairs(vehicles) do
    v.parked = 1
  end

  TriggerClientEvent('nv_morsmutual:cl_list', src, {
    ok = ok,
    cooldown = remaining,
    vehicles = vehicles,
    ownerId = ownerId
  })
end)

-- Request delivery:
-- 1) Fetch row from DB (parked)
-- 2) Delete from DB immediately (now it's "unparked")
-- 3) Store row in memory so we can insert it back later
-- 4) Send props to client to spawn and drive it
RegisterNetEvent('nv_morsmutual:sv_requestDelivery', function(plate, spawn)
  local src = source
  plate = upperPlate(plate)
  if plate == '' then return end

  local ownerId = getIdentifier(src)
  if not ownerId then
    TriggerClientEvent('nv_morsmutual:cl_notify', src, 'No identifier found.')
    return
  end

  local ok, remaining = canUse(ownerId)
  if not ok then
    TriggerClientEvent('nv_morsmutual:cl_notify', src, ('Insurance is busy. Try again in %ds.'):format(remaining))
    return
  end

  if activeDeliveries[ownerId] then
    TriggerClientEvent('nv_morsmutual:cl_notify', src, 'You already have a delivery in progress.')
    return
  end

  -- Already out?
  if isOut(ownerId, plate) then
    TriggerClientEvent('nv_morsmutual:cl_notify', src, 'That vehicle is already unparked / out.')
    return
  end

  local row = getVehicleByPlate(ownerId, plate)
  if not row then
    -- If it's not in DB, then by your rules it's unparked/out.
    TriggerClientEvent('nv_morsmutual:cl_notify', src, 'That vehicle is currently unparked / out (not in garage).')
    return
  end

  -- Validate spawn
  local sx, sy, sz, sh = tonumber(spawn and spawn.x), tonumber(spawn and spawn.y), tonumber(spawn and spawn.z), tonumber(spawn and spawn.h)
  if not sx or not sy or not sz or not sh then
    TriggerClientEvent('nv_morsmutual:cl_notify', src, 'Invalid spawn point.')
    return
  end

  -- Lock + cooldown
  activeDeliveries[ownerId] = plate
  cooldowns[ownerId] = os.time() + tonumber(Config.CooldownSeconds or 60)

  -- Remove from garage table immediately (UNPARKED)
  local okDel, errDel = pcall(function()
    deleteVehicleRow(ownerId, plate)
  end)
  if not okDel then
    dbg(("DELETE failed for %s/%s: %s"):format(ownerId, plate, tostring(errDel)))
    activeDeliveries[ownerId] = nil
    TriggerClientEvent('nv_morsmutual:cl_notify', src, 'DB error removing vehicle from garage.')
    return
  end

  -- Store row in memory so we can reinsert when parked again
  setOut(ownerId, plate, row, 'delivering')

  TriggerClientEvent('nv_morsmutual:cl_deliveryApproved', src, {
    plate = plate,
    model = row.model,
    props = {
      plate = row.plate,
      color1 = row.color1,
      color2 = row.color2,
      pearlescent = row.pearlescent,
      wheelColor = row.wheelColor,
      wheelType = row.wheelType,
      windowTint = row.windowTint,
      mods = row.mods,
      extras = row.extras,
    },
    spawn = { x=sx, y=sy, z=sz, h=sh }
  })
end)

-- Delivery done:
-- If failed, we INSERT it back (so it becomes parked again).
-- If success, it stays OUT (still removed from DB) until you call sv_markParked.
RegisterNetEvent('nv_morsmutual:sv_deliveryDone', function(plate, deliveredOk)
  local src = source
  local ownerId = getIdentifier(src)
  if not ownerId then return end

  plate = upperPlate(plate or activeDeliveries[ownerId])
  activeDeliveries[ownerId] = nil
  if plate == '' then return end

  local entry = outVehicles[ownerId] and outVehicles[ownerId][plate]
  if not entry or not entry.row then
    -- nothing to restore
    return
  end

  if deliveredOk then
    entry.state = 'out'
    dbg(("Delivery success -> %s/%s remains OUT (row removed from DB)"):format(ownerId, plate))
  else
    -- restore into DB (park it again)
    dbg(("Delivery failed -> restoring %s/%s back into DB"):format(ownerId, plate))
    pcall(function()
      upsertVehicleRow(ownerId, entry.row)
    end)
    clearOut(ownerId, plate)
  end
end)

-- Mark parked:
-- This should be called when the player stores the vehicle.
-- We INSERT it back into user_vehicles (PARKED).
-- You can call with just plate if server memory exists,
-- or include props/coords if server restarted and memory is empty.
RegisterNetEvent('nv_morsmutual:sv_markParked', function(plate, props, coords, heading)
  local src = source
  local ownerId = getIdentifier(src)
  if not ownerId then return end

  plate = upperPlate(plate)
  if plate == '' then return end

  local entry = outVehicles[ownerId] and outVehicles[ownerId][plate]
  local row = entry and entry.row or nil

  -- Fallback: if server memory is gone (restart), require props to reinsert
  if not row then
    if type(props) ~= 'table' then
      TriggerClientEvent('nv_morsmutual:cl_notify', src, 'Cannot park: missing stored data (server restart). Send vehicle properties.')
      return
    end

    row = {
      discordid = ownerId,
      plate = plate,
      model = tostring(props.model or props.hash or props.vehicleModel or ''),
      color1 = (type(props.color1) == 'table') and props.color1[1] or props.color1,
      color2 = (type(props.color2) == 'table') and props.color2[1] or props.color2,
      pearlescent = props.pearlescentColor or props.pearlescent,
      wheelColor = props.wheelColor,
      wheelType = props.wheels or props.wheelType,
      windowTint = props.windowTint,
      mods = toJsonString(props),
      extras = toJsonString(props.extras),
    }
  end

  -- Update coords on insert if provided
  if type(coords) == 'table' then
    row.x = tonumber(coords.x) or row.x
    row.y = tonumber(coords.y) or row.y
    row.z = tonumber(coords.z) or row.z
  end
  if heading ~= nil then
    row.h = tonumber(heading) or row.h
  end

  dbg(("Parking -> inserting %s/%s back into DB"):format(ownerId, plate))
  local okIns, errIns = pcall(function()
    upsertVehicleRow(ownerId, row)
  end)

  if not okIns then
    dbg("Park insert failed: "..tostring(errIns))
    TriggerClientEvent('nv_morsmutual:cl_notify', src, 'DB error: failed to park vehicle.')
    return
  end

  clearOut(ownerId, plate)
end)

-- Optional: allow cancel to restore vehicle to DB
RegisterNetEvent('nv_morsmutual:sv_cancelOut', function(plate)
  local src = source
  local ownerId = getIdentifier(src)
  if not ownerId then return end

  plate = upperPlate(plate)
  local entry = outVehicles[ownerId] and outVehicles[ownerId][plate]
  if not entry or not entry.row then return end

  pcall(function()
    upsertVehicleRow(ownerId, entry.row)
  end)
  clearOut(ownerId, plate)
end)
