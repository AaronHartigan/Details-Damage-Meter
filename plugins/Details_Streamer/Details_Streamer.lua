
local SharedMedia = LibStub:GetLibrary ("LibSharedMedia-3.0")
local LDB = LibStub("LibDataBroker-1.1", true)
local LDBIcon = LDB and LibStub("LibDBIcon-1.0", true)
local LibWindow = LibStub("LibWindow-1.1")
local _

---need cleanup Loc ["STRING_MEMORY_ALERT_BUTTON"],

--create the plugin object
-- "Details_StreamOverlay" is the old name
local StreamOverlay = _detalhes:NewPluginObject("Details_Streamer", DETAILSPLUGIN_ALWAYSENABLED)
--tinsert(UISpecialFrames, "Details_StreamOverlays")
--main frame (shortcut)
local SOF = StreamOverlay.Frame

--shortcut for details framework
local playerName

StreamOverlay.CurrentVersion = "v1.2"

--mantaing the tables for casts, has hash indexes of numbers pointing to tables, tables inside store data of the UNIT_CAST events
--also mantain information about the cast, if is done, interrupted, channeled, instant.
--Target = the target of the spell casted or the spellname if is a death table
--Id = the CastId from UNIT_CAST events.
--CastStart = GetTime from the cast start.
--HasCastTime = if true, isn't a instant cast.
--Interrupted = if the cast has been interrupted (any interrupt even walk).
--Done = the cast is done and isn't more relevant to track updates.
--Percent = cast percentage, used to update the statusbar.
--Death = this is a event from death tables.
local CastsTable = {}

--store bars references
StreamOverlay.battle_lines = {}
--store the information to be shown on bars, like text, icon, colors
StreamOverlay.battle_content = {}

StreamOverlay.squares = {}

-- StreamOverlay:UpdateLines() = update the bar text, icons and statusbar. Uses battle_lines and battle_content tables.
-- StreamOverlay:NewText() = adds a new line to battle_content and call update.
-- StreamOverlay:CreateBattleLine() = create a new line on the frame and add to battle_lines table.
-- StreamOverlay:SetBattleLineStyle (row, index) = update bar config like font size, bar height, etc, 
-- StreamOverlay:RefreshInUse (line) = check if the bar still need to be shown in the screen or if can hide. Runs every 1 minute.
-- StreamOverlay:Refresh() = check if need to create more lines after a resize.
-- StreamOverlay:GetSpellInformation (spellid) = get information about the spell, if is a cooldown, defense, neutral, class, etc.
-- StreamOverlay:CastStart (castid) = called from the UNIT_CAST parser, it starts a cast when isn't a instant cast.
-- StreamOverlay:CastFinished (castid) = called from the UNIT_CAST parser, finish a cast.

-- track_spell_cast() runs on tick, check CastsTables updating ongoing spell casting, updates cast percentage.

-- StreamOverlay.OnDeath hook deaths from details! and show here (if player only).

--frame listening to UNIT_CAST events
local eventFrame = CreateFrame("frame")
--max left and right text sizes, is updated later in a function
local text1Size, text2Size = 200, 200
--icon size, is updated later in a function
local iconSize = 16
--default icon for an attack on a monster
local defaultAttackIcon = [[Interface\CURSOR\UnableAttack]]

