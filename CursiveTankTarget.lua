-- CursiveTankTarget 3.2.2-accurate+guid
-- Base: 3.2.2 with keybind visible.
-- Additions: accurate arrow resolver to avoid same-name spillover; /ctt guidonly to restrict to GUID-only targeting.

if type(CTT_Tanks) ~= "table" then CTT_Tanks = {} end
if type(CTT_Enabled) ~= "boolean" then CTT_Enabled = true end
if type(CTT_Debug) ~= "boolean" then CTT_Debug = false end
if type(CTT_Scale) ~= "number" then CTT_Scale = 1.25 end
if type(CTT_GuidOnly) ~= "boolean" then CTT_GuidOnly = false end

local ADDON_VERSION = "3.2.2-accurate+guid"
local _G = getfenv(0)

local function help()
  DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[CTT]|r CursiveTankTarget v"..ADDON_VERSION)
  DEFAULT_CHAT_FRAME:AddMessage("  /ctt add | remove | clear | list | on | off | debug | assist")
  DEFAULT_CHAT_FRAME:AddMessage("  /ctt scale <factor>  (current: "..tostring(CTT_Scale)..")")
  DEFAULT_CHAT_FRAME:AddMessage("  /ctt guidonly [on|off]  (current: "..(CTT_GuidOnly and "ON" or "OFF")..")")
end

-- ===== Target resolution support =====
local roster, rosterTick = {}, 0
local function BuildRoster()
  local now = GetTime()
  if now < rosterTick then return end
  rosterTick = now + 0.5
  for k in pairs(roster) do roster[k] = nil end
  local n = UnitName("player"); if n then roster[n] = "player" end
  for i=1,4 do
    local u="party"..i
    if UnitExists(u) then
      local nm=UnitName(u); if nm then roster[nm]=u end
      local p=u.."pet"; if UnitExists(p) then local pn=UnitName(p); if pn then roster[pn]=p end end
    end
  end
  for i=1,40 do
    local u="raid"..i
    if UnitExists(u) then
      local nm=UnitName(u); if nm then roster[nm]=u end
      local p=u.."pet"; if UnitExists(p) then local pn=UnitName(p); if pn then roster[pn]=p end end
    end
  end
  -- NOTE: we do NOT map player's current "target" into roster (prevents same-name spillover)
end

-- Accurate resolver: prefers frame.unit->target, else frame.guid->target; finally, only for the player's current target bar, use targettarget.
local function GetMobTargetName(frame)
  if not frame then return nil, "none" end

  if CTT_GuidOnly then
    local guid = frame.guid
    if guid and UnitExists(guid) and UnitExists(guid.."target") then
      return UnitName(guid.."target"), "guid"
    end
    return nil, "guidonly"
  end

  local unit = frame.unit or frame.unitToken
  if unit and UnitExists(unit) and UnitExists(unit.."target") then
    return UnitName(unit.."target"), "unit"
  end

  local guid = frame.guid
  if guid and UnitExists(guid) and UnitExists(guid.."target") then
    return UnitName(guid.."target"), "guid"
  end

  -- As a last resort, if this bar is actually your current target (Cursive shows its default arrow),
  -- use "targettarget" to read the mob's target; this is safe because it only applies to the selected bar.
  if frame.target_left and frame.target_left:IsShown() and UnitExists("targettarget") then
    return UnitName("targettarget"), "player-target"
  end

  return nil, "none"
end

-- Back-compat shim for old calls
local function GetTargetNameByGuidOrRoster(frame, guid)
  return GetMobTargetName(frame)
end

-- ===== Frame registry (assist fallback ordering) =====
local CTT_Frames = {}
local function CTT_RegisterFrame(frame)
  if not frame or frame.cttReg then return end
  table.insert(CTT_Frames, frame)
  frame.cttReg = true
end

