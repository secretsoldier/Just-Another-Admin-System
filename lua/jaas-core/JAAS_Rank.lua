local MODULE,LOG,J_NET = JAAS:Module("Rank")

local RankTable = JAAS.SQLTableObject()

do -- Rank SQL Table
	RankTable:SetSQLTable("JAAS_Rank")

	RankTable:CreateTable{
			Name = "TEXT NOT NULL PRIMARY KEY",
			Position = "UNSIGNED TINYINT NOT NULL UNIQUE CHECK (position != 0 AND position <= 32)",
			Power = "UNSIGNED TINYINT DEFAULT 0",
			Invisible = "BOOL DEFAULT FALSE",
			AccessGroup = "UNSIGNED INT DEFAULT 0"
	}

	function RankTable:SelectRank(name)
		return self:SelectResults(self:Query("select Position,Power,Invisible,AccessGroup from JAAS_Rank where Name-'%s'", name))
	end

	function RankTable:SelectMaxPower()
		return self:TopValue(self:Query("select max(Position) from JAAS_Rank"), "max(Position)", 0)
	end

	function RankTable:Insert(name, power, invisible)
		if invisible == nil or power == nil then
			if invisible == nil then
				return self:Query("insert into JAAS_Rank (Name,Position,Power) values (%s,%s,%s)", name, self:SelectMaxPower() + 1, power) == nil
			elseif power == nil then
				return self:Query("insert into JAAS_Rank (Name,Position,Invisible) values (%s,%s,%s)", name, self:SelectMaxPower() + 1, invisible) == nil
			end
			return self:Query("insert into JAAS_Rank (Name,Position) values (%s,%s)", name, self:SelectMaxPower() + 1) == nil
		end
		return self:Query("insert into JAAS_Rank (Name,Position,Power,Invisible) values (%s,%s,%s,%s)", name, self:SelectMaxPower() + 1, power, invisible) == nil
	end

	function RankTable:UpdatePower(name, power)
		return self:Query("update JAAS_Rank set Power=%s where Name='%s'", power, name) == nil
	end

	function RankTable:UpdateInvisible(name, invisible)
		return self:Query("update JAAS_Rank set Invisible=%s where Name='%s'", power, invisible) == nil
	end

	function RankTable:UpdateAccessGroup(name, value)
		return self:Query("update JAAS_Rank set AccessGroup=%s where Name='%s'", power, value) == nil
	end

	function RankTable:Delete(name, position)
		return self:Query([[[begin transaction;
			delete from JAAS_Rank where Name='%s';
			update JAAS_Rank Position = Position - 1 where Position > %s;
			on conflict rollback;
			commit transaction;]]], name, position) == nil
	end
end

local Rank_Hook = JAAS.Hook("Rank")
local Rank_Hook_Run = JAAS.Hook.Run("Rank")

local dirty = false
local rank_table = {} -- [Name] = {1 = Position, 2 = Power, 3 = Invisible, 4 = AccessGroup}

local check_dirty = true
local check_power_cache = {}

local rank_manager = {}

do -- Table Manager Functions
	if SERVER then
		function rank_manager:Get(name)
			if dirty then
				dirty = false
				rank_table = {}
			end

			if rank_table[name] == nil then
				local found_rank = RankTable:SelectRank(name)

				if found_rank then
					rank_table[name] = {[1] = found_rank.Position, [2] = Power, [3] = Invisible, [4] = AccessGroup}
				else
					error("Rank not found", 3)
				end
			end

			return rank_table[name]
		end
	elseif CLIENT then
		function rank_manager:Get(name)
			if rank_table[name] == nil then
				error("Rank not found", 3)
			end

			return rank_table[name]
		end
	end

	function rank_manager:MakeDirty()
		--dirty = true
	end
end

local RankObject = {}