local function CreatePluginFrames()
	--shortcut for details fade function
	local fader = Details.FadeHandler.Fader

	function StreamOverlay:OnDetailsEvent(event, ...)
		if (event == "HIDE") then --plugin hidded, disabled
			self.open = false

		elseif (event == "SHOW") then --plugin hidded, disabled
			self.open = true

		elseif (event == "PLUGIN_DISABLED") then
			StreamOverlay:OnDisablePlugin()

		elseif (event == "DETAILS_STARTED") then
			StreamOverlay:OnEnablePlugin()

		elseif (event == "PLUGIN_ENABLED") then
			StreamOverlay:OnEnablePlugin()

		end
	end

	function StreamOverlay:OnEnablePlugin()
		--show the frame and restore position
		SOF:Show()

		--restore size and location
		StreamOverlay:RestoreWindowSizeAndLocation()

		--refresh the frame
		StreamOverlay:Refresh()
		StreamOverlay:SetBackgroundColor()
		StreamOverlay:CreateMinimapIcon()
		
		--enable the minimap icon
		LDBIcon:Refresh("DetailsStreamer", StreamOverlay.db.minimap)
		StreamOverlay:SetLocked()
		
		--install the death hook
		Details:InstallHook(DETAILS_HOOK_DEATH, StreamOverlay.OnDeath)
		
		--enable event listener
		eventFrame:RegisterMyEvents()
		
		--enable the tick update
		eventFrame:SetScript("OnUpdate", eventFrame.track_spell_cast)
		
		--refresh dps frame
		StreamOverlay:UpdateDpsHpsFrameConfig()
	end
	
	function StreamOverlay:OnDisablePlugin()
		--shutdown the tick update
		eventFrame:SetScript("OnUpdate", nil)
	
		--disable the event listener
		eventFrame:UnregisterMyEvents()
	
		--unistall the death hook
		Details:UnInstallHook (DETAILS_HOOK_DEATH, StreamOverlay.OnDeath)
	
		--shutdown minimap icon
		StreamOverlay:CreateMinimapIcon()
		local realstate = StreamOverlay.db.minimap.hide
		StreamOverlay.db.minimap.hide = true
		LDBIcon:Refresh ("DetailsStreamer", StreamOverlay.db.minimap)
		StreamOverlay.db.minimap.hide = realstate
		
		--save position, size and hide the frame
		StreamOverlay:SaveWindowSizeAnLocation()
		SOF:Hide()
		
		--refresh dps frame
		StreamOverlay:UpdateDpsHpsFrameConfig (true)
	end
	
	--title bar, only shown when the frame isn't locked
	local titlebar = CreateFrame("frame", "DetailsStreamerTitlebar", SOF, "BackdropTemplate")
	titlebar:SetHeight(20)
	titlebar:SetPoint("bottomleft", SOF, "topleft")
	titlebar:SetPoint("bottomright", SOF, "topright")
	titlebar:SetBackdrop({bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], tile = true, tileSize = 16, insets = {left = 0, right = 0, top = 0, bottom = 0}})
	titlebar:SetBackdropColor(.1, .1, .1, .9)
	titlebar.text = titlebar:CreateFontString(nil, "overlay", "GameFontNormal")
	titlebar.text:SetPoint("center", titlebar, "center")
	titlebar.text:SetText("Details! Streamer: Action Tracker")
	titlebar:SetScript("OnEnter", function(self) 
		GameTooltip:SetOwner(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:AddLine("|cFFFF7700Left Click|r: Open Options\n|cFFFF7700Right Click|r: Lock the Frame\n|cFFFF7700Slash Command|r: /streamer")
		GameTooltip:Show()
	end)
	titlebar:SetScript("OnLeave", function() 
		GameTooltip:Hide()
	end)
	
	SOF:SetScript("OnMouseDown", function(self)

	end)
	SOF:SetScript("OnMouseUp", function(self)

	end)	
	
	titlebar:SetScript("OnMouseDown", function(self, button) 
		if (not SOF.moving and not StreamOverlay.db.main_frame_locked) then
			SOF:StartMoving()
			SOF.moving = true
			SOF.movingAt = GetTime()
		end
	end)
	
	titlebar:SetScript("OnMouseUp", function(self, button) 
	
		if (SOF.movingAt) then
			if (SOF.moving) then
				SOF.moving = false
				SOF:StopMovingOrSizing()
				StreamOverlay:SaveWindowSizeAnLocation()
			end
			
			if (SOF.movingAt+0.200 < GetTime()) then
				return
			end
			SOF.movingAt = nil
		end
	
		if (button == "LeftButton") then
			--open options
			StreamOverlay.OpenOptionsPanel()
		elseif (button == "RightButton") then
			--lock the frame
			StreamOverlay:SetLocked (not StreamOverlay.db.main_frame_locked)
			if (StreamOverlayOptionsPanel) then
				StreamOverlayOptionsPanel:RefreshOptions()
			end
		end
	end)
	
	--main frame parameters
	SOF:SetPoint("center", UIParent, "center")
	SOF:SetSize(300, 500)
	SOF:SetBackdrop({bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], tile = true, tileSize = 16, insets = {left = 0, right = 0, top = 0, bottom = 0}})
	SOF:EnableMouse(true)
	SOF:SetMovable(true)
	SOF:SetResizable(true)
	SOF:SetClampedToScreen (true)

	pcall(function()
		if (DetailsFramework.IsDragonflight()) then
			SOF:SetResizeBounds(150, 10, 800, 1024)
		else
			SOF:SetMinResize(150, 10)
			SOF:SetMaxResize(800, 1024)
		end
	end)

	function StreamOverlay:SaveWindowSizeAnLocation()
		--save size first
		StreamOverlay.db.main_frame_size [1] = SOF:GetWidth()
		StreamOverlay.db.main_frame_size [2] = SOF:GetHeight()
		--save main frame position
		LibWindow.RegisterConfig(SOF, StreamOverlay.db)
		LibWindow.SavePosition(SOF)
		--save the dps frame position
		LibWindow.RegisterConfig(StreamerOverlayDpsHpsFrame, StreamOverlay.db.per_second)
		LibWindow.SavePosition(StreamerOverlayDpsHpsFrame)
	end
	function StreamOverlay:RestoreWindowSizeAndLocation()
		--restore the size first
		SOF:SetSize(unpack(StreamOverlay.db.main_frame_size))
		--set the main window location
		LibWindow.RegisterConfig(SOF, StreamOverlay.db)
		LibWindow.RestorePosition(SOF)
		LibWindow.SavePosition(SOF)
		--set the dps frame location
		LibWindow.RegisterConfig(StreamerOverlayDpsHpsFrame, StreamOverlay.db.per_second)
		LibWindow.RestorePosition(StreamerOverlayDpsHpsFrame)
		LibWindow.SavePosition(StreamerOverlayDpsHpsFrame)
		--set the frame strata
		SOF:SetFrameStrata(StreamOverlay.db.main_frame_strata)
		StreamerOverlayDpsHpsFrame:SetFrameStrata(StreamOverlay.db.main_frame_strata)
	end
	
	--two resizers
	local left_resize = CreateFrame("button", "DetailsStreamerLeftResizer", SOF, "BackdropTemplate")
	local right_resize = CreateFrame("button", "DetailsStreamerRightResizer", SOF, "BackdropTemplate")
	left_resize:SetPoint("bottomleft", SOF, "bottomleft")
	right_resize:SetPoint("bottomright", SOF, "bottomright")
	left_resize:SetSize(16, 16)
	right_resize:SetSize(16, 16)
	right_resize:SetNormalTexture([[Interface\CHATFRAME\UI-ChatIM-SizeGrabber-Up]])
	right_resize:SetHighlightTexture([[Interface\CHATFRAME\UI-ChatIM-SizeGrabber-Highlight]])
	right_resize:SetPushedTexture([[Interface\CHATFRAME\UI-ChatIM-SizeGrabber-Down]])
	left_resize:SetNormalTexture([[Interface\CHATFRAME\UI-ChatIM-SizeGrabber-Up]])
	left_resize:SetHighlightTexture([[Interface\CHATFRAME\UI-ChatIM-SizeGrabber-Highlight]])
	left_resize:SetPushedTexture([[Interface\CHATFRAME\UI-ChatIM-SizeGrabber-Down]])
	left_resize:GetNormalTexture():SetTexCoord(1, 0, 0, 1)
	left_resize:GetHighlightTexture():SetTexCoord(1, 0, 0, 1)
	left_resize:GetPushedTexture():SetTexCoord(1, 0, 0, 1)
	
	left_resize:SetScript("OnMouseDown", function(self)
		if (not SOF.resizing and not StreamOverlay.db.main_frame_locked) then
			SOF.resizing = true
			SOF:StartSizing("bottomleft")
		end
	end)
	left_resize:SetScript("OnMouseUp", function(self)
		if (SOF.resizing) then
			SOF.resizing = false
			SOF:StopMovingOrSizing()
			StreamOverlay:Refresh()
			
			StreamOverlay:SaveWindowSizeAnLocation()
		end
	end)
	right_resize:SetScript("OnMouseDown", function(self)
		if (not SOF.resizing and not StreamOverlay.db.main_frame_locked) then
			SOF.resizing = true
			SOF:StartSizing("bottomright")
		end
	end)
	right_resize:SetScript("OnMouseUp", function(self) 
		if (SOF.resizing) then
			SOF.resizing = false
			SOF:StopMovingOrSizing()
			StreamOverlay:Refresh()
			
			StreamOverlay:SaveWindowSizeAnLocation()
		end
	end)
	
	SOF:SetScript("OnSizeChanged", function(self)
		StreamOverlay:Refresh()
	end)
	
	SOF:SetScript("OnMouseDown", function(self)
		if (not SOF.moving and not StreamOverlay.db.main_frame_locked) then
			SOF:StartMoving()
			SOF.moving = true
		end
	end)
	SOF:SetScript("OnMouseUp", function(self)
		if (SOF.moving) then
			SOF.moving = false
			SOF:StopMovingOrSizing()
			
			StreamOverlay:SaveWindowSizeAnLocation()
		end
	end)
	
	
	--scroll frame
	local autoscroll = CreateFrame("scrollframe", "Details_StreamOverlayScrollFrame", SOF, "FauxScrollFrameTemplate, BackdropTemplate")
	autoscroll:SetScript("OnVerticalScroll", function(self, offset) FauxScrollFrame_OnVerticalScroll (self, offset, 20, StreamOverlay.UpdateLines) end)
	
	--looks like this isn't working
	function StreamOverlay:ClearAll()
		if (StreamOverlay.db.use_square_mode) then
			for index = 1, #StreamOverlay.squares do
				local square = StreamOverlay.squares[index]
				if (square) then
					square.in_use = 1
				end
			end
			StreamOverlay:UpdateSquares()

		else
			for index = 1, #StreamOverlay.battle_lines do
				local line = StreamOverlay.battle_lines [index]
				if (line) then
					line.in_use = 1
				end
			end
			StreamOverlay:UpdateLines()
		end
	end
	
	function StreamOverlay:UpdateCooldownFrame(square, inCooldown, startTime, endTime, castInfo)

		if (castInfo and castInfo.Interrupted and castInfo.InterruptedPct) then
			CooldownFrame_SetDisplayAsPercentage(square.cooldown, abs(castInfo.InterruptedPct - 1))
			--square.interruptedTexture:Show()
			return
		end

		if (endTime and endTime < GetTime()) then
			CooldownFrame_Clear(square.cooldown)
			square.cooldown:Hide()
			return
		end

		if (inCooldown) then
			local duration = endTime - startTime
			CooldownFrame_Set(square.cooldown, startTime, duration, duration > 0, true)
			square.cooldown:Show()

		else
			CooldownFrame_Clear(square.cooldown)
			square.cooldown:Hide()
		end
	end

	function StreamOverlay:CreateSquareBox()
		local index = #StreamOverlay.squares + 1

		local newSquare = CreateFrame("frame", "StreamOverlaySquare" .. index, SOF, "BackdropTemplate")
		newSquare:SetBackdrop({bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1, tile = true, tileSize = 16, insets = {left = 0, right = 0, top = 0, bottom = 0}})
		newSquare:SetBackdropBorderColor(0, 0, 0, 0)
		newSquare.squareIndex = index

		newSquare.texture = newSquare:CreateTexture(nil, "artwork")
		newSquare.texture:SetAllPoints()

		newSquare.interruptedTexture = newSquare:CreateTexture(nil, "overlay")
		newSquare.interruptedTexture:SetColorTexture(1, 0, 0, 0.4)
		newSquare.interruptedTexture:SetAllPoints()
		newSquare.interruptedTexture:Hide()

		local cooldownFrame = CreateFrame("cooldown", "$parentCooldown", newSquare, "CooldownFrameTemplate, BackdropTemplate")
		cooldownFrame:SetAllPoints()
		cooldownFrame:EnableMouse(false)
		cooldownFrame:SetHideCountdownNumbers(true)
		newSquare.cooldown = cooldownFrame

		StreamOverlay.squares[#StreamOverlay.squares+1] = newSquare
		newSquare.in_use = 1
		newSquare:Hide()

		StreamOverlay:SetSquareStyle(newSquare, index)
		StreamOverlay:ReorderSquares()
	end

	function StreamOverlay:ReorderSquares()
		local direction = StreamOverlay.db.square_grow_direction
		for index = 1, #StreamOverlay.squares do
			local thisSquare = StreamOverlay.squares[index]
			thisSquare:ClearAllPoints()
			if (direction == "right") then --growing from left to right
				if (index == 1) then
					thisSquare:SetPoint("topleft", SOF, "topleft", 2, 0)
				else
					thisSquare:SetPoint("left", StreamOverlay.squares[index - 1], "right", 2, 0)
				end
			else
				if (index == 1) then
					thisSquare:SetPoint("topright", SOF, "topright", -2, 0)
				else
					thisSquare:SetPoint("right", StreamOverlay.squares[index - 1], "left", -2, 0)
				end
			end
		end
	end

	function StreamOverlay:UpdateSquares()
		for index = 1, StreamOverlay.total_lines do
			StreamOverlay:UpdateSquare(index)
		end
	end

	function StreamOverlay:UpdateSquare(index)
		local square = StreamOverlay.squares[index]

		local data = StreamOverlay.battle_content[index]
		if (data) then
			square.texture:SetTexture(data[1])
			square.texture:SetTexCoord(5/64, 59/64, 5/64, 59/64)

			--percentage
			local castinfo = CastsTable[data.CastID]
			local percent = castinfo and castinfo.Percent or 0
			if (percent > 100) then
				percent = 100
			end

			local startTime = data.startTime
			local endTime = data.endTime
			StreamOverlay:UpdateCooldownFrame(square, true, startTime, endTime, castinfo)

			if (castinfo.Interrupted) then
				--square.interruptedTexture:Show()
			else
				square.interruptedTexture:Hide()
			end

			square.in_use = data.CastStart
			StreamOverlay:RefreshInUse(square)
		else
			square.in_use = 1
			StreamOverlay:RefreshInUse(square)
		end
	end

	--iterate each bar and update its text, icons and statusbar
	function StreamOverlay:UpdateLines()
		if (StreamOverlay.db.use_square_mode) then
			return
		end

		FauxScrollFrame_Update(autoscroll, StreamOverlay.total_lines, StreamOverlay.total_lines, 20)

		for index = 1, StreamOverlay.total_lines do
			--here gets the bar and the table with the information to shown on the bar
			local data = StreamOverlay.battle_content [index]
			local line = StreamOverlay.battle_lines [index]
			if (data) then
			
				--left
				line.icon1:SetTexture(data [1])
				line.icon1:SetTexCoord(5/64, 59/64, 5/64, 59/64)
				
				local text = data [2]
				line.text1:SetText(text)
				local loops = 20
				while (line.text1:GetStringWidth() > text1Size and loops > 0) do
					text = strsub (text, 1, #text-1)
					line.text1:SetText(text)
					loops = loops - 1 --just to be safe
				end
				
				--right
				local text = data [6]
				line.text2:SetText(text)
				local loops = 20
				while (line.text2:GetStringWidth() > text2Size and loops > 0) do
					text = strsub (text, 1, #text-1)
					line.text2:SetText(text)
					loops = loops - 1 --just to be safe
				end

				if (text == "") then
					line.icon2:Hide()
					line.arrow:Hide()
				else
					line.icon2:Show()
					line.arrow:Show()
				end
				
				if (data[7]) then
					line.text2:SetTextColor(data[7].r, data[7].g, data[7].b)
				else
					line.text2:SetTextColor(1, 1, 1)
				end

				line.icon2:SetTexture(data [4])
				line.icon2:SetTexCoord(unpack(data [5]))
				if (data [4] == defaultAttackIcon) then
					line.icon2:SetSize(iconSize*0.8, iconSize*0.8)
					line.icon2:SetPoint("left", line, "center", 8, 0)
					line.text2:SetPoint("left", line.icon2, "right", 5, 0)
				else
					line.icon2:SetSize(iconSize, iconSize)
					line.icon2:SetPoint("left", line, "center", 8, 0)
					line.text2:SetPoint("left", line.icon2, "right", 5, 0)
				end
				
				--background
				line:SetBackdropColor(unpack(data [8]))
				
				if (data [9]) then
					line:SetBackdropBorderColor(unpack(data [9]))
				else
					line:SetBackdropBorderColor(0, 0, 0, 0)
				end
				
				--percentage
				local castinfo = CastsTable [data.CastID]
				local percent = castinfo and castinfo.Percent or 0
				if (percent > 100) then
					percent = 100
				end

				line.statusbar:SetValue(percent)
				
				if (StreamOverlay.db.use_spark) then
					line.spark:Show()
				else
					line.spark:Hide()
				end
				
				if (castinfo.Success) then
					line.spark:SetVertexColor(1, 1, 1, 0.4)
					line.spark:SetPoint("left", line.statusbar, "left", (line.statusbar:GetWidth() / 100 * percent) - 8, 0)

				elseif (castinfo.Interrupted) then
					line.spark:SetVertexColor(1, 0, 0, 0.4)
					line.spark:SetPoint("left", line.statusbar, "left", (line.statusbar:GetWidth() / 100 * percent) - 8, 0)
				end
				
				line.in_use = data.CastStart
				StreamOverlay:RefreshInUse (line)
			else
				line.in_use = 1
				StreamOverlay:RefreshInUse (line)
			end
		end
	end
	
	function StreamOverlay:NewText (icon1, text1, color1, icon2, icon2coords, text2, color2, backgroundcolor, bordercolor, ID, CastStart, startTime, endTime)
		if (StreamOverlay.ShowingDeath) then
			StreamOverlay.ShowingDeath = nil
			StreamOverlay:ClearAll()
		end

		--CastStart from the cast_send
		table.insert (StreamOverlay.battle_content, 1, {icon1, text1, color1, icon2, icon2coords, text2, color2, backgroundcolor, bordercolor, CastID = ID, CastStart = CastStart, startTime = startTime, endTime = endTime})
		table.remove (StreamOverlay.battle_content, StreamOverlay.total_lines+1)

		if (StreamOverlay.db.use_square_mode) then
			StreamOverlay:UpdateSquares()
		else
			StreamOverlay:UpdateLines()
		end
	end
	
	function StreamOverlay:CreateBattleLine()
	
		local index = #StreamOverlay.battle_lines+1
	
		local f = CreateFrame("frame", "StreamOverlayBar" .. index, SOF, "BackdropTemplate")
		local statusbar = CreateFrame("StatusBar", "StreamOverlayBar" .. index .. "StatusBar", f, "BackdropTemplate")
		local statusbar_texture = statusbar:CreateTexture(nil, "border")
		statusbar_texture:SetTexture(1, 1, 1, 0.15)
		statusbar:SetStatusBarColor(0, 0, 0, 0)
		statusbar:SetStatusBarTexture(statusbar_texture)
		statusbar:SetMinMaxValues(0, 100)
		statusbar:SetValue(0)
		local statusbar_spark = statusbar:CreateTexture(nil, "artwork")
		statusbar_spark:SetTexture([[Interface\CastingBar\UI-CastingBar-Spark]])
		statusbar_spark:SetSize(16, 50)
		statusbar_spark:SetBlendMode("ADD")
		statusbar_spark:Hide()
		
		local h = (index-1) * StreamOverlay.db.row_spacement * -1

		f:SetPoint("topleft", SOF, "topleft", 0, h)
		f:SetPoint("topright", SOF, "topright", 0, h)

		--backdrop color not editable
		f:SetBackdrop({bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1, tile = true, tileSize = 16, insets = {left = 0, right = 0, top = 0, bottom = 0}})
		f:SetBackdropBorderColor(0, 0, 0, 0)
		--f:SetBackdropColor(0, 0, 0, 0)
		
		local icon1 = statusbar:CreateTexture(nil, "overlay")
		local icon2 = statusbar:CreateTexture(nil, "overlay")
		
		local arrow = statusbar:CreateTexture(nil, "overlay")
		
		local text1 = statusbar:CreateFontString(nil, "overlay", "GameFontNormal")
		local text2 = statusbar:CreateFontString(nil, "overlay", "GameFontNormal")
		
		icon1:SetPoint("left", f, "left", 2, 0) --player spell icon
		text1:SetPoint("left", icon1, "right", 2, 0) --player spell name
		
		arrow:SetPoint("center", f, "center") --separate player spell and targets
		
		icon2:SetPoint("left", f, "center", 10, 0)
		text2:SetPoint("left", icon2, "right", 3, 0)
		
		statusbar:SetPoint("topleft", f, "topleft", 0, 0)
		statusbar:SetPoint("bottomright", f, "bottomright", 0, 0)
		
		f.icon1 = icon1
		f.icon2 = icon2
		f.text1 = text1
		f.text2 = text2
		f.arrow = arrow
		f.statusbar = statusbar
		f.statusbar_texture = statusbar_texture
		f.spark = statusbar_spark
		
		StreamOverlay.battle_lines [#StreamOverlay.battle_lines+1] = f
		
		f.in_use = 1
		f:Hide()
		
		StreamOverlay:SetBattleLineStyle (f)
	end

	
	function StreamOverlay:RefreshAllBattleLineStyle()
		if (StreamOverlay.db.use_square_mode) then
			return
		end

		for i, row in ipairs(StreamOverlay.battle_lines) do
			StreamOverlay:SetBattleLineStyle (row, i)
		end

		--update the dps hps frame text
		StreamOverlay:SetFontFace (StreamerOverlayDpsHpsFrameText, SharedMedia:Fetch ("font", StreamOverlay.db.font_face))
		StreamOverlay:SetFontColor(StreamerOverlayDpsHpsFrameText, StreamOverlay.db.font_color)
	end

	function StreamOverlay:RefreshAllBoxesStyle()
		if (not StreamOverlay.db.use_square_mode) then
			return
		end

		for i, square in ipairs(StreamOverlay.squares) do
			StreamOverlay:SetSquareStyle(square, i)
		end
	end
	
	function StreamOverlay:SetSquareStyle(square, index)
		local options = StreamOverlay.db
		square:SetSize(StreamOverlay.db.square_size, StreamOverlay.db.square_size)
	end

	function StreamOverlay:SetBattleLineStyle (row, index)
		local options = StreamOverlay.db
		
		row:SetHeight(StreamOverlay.db.row_height)
		
		if (index) then
			local h = (index-1) * StreamOverlay.db.row_spacement * -1
			row:SetPoint("topleft", SOF, "topleft", 0, h)
			row:SetPoint("topright", SOF, "topright", 0, h)
		end
		
		StreamOverlay:SetFontSize (row.text1, StreamOverlay.db.font_size)
		StreamOverlay:SetFontSize (row.text2, StreamOverlay.db.font_size)
		
		local font = SharedMedia:Fetch ("font", StreamOverlay.db.font_face)
		StreamOverlay:SetFontFace (row.text1, font)
		StreamOverlay:SetFontFace (row.text2, font)
		
		StreamOverlay:SetFontColor(row.text1, StreamOverlay.db.font_color)
		StreamOverlay:SetFontColor(row.text2, StreamOverlay.db.font_color)
		
		iconSize = StreamOverlay.db.row_height-4
		row.icon1:SetSize(iconSize, iconSize)
		row.icon2:SetSize(iconSize, iconSize)
		
		local current_texture = row.icon2:GetTexture()
		if (current_texture == defaultAttackIcon) then
			row.icon2:SetSize(iconSize*0.8, iconSize*0.8)
			row.icon2:SetPoint("left", row, "center", 8, 0)
			row.text2:SetPoint("left", row.icon2, "right", 5, 0)
		else
			row.icon2:SetPoint("left", row, "center", 8, 0)
			row.text2:SetPoint("left", row.icon2, "right", 5, 0)
		end
		
		if (row.text2:GetText() == "") then
			row.icon2:Hide()
			row.arrow:Hide()
		else
			row.icon2:Show()
			row.arrow:Show()
		end
		
		local texture = SharedMedia:Fetch("statusbar", StreamOverlay.db.row_texture)
		row.statusbar_texture:SetTexture(texture)
		row.statusbar_texture:SetVertexColor(unpack(StreamOverlay.db.row_color))

		row.arrow:SetTexture(StreamOverlay.db.arrow_texture)
		row.arrow:SetSize(StreamOverlay.db.arrow_size, StreamOverlay.db.arrow_size)
		row.arrow:SetVertexColor(unpack(StreamOverlay.db.arrow_color))
		row.arrow:SetPoint("center", row, "center", StreamOverlay.db.arrow_anchor_x, StreamOverlay.db.arrow_anchor_y)
	end

	function StreamOverlay:RefreshInUse(line)
		local now = GetTime()
		local i = -1 --was nil before from _G["i"]
		if (line) then
			local line_in_use = line.in_use or 1
			local content_in_use = StreamOverlay.battle_content [i] and StreamOverlay.battle_content [i].CastStart or 1

			if (max(line_in_use, content_in_use) + 60 < now) then
				fader (nil, line, "in")
			else
				fader (nil, line, "out")
			end
		else
			if (not StreamOverlay.db.use_square_mode) then
				for i = 1, #StreamOverlay.battle_lines do
					local line = StreamOverlay.battle_lines[i]
					
					local line_in_use = line.in_use or 1
					local content_in_use = StreamOverlay.battle_content [i] and StreamOverlay.battle_content [i].CastStart or 1

					if (max(line_in_use, content_in_use) + 60 < now) then
						fader (nil, StreamOverlay.battle_lines [i], "in")
					else
						fader (nil, StreamOverlay.battle_lines [i], "out")
					end
				end

			else
				for i = 1, #StreamOverlay.squares do
					local line = StreamOverlay.squares[i]
					
					local line_in_use = line.in_use or 1
					local content_in_use = StreamOverlay.battle_content[i] and StreamOverlay.battle_content[i].CastStart or 1

					if (max(line_in_use, content_in_use) + 60 < now) then
						fader (nil, StreamOverlay.squares[i], "in")
					else
						fader (nil, StreamOverlay.squares[i], "out")
					end
				end

			end
		end
	end
	
	C_Timer.NewTicker(60, StreamOverlay.RefreshInUse)

	function StreamOverlay:Refresh()
		if (StreamOverlay.db.use_square_mode) then
			--hide any line created
			for i = 1, #StreamOverlay.battle_lines do
				StreamOverlay.battle_lines[i]:Hide()
			end

			local amountOfSquares = StreamOverlay.db.square_amount
			StreamOverlay.total_lines = amountOfSquares

			if (amountOfSquares > #StreamOverlay.squares) then
				for i = #StreamOverlay.squares + 1, amountOfSquares do
					StreamOverlay:CreateSquareBox()
				end
				for i = 1, amountOfSquares do
					StreamOverlay.squares[i]:Show()
				end

			elseif (#StreamOverlay.squares > amountOfSquares) then
				for i = #StreamOverlay.squares, amountOfSquares + 1, -1 do
					StreamOverlay.squares[i]:Hide()
				end
				for i = 1, amountOfSquares do
					StreamOverlay.squares[i]:Show()
				end
			else
				for i = 1, amountOfSquares do
					StreamOverlay.squares[i]:Show()
				end
			end

			StreamOverlay:UpdateSquares()
			StreamOverlay:RefreshInUse()

		else --showing lines
			--hide any square created
			for i = 1, #StreamOverlay.squares do
				StreamOverlay.squares[i]:Hide()
			end

			--how many lines fit in the frame
			local amountOfLines = math.floor(SOF:GetHeight() / StreamOverlay.db.row_spacement)

			if (amountOfLines < 0) then
				amountOfLines = 0
			end

			StreamOverlay.total_lines = amountOfLines

			if (amountOfLines == 0) then
				for i = 1, #StreamOverlay.battle_lines do
					StreamOverlay.battle_lines[i]:Hide()
				end
				return
			end

			-- need create more lines
			if (amountOfLines > #StreamOverlay.battle_lines) then
				for i = #StreamOverlay.battle_lines + 1, amountOfLines do
					StreamOverlay:CreateBattleLine()
				end
				for i = 1, amountOfLines do
					StreamOverlay.battle_lines[i]:Show()
				end

			elseif (#StreamOverlay.battle_lines > amountOfLines) then
				for i = #StreamOverlay.battle_lines, amountOfLines + 1, -1 do
					StreamOverlay.battle_lines[i]:Hide()
				end
				for i = 1, amountOfLines do
					StreamOverlay.battle_lines[i]:Show()
				end
			else
				for i = 1, amountOfLines do
					StreamOverlay.battle_lines[i]:Show()
				end
			end

			local width = SOF:GetWidth() / 2
			text1Size, text2Size = width - 28, width - 30

			StreamOverlay:UpdateLines()
			StreamOverlay:RefreshInUse()
		end
	end

	function StreamOverlay:SetBackgroundColor(r, g, b, a)
		if (not r) then
			r, g, b, a = unpack(StreamOverlay.db.main_frame_color)
		else
			local c = StreamOverlay.db.main_frame_color
			c[1], c[2], c[3], c[4] = r, g, b, a
		end
		SOF:SetBackdropColor(r, g, b, a)
	end

	function StreamOverlay:ApplyBackgroundColor(r, g, b, a)
		SOF:SetBackdropColor(r, g, b, a)
	end
end

local COLOR_HARMFUL = {.9, .5, .5, .4}
local COLOR_HELPFUL = {.1, .9, .1, .4}
local COLOR_ATTKCOOLDOWN = {1, 1, 0, .6}
local COLOR_DEFECOOLDOWN = {1, 1, 1, .6}
local COLOR_BORDER_DEFAULT = {0, 0, 0, 0}
local COLOR_BORDER_ABSORB = {1, 1, 0, 0.5}

local HarmfulSpellsTable = StreamOverlay.HarmfulSpells
local HelpfulSpellsTable = StreamOverlay.HelpfulSpells
local AttackCooldownSpellsTable = StreamOverlay.AttackCooldownSpells
local ClassSpellsTable = StreamOverlay.MiscClassSpells
local CooldownTable = StreamOverlay.DefensiveCooldownSpells
local ClassColorsTable = StreamOverlay.class_colors
local ClassSpellList = StreamOverlay.ClassSpellList 
local AbsorbSpellsTable = StreamOverlay.AbsorbSpells

local ignoredSpells = {
	[49821] = true, --mind sear ticks
	[121557] = true, --angelic feather walkon
}

--spell types:
-- 1 attack cooldown
-- 2 personal defensive cooldown
-- 3 targetted defensive cooldown
-- 4 raid defensive cooldown
-- 5 personal utility cooldown
-- 6 interrupt

local spellTypeColor = {
	[1] = COLOR_ATTKCOOLDOWN,
	[2] = COLOR_DEFECOOLDOWN,
	[3] = COLOR_DEFECOOLDOWN,
	[4] = COLOR_DEFECOOLDOWN,
}

function StreamOverlay:GetSpellInformation(spellId)
	local _, _, icon = GetSpellInfo(spellId)

	local backgroundcolor

	local spellInfo = LIB_OPEN_RAID_COOLDOWNS_INFO[spellId]
	if (spellInfo) then
		backgroundcolor = spellTypeColor[spellInfo.type]
	end

	if (HarmfulSpellsTable[spellId]) then
		backgroundcolor = COLOR_HARMFUL

	elseif (HelpfulSpellsTable[spellId]) then
		backgroundcolor = COLOR_HELPFUL

	elseif (AttackCooldownSpellsTable[spellId]) then
		backgroundcolor = COLOR_ATTKCOOLDOWN

	elseif (CooldownTable[spellId]) then
		backgroundcolor = COLOR_DEFECOOLDOWN

	elseif (ClassSpellsTable[spellId]) then
		local class = ClassSpellList [spellId]
		backgroundcolor = ClassColorsTable [class]

	else
		if (not backgroundcolor) then
			backgroundcolor = COLOR_HARMFUL
		end
	end

	local bordercolor
	if (AbsorbSpellsTable[spellId]) then
		bordercolor = COLOR_BORDER_ABSORB
	else
		bordercolor = COLOR_BORDER_DEFAULT
	end

	return icon, backgroundcolor, bordercolor
end

local RoleIcons = "Interface\\LFGFRAME\\UI-LFG-ICON-PORTRAITROLES"
local RoleIconsCoord = {
	["TANK"] = {0, 0.28125, 0.328125, 0.625},
	["HEALER"] = {0.3125, 0.59375, 0, 0.296875},
	["DAMAGER"] = {0.3125, 0.59375, 0.328125, 0.625},
	["NONE"] = {0.3125, 0.59375, 0.328125, 0.625}
}
local DefaultCoords = {0, 1, 0, 1}
local DefaultColor = {r=1, g=1, b=1}
local PetCoords = {0.25, 0.49609375, 0.75, 1}

local parse_target_name = function(target)
	return StreamOverlay:GetOnlyName(target)
end

local parse_target_icon = function(targetObject, target)
	local icon2, icon2coords, pclass
	if (targetObject) then
		local role = targetObject.role
		pclass = targetObject.classe
		if (role) then
			icon2 = RoleIcons
			icon2coords = RoleIconsCoord [role]
		else
			local class = targetObject.classe
			if (class == "PET") then
				icon2 = [[Interface\AddOns\Details\images\classes_small_alpha]]
				icon2coords = PetCoords
			elseif (class and RAID_CLASS_COLORS [class]) then
				if (targetObject.spec) then
					icon2 = [[Interface\AddOns\Details\images\spec_icons_normal_alpha]]
					icon2coords = Details.class_specs_coords [targetObject.spec]
				else
					local spec_from_cache = Details.cached_specs [targetObject.serial]
					if (spec_from_cache) then
						icon2 = [[Interface\AddOns\Details\images\spec_icons_normal_alpha]]
						icon2coords = Details.class_specs_coords [spec_from_cache]
					else
						icon2 = [[Interface\AddOns\Details\images\classes_small_alpha]]
						icon2coords = Details.class_coords [class]
					end
				end
			else
				local _, class = UnitClass(targetObject.nome)
				if (class) then
					icon2 = [[Interface\AddOns\Details\images\classes_small_alpha]]
					icon2coords = Details.class_coords [class]
				else
					icon2 = ""
					icon2coords = DefaultCoords
				end
			end
		end
	else
		local _, class = UnitClass(target)
		if (class) then
			icon2 = [[Interface\AddOns\Details\images\classes_small_alpha]]
			icon2coords = Details.class_coords [class]
			pclass = class
		else
			icon2 = ""
			icon2coords = DefaultCoords
		end
	end
	
	if (icon2 == "") then
		icon2 = [[Interface\CURSOR\Attack]]
		icon2 = [[Interface\CURSOR\UnableAttack]]
		icon2coords = {1, 0, 0, 1}
	end
	return icon2, icon2coords, pclass
end

local parse_target_color = function(class)
	local color2 = RAID_CLASS_COLORS [class]
	return color2
end

function StreamOverlay:CastStart (castGUID)
	local spellid = CastsTable [castGUID].SpellId
	local target = CastsTable [castGUID].Target
	local caststart = CastsTable [castGUID].CastStart

	local startTime = CastsTable [castGUID].CastTimeStart
	local endTime = CastsTable [castGUID].CastTimeEnd

	if (ignoredSpells [spellid]) then
		return
	end

	local icon, backgroundcolor, bordercolor = StreamOverlay:GetSpellInformation (spellid)
	local spellname, _, spellicon = GetSpellInfo(spellid)

	local targetObject = Details:GetActor("current", 1, target) or Details:GetActor("current", 2, target)
	local icon2, icon2coords, class = parse_target_icon (targetObject, target)
	
	local color2
	if (icon2 == RoleIcons) then
		color2 = parse_target_color (class)
		if (not color2) then
			color2 = DefaultColor
		end
	else
		color2 = DefaultColor
	end
	
	target = parse_target_name (target)
	
	StreamOverlay:NewText (spellicon, spellname, color1, icon2, icon2coords, target, color2, backgroundcolor, bordercolor, castGUID, caststart, startTime, endTime)
end

function StreamOverlay:CastFinished (castid)
	local spellid = CastsTable [castid].SpellId
	local target = CastsTable [castid].Target
	local caststart = CastsTable [castid].CastStart
	local hascasttime = CastsTable [castid].HasCastTime
	
	if (ignoredSpells [spellid]) then
		return
	end
	
	if (hascasttime) then
		--just finished a casted cast
		CastsTable [castid].Success = true
		
	else
		--just casted a instant spell
		
		local icon, backgroundcolor, bordercolor = StreamOverlay:GetSpellInformation (spellid)
		local spellname, _, spellicon = GetSpellInfo(spellid)
		
		local targetObject = Details:GetActor("current", 1, target) or Details:GetActor("current", 2, target)
		
		local icon2, icon2coords, class = parse_target_icon (targetObject, target)
		
		local color2
		if (icon2 == RoleIcons) then
			color2 = parse_target_color (class)
			if (not color2) then
				color2 = DefaultColor
			end
		else
			color2 = DefaultColor
		end
		
		target = parse_target_name (target)
		
		StreamOverlay:NewText (spellicon, spellname, nil, icon2, icon2coords, target, color2, backgroundcolor, bordercolor, castid, caststart, GetTime(), GetTime()+1.2)
	end
end

eventFrame.track_spell_cast = function()

	if (not StreamOverlay.db.use_square_mode) then
		for i = 1, #StreamOverlay.battle_content do
			local content = StreamOverlay.battle_content [i]
			local line = StreamOverlay.battle_lines [i]
			local castinfo = CastsTable [content.CastID]
			
			if (not castinfo.Done) then

				--is being casted?
				if (castinfo.HasCastTime) then
					if (castinfo.Success) then
						--okey it's done
						castinfo.Done = true
						castinfo.Percent = 100
						line.statusbar:SetValue(100)
						line.spark:SetPoint("left", line.statusbar, "left", (line.statusbar:GetWidth() / 100 * 100) - 8, 0)
						--line.spark:Hide()
						
					elseif (castinfo.Interrupted) then
						--has been interrupted
						castinfo.Done = true
						line.spark:SetVertexColor(1, 0.7, 0)
						
					elseif (castinfo.IsChanneled) then
						--casting a channeled spell
						local name, text, texture, startTime, endTime, isTradeSkill, notInterruptible = UnitChannelInfo ("player")

						if (name) then
							startTime = startTime / 1000
							endTime = endTime / 1000
							
							local diff = endTime - startTime
							local current = GetTime() - startTime
							local percent = current / diff * 100
							percent = math.abs(percent - 100)
							castinfo.Percent = percent
							line.statusbar:SetValue(percent)
							if (StreamOverlay.db.use_spark) then
								line.spark:Show()
							else
								line.spark:Hide()
							end

							line.spark:SetVertexColor(1, 1, 1, 1)
							line.spark:SetPoint("left", line.statusbar, "left", (line.statusbar:GetWidth() / 100 * percent) - 6, 0)
						end

					else
						--still casting
						local spell, displayName, icon, startTime, endTime, isTradeSkill, castID, interrupt = UnitCastingInfo("player")
						if (spell) then
							startTime = startTime / 1000
							endTime = endTime / 1000
							
							local diff = endTime - startTime
							local current = GetTime() - startTime
							
							local percent = current / diff * 100
							castinfo.Percent = percent
							line.statusbar:SetValue(percent)
							if (StreamOverlay.db.use_spark) then
								line.spark:Show()
							else
								line.spark:Hide()
							end
							line.spark:SetVertexColor(1, 1, 1, 1)
							line.spark:SetPoint("left", line.statusbar, "left", (line.statusbar:GetWidth() / 100 * percent) - 6, 0)
						end
					end
					
				else
					--it's instant cast
					if (castinfo.CastStart+1.2 < GetTime()) then
						castinfo.Done = true
						castinfo.Percent = 100
						line.statusbar:SetValue(100)
						line.spark:SetPoint("left", line.statusbar, "left", (line.statusbar:GetWidth() / 100 * 100) - 8, 0)
						--line.spark:Hide()
					else
						local startTime = castinfo.CastStart
						local endTime = (castinfo.CastStart + 1.2)
						
						local diff = endTime - startTime
						local current = GetTime() - startTime
						
						local percent = current / diff * 100
						castinfo.Percent = percent
						line.statusbar:SetValue(percent)
						
						if (StreamOverlay.db.use_spark) then
							line.spark:Show()
						else
							line.spark:Hide()
						end
						
						line.spark:SetVertexColor(1, 1, 1, 1)
						line.spark:SetPoint("left", line.statusbar, "left", (line.statusbar:GetWidth() / 100 * percent) - 6, 0)
					end
				end
				
				line.in_use = GetTime()
			end
		end
	else
		for i = 1, #StreamOverlay.battle_content do
			local content = StreamOverlay.battle_content[i]
			local line = StreamOverlay.squares[i]
			local castinfo = CastsTable[content.CastID]
			
			StreamOverlay:ApplyBackgroundColor(0, 0, 0, 0)

			if (not castinfo.Done and line) then

				--is being casted?
				if (castinfo.HasCastTime) then
					if (castinfo.Success) then
						--okey it's done
						castinfo.Done = true
						castinfo.Percent = 100
						StreamOverlay:UpdateCooldownFrame(line, false)
						
					elseif (castinfo.Interrupted) then
						--has been interrupted
						castinfo.Done = true
						local totalTime = castinfo.CastTimeEnd - castinfo.CastTimeStart
						local pct = castinfo.CastTimeEnd - GetTime()
						castinfo.InterruptedPct = pct / totalTime
						
					elseif (castinfo.IsChanneled) then
						--casting a channeled spell
						local name, text, texture, startTime, endTime, isTradeSkill, notInterruptible = UnitChannelInfo ("player")

						if (name) then
							startTime = startTime / 1000
							endTime = endTime / 1000
							
							local diff = endTime - startTime
							local current = GetTime() - startTime
							local percent = current / diff * 100
							percent = math.abs(percent - 100)
							castinfo.Percent = percent
							StreamOverlay:UpdateCooldownFrame(line, true, startTime, endTime, castinfo)
						end

					else
						--still casting
						local spell, displayName, icon, startTime, endTime, isTradeSkill, castID, interrupt = UnitCastingInfo ("player")
						if (spell) then
							startTime = startTime / 1000
							endTime = endTime / 1000
							local diff = endTime - startTime
							local current = GetTime() - startTime
							local percent = current / diff * 100
							castinfo.Percent = percent
							StreamOverlay:UpdateCooldownFrame(line, true, startTime, endTime, castinfo)
						end
					end
					
				else
					--it's instant cast
					if (castinfo.CastStart+1.2 < GetTime()) then
						castinfo.Done = true
						castinfo.Percent = 100
						StreamOverlay:UpdateCooldownFrame(line, false)

					else
						local startTime = castinfo.CastStart
						local endTime = (castinfo.CastStart + 1.2)
						local diff = endTime - startTime
						local current = GetTime() - startTime
						local percent = current / diff * 100
						castinfo.Percent = percent

						StreamOverlay:UpdateCooldownFrame(line, true, startTime, endTime, castinfo)
					end
				end
				
				line.in_use = GetTime()

			elseif (castinfo.Done and line) then
				if (castinfo.Interrupted and castinfo.InterruptedPct) then
					StreamOverlay:UpdateCooldownFrame(line, true, castinfo.CastTimeStart, castinfo.InterruptedTime, castinfo)
				end
			end
		end
	end
end

function eventFrame:RegisterMyEvents()
	eventFrame:RegisterEvent ("UNIT_SPELLCAST_START")
	eventFrame:RegisterEvent ("UNIT_SPELLCAST_SENT")
	eventFrame:RegisterEvent ("UNIT_SPELLCAST_SUCCEEDED")
	eventFrame:RegisterEvent ("UNIT_SPELLCAST_INTERRUPTED")
	eventFrame:RegisterEvent ("UNIT_SPELLCAST_FAILED_QUIET")
	eventFrame:RegisterEvent ("UNIT_SPELLCAST_FAILED")
	eventFrame:RegisterEvent ("UNIT_SPELLCAST_DELAYED")
	eventFrame:RegisterEvent ("UNIT_SPELLCAST_CHANNEL_START")
	eventFrame:RegisterEvent ("UNIT_SPELLCAST_CHANNEL_STOP")
	eventFrame:RegisterEvent ("UNIT_SPELLCAST_CHANNEL_UPDATE")
	eventFrame:RegisterEvent ("UNIT_SPELLCAST_STOP")

	if (not DetailsFramework.IsTBCWow() and not DetailsFramework.IsWotLKWow()) then
		eventFrame:RegisterEvent ("UNIT_SPELLCAST_INTERRUPTIBLE")
		eventFrame:RegisterEvent ("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
	end
end

function eventFrame:UnregisterMyEvents()
	eventFrame:UnregisterEvent ("UNIT_SPELLCAST_START")
	eventFrame:UnregisterEvent ("UNIT_SPELLCAST_SENT")
	eventFrame:UnregisterEvent ("UNIT_SPELLCAST_SUCCEEDED")
	eventFrame:UnregisterEvent ("UNIT_SPELLCAST_INTERRUPTED")
	eventFrame:UnregisterEvent ("UNIT_SPELLCAST_FAILED_QUIET")
	eventFrame:UnregisterEvent ("UNIT_SPELLCAST_FAILED")
	eventFrame:UnregisterEvent ("UNIT_SPELLCAST_DELAYED")
	eventFrame:UnregisterEvent ("UNIT_SPELLCAST_CHANNEL_START")
	eventFrame:UnregisterEvent ("UNIT_SPELLCAST_CHANNEL_STOP")
	eventFrame:UnregisterEvent ("UNIT_SPELLCAST_CHANNEL_UPDATE")
	eventFrame:UnregisterEvent ("UNIT_SPELLCAST_STOP")

	if (not DetailsFramework.IsTBCWow() and not DetailsFramework.IsWotLKWow()) then
		eventFrame:UnregisterEvent ("UNIT_SPELLCAST_INTERRUPTIBLE")
		eventFrame:UnregisterEvent ("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
	end
end

local lastspell, lastcastid, lastchannelid, ischanneling, lastspellID
local channelspells = {}
local lastChannelSpell = ""

local APM = 0
local ACTIONS = 0
local ACTIONS_EVENT_TIME = {}
local AMP_Tick = C_Timer.NewTicker(1, function()
	APM = ACTIONS * 60
	ACTIONS = 0
end)
local APM_FRAME = CreateFrame("frame", "DetailsAPMFrame", UIParent, "BackdropTemplate")
APM_FRAME:RegisterEvent ("PLAYER_STARTED_MOVING")
APM_FRAME:RegisterEvent ("PLAYER_STOPPED_MOVING")
APM_FRAME:SetScript("OnEvent", function()
	ACTIONS = ACTIONS + 1
end)

eventFrame:SetScript("OnEvent", function(self, event, ...)
	if (event ~= "UNIT_SPELLCAST_SENT" and event ~= "UNIT_SPELLCAST_SUCCEEDED" and ACTIONS_EVENT_TIME [event] ~= GetTime()) then
		ACTIONS = ACTIONS + 1
		ACTIONS_EVENT_TIME [event] = GetTime()
	end

	if (event == "UNIT_SPELLCAST_SENT") then
		local unitID, target, castGUID, spellID = ...
		--local unitID, spell, rank, target, id = ...
		local spell = GetSpellInfo(spellID)
		
		if (unitID == "player") then
			CastsTable [castGUID] = {Target = target or "", Id = castGUID, CastStart = GetTime()}
			lastChannelSpell = castGUID
			lastspell = spell
			lastspellID = spellID
			lastcastid = castGUID
		end
	
	elseif (event == "UNIT_SPELLCAST_START") then
		--spell, rank, id, 
		local unitID, castGUID, spellID = ...
		
		if (unitID == "player" and CastsTable [castGUID]) then
			CastsTable [castGUID].SpellId = spellID
			CastsTable [castGUID].HasCastTime = true

			local name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible, spellId = UnitCastingInfo("player")
			CastsTable [castGUID].CastTimeStart = startTime / 1000
			CastsTable [castGUID].CastTimeEnd = endTime / 1000

			StreamOverlay:CastStart(castGUID)
		end
	
	elseif (event == "UNIT_SPELLCAST_INTERRUPTED") then
		--local unitID, spell, rank, id, spellID = ...
		local unitID, castGUID, spellID = ...
		
		if (unitID == "player" and CastsTable [castGUID]) then
			CastsTable [castGUID].Interrupted = true
			CastsTable [castGUID].InterruptedTime = GetTime()
		end

	--channels isn't passing the CastID / cast id for channels is always Zero.
	elseif (event == "UNIT_SPELLCAST_CHANNEL_STOP") then
		--local unitID, spell, rank, id, spellID = ...
		local unitID, castGUID, spellID = ...
		
		if (unitID == "player") then
			castGUID = lastchannelid
		
			if (not CastsTable [castGUID]) then
				castGUID = lastChannelSpell
				if (not castGUID or not CastsTable [castGUID]) then
					return
				end
			end
			CastsTable [castGUID].Interrupted = true
			CastsTable [castGUID].InterruptedTime = GetTime()
			ischanneling = false
			lastchannelid = nil
		end
	
	elseif (event == "UNIT_SPELLCAST_CHANNEL_START") then
		
		local unitID, castGUID, spellID = ...
		
		if (unitID == "player" and (CastsTable [castGUID] or spellID == lastspellID)) then
			if (castGUID == "" or not castGUID) then
				castGUID = lastcastid
			end
			
			if (ischanneling) then
				--channel updated
				CastsTable [lastchannelid].Interrupted = true
				CastsTable [lastchannelid].InterruptedTime = GetTime()
			end
			
			if (not CastsTable [castGUID]) then
				castGUID = lastChannelSpell
			end
			
			CastsTable [castGUID].HasCastTime = true
			CastsTable [castGUID].IsChanneled = true
			CastsTable [castGUID].SpellId = spellID
			lastchannelid = castGUID
			ischanneling = true

			local name, text, texture, startTime, endTime, isTradeSkill, notInterruptible, spellId = UnitChannelInfo("player")
			CastsTable [castGUID].CastTimeStart = startTime / 1000
			CastsTable [castGUID].CastTimeEnd = endTime / 1000
			
			local spell = GetSpellInfo(spellID)
			channelspells[spell] = true
			
			StreamOverlay:CastStart(castGUID)
		end
	
	elseif (event == "UNIT_SPELLCAST_SUCCEEDED") then
		--local unitID, spell, rank, id, spellID = ...
		local unitID, castGUID, spellID = ...
		local spell = GetSpellInfo(spellID)
		
		if (unitID == "player" and CastsTable[castGUID] and not channelspells [spell]) then
			if (CastsTable[castGUID].HasCastTime and not CastsTable[castGUID].IsChanneled) then
				--a cast (non channeled) just successful finished
				CastsTable [castGUID].Success = true
				StreamOverlay:CastFinished (castGUID)
				
			elseif (not CastsTable[castGUID].HasCastTime) then
				--instant cast finished
				CastsTable [castGUID].SpellId = spellID
				CastsTable [castGUID].Success = true
				StreamOverlay:CastFinished (castGUID)
			end
		end
	end
	
end)

local format_time = function(v) return "-" .. format("%.2f", v) end

--when the player die, show the events before the death
function StreamOverlay.OnDeath (_, token, time, who_serial, who_name, who_flags, alvo_serial, alvo_name, alvo_flags, death_table, last_cooldown, death_at_combattime, max_health)

	if (alvo_serial ~= UnitGUID("player")) then
		return
	end

	StreamOverlay:ClearAll()

	for i = 1, #death_table do
		local ev = death_table [i]
		if (ev and type(ev) == "table" and ev[1] and type(ev[1]) == "boolean") then
			--it's a damage
			local spellid = ev[2]
			local amount = ev[3]
			local attime = ev[4]
			local health = ev[5]
			local source = ev[6]
			local absorbed = ev[7]
			
			--get the actor from details
			local sourceObject = Details:GetActor("current", 1, source)
			local classIcon, l, r, t, b
			if (sourceObject) then
				classIcon, l, r, t, b = StreamOverlay:GetClassIcon (sourceObject.classe)
			else
				classIcon, l, r, t, b = defaultAttackIcon, 0, 1, 0, 1
			end
			
			--spellname
			local spellname, _, spellicon = StreamOverlay.getspellinfo (spellid)
			source = StreamOverlay:GetOnlyName(source)
			
			local CastInfoIndex = i * -1
			
			local percent = health / max_health * 100
			percent = math.min (percent, 100)
			--HasCastTime has to be true, this can't be considered a instant cast
			--Done = won't be touch during cast bar updates
			--Percent is used on the bar text updates
			--Interrupted / Death is irrelevant at this point because the bar is flagged as Done
			CastsTable [CastInfoIndex] = {Target = spellname, Id = CastInfoIndex, CastStart = GetTime(), HasCastTime = true, Interrupted = true, Done = true, Percent = percent, Death = true}
			
			local at = format_time (time - attime)
			
			local damage_color = "|cFFFFFFFF"
			if (amount > 100000) then
				damage_color = "|cFFFF3300"
			elseif (amount > 75000) then
				damage_color = "|cFFFF6600"
			elseif (amount > 50000) then
				damage_color = "|cFFFF9900"
			elseif (amount > 25000) then
				damage_color = "|cFFFFAA00"
			elseif (amount > 10000) then
				damage_color = "|cFFFFFF66"
			elseif (amount > 5000) then
				damage_color = "|cFFFFFFAA"
			end
			
			--adds the text to the line
			StreamOverlay:NewText (spellicon, at .. " | " .. damage_color .. StreamOverlay:ToK2 (amount) .. "|r (" .. spellname .. ")", {1, 1, 1, 1}, classIcon, {l, r, t, b}, source, {r=1, g=1, b=1}, {1, 1, 1, 0.6}, {0, 0, 0}, CastInfoIndex, GetTime())
			
--			:NewText (icon1, text1, color1, icon2, icon2coords, text2, color2, backgroundcolor, bordercolor, ID, CastStart)
		end
	end
	
	StreamOverlay.ShowingDeath = true

end

--passes the new lock state
--the window is click throught when locked
function StreamOverlay:SetLocked (state)
	
	if (state == nil) then
		state = StreamOverlay.db.main_frame_locked
	end
	
	if (state) then
		--is locked
		StreamOverlay.db.main_frame_locked = true
		DetailsStreamerTitlebar:Hide()
		DetailsStreamerLeftResizer:Hide()
		DetailsStreamerRightResizer:Hide()
		SOF:EnableMouse(false)
	else
		--not locked
		StreamOverlay.db.main_frame_locked = false
		DetailsStreamerTitlebar:Show()
		DetailsStreamerLeftResizer:Show()
		DetailsStreamerRightResizer:Show()
		SOF:EnableMouse(true)
	end
	
	StreamOverlay:UpdateDpsHpsFrameConfig()
end

----------------------------------------------------------------------------------------------------------------------------------------------------------------
--on screen hps dps

local screen_frame = CreateFrame("frame", "StreamerOverlayDpsHpsFrame", UIParent, "BackdropTemplate")
screen_frame:SetSize(70, 20)
screen_frame:SetBackdrop({bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], tile = true, tileSize = 16, insets = {left = 0, right = 0, top = 0, bottom = 0}})
screen_frame:SetBackdropColor(.1, .1, .1, .9)
screen_frame:SetMovable(true)
screen_frame:Hide()
screen_frame:SetPoint("center", UIParent, "center")
screen_frame:SetScript("OnMouseDown", function(self)
	if (not screen_frame.moving and not StreamOverlay.db.main_frame_locked) then
		screen_frame:StartMoving()
		screen_frame.moving = true
		screen_frame.movingAt = GetTime()
	end
end)
screen_frame:SetScript("OnMouseUp", function(self)
	if (screen_frame.movingAt) then
		if (screen_frame.moving) then
			screen_frame.moving = false
			screen_frame:StopMovingOrSizing()
			StreamOverlay:SaveWindowSizeAnLocation()
		end
		
		if (screen_frame.movingAt+0.200 < GetTime()) then
			return
		end
		screen_frame.movingAt = nil
		
		StreamOverlay.OpenOptionsPanel()
	end
end)
screen_frame:SetScript("OnEnter", function(self) 
	GameTooltip:SetOwner(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
	GameTooltip:AddLine("|cFFFF7700Left Click|r: Open Options\n|cFFFF7700Slash Command|r: /streamer")
	GameTooltip:Show()
end)
screen_frame:SetScript("OnLeave", function() 
	GameTooltip:Hide()
end)
	
	
local screen_frame_text = screen_frame:CreateFontString("StreamerOverlayDpsHpsFrameText", "overlay", "GameFontNormal")
screen_frame_text:SetPoint("center", screen_frame, "center")
screen_frame.text = screen_frame_text

local screen_frame_attribute = 1
local format_function

function StreamOverlay:UpdateDpsHpsFrameConfig (PluginDisabled)
	
	if (PluginDisabled) then
		if (StreamOverlay.DpsHpsTick) then
			StreamOverlay.DpsHpsTick:Cancel()
			StreamOverlay.DpsHpsTick = nil
		end
		screen_frame:Hide()
		return
	end
	
	local db = StreamOverlay.db.per_second

	StreamOverlay:SetFontSize (screen_frame.text, db.size)
	StreamOverlay:SetFontOutline (screen_frame.text, db.font_shadow)
	screen_frame:SetScale(db.scale)
	
	screen_frame_attribute = db.attribute_type
	format_function = Details:GetCurrentToKFunction()
	
	if (StreamOverlay.db.main_frame_locked) then
		screen_frame:SetBackdrop(nil)
		screen_frame:EnableMouse(false)
	else
		screen_frame:SetBackdrop({bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], tile = true, tileSize = 16, insets = {left = 0, right = 0, top = 0, bottom = 0}})
		screen_frame:SetBackdropColor(.1, .1, .1, .9)
		screen_frame:EnableMouse(true)
	end
	
	if (db.enabled) then
		screen_frame:Show()
		if (StreamOverlay.DpsHpsTick) then
			StreamOverlay.DpsHpsTick:Cancel()
			StreamOverlay.DpsHpsTick = nil
		end
		StreamOverlay.DpsHpsTick = C_Timer.NewTicker(db.update_speed, StreamOverlay.UpdateDpsHpsFrame)
	else
		screen_frame:Hide()
		if (StreamOverlay.DpsHpsTick) then
			StreamOverlay.DpsHpsTick:Cancel()
			StreamOverlay.DpsHpsTick = nil
		end
	end
	
	--update the dps hps frame text
	StreamOverlay:SetFontFace (StreamerOverlayDpsHpsFrameText, SharedMedia:Fetch ("font", StreamOverlay.db.font_face))
	StreamOverlay:SetFontColor(StreamerOverlayDpsHpsFrameText, StreamOverlay.db.font_color)
	
end

function StreamOverlay:UpdateDpsHpsFrame()
	--low level actor parsing - we can just use Details:GetActor(), but is faster without having to call functions
	local container = _detalhes.tabela_vigente [screen_frame_attribute]
	local actor = container._ActorTable [container._NameIndexTable [playerName]]
	
	if (actor) then
		screen_frame_text:SetText(format_function (_, actor.total / _detalhes.tabela_vigente:GetCombatTime()))
	else
		if (StreamOverlay.db.per_second.attribute_type == 1) then
			screen_frame_text:SetText("DPS")
		else
			screen_frame_text:SetText("HPS")
		end
	end
end


----------------------------------------------------------------------------------------------------------------------------------------------------------------

function StreamOverlay.OpenOptionsPanel (fromOptionsPanel)
	if (not StreamOverlayOptionsPanel) then
		local detailsFramework = Details:GetFramework()

		local options_text_template = detailsFramework:GetTemplate("font", "OPTIONS_FONT_TEMPLATE")
		local options_dropdown_template = detailsFramework:GetTemplate("dropdown", "OPTIONS_DROPDOWN_TEMPLATE")
		local options_switch_template = detailsFramework:GetTemplate("switch", "OPTIONS_CHECKBOX_TEMPLATE")
		local options_slider_template = detailsFramework:GetTemplate("slider", "OPTIONS_SLIDER_TEMPLATE")
		local options_button_template = detailsFramework:GetTemplate("button", "OPTIONS_BUTTON_TEMPLATE")

		local optionsFrame = StreamOverlay:CreatePluginOptionsFrame("StreamOverlayOptionsPanel", "Details! Streamer: Action Tracker", 1)
		optionsFrame:SetBackdrop({edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1, bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], tileSize = 64, tile = true})
		optionsFrame:SetBackdropColor(0, 0, 0, 0.5)
		optionsFrame:SetBackdropBorderColor(0, 0, 0, 1)
		optionsFrame:SetWidth(535)
		optionsFrame:SetHeight(655)

		if (StreamOverlayWelcomeWindow) then
			if (StreamOverlayWelcomeWindow:IsShown()) then
				StreamOverlayWelcomeWindow:Hide()
			end
		end

		local statusBar = DetailsFramework:CreateStatusBar(optionsFrame)
		statusBar.text = statusBar:CreateFontString(nil, "overlay", "GameFontNormal")
		statusBar.text:SetPoint("left", statusBar, "left", 5, 0)
		statusBar.text:SetText("By Terciob | From Details! Damage Meter Streamer Plugin")
		DetailsFramework:SetFontSize(statusBar.text, 11)
		DetailsFramework:SetFontColor(statusBar.text, "gray")

		StreamOverlayOptionsPanelBackgroundBigDog:ClearAllPoints()
		StreamOverlayOptionsPanelBackgroundBigDog:SetPoint("bottomright", statusBar, "topright", 0, 0)

		local selectModeFrame = CreateFrame("frame", nil, optionsFrame, "BackdropTemplate")
		DetailsFramework:ApplyStandardBackdrop(selectModeFrame)
		selectModeFrame:SetPoint("topleft", optionsFrame, "topleft", 5, -95)
		selectModeFrame:SetSize(optionsFrame:GetWidth() - 10, 120)

		local selectedFrame = CreateFrame("frame", nil, selectModeFrame, "BackdropTemplate")
		selectedFrame:SetSize(260, 81)
		selectedFrame:SetBackdrop({edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 3})
		selectedFrame:SetBackdropBorderColor(1, 1, 0, 0.75)

		local selectClassicMode = function()
			StreamOverlay.db.use_square_mode = false
			StreamOverlay:Refresh()
			selectedFrame:SetPoint("topleft", selectModeFrame.classicModeSelectButton.widget, "topleft", -3, 3)
			selectedFrame:SetSize(238, 84)
		end

		local selectSquareMode = function()
			StreamOverlay.db.use_square_mode = true
			StreamOverlay:Refresh()
			selectedFrame:SetPoint("topleft", selectModeFrame.squareModeSelectButton.widget, "topleft", -6, 3)
			selectedFrame:SetSize(240, 84)
		end

		local selectModeLabel = DetailsFramework:CreateLabel(selectModeFrame, "Select Mode (test casting some spells)", 14, "orange")
		selectModeLabel:SetPoint("top", optionsFrame, "top", 0, -100)

		local classicModeSelectButton = DetailsFramework:CreateButton(selectModeFrame, selectClassicMode, 256, 77, "")
		classicModeSelectButton:SetPoint("topleft", optionsFrame, "topleft", 15, -120)
		local classicModeTexture = classicModeSelectButton:CreateTexture(nil, "overlay")
		classicModeTexture:SetTexture([[Interface\Addons\Details_Streamer\images\tracker_full]])
		classicModeTexture:SetAllPoints()
		classicModeTexture:SetTexCoord(0, 1, .15, .75)

		local squareModeSelectButton = DetailsFramework:CreateButton(selectModeFrame, selectSquareMode, 200, 77, "")
		squareModeSelectButton:SetPoint("left", classicModeSelectButton, "right", 0, 0)
		local squareModeTexture = squareModeSelectButton:CreateTexture(nil, "overlay")
		squareModeTexture:SetTexture([[Interface\Addons\Details_Streamer\images\tracker_square]])
		squareModeTexture:SetPoint("center", 25, -10)

		selectModeFrame.classicModeSelectButton = classicModeSelectButton
		selectModeFrame.squareModeSelectButton = squareModeSelectButton

		if (StreamOverlay.db.use_square_mode) then
			selectSquareMode()
		else
			selectClassicMode()
		end

		-- select texture
		local setRowTexture = function(_, _, value)
			StreamOverlay.db.row_texture = value
			StreamOverlay:RefreshAllBattleLineStyle()
		end
		local textures = SharedMedia:HashTable("statusbar")
		local textureTable = {}
		for name, texturePath in pairs(textures) do
			textureTable[#textureTable+1] = {value = name, label = name, statusbar = texturePath, onclick = setRowTexture}
		end
		table.sort(textureTable, function(t1, t2) return t1.label < t2.label end)

		--select font
		local setFontFace = function(_, _, value)
			StreamOverlay.db.font_face = value
			StreamOverlay:RefreshAllBattleLineStyle()
		end
		local fontObjects = SharedMedia:HashTable("font")
		local fontTable = {}
		for name, fontPath in pairs(fontObjects) do
			fontTable[#fontTable+1] = {value = name, label = name, onclick = setFontFace, font = fontPath, descfont = name}
		end
		table.sort(fontTable, function(t1, t2) return t1.label < t2.label end)

		-- select arrow
		local arrows = {
			[[Interface\CHATFRAME\ChatFrameExpandArrow]],
			[[Interface\CHATFRAME\UI-InChatFriendsArrow]],
			[[Interface\MONEYFRAME\Arrow-Right-Disabled]],
			[[Interface\OPTIONSFRAME\VoiceChat-Play]],
			[[Interface\MINIMAP\TrapInactive_HammerGold]],
			[[Interface\MINIMAP\Vehicle-HammerGold-1]],
			[[Interface\GossipFrame\BattleMasterGossipIcon]],
			[[Interface\GROUPFRAME\UI-GROUP-MAINASSISTICON]],
			[[Interface\GROUPFRAME\UI-GROUP-MAINTANKICON]],
			[[Interface\HELPFRAME\HelpIcon-ItemRestoration]],
			[[Interface\PetBattles\DeadPetIcon]],
			[[Interface\BattlefieldFrame\Battleground-Alliance]],
			[[Interface\BattlefieldFrame\Battleground-Horde]],
			[[Interface\Buttons\UI-SliderBar-Button-Vertical]],
			[[Interface\Buttons\UI-SpellbookIcon-NextPage-Up]],
			[[Interface\Buttons\UI-StopButton]],
			[[Interface\COMMON\friendship-heart]],
			[[Interface\COMMON\friendship-FistHuman]],
			[[Interface\COMMON\VOICECHAT-MUTED]],
			[[Interface\Glues\LOGIN\Glues-CheckBox-Check]],
			[[Interface\PvPRankBadges\PvPRank06]],
			[[Interface\Scenarios\ScenarioIcon-Boss]],
			[[Interface\Tooltips\ReforgeGreenArrow]],
		}

		local setArrowTextureCallback = function(_, _, value)
			StreamOverlay.db.arrow_texture = value
			StreamOverlay:RefreshAllBattleLineStyle()
		end

		local arrowIconTable = {}
		for _, arrow in ipairs(arrows) do
			arrowIconTable[#arrowIconTable+1] = {value = arrow, label = arrow:gsub("Interface(.*)\\", ""), onclick = setArrowTextureCallback, icon = arrow}
		end

		--

		local setWindowStrataCallback = function(_, _, strata)
			StreamOverlay.db.main_frame_strata = strata
			SOF:SetFrameStrata(strata)
			StreamerOverlayDpsHpsFrame:SetFrameStrata(strata)
		end
		local strataTable = {
			{value = "BACKGROUND", label = "Background", onclick = setWindowStrataCallback, icon = [[Interface\Buttons\UI-MicroStream-Green]], iconcolor = {0, .5, 0, .8}, texcoord = nil},
			{value = "LOW", label = "Low", onclick = setWindowStrataCallback, icon = [[Interface\Buttons\UI-MicroStream-Green]] , texcoord = nil},
			{value = "MEDIUM", label = "Medium", onclick = setWindowStrataCallback, icon = [[Interface\Buttons\UI-MicroStream-Yellow]] , texcoord = nil},
			{value = "HIGH", label = "High", onclick = setWindowStrataCallback, icon = [[Interface\Buttons\UI-MicroStream-Yellow]] , iconcolor = {1, .7, 0, 1}, texcoord = nil},
			{value = "DIALOG", label = "Dialog", onclick = setWindowStrataCallback, icon = [[Interface\Buttons\UI-MicroStream-Red]] , iconcolor = {1, 0, 0, 1},  texcoord = nil},
		}

		--

		local setTextPerSecondTypeCallback = function(_, _, value)
			StreamOverlay.db.per_second.attribute_type = value
		end
		local attributeTable = {
			{value = 1, label = "DPS", onclick = setTextPerSecondTypeCallback},
			{value = 2, label = "HPS", onclick = setTextPerSecondTypeCallback},
		}

		--

		local squareGrowOptions = {
			{value = "right", label = "RIGHT", onclick = function() StreamOverlay.db.square_grow_direction = "right"; StreamOverlay:ReorderSquares() end},
			{value = "left", label = "LEFT", onclick = function() StreamOverlay.db.square_grow_direction = "left"; StreamOverlay:ReorderSquares() end},
		}

		local options = {
			{
				type = "toggle",
				name = "Locked",
				desc = "Can't move or interact within the frame when it's locked.",
				order = 1,
				get = function() return StreamOverlay.db.main_frame_locked end,
				set = function(self, fixedParam, val) 
					StreamOverlay:SetLocked (not StreamOverlay.db.main_frame_locked)
				end,
			},

			{
				type = "toggle",
				name = "Minimap Icon",
				desc = "Show/Hide minimap icon.",
				order = 1,
				get = function() return not StreamOverlay.db.minimap.hide end,
				set = function(self, fixedParam, val) 
					StreamOverlay.db.minimap.hide = not StreamOverlay.db.minimap.hide
					if (LDBIcon) then
						LDBIcon:Refresh ("DetailsStreamer", StreamOverlay.db.minimap)
					end
				end,
			},

			{
				type = "color",
				get = function() return StreamOverlay.db.main_frame_color end,
				set = function(self, r, g, b, a) 
					StreamOverlay:SetBackgroundColor (r, g, b, a)
				end,
				desc = "Color used on the background.",
				name = "Background Color"
			},

			{
				type = "range",
				get = function() return StreamOverlay.db.scale or 1 end,
				set = function(self, fixedparam, value) StreamOverlay.db.scale = value; StreamOverlay.Frame:SetScale(value) end,
				min = 0.6,
				max = 2,
				step = 0.1,
				desc = "Scale",
				name = "Scale",
				usedecimals = true,
			},

			{type = "blank"},

			{
				type = "range",
				get = function() return StreamOverlay.db.row_height end,
				set = function(self, fixedparam, value) StreamOverlay.db.row_height = value; StreamOverlay:RefreshAllBattleLineStyle() end,
				min = 10,
				max = 30,
				step = 1,
				desc = "How hight is each bar.",
				name = "Bar Height",
			},
			
			{
				type = "range",
				get = function() return StreamOverlay.db.row_spacement end,
				set = function(self, fixedparam, value) StreamOverlay.db.row_spacement = value; StreamOverlay:RefreshAllBattleLineStyle() end,
				min = 8,
				max = 31,
				step = 1,
				desc = "How much space each bar use.",
				name = "Bar Space",
			},
			
			{
				type = "select",
				get = function() return StreamOverlay.db.row_texture end,
				values = function() return textureTable end,
				desc = "Which texture is used on bars.",
				name = "Bar Texture"
			},
			
			{
				type = "color",
				get = function() return StreamOverlay.db.row_color end,
				set = function(self, r, g, b, a) 
					local c = StreamOverlay.db.row_color
					c[1], c[2], c[3], c[4] = r, g, b, a
					StreamOverlay:RefreshAllBattleLineStyle()
				end,
				desc = "Color used on the background.",
				name = "Bar Color"
			},
			
			{type = "space"},
			
			{
				type = "range",
				get = function() return StreamOverlay.db.font_size end,
				set = function(self, fixedparam, value) StreamOverlay.db.font_size = value; StreamOverlay:RefreshAllBattleLineStyle() end,
				min = 8,
				max = 32,
				step = 1,
				desc = "The size of the text.",
				name = "Text Size",
			},
			
			{
				type = "select",
				get = function() return StreamOverlay.db.font_face end,
				values = function() return fontTable end,
				desc = "Font used on texts.",
				name = "Text Font"
			},
			
			{
				type = "color",
				get = function() return StreamOverlay.db.font_color end,
				set = function(self, r, g, b, a) 
					local c = StreamOverlay.db.font_color
					c[1], c[2], c[3], c[4] = r, g, b, a
					StreamOverlay:RefreshAllBattleLineStyle()
				end,
				desc = "Color used on texts.",
				name = "Text Color"
			},

			{type = "space"},
			
			{
				type = "toggle",
				name = "Show Dps/Hps",
				desc = "Show in the screen your current Dps or Hps.",
				order = 1,
				get = function() return StreamOverlay.db.per_second.enabled end,
				set = function(self, fixedParam, val) 
					StreamOverlay.db.per_second.enabled = not StreamOverlay.db.per_second.enabled
					-- update hps dps frame
					StreamOverlay:UpdateDpsHpsFrameConfig()
				end,
			},
			
			{
				type = "select",
				get = function() return StreamOverlay.db.per_second.attribute_type end,
				values = function() return attributeTable end,
				desc = "Show DPS or HPS.",
				name = "Show"
			},
			
			{
				type = "range",
				get = function() return StreamOverlay.db.per_second.size end,
				set = function(self, fixedparam, value) StreamOverlay.db.per_second.size = value; 
					-- update hps dps frame
					StreamOverlay:UpdateDpsHpsFrameConfig()
				end,
				min = 8,
				max = 32,
				step = 1,
				desc = "The size of the text.",
				name = "Dps/Hps Text Size",
			},
			
			{
				type = "range",
				get = function() return StreamOverlay.db.per_second.scale end,
				set = function(self, fixedparam, value) StreamOverlay.db.per_second.scale = value; 
					-- update hps dps frame
					StreamOverlay:UpdateDpsHpsFrameConfig()
				end,
				min = 0.65,
				max = 1.5,
				step = 1,
				desc = "The size of the text.",
				name = "Dps/Hps Scale",
				usedecimals = true,
			},
			
			{
				type = "range",
				get = function() return StreamOverlay.db.per_second.update_speed end,
				set = function(self, fixedparam, value) StreamOverlay.db.per_second.update_speed = value; 
					-- update hps dps frame
					StreamOverlay:UpdateDpsHpsFrameConfig()
				end,
				min = 0.016,
				max = 1,
				step = 0.016,
				desc = "How fast the frame get updated.",
				name = "Dps/Hps Update Speed",
				usedecimals = true,
			},
			
			{
				type = "toggle",
				name = "Dps/Hps Text Shadow",
				desc = "Enable text shadow.",
				order = 1,
				get = function() return StreamOverlay.db.per_second.font_shadow end,
				set = function(self, fixedParam, val) 
					StreamOverlay.db.per_second.font_shadow = not StreamOverlay.db.per_second.font_shadow
					-- update hps dps frame
					StreamOverlay:UpdateDpsHpsFrameConfig()
				end,
			},

			{type = "breakline"},

			{
				type = "range",
				get = function() return StreamOverlay.db.square_amount end,
				set = function(self, fixedparam, value) 
					StreamOverlay.db.square_amount = value
					StreamOverlay:Refresh()
				end,
				min = 3,
				max = 16,
				step = 1,
				desc = "Square Amount",
				name = "Square Amount",
			},
			{
				type = "range",
				get = function() return StreamOverlay.db.square_size end,
				set = function(self, fixedparam, value) 
					StreamOverlay.db.square_size = value
					StreamOverlay:RefreshAllBoxesStyle()
				end,
				min = 10,
				max = 256,
				step = 1,
				desc = "Square Size",
				name = "Square Size",
			},
			{
				type = "select",
				get = function() return StreamOverlay.db.square_grow_direction end,
				values = function() return squareGrowOptions end,
				desc = "Square Direction",
				name = "Square Direction",
			},

			{type = "blank"},

			{
				type = "select",
				get = function() return StreamOverlay.db.arrow_texture end,
				values = function() return arrowIconTable end,
				desc = "The icon used on the middle of the bar",
				name = "Arrow Icon"
			},

			{
				type = "range",
				get = function() return StreamOverlay.db.arrow_size end,
				set = function(self, fixedparam, value) StreamOverlay.db.arrow_size = value; StreamOverlay:RefreshAllBattleLineStyle() end,
				min = 6,
				max = 32,
				step = 1,
				desc = "The size of the arrow.",
				name = "Arrow Size",
			},

			{
				type = "color",
				get = function() return StreamOverlay.db.arrow_color end,
				set = function(self, r, g, b, a) 
					local c = StreamOverlay.db.arrow_color
					c[1], c[2], c[3], c[4] = r, g, b, a
					StreamOverlay:RefreshAllBattleLineStyle()
				end,
				desc = "The color used on the arrow.",
				name = "Arrow Color"
			},
			
			{
				type = "range",
				get = function() return StreamOverlay.db.arrow_anchor_x end,
				set = function(self, fixedparam, value) StreamOverlay.db.arrow_anchor_x = value; StreamOverlay:RefreshAllBattleLineStyle() end,
				min = -16,
				max = 16,
				step = 1,
				desc = "Adjust the arrow positioning on X axis.",
				name = "Arrow Anchor X",
			},
			
			{
				type = "range",
				get = function() return StreamOverlay.db.arrow_anchor_y end,
				set = function(self, fixedparam, value) StreamOverlay.db.arrow_anchor_y = value; StreamOverlay:RefreshAllBattleLineStyle() end,
				min = -16,
				max = 16,
				step = 1,
				desc = "Adjust the arrow positioning on Y axis.",
				name = "Arrow Anchor Y",
			},
			
			{type = "space"},
			
			{
				type = "range",
				get = function() return StreamOverlay.db.main_frame_size[1] end,
				set = function(self, fixedparam, value) StreamOverlay.db.main_frame_size[1] = value; StreamOverlay:RestoreWindowSizeAndLocation() end,
				min = 150,
				max = 800,
				step = 1,
				desc = "Adjust the window width.",
				name = "Window Width",
			},
			
			{
				type = "range",
				get = function() return StreamOverlay.db.main_frame_size[2] end,
				set = function(self, fixedparam, value) StreamOverlay.db.main_frame_size[2] = value; StreamOverlay:RestoreWindowSizeAndLocation() end,
				min = 40,
				max = 1024,
				step = 1,
				desc = "Adjust the window height.",
				name = "Window Height",
			},
			
			{
				type = "select",
				get = function() return StreamOverlay.db.main_frame_strata end,
				values = function() return strataTable end,
				desc = "How high the frame is placed in your interface, high values makes it be shown above backpack, talents frame, etc.",
				name = "Window Strata"
			},
				
			{type = "space"},
			{
				type = "toggle",
				name = "Show Spark",
				desc = "Show or hide the spark at bars",
				order = 1,
				get = function() return StreamOverlay.db.use_spark end,
				set = function(self, fixedParam, val) 
					StreamOverlay.db.use_spark = not StreamOverlay.db.use_spark
					
					
				end,
			},
			
		}
		
		detailsFramework:BuildMenu(optionsFrame, options, 15, -235, 860, true, options_text_template, options_dropdown_template, options_switch_template, true, options_slider_template, options_button_template)
		
		--select profile dropdown
		local selectProfile = function(_, _, profileName)
			local pname = UnitName("player") .. " - " .. GetRealmName()
			
			--save the current config on the profile
			local current_profile = Details_StreamerDB.characters [pname]
			local current_ptable = Details_StreamerDB.profiles [current_profile]
			_detalhes.table.overwrite (current_ptable, StreamOverlay.db) --overwrite the profile with the local settings
			
			--get the selected profile and overwrite the settings
			local ptable = Details_StreamerDB.profiles [profileName]
			
			_detalhes.table.deploy(ptable, StreamOverlay.DefaultConfigTable) --update with any new config from the default table
			_detalhes.table.overwrite (StreamOverlay.db, ptable) --overwrite the local settings with the profile settings
			
			Details_StreamerDB.characters [pname] = profileName
			
			--restore size and location
			StreamOverlay:RestoreWindowSizeAndLocation()
			
			--set locked and the backdrop color
			StreamOverlay:SetLocked (StreamOverlay.db.main_frame_locked)
			StreamOverlay:SetBackgroundColor (unpack(StreamOverlay.db.main_frame_color))
			
			--update the minimap icon
			if (LDBIcon) then
				LDBIcon:Refresh ("DetailsStreamer", StreamOverlay.db.minimap)
			end
			
			--update all settings
			StreamOverlay:RefreshAllBattleLineStyle()
			
			--update the options panel
			optionsFrame:RefreshOptions()
		end
		
		local select_profile_fill = function()
			local t = {}
			for profileName, _ in pairs(Details_StreamerDB.profiles) do
				t [#t+1] = {value = profileName, label = profileName, onclick = selectProfile}
			end
			return t
		end
		
		local label_profile = Details.gump:CreateLabel(optionsFrame, "Profile" .. ": ", Details.gump:GetTemplate("font", "OPTIONS_FONT_TEMPLATE"))
		local dropdown_profile = Details.gump:CreateDropDown (optionsFrame, select_profile_fill, nil, 160, 20, "dropdown_profile", nil, Details.gump:GetTemplate("dropdown", "OPTIONS_DROPDOWN_TEMPLATE"))
		dropdown_profile:SetPoint("left", label_profile, "right", 2, 0)
		label_profile:SetPoint("topleft", optionsFrame, "topleft", 15, -65)
		
		local pname = UnitName ("player") .. " - " .. GetRealmName()
		dropdown_profile:Select(Details_StreamerDB.characters [pname])
		
		--new profile button
		if (not Details_StreamerDB.profiles [pname]) then
			local add_profile = function()
				--profile name
				local pname = UnitName ("player") .. " - " .. GetRealmName()
				--default if is first run
				Details_StreamerDB.characters [pname] = pname
				--load dbtable
				Details_StreamerDB.profiles [pname] = {}
				_detalhes.table.overwrite (Details_StreamerDB.profiles [pname], StreamOverlay.db)
				_detalhes.table.deploy(Details_StreamerDB.profiles [pname], StreamOverlay.DefaultConfigTable) --update with any new config from the default table
				--StreamOverlay.db = Details_StreamerDB.profiles [pname] --no can't change the local database table
				
				optionsFrame.NewProfileButton:Hide()
				
				--update all settings
				StreamOverlay:RefreshAllBattleLineStyle()
				
				--update the options panel
				optionsFrame:RefreshOptions()
				dropdown_profile:Select(Details_StreamerDB.characters [pname])
				
			end
			optionsFrame.NewProfileButton = Details.gump:CreateButton(optionsFrame, add_profile, 60, 18, "New Profiile", _, _, _, _, _, _, Details.gump:GetTemplate("dropdown", "OPTIONS_DROPDOWN_TEMPLATE"), Details.gump:GetTemplate("font", "OPTIONS_FONT_TEMPLATE"))
			optionsFrame.NewProfileButton:SetPoint("left", dropdown_profile, "right", 4, 0)
		end
		
		--enable / disable plugin button
		local toggle_OnOff = function()
			local pluginStable = Details:GetPluginSavedTable("DETAILS_PLUGIN_STREAM_OVERLAY")
			local pluginObject = Details:GetPlugin("DETAILS_PLUGIN_STREAM_OVERLAY")

			if (pluginStable.enabled) then
                pluginStable.enabled = false
                pluginObject.__enabled = false
				Details:SendEvent("PLUGIN_DISABLED", pluginObject)
				optionsFrame.toggleButton.text = "Start Plugin"

			else
                pluginStable.enabled = true
                pluginObject.__enabled = true
				Details:SendEvent("PLUGIN_ENABLED", pluginObject)
				optionsFrame.toggleButton.text = "Disable Plugin"
			end
		end

		--get the plugin state
		local pluginStable = Details:GetPluginSavedTable("DETAILS_PLUGIN_STREAM_OVERLAY")

		local toggleButton = DetailsFramework:CreateButton(optionsFrame, toggle_OnOff, 120, 20, pluginStable.enabled and "Disable Plugin" or "Start Plugin")
		toggleButton:SetPoint("topleft", optionsFrame, "topleft", 15, -35)
		toggleButton:SetTemplate(DetailsFramework:GetTemplate("button", "OPTIONS_BUTTON_TEMPLATE"))

		optionsFrame.toggleButton = toggleButton

		optionsFrame:SetScript("OnHide", function()
			if (StreamOverlay.FromOptionsPanel) then
				--reopen the options panel
				C_Timer.After(0.2, function()
					Details:OpenOptionsWindow(Details:GetInstance(1))
				end)
			end
		end)

		optionsFrame:SetScript("OnShow", function()
			local pluginStable = Details:GetPluginSavedTable("DETAILS_PLUGIN_STREAM_OVERLAY")
			local pluginObject = Details:GetPlugin("DETAILS_PLUGIN_STREAM_OVERLAY")

			if (pluginObject) then
				if (pluginStable.enabled) then
					toggleButton:SetText("Disable Plugin")
				else
					toggleButton:SetText("Enable Plugin")
				end
			end
		end)


		
	end
	
	StreamOverlayOptionsPanel:Show()
	StreamOverlay.FromOptionsPanel = fromOptionsPanel
	if (fromOptionsPanel) then
		if (DetailsOptionsWindow) then
			C_Timer.After(0.2, function()
				DetailsOptionsWindow:Hide()
			end)
		end
	end
	
end


function StreamOverlay:OnEvent (_, event, ...)

	if (event == "ADDON_LOADED") then
		local AddonName = select(1, ...)
		if (AddonName == "Details_Streamer") then
			
			playerName = UnitName ("player")

			if (_G._detalhes) then
			
				if (DetailsFramework.IsClassicWow()) then
					return
				end

				--create widgets
				CreatePluginFrames()

				--core version required
				local MINIMAL_DETAILS_VERSION_REQUIRED = 80
				
				local default_options_table = {

					use_square_mode = false,
					square_size = 32,
					square_amount = 5,
					square_grow_direction = "right",

					main_frame_locked = false,
					main_frame_color = {0, 0, 0, .2},
					main_frame_size = {250, 230},
					main_frame_strata = "LOW",
					row_height = 20,
					row_spacement = 21,
					row_texture = "Details Serenity",
					row_color = {.1, .1, .1, 0.4},
					font_size = 10, 
					font_face = "Friz Quadrata TT",
					font_color = {1, 1, 1, 1},
					
					arrow_texture = [[Interface\CHATFRAME\ChatFrameExpandArrow]],
					arrow_size = 10,
					arrow_color = {1, 1, 1, .5},
					arrow_anchor_x = 0,
					arrow_anchor_y = 0,
					
					minimap = {hide = false, radius = 160, minimapPos = 160},

					use_spark = true,
					
					per_second = {
						enabled = false,
						size = 32,
						scale = 1.5,
						font_shadow = true,
						attribute_type = 1,
						update_speed = 0.05,
					},
					
					is_first_run = true,
				}
				
				StreamOverlay.DefaultConfigTable = default_options_table
				
				--Install
				local install, saveddata = _G._detalhes:InstallPlugin ("TOOLBAR", "Action Tracker", [[Interface\MINIMAP\MOVIERECORDINGICON]], StreamOverlay, "DETAILS_PLUGIN_STREAM_OVERLAY", MINIMAL_DETAILS_VERSION_REQUIRED, "Terciob", StreamOverlay.CurrentVersion, default_options_table)
				if (type(install) == "table" and install.error) then
					print(install.error)
				end
				
				Details_StreamerDB = Details_StreamerDB or {characters = {}, profiles = {}}
				
				StreamOverlay:CreateMinimapIcon()
				
				StreamOverlay:SetPluginDescription ("Show in real time the spells you are casting.\n\nThe viewer can now follow what you are doing, what spells you are casting, learn your rotation.\n\nAlso tells who is the target and its class/spec on raiding or role if you are in arena.\n\nWhen you die, the panel is filled with your death log.")
				
				if (StreamOverlay.db.is_first_run) then --problem with setting the plugin as disabled
					if (Details:GetTutorialCVar("STREAMER_PLUGIN_FIRSTRUN")) then
						Details:DisablePlugin ("DETAILS_PLUGIN_STREAM_OVERLAY")
						StreamOverlay.db.is_first_run = false
					else
						Details:DisablePlugin ("DETAILS_PLUGIN_STREAM_OVERLAY")
					end
				end

				if (StreamOverlay.db.is_first_run and not Details:GetTutorialCVar("STREAMER_PLUGIN_FIRSTRUN")) then
					local show_frame = function()

						if ((DetailsWelcomeWindow and DetailsWelcomeWindow:IsShown()) or not StreamOverlay.db.is_first_run) then
							return
						end

						StreamOverlay.ShowWelcomeFrame:Cancel()

						local welcomeWindow = CreateFrame("frame", "StreamOverlayWelcomeWindow", UIParent, "BackdropTemplate")
						welcomeWindow:SetPoint("center", UIParent, "center")
						welcomeWindow:SetBackdrop({edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1, bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], tileSize = 64, tile = true})
						welcomeWindow:SetBackdropColor(0, 0, 0, 0.5)
						welcomeWindow:SetBackdropBorderColor(0, 0, 0, 1)
						welcomeWindow:SetSize(740, 270)
						DetailsFramework:ApplyStandardBackdrop(welcomeWindow)

						local icon = welcomeWindow:CreateTexture(nil, "overlay")
						icon:SetTexture([[Interface\MINIMAP\MOVIERECORDINGICON]])
						local title = welcomeWindow:CreateFontString(nil, "overlay", "GameFontNormal")
						title:SetText("Details!: Action Tracker (plugin)")
						StreamOverlay:SetFontSize (title, 20)

						local youtubeTwitchIcons = welcomeWindow:CreateTexture(nil, "overlay")
						youtubeTwitchIcons:SetTexture([[Interface\AddOns\Details\images\icons2]])
						youtubeTwitchIcons:SetTexCoord(0, 109/512, 370/512, 413/512)
						youtubeTwitchIcons:SetSize(109, 413 - 370)
						youtubeTwitchIcons:SetPoint("topleft", welcomeWindow, "topleft", 123, -61)

						local text1 = welcomeWindow:CreateFontString(nil, "overlay", "GameFontNormal")
						text1:SetText("SHOW TO YOUR VIEWERS YOUR ROTATION\nThis way they can learn while watching your content")
						local text2 = welcomeWindow:CreateFontString(nil, "overlay", "GameFontNormal")
						text2:SetText("Use the command:")
						local text3 = welcomeWindow:CreateFontString(nil, "overlay", "GameFontNormal")
						text3:SetText("/streamer")
						DetailsFramework:SetFontSize(text3, 16)

						icon:SetPoint("topleft", welcomeWindow, "topleft", 10, -20)
						title:SetPoint("left", icon, "right", 10, 0)

						text1:SetPoint("topleft", welcomeWindow, "topleft", 10, -120)
						text2:SetPoint("center", text1, "center", 0, -40)
						text3:SetPoint("center", text2, "center", 0, -16)

						local image1 = welcomeWindow:CreateTexture(nil, "overlay")
						image1:SetTexture([[Interface\AddOns\Details_Streamer\streamer_plugin_lines]])
						image1:SetPoint("topleft", welcomeWindow, "topleft", 410, -6)
						image1:SetSize(512, 256)
						
						local close_func = function()
							StreamOverlay.db.is_first_run = false
							Details:SetTutorialCVar ("STREAMER_PLUGIN_FIRSTRUN", true)
							welcomeWindow:Hide()
						end
						
						local close = Details.gump:CreateButton(welcomeWindow, close_func, 120, 20, "Okay", nil, nil, nil, nil, nil, nil, Details.gump:GetTemplate("button", "OPTIONS_BUTTON_TEMPLATE"))
						close:SetPoint("center", text3, "center", 0, -50)
					end
					
					StreamOverlay.ShowWelcomeFrame = C_Timer.NewTicker(5, show_frame)
				end
				
				--wipe (StreamOverlay.db)
				SOF:RegisterEvent ("PLAYER_LOGOUT")
				
				--profile name
				SOF.PlayerNameProfile = UnitName("player") .. " - " .. GetRealmName()
				local pname = SOF.PlayerNameProfile

				--default if is first run
				local next_pname = next (Details_StreamerDB.profiles or {})
				Details_StreamerDB.characters [pname] = Details_StreamerDB.characters [pname] or next_pname or pname
				
				--load dbtable
				local ptable = Details_StreamerDB.profiles [ Details_StreamerDB.characters [pname] ] or {} --already existen config set or empty table
				_detalhes.table.overwrite (StreamOverlay.db, ptable) --profile overwrite the local settings
				_detalhes.table.deploy(ptable, StreamOverlay.db) --local settings deploy stuff which non exist on profile
				
				Details_StreamerDB.profiles [ Details_StreamerDB.characters [pname] ] = ptable
			end
		end
		
	elseif (event == "PLAYER_LOGOUT") then
		local pname = UnitName("player") .. " - " .. GetRealmName()
		--print(Details_Streamer.PlayerNameProfile)
		Details_StreamerDB.profiles [ Details_StreamerDB.characters [pname] ] = StreamOverlay.db
	end
end

--create minimap icon
function StreamOverlay:CreateMinimapIcon()

	if (StreamOverlay.minimap_icon_created) then
		return
	end

	StreamOverlay.minimap_icon_created = true

	local LDB = LibStub("LibDataBroker-1.1", true)
	local LDBIcon = LDB and LibStub("LibDBIcon-1.0", true)

	if LDB then
		local minimapIcon = LDB:NewDataObject ("DetailsStreamer", {
			type = "data source",
			icon = [[Interface\MINIMAP\MOVIERECORDINGICON]],
			
			OnClick = function(self, button)
				if (button == "LeftButton") then
					StreamOverlay.OpenOptionsPanel()
				elseif (button == "RightButton") then
					StreamOverlay.db.minimap.hide = not StreamOverlay.db.minimap.hide
					if (LDBIcon) then
						LDBIcon:Refresh ("DetailsStreamer", StreamOverlay.db.minimap)
					end
				end
			end,
			
			OnTooltipShow = function(tooltip)
				tooltip:AddLine("Details!: Action Tracker", 1, 1, 1)
				tooltip:AddLine("|cFFFF7700Left Click|r: open options.")
				tooltip:AddLine("|cFFFF7700Right Click|r: hide this icon.")
			end,
		})
		
		if (minimapIcon and not LDBIcon:IsRegistered ("DetailsStreamer")) then
			LDBIcon:Register ("DetailsStreamer", minimapIcon, StreamOverlay.db.minimap)
		end
	end
end

SLASH_STREAMER1, SLASH_STREAMER2 = "/streamer", "/detailsstreamer"
function SlashCmdList.STREAMER (msg, editbox)
	local command, rest = msg:match ("^(%S*)%s*(.-)$")

	--open options panel
	StreamOverlay.OpenOptionsPanel()
end

--[[ extrair lista das magias
local editbox = CreateFrame("editbox", nil, UIParent)
editbox:SetSize(300, 700)
editbox:SetPoint("topleft", UIParent, "topleft")
editbox:SetBackdrop({bgFile = "Interface\\AddOns\\Details\\images\\background", tile = true, tileSize = 16, insets = {left = 0, right = 0, top = 0, bottom = 0}})
editbox:SetBackdropColor(0, 0, 0, .2)
editbox:SetAutoFocus(false)
editbox:ClearFocus()
editbox:SetMultiLine (true)
editbox:SetFontObject(GameFontHighlightSmall)
editbox:SetJustifyH("CENTER")
editbox:EnableMouse(true)
editbox:SetText("")
editbox:SetScript("OnEscapePressed", function() editbox:ClearFocus() end)
editbox:SetScript("OnEditFocusGained", function() editbox:HighlightText() end)

local list = ""

local harmful_spells = StreamOverlay.HarmfulSpells
local helpful_spells = StreamOverlay.HelpfulSpells

if (not harmful_spells [spellid] and not helpful_spells [spellid]) then
	if (bit.band(who_flags, 0x00000400) ~= 0 and who_name) then
		local text = editbox:GetText()
		if (not list:find(spellid) and not text:find(spellid)) then
		
			local class = _detalhes:GetClass(who_name) or "unknow"
		
			if (class ~= "unknow") then
				text = text .. "\n"..spellid .. " " .. spellname .. " " .. class
				editbox:SetText(text)
			end
		end
	end
end
--]]
--endd
--doo