-- ===== Assist logic (preserved behavior from 3.2.2) =====
function CTT_Assist()
  BuildRoster()
  local ui = _G.ui
  local function try_target_frame(frame)
    if not frame or not frame.IsShown or not frame:IsShown() then return false end
    local guid = frame.guid
    local tname, via = GetTargetNameByGuidOrRoster(frame, guid)
    local eligible = (next(CTT_Tanks) and tname and not CTT_Tanks[tname])

    if CTT_Debug then
      local nm = frame.nameText and frame.nameText:GetText() or "(noname)"
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff2020[CTT]|r assist-scan nm=%s target=%s via=%s eligible=%s",
        tostring(nm), tostring(tname), tostring(via), tostring(eligible)))
    end

    if not eligible then return false end

    -- GUID direct (if available)
    if guid and UnitExists(guid) then
      TargetUnit(guid)
      if CTT_Debug then DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[CTT]|r Assist: targeted guid "..tostring(guid)) end
      return true
    end

    -- Name fallback (legacy behavior)
    local nm = frame.nameText and frame.nameText:GetText()
    if nm and nm ~= "" then
      TargetByName(nm)
      if CTT_Debug then DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[CTT]|r Assist: TargetByName("..nm..")") end
      return true
    end

    return false
  end

  if ui and ui.unitFrames then
    local cols = {}
    for c,_ in pairs(ui.unitFrames) do table.insert(cols, c) end
    table.sort(cols, function(a,b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
    for _, c in ipairs(cols) do
      local rows = ui.unitFrames[c]
      if rows then
        local rks = {}
        for r,_ in pairs(rows) do table.insert(rks, r) end
        table.sort(rks, function(a,b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
        for _, r in ipairs(rks) do
          local frame = rows[r]
          if try_target_frame(frame) then return end
        end
      end
    end
  else
    -- Fallback: scan our registry
    local n = (table and table.getn and table.getn(CTT_Frames)) or 0
    for i=1,n do
      if try_target_frame(CTT_Frames[i]) then return end
    end
  end

  DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[CTT]|r Assist: no eligible unit found.")
end

-- ===== Slash =====
if type(_G.SlashCmdList) ~= "table" then _G.SlashCmdList = {} end
_G.SLASH_CURSIVETANKTARGET1 = "/ctt"
_G.SlashCmdList["CURSIVETANKTARGET"] = function(msg)
  msg = tostring(msg or "")
  msg = string.lower(msg); msg = string.gsub(msg, "^%s+", ""); msg = string.gsub(msg, "%s+$", "")

  -- scale command: /ctt scale 1.25
  do
    local s,e,num = string.find(msg, "^scale%s+([%d%.]+)$")
    if s then
      local f = tonumber(num)
      if f and f > 0.25 and f <= 5.0 then
        CTT_Scale = f
        DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[CTT]|r Scale set to "..string.format("%.2f", CTT_Scale))
        return
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[CTT]|r Scale must be between 0.25 and 5.0")
        return
      end
    end
  end

  -- guidonly command: /ctt guidonly [on|off], empty toggles
  do
    local s,e,flag = string.find(msg, "^guidonly%s*([%a_]*)$")
    if s then
      if flag == "on" then CTT_GuidOnly = true
      elseif flag == "off" then CTT_GuidOnly = false
      else CTT_GuidOnly = not CTT_GuidOnly end
      DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[CTT]|r GUID-only is now "..(CTT_GuidOnly and "ON" or "OFF"))
      return
    end
  end

  if msg == "" or msg == "help" then
    help(); return
  end

  if msg == "debug" then
    CTT_Debug = not CTT_Debug
    DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[CTT]|r Debug "..(CTT_Debug and "ON" or "OFF"))
    return
  end

  if type(CTT_Tanks) ~= "table" then CTT_Tanks = {} end

  if msg == "add" then
    if UnitExists("target") then
      local name = UnitName("target")
      if name then
        CTT_Tanks[name] = true
        DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[CTT]|r Added tank: "..name)
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[CTT]|r Target has no resolvable name.")
      end
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[CTT]|r No target selected.")
    end

  elseif msg == "remove" then
    if UnitExists("target") then
      local name = UnitName("target")
      if name and CTT_Tanks[name] then
        CTT_Tanks[name] = nil
        DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[CTT]|r Removed tank: "..name)
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[CTT]|r Target not in tank list.")
      end
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[CTT]|r No target selected.")
    end

  elseif msg == "clear" then
    CTT_Tanks = {}
    DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[CTT]|r Tank list cleared.")

  elseif msg == "list" then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[CTT]|r Tanks:")
    if not next(CTT_Tanks) then
      DEFAULT_CHAT_FRAME:AddMessage("  (empty)")
    else
      for n,_ in pairs(CTT_Tanks) do DEFAULT_CHAT_FRAME:AddMessage("  "..n) end
    end

  elseif msg == "on" or msg == "enable" then
    CTT_Enabled = true
    DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[CTT]|r Enabled.")

  elseif msg == "off" or msg == "disable" then
    CTT_Enabled = false
    DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[CTT]|r Disabled.")

  elseif msg == "assist" then
    CTT_Assist()

  else
    help()
  end
end

-- ===== Overload CreateBarFirstSection =====
if not _G.CTT_Orig_CreateBarFirstSection then _G.CTT_Orig_CreateBarFirstSection = _G.CreateBarFirstSection end

_G.CreateBarFirstSection = function(unitFrame, guid)
  if type(_G.CTT_Orig_CreateBarFirstSection) == "function" then _G.CTT_Orig_CreateBarFirstSection(unitFrame, guid) end

  local config = (Cursive and Cursive.db and Cursive.db.profile) or {}
  local firstSection = unitFrame.firstSection or unitFrame

  -- Base sizing (8x8 fallback); scaled by CTT_Scale
  local base_w = 8
  local base_h = 8
  if _G.ui and _G.ui.targetIndicatorSize then base_w = _G.ui.targetIndicatorSize end

  local function applyScale(frame)
    local W = math.floor(base_w * (CTT_Scale or 1.25) + 0.5)
    local H = math.floor(base_h * (CTT_Scale or 1.25) + 0.5)
    if frame then frame:SetWidth(W); frame:SetHeight(H) end
  end

  -- Local textures (your working TGAs)
  local TEX_LEFT  = "Interface\\AddOns\\CursiveTankTarget\\img\\target-left"
  local TEX_RIGHT = "Interface\\AddOns\\CursiveTankTarget\\img\\target-right"

  if not unitFrame.cttInvLeft then
    local t = firstSection:CreateTexture(nil, "OVERLAY")
    applyScale(t)
    t:SetPoint("LEFT", unitFrame, "LEFT", 0, 0)
    t:SetTexture(TEX_LEFT)
    t:Hide()
    unitFrame.cttInvLeft = t
  end
  if not unitFrame.cttInvRight then
    local t = firstSection:CreateTexture(nil, "OVERLAY")
    applyScale(t)
    t:SetPoint("RIGHT", firstSection, "RIGHT", 0, 0)
    t:SetTexture(TEX_RIGHT)
    t:Hide()
    unitFrame.cttInvRight = t
  end

  unitFrame.cttInvBaseW = base_w
  unitFrame.cttInvBaseH = base_h
  unitFrame.cttInvAppliedScale = -1

  -- Register for assist fallback
  CTT_RegisterFrame(unitFrame)

  if not unitFrame.cttInvUpdater then
    unitFrame.cttInvUpdater = true
    unitFrame.cttInvNext = 0
    local old = nil; if unitFrame.GetScript then old = unitFrame:GetScript("OnUpdate") end

    unitFrame:SetScript("OnUpdate", function()
      if old then old() end
      if not CTT_Enabled then if unitFrame.cttInvLeft then unitFrame.cttInvLeft:Hide() end if unitFrame.cttInvRight then unitFrame.cttInvRight:Hide() end return end

      -- Live re-scaling if changed
      local cur = CTT_Scale or 1.25
      if unitFrame.cttInvAppliedScale ~= cur then
        local W = math.floor((unitFrame.cttInvBaseW or 8) * cur + 0.5)
        local H = math.floor((unitFrame.cttInvBaseH or 8) * cur + 0.5)
        if unitFrame.cttInvLeft then unitFrame.cttInvLeft:SetWidth(W); unitFrame.cttInvLeft:SetHeight(H) end
        if unitFrame.cttInvRight then unitFrame.cttInvRight:SetWidth(W); unitFrame.cttInvRight:SetHeight(H) end
        unitFrame.cttInvAppliedScale = cur
      end

      local now = GetTime(); if now < (unitFrame.cttInvNext or 0) then return end
      unitFrame.cttInvNext = now + 0.25

      local tname, via = GetMobTargetName(unitFrame)
      local notTank = false
      if next(CTT_Tanks) and tname and not CTT_Tanks[tname] then notTank = true end

      local invbars = (Cursive and Cursive.db and Cursive.db.profile and Cursive.db.profile.invertbars) and true or false

      if notTank then
        if invbars then
          if unitFrame.cttInvLeft then unitFrame.cttInvLeft:Show() end
          if unitFrame.cttInvRight then unitFrame.cttInvRight:Hide() end
        else
          if unitFrame.cttInvRight then unitFrame.cttInvRight:Show() end
          if unitFrame.cttInvLeft then unitFrame.cttInvLeft:Hide() end
        end
      else
        if unitFrame.cttInvLeft then unitFrame.cttInvLeft:Hide() end
        if unitFrame.cttInvRight then unitFrame.cttInvRight:Hide() end
      end
    end)
  end
end