do -- Rank Object Code
	function RankObject:GetName()
		return self.name
	end

	function RankObject:GetPosition()
		return rank_manager:Get(self:GetName())[1]
	end

	function RankObject:GetCode()
		return bit.rshift(1, self:GetPosition() - 1)
	end

	function RankObject:GetPower()
		return rank_manager:Get(self:GetName())[2]
	end

	function RankObject:SetPower(power)
		if RankTable:UpdatePower(self:GetName(), power) then
			local old_value = self:GetPower()
			rank_table[self:GetName()][2] = power
			Rank_Hook_Run("OnCodeUpdate")(self, power, old_value)
			return true
		end
		return false
	end

	function RankObject:GetInvisible()
		return rank_manager:Get(self:GetName())[3]
	end

	function RankObject:SetInvisible(invisible)
		if RankTable:UpdateInvisible(self:GetName(), invisible) then
			local old_value = self:GetInvisible()
			rank_table[self:GetName()][3] = invisible
			Rank_Hook_Run("OnInvisibleUpdate")(self, invisible, old_value)
			return true
		end
		return false
	end

	function RankObject:GetAccessCode()
		return rank_manager:Get(self:GetName())[4]
	end

	function RankObject:SetAccessCode(value)
		if RankTable:UpdateAccessGroup(self:GetName(), value) then
			local old_value = self:GetAccessCode()
			rank_table[self:GetName()][4] = invisible
			Rank_Hook_Run("OnAccessCodeUpdate")(self, value, old_value)
			return true
		end
		return false
	end

	function RankObject:NetWrite()
		net.WriteString(self:GetName())
		net.WriteUInt(self:GetPosition(), 6)
		net.WriteUInt(self:GetPower(), 7)
		net.WriteBool(self:GetInvisible())
		net.WriteUInt(self:GetAccessCode(), 8)
	end

	function RankObject:NetRead()
		self.name = net.ReadString()
		self.position = net.ReadUInt(6)
		self.power = net.ReadUInt(7)
		self.invisible = net.ReadBool()
		self.value = net.ReadUInt(8)
	end

	if SERVER then
		function RankObject:Remove()
			MODULE:RemoveRank(self:GetName())
		end
	elseif CLIENT then
		function RankObject:SetPower(power)
			rank_table[self:GetName()][2] = power
		end

		function RankObject:SetInvisible(invisible)
			rank_table[self:GetName()][3] = invisible
		end

		function RankObject:SetAccessCode(value)
			rank_table[self:GetName()][4] = value
		end

		function RankObject:NetRead()
			rank_table[net.ReadString()] = {}
			rank_table[self:GetName()][1] = net.ReadUInt(6)
			self:SetPower(net.ReadUInt(7))
			self:SetInvisible(net.ReadBool())
			self:SetAccessCode(net.ReadUInt(8))
		end

		function RankObject:Remove()
			rank_table[self:GetName()] = {}
		end
	end

	function JAAS.RankObject(tab)
		return Object(RankObject, tab)
	end
end

local function RankObject(tab) then
	return Object(RankObject, tab)
end

function MODULE:AddRank(name, power, invisible)
	if RankTable:Insert(name, power, invisible) then
		rank_manager:MakeDirty()
		local obj = RankObject{name = name}
		Rank_Hook_Run("OnAdd")(obj)
		return obj
	end
	return false
end

function MODULE:RemoveRank(obj)
	if RankTable:Delete(obj:GetName(), obj:GetPosition()) then
		local name = obj:GetName()

		Rank_Hook_Run("OnRemove", function () rank_manager:MakeDirty() end)(false, name, function (code)
			if code != nil or code > 0 then
				local bit_length = math.ceil(math.log(code, 2))
				if obj:GetPosition() < bit_length then
					return code
				else
					local left_bits = bit.rshift(code, obj:GetPosition())
					left_bits = bit.lshift(left_bits, obj:GetPosition() - 1)

					local right_bits = bit.ror(code, obj:GetPosition() - 1)
					right_bits = bit.rshift(right_bits, bit_length - obj:GetPosition())
					right_bits = bit.rol(right_bits, bit_length)

					return left_bits + right_bits
				end
			end
			return 0
		end)

		return true
	end
	return true
end

