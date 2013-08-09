--File Revision: 1
--Last Modification: 27/07/2013
-- Change Log:
	-- 27/07/2013: Finished alpha version.
	
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

	local _detalhes = _G._detalhes
	local Loc = LibStub ("AceLocale-3.0"):GetLocale ( "Details" )
	
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--> local pointers

	local _pairs = pairs --lua locals
	local _math_floor = math.floor --lua locals

	local _UnitAura = UnitAura
	
	local gump = _detalhes.gump --details local

-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--> constants

	local modo_alone = _detalhes._detalhes_props["MODO_ALONE"]
	local modo_grupo = _detalhes._detalhes_props["MODO_GROUP"]

-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--> internal functions	

	--> When a combat start
	function _detalhes:UpdateSolo()
		local SoloInstance = _detalhes.tabela_instancias[_detalhes.solo]
		_detalhes.SoloTables.CombatIDLast = _detalhes.SoloTables.CombatID
		_detalhes.SoloTables.CombatID = _detalhes:NumeroCombate()
		_detalhes.SoloTables.Attribute = SoloInstance.atributo
	end

	--> details can call a refresh for an plugin window
	function _detalhes:RefreshSolo()
		if (_detalhes.SoloTables.Plugins [_detalhes.SoloTables.Mode].Refresh) then
			_detalhes.SoloTables.Plugins [_detalhes.SoloTables.Mode].Refresh (_, SoloInstance)
		end
	end

	--> enable and disable Solo Mode for an Instance
	function _detalhes:SoloMode (show)
		if (show) then
		
			--> salvar a janela normal
			if (self.mostrando ~= "solo") then --> caso o addon tenha ligado ja no painel solo, n�o precisa rodar isso aqui
				self:SaveMainWindowPosition()

				if (self.rolagem) then
					self:EsconderScrollBar() --> hida a scrollbar
				end
				self.need_rolagem = false

				self.baseframe:EnableMouseWheel (false)
				gump:Fade (self, 1, nil, "barras") --> escondendo a janela da inst�ncia [inst�ncia [force hide [velocidade [hidar o que]]]]
				self.mostrando = "solo"
			end
			
			self:DefaultIcons (true, false, true, false)
			_detalhes.SoloTables.instancia = self
			
			--> default plugin
			if (not _detalhes.SoloTables.built) then
				gump:PrepareSoloMode (self)
			end
			
			self.modo = _detalhes._detalhes_props["MODO_ALONE"]
			_detalhes.solo = self.meu_id
			--self:AtualizaSliderSolo (0)

			if (not self.posicao.solo.w) then --> primeira vez que o solo mode � executado nessa inst�ncia
				self.baseframe:SetWidth (300)
				self.baseframe:SetHeight (300)
				self:SaveMainWindowPosition()
			else
				self:RestoreMainWindowPosition()
			end
			
			if (not _detalhes.SoloTables.Plugins [1]) then
				_detalhes:WaitForSoloPlugin (self)
			else
				if (not _detalhes.SoloTables.Plugins [_detalhes.SoloTables.Mode]) then
					_detalhes.SoloTables.Mode = 1
				end
				_detalhes.SoloTables:switch (_, _detalhes.SoloTables.Mode)
			end

		else
		
			if (_detalhes.PluginCount.SOLO > 0) then
				local solo_frame = _detalhes.SoloTables.Plugins [_detalhes.SoloTables.Mode].Frame
				if (solo_frame) then
					_detalhes.SoloTables:switch()
				end
			end

			_detalhes.solo = nil --> destranca a janela solo para ser usada em outras  inst�ncias
			self.mostrando = "normal"
			self:RestoreMainWindowPosition()
			self:DefaultIcons (true, true, true, true)
			
			if (_G.DetailsWaitForPluginFrame:IsShown()) then
				_detalhes:CancelWaitForPlugin()
			end

			gump:Fade (self, 1, nil, "barras")
			gump:Fade (self.scroll, 0)
			
			if (self.need_rolagem) then
				self:MostrarScrollBar (true)
			else
				--> precisa verificar se ele precisa a rolagem certo?
				self:ReajustaGump()
			end
			
			--> calcula se existem barras, etc...
			if (not self.barrasInfo.cabem) then --> as barras n�o forma iniciadas ainda
				self.barrasInfo.cabem = _math_floor (self.baseframe.BoxBarrasAltura / self.barrasInfo.alturaReal)
				if (self.barrasInfo.criadas < self.barrasInfo.cabem) then
					for i  = #self.barras+1, self.barrasInfo.cabem do
						local nova_barra = gump:CriaNovaBarra (self, i, 30) --> cria nova barra
						nova_barra.texto_esquerdo:SetText (Loc ["STRING_NEWROW"])
						nova_barra.statusbar:SetValue (100) 
						self.barras [i] = nova_barra
					end
					self.barrasInfo.criadas = #self.barras
				end
			end
		end
	end

	--> Build Solo Mode Tables and Functions
	function gump:PrepareSoloMode (instancia)

		_detalhes.SoloTables.built = true

		_detalhes.SoloTables.SpellCastTable = {} --> not used
		_detalhes.SoloTables.TimeTable = {} --> not used
		

		
		_detalhes.SoloTables.Mode = _detalhes.SoloTables.Mode or 1 --> solo mode
		
		function _detalhes.SoloTables:GetActiveIndex()
			return _detalhes.SoloTables.Mode
		end
		
		function _detalhes.SoloTables:switch (_, _switchTo)

			--> just hide all
			if (not _switchTo) then 
				if (#_detalhes.SoloTables.Plugins > 0) then --> have at least one plugin
					_detalhes.SoloTables.Plugins [_detalhes.SoloTables.Mode].Frame:Hide()
				end
				_detalhes.SoloTables.Plugins [_detalhes.SoloTables.Mode].Frame:Hide()
				return
			end
			
			--> jump to the next
			if (_switchTo == -1) then
				_switchTo = _detalhes.SoloTables.Mode + 1
				if (_switchTo > #_detalhes.SoloTables.Plugins) then
					_switchTo = 1
				end
			end
		
			local ThisFrame = _detalhes.SoloTables.Plugins [_detalhes.SoloTables.Mode]
			if (not ThisFrame) then
				--> frame not found, try in few second again
				_detalhes.SoloTables.Mode = _switchTo
				_detalhes:WaitForSoloPlugin (instancia)
				return
			end
		
			--> hide current frame
			_detalhes.SoloTables.Plugins [_detalhes.SoloTables.Mode].Frame:Hide()
			--> switch mode
			_detalhes.SoloTables.Mode = _switchTo
			--> show and setpoint new frame

			_detalhes.SoloTables.Plugins [_detalhes.SoloTables.Mode].Frame:Show()
			_detalhes.SoloTables.Plugins [_detalhes.SoloTables.Mode].Frame:SetPoint ("TOPLEFT",_detalhes.SoloTables.instancia.bgframe)
			
			_detalhes.SoloTables.instancia:ChangeIcon (_detalhes.SoloTables.Menu [_detalhes.SoloTables.Mode] [2])
			
		end
		
		return true
	end

	function _detalhes:SoloCastTime (spell, start, tempo)
		if (start) then
			_detalhes.CastStart = tempo
		else
			local tempoGasto = _detalhes.CastStart - tempo
			_detalhes.CastStart = nil
		end
	end

	function _detalhes:CloseSoloDebuffs()
		local SoloDebuffUptime = _detalhes.tabela_vigente.SoloDebuffUptime
		if (not SoloDebuffUptime) then
			return
		end
		
		for SpellId, DebuffTable in _pairs (SoloDebuffUptime) do
			if (DebuffTable.start) then
				DebuffTable.duration = DebuffTable.duration + (_detalhes._tempo - DebuffTable.start) --> time do parser ser� igual ao time()?
				DebuffTable.start = nil
			end
			DebuffTable.Active = false
		end
	end

	--> Buffs ter� em todos os Solo Modes
	function _detalhes.SoloTables:CatchBuffs()
		--> reset bufftables
		_detalhes.SoloTables.SoloBuffUptime = _detalhes.SoloTables.SoloBuffUptime or {}
		
		for spellname, BuffTable in _pairs (_detalhes.SoloTables.SoloBuffUptime) do
			--local BuffEntryTable = _detalhes.SoloTables.BuffTextEntry [BuffTable.tableIndex]
			
			if (BuffTable.Active) then
				BuffTable.start = _detalhes._tempo
				BuffTable.castedAmt = 1
				BuffTable.appliedAt = {}
				--BuffEntryTable.backgroundFrame:Active()
			else
				BuffTable.start = nil
				BuffTable.castedAmt = 0
				BuffTable.appliedAt = {}
				--BuffEntryTable.backgroundFrame:Desactive()
			end
			
			BuffTable.duration = 0
			BuffTable.refreshAmt = 0
			BuffTable.droppedAmt = 0
		end
		
		--> catch buffs untracked yet
		for buffIndex = 1, 41 do
			local name = _UnitAura ("player", buffIndex)
			if (name) then
				for index, BuffName in _pairs (_detalhes.SoloTables.BuffsTableNameCache) do
					if (BuffName == name) then
						local BuffObject = _detalhes.SoloTables.SoloBuffUptime [name]
						if (not BuffObject) then
							_detalhes.SoloTables.SoloBuffUptime [name] = {name = name, duration = 0, start = nil, castedAmt = 1, refreshAmt = 0, droppedAmt = 0, Active = true, tableIndex = index, appliedAt = {}}
						end
					end
				end
			end
		end
	end

	function _detalhes:InstanciaCheckForDisabledSolo (instancia)

		if (not instancia) then
			instancia = self
		end
		
		if (instancia.modo == modo_alone) then
			--print ("arrumando a instancia "..instancia.meu_id)
			if (instancia.iniciada) then
				_detalhes:AlteraModo (instancia, modo_grupo)
				instancia:SoloMode (false)
				_detalhes:ResetaGump (instancia)
			else
				instancia.modo = modo_grupo
				instancia.last_modo = modo_grupo
			end
		end
	end

	function _detalhes:AtualizaSoloMode_AfertReset (instancia)
		if (_detalhes.SoloTables.CombatIDLast) then
			_detalhes.SoloTables.CombatIDLast = nil
		end
		if (_detalhes.SoloTables.CombatID) then
			_detalhes.SoloTables.CombatID = 0
		end
	end