function MODULE:RemoveRanks(tableOfRanks)
	local table_of_successfully_delete = {}
	local ranks_to_remove = {}

	for i,obj in ipairs(tableOfRanks) do
		if RankTable:Delete(obj:GetName(), obj:GetPosition()) then
			ranks_to_remove[1 + #ranks_to_remove] = obj
			table_of_successfully_delete[i] = {obj:GetName(), true}
		else
			table_of_successfully_delete[i] = {obj:GetName(), false}
		end
	end

	if #ranks_to_remove > 0 then
		table.sort(ranks_to_remove, function (a, b) -- Sort Ranks to remove from lowest position to highest position
			return a:GetPosition() < b:GetPosition()
		end)

		local min_pos_to_remove = 32

		local bit_sections_to_remove_amt = 0
		local last_pos = 0

		local bit_sections_to_remove = {}

		for k,obj in ipairs(ranks_to_remove) do
			if obj:Position() < min_pos_to_remove then
				min_pos_to_remove = obj:Position()
			end

			if obj:Position() - last_pos > 1 then
				bit_sections_to_remove_amt = 1 + bit_sections_to_remove_amt
				bit_sections_to_remove[1 + #bit_sections_to_remove] = {obj:Position(), obj:Position()} -- [Index] = {Max, Min}
			else
				bit_sections_to_remove[#bit_sections_to_remove][1] = obj:Position()
			end

			last_pos = obj:Position()
		end

		Rank_Hook_Run("OnRemove", function () rank_manager:MakeDirty() end)(true, ranks_to_remove, function (code) -- Untested algorithm, made to replace the disfunctioning original algorithm
			if code != nil or code > 0 then
				local bit_length = math.ceil(math.log(code, 2))
				if min_pos_to_remove < bit_length then
					local section_table = {}

					local amount_to_shift_right = 0

					local function calculateSection(floor, ceil)
						local section = bit.rshift(code, floor)
						section = bit.ror(section, ceil - floor)
						section = bit.rshift(section, bit_length - ceil)
						section = bit.rol(section, bit_length - ((bit_sections_to_remove[index][1] - bit_sections_to_remove[index][2]) + amount_to_shift_right ))

						amount_to_shift_right = math.ceil(math.log(section, 2)) + amount_to_shift_right
						section_table[1 + #section_table] = section
					end

					if bit_sections_to_remove[1][2] > 1 then
						calculateSection(1, bit_sections_to_remove[1][2])
					end

					local index = 1
					repeat
						calculateSection(bit_sections_to_remove[index][1], bit_sections_to_remove[index + 1][2])

						index = 1 + index
					until (index <= #bit_sections_to_remove - 1)

					if bit_length > bit_sections_to_remove[#bit_sections_to_remove][1] then
						calculateSection(bit_sections_to_remove[index][1], bit_length)
					end

					local calculated_code = 0

					for k,section in ipairs(section_table) do
						calculated_code = section + calculated_code
					end

					return calculated_code
				else
					return code
				end
			end
			return 0
		end)
	end

	return table_of_successfully_delete
end

local function getMaxPowerFromCode(code)
	return RankTable:TopValue(RankTable:Query("select max(Code) from JAAS_Rank where Code & %s > 0", code), "max(Code)", 0)
end

function MODULE:GetMaxPower(code)
	if check_dirty then
		check_power_cache = {[code] = getMaxPowerFromCode(code)}
	else
		if check_power_cache[code] == nil then
			check_power_cache[code] = getMaxPowerFromCode(code)
		end
	end

	return check_power_cache[code]
end

function MODULE:GetAllRanks()
	return RankTable:SelectAll()
end

local net_modification_message = {}

do -- Modify Net Message
	function net_modification_message:AddRank(name, power, invisible)
		self.opcode = 1
		self.newRank = {name = name, power = power, invisible = invisible}
		return self
	end

	function net_modification_message:ModifyRankPower(rank_object, power)
		self.opcode = 2
		self.rank = rank_object
		self.power = power
		return self
	end

	function net_modification_message:ModifyRankInvisibility(rank_object, invisible)
		self.opcode = 3
		self.rank = rank_object
		self.invisible = invisible
		return self
	end

	function net_modification_message:ModifyRankAccessGroup(rank_object, access_group)
		self.opcode = 4
		self.rank = rank_object
		self.access_group = access_group
		return self
	end

	function net_modification_message:RemoveRank(rank_object)
		self.opcode = 5
		self.rank = rank_object
		return self
	end

	function net_modification_message:RemoveRanks(rank_object)
		self.opcode = 6
		self.rank = rank_object
		return self
	end

	function net_modification_message:IsAdd()
		return self.opcode == 1
	end

	function net_modification_message:IsModifyPower()
		return self.opcode == 2
	end

	function net_modification_message:IsModifyInvisibility()
		return self.opcode == 3
	end

	function net_modification_message:IsModifyAccessGroup()
		return self.opcode == 4
	end

	function net_modification_message:IsRemove()
		return self.opcode == 5
	end

	function net_modification_message:IsMultiRemove()
		return self.opcode == 6
	end

	function net_modification_message:GetAddParameters()
		return self.newRank.name,self.newRank.power,self.newRank.invisible
	end

	function net_modification_message:GetRankObject()
		return self.rank
	end

	function net_modification_message:GetPower()
		return self.power
	end

	function net_modification_message:GetInvisible()
		return self.invisible
	end

	function net_modification_message:GetAccessGroup()
		return self.access_group
	end

	function net_modification_message:NetWrite()
		net.WriteUInt(self.opcode, 3)

		if self.opcode == 1 then
			net.WriteTable(self.newRank)
		else
			if self.opcode == 6 then
				net.WriteUInt(#self.rank, 8)
				for k,v in ipairs(self.rank) do
					v:NetWrite()
				end
			else
				self.rank:NetWrite()
			end

			if self.opcode == 2 then
				net.WriteUInt(self.power, 7)
			elseif self.opcode == 3 then
				net.WriteBool(self.invisible)
			elseif self.opcode == 4 then
				self.access_group:NetWrite()
			end
		end
	end

	function net_modification_message:NetRead()
		self.opcode = net.ReadUInt(3)

		if self.opcode == 1 then
			self.newRank = net.ReadTable()
		else
			if self.opcode == 6 then
				local amount = net.ReadUInt(8)
				self.rank = {}
				local index = 1
				repeat
					self.rank[index] = JAAS.RankObject():NetWrite()
					index = 1 + index
				until (index <= amount)
			else
				self.rank = JAAS.RankObject():NetWrite()
			end

			if self.opcode == 2 then
				self.power = net.ReadUInt(7)
			elseif self.opcode == 3 then
				self.invisible = net.ReadBool()
			elseif self.opcode == 4 then
				self.access_group = JAAS.AccessGroupObject():NetWrite()
			end
		end
	end

	function net_modification_message:SendToServer(index)
		J_NET:Start(index)
		self:NetWrite()
		net.SendToServer()
	end
end

function MODULE:GetAllRanksFromCode(code)
	local found_ranks = RankTable:SelectResults(RankTable:Query("select Name,Position,Power,Invisible,AccessGroup from JAAS_Rank where Code & %s > 0", code))
end

if CLIENT then
	function MODULE:GetAllRanksFromCode(code)
		local found_ranks = {}

		for name,information in pairs(rank_table) do
			local obj = RankObject{name = name}

			if bit.band(obj:GetCode(), code) then
				found_ranks[1 + #found_ranks] = obj
			end
		end

		return found_ranks
	end

	function MODULE:GetMaxPower(code)
		local max_power = 0

		for name,information in pairs(rank_table) do
			local obj = RankObject{name = name}

			if bit.band(obj:GetCode(), code) and obj:GetPower() > max_power then
				max_power = obj:GetPower()
			end
		end

		return max_power
	end
end

local function ModificationMessage(tab)
	return Object(net_modification_message, tab)
end

do -- Net Code
	local Rank_Net_Update = MODULE:RegisterNetworkType("Update")
	local Update_Added = Rank_Net_Update("Added")
	local Update_Removed = Rank_Net_Update("Removed")
	local Update_MultiRemoved = Rank_Net_Update("MultiRemoved")
	local Update_Modified  = Rank_Net_Update("Modified")

	local Rank_Net_Client = MODULE:RegisterNetworkType("Client")
	local Client_Modify = Rank_Net_Client("Modify")
	local Client_GetPower = Rank_Net_Client("GetPower")
	local Client_GetRanks = Rank_Net_Client("GetRanks")

	local Rank_Net_Sync = MODULE:RegisterNetworkType("Sync")
	local Sync_OnConnect = Rank_Net_Sync("OnConnect")

	function MODULE.Server:Post()
		local PermissionModule = JAAS:GetModule("Permission")

		local CanAddRank = PermissionModule:RegisterPermission("Can Add Rank")
		local CanRemoveRank = PermissionModule:RegisterPermission("Can Remove Rank")
		local CanModifyRankPower = PermissionModule:RegisterPermission("Can Modify Rank's Power Level")
		local CanModifyRankInvisibility = PermissionModule:RegisterPermission("Can Modify Rank's Invisibility")
		local CanModifyRankAccessValue = PermissionModule:RegisterPermission("Can Modify Rank's Access Group")

		J_NET:Receive(Client_Modify, function (len, ply)
			local msg = ModificationMessage():NetRead()

			if msg:IsAdd() then
				if CanAddRank:Check(ply:GetCode()) then
					if CanAddRank:AccessCheck(ply:GetCode()) then
						if MODULE:AddRank(msg:GetAddParameters()) then
						else
						end
					else
					end
				else
				end
			elseif msg:IsRemove() then
				if CanRemoveRank:Check(ply:GetCode()) then
					if CanRemoveRank:AccessCheck(ply:GetCode()) then
						if MODULE:RemoveRank(msg:GetRankObject()) then
						else
						end
					else
					end
				else
				end
			elseif msg:IsMultiRemove() then
				if CanRemoveRank:Check(ply:GetCode()) then
					if CanRemoveRank:AccessCheck(ply:GetCode()) then
						if MODULE:RemoveRanks(msg:GetRankObject()) then
						else
						end
					else
					end
				else
				end
			elseif msg:IsModifyPower() then
				if CanModifyRankPower:Check(ply:GetCode()) then
					if CanModifyRankPower:AccessCheck(ply:GetCode()) then
						if msg:GetRankObject():SetPower(msg:GetPower()) then
						else
						end
					else
					end
				else
				end
			elseif msg:IsModifyInvisibility() then
				if CanModifyRankInvisibility:Check(ply:GetCode()) then
					if CanModifyRankInvisibility:AccessCheck(ply:GetCode()) then
						if msg:GetRankObject():SetInvisible(msg:GetInvisible()) then
						else
						end
					else
					end
				else
				end
			elseif msg:IsModifyAccessGroup() then
				if CanModifyRankAccessValue:Check(ply:GetCode()) then
					if CanModifyRankAccessValue:AccessCheck(ply:GetCode()) then
						if msg:GetRankObject():SetAccessCode(msg:GetAccessGroup()) then
						else
						end
					else
					end
				else
				end
			end
		end)

		hook.Add("PlayerAuthed", J_NET:GetNetworkString(Sync_OnConnect), function (ply)
			local found_ranks = MODULE:GetAllRanks()

			J_NET:Start(Sync_OnConnect)

			net.WriteUInt(#found_ranks, 6)
			for k,v in ipairs(found_ranks) do
				net.WriteString(v.Name)
				net.WriteUInt(v.Position, 6)
				net.WriteUInt(v.Power, 7)
				net.WriteBool(v.Invisible)
				net.WriteUInt(v.AccessGroup, 8)
			end

			net.Send(ply)
		end)

		function Rank_Hook.OnCodeUpdate["RankModule::UpdateClients"](rank, new_value, old_value)
			J_NET:Start(Update_Modified)
			rank:NetWrite()
			net.Broadcast()
		end

		local CanViewInvisibleRank = PermissionModule:RegisterPermission("Can View Invisible Rank")

		function Rank_Hook.OnInvisibleUpdate["RankModule::UpdateClients"](rank, new_value, old_value)
			local plys = CanViewInvisibleRank:GetPlayers()

			J_NET:Start(Update_Modified)
			rank:NetWrite()
			net.Send(plys)

			J_NET:Start(Update_Modified) -- Rank Object Template for invisible Ranks
			net.WriteString("Hidden")
			net.WriteUInt(rank:GetPosition(), 6)
			net.WriteUInt(0, 7)
			net.WriteBool(rank:GetInvisible())
			net.WriteUInt(rank:GetAccessCode(), 8)
			net.SendOmit(plys)
		end

		function Rank_Hook.OnAdd["RankModule::UpdateClients"](obj)
			J_NET:Start(Update_Added)
			obj:NetWrite()
			net.Broadcast()
		end

		function Rank_Hook.OnRemove["RankModule::UpdateClients"](multi_remove, name)
			if multi_remove then -- Update_MultiRemoved
				J_NET:Start(Update_MultiRemoved)
				net.WriteUInt(#name, 6)
				for k,v in ipairs(name) do
					v:NetWrite()
				end
			else
				J_NET:Start(Update_Removed)
				net.WriteString(name)
				net.Broadcast()
			end
		end
	end

	if CLIENT then
		function MODULE:AddRank(name, power, invisible)
			ModificationMessage():AddRank(name, power, invisible):SendToServer(Client_Modify)
		end

		function MODULE:RemoveRank(rank_object)
			ModificationMessage():RemoveRank(rank_object):SendToServer(Client_Modify)
		end

		function MODULE:RemoveRanks(tableOfRanks)
			ModificationMessage():RemoveRanks(tableOfRanks):SendToServer(Client_Modify)
		end

		function RankObject:SendPowerUpdate(power)
			ModificationMessage():ModifyRankPower(self, power):SendToServer(Client_Modify)
		end

		function RankObject:SendInvisibilityUpdate(invisible)
			ModificationMessage():ModifyRankInvisibility(self, invisible):SendToServer(Client_Modify)
		end

		function RankObject:SendAccessGroupUpdate(access_group)
			ModificationMessage():ModifyRankAccessGroup(self, access_group):SendToServer(Client_Modify)
		end

		J_NET:Receive(Sync_OnConnect, function ()
			local obj = RankObject():NetRead()
		end)

		J_NET:Receive(Update_Added, function ()
			local obj = RankObject():NetRead()
			Rank_Hook_Run("OnAdd")(obj)
		end)

		J_NET:ReceiveString(Update_Removed, function (name)
			local obj = RankObject{name = name}

			Rank_Hook_Run("OnRemove", function () obj:Remove() end)(false, obj:GetName(), function (code)
				if code != nil or code > 0 then
					local bit_length = math.ceil(math.log(code, 2))
					if obj:GetPosition() < bit_length then
						return code
					else
						local left_bits = bit.rshift(code, obj:GetPosition())
						left_bits = bit.lshift(left_bits, obj:GetPosition() - 1)

						local right_bits = bit.ror(code, obj:GetPosition() - 1)
						right_bits = bit.rshift(right_bits, bit_length - obj:GetPosition())
						right_bits = bit.rol(right_bits, bit_length)

						return left_bits + right_bits
					end
				end
				return 0
			end)
		end)

		J_NET:Receive(Update_MultiRemoved, function ()
			local ranks_to_remove = {}
			local rank_to_remove_amount = net.ReadUInt(6)

			local index = 1
			repeat
				RankObject():NetRead()
				index = 1 + index
			until (index <= rank_to_remove_amount)

			local min_pos_to_remove = 32

			local bit_sections_to_remove_amt = 0
			local last_pos = 0

			local bit_sections_to_remove = {}

			for k,obj in ipairs(ranks_to_remove) do
				if obj:Position() < min_pos_to_remove then
					min_pos_to_remove = obj:Position()
				end

				if obj:Position() - last_pos > 1 then
					bit_sections_to_remove_amt = 1 + bit_sections_to_remove_amt
					bit_sections_to_remove[1 + #bit_sections_to_remove] = {obj:Position(), obj:Position()} -- [Index] = {Max, Min}
				else
					bit_sections_to_remove[#bit_sections_to_remove][1] = obj:Position()
				end

				last_pos = obj:Position()
			end

			Rank_Hook_Run("OnRemove", function () obj:Remove() end)(true, obj:GetName(), function (code) -- Untested algorithm, made to replace the disfunctioning original algorithm
				if code != nil or code > 0 then
					local bit_length = math.ceil(math.log(code, 2))
					if min_pos_to_remove < bit_length then
						local section_table = {}

						local amount_to_shift_right = 0

						local function calculateSection(floor, ceil)
							local section = bit.rshift(code, floor)
							section = bit.ror(section, ceil - floor)
							section = bit.rshift(section, bit_length - ceil)
							section = bit.rol(section, bit_length - ((bit_sections_to_remove[index][1] - bit_sections_to_remove[index][2]) + amount_to_shift_right ))

							amount_to_shift_right = math.ceil(math.log(section, 2)) + amount_to_shift_right
							section_table[1 + #section_table] = section
						end

						if bit_sections_to_remove[1][2] > 1 then
							calculateSection(1, bit_sections_to_remove[1][2])
						end

						local index = 1
						repeat
							calculateSection(bit_sections_to_remove[index][1], bit_sections_to_remove[index + 1][2])

							index = 1 + index
						until (index <= #bit_sections_to_remove - 1)

						if bit_length > bit_sections_to_remove[#bit_sections_to_remove][1] then
							calculateSection(bit_sections_to_remove[index][1], bit_length)
						end

						local calculated_code = 0

						for k,section in ipairs(section_table) do
							calculated_code = section + calculated_code
						end

						return calculated_code
					else
						return code
					end
				end
				return 0
			end)
		end)

		J_NET:Receive(Update_Modified, function ()
			local obj = RankObject():NetRead()
			Rank_Hook_Run("OnModified")(obj)
		end)
	end
end