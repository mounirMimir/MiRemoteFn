--!strict
----- Services -----
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

----- References -----
local RemotesFolder = Instance.new("Folder")
RemotesFolder.Name = "MiRemotesFolder"
RemotesFolder.Parent = ReplicatedStorage

----- Types -----
local Typedef = require("@self/Typedef")
type ThreadEntry = Typedef.ThreadEntry
type ServerRemoteFnInternal = Typedef.ServerRemoteFnInternal
type ClientRemoteFnInternal = Typedef.ClientRemoteFnInternal
export type ServerRemoteFn = Typedef.ServerRemoteFn
export type ClientRemoteFn = Typedef.ClientRemoteFn

----- Server Class -----
local ServerPebMet: Typedef.ServerPublicMethods<ServerRemoteFnInternal> = {
	InvokeClient = function(self, player, timeout, ...)
		local playerData = self._PlayerData[player]
		if playerData == nil then
			playerData = {
				CurrentId = 0,
				ThreadData = {},
			}
			self._PlayerData[player] = playerData
		end

		playerData.CurrentId += 1
		local entryId = playerData.CurrentId

		playerData.ThreadData[entryId] = {
			yieldedThread = coroutine.running(),
			timeoutThread = task.delay(timeout, self.__OnTimeout, self, player, entryId),
		}

		self._ClientRemote:FireClient(player, entryId, ...)

		return coroutine.yield()
	end,

	Destroy = function(self)
		if self._Destroyed then
			return
		end
		self._Destroyed = true

		if self._OnClientEvent then
			self._OnClientEvent:Disconnect()
		end
		if self._OnServerEvent then
			self._OnServerEvent:Disconnect()
		end
		if self._PlayerRemoving then
			self._PlayerRemoving:Disconnect()
		end

		self._ServerRemote:Destroy()
		self._ClientRemote:Destroy()

		for _, data in self._PlayerData do
			for _, threadEntry in data.ThreadData do
				task.cancel(threadEntry.TimeoutThread)
				task.defer(task.spawn, threadEntry.YieldedThread, false, `remote function destroyed {self._Name}`)
			end
		end
		table.clear(self._PlayerData)
	end
}

local ServerPriMet: Typedef.ServerPrivateMethods<ServerRemoteFnInternal> = {
	__OnInvoke = function(self, player, id, ...)
		if self.Event == nil then
			warn(`no event implemented for {self._Name} in the Server`)
			return
		end

		local ok, result = pcall(function(...)
			return table.pack(self.Event(player, ...))
		end, ...)

		if not ok then
			warn(`event handler errored on the server for {self._Name}: {result}`)
			return
		end

		self._ServerRemote:FireClient(player, id, table.unpack(result, 1, result.n))
	end,

	__OnResponse = function(self, player, id, ...)
		local threadEntry = self._PlayerData[player].ThreadData[id]
		self._PlayerData[player].ThreadData[id] = nil
		if threadEntry == nil then
			return
		end

		task.cancel(threadEntry.TimeoutThread)
		task.spawn(threadEntry.YieldedThread, true, ...)
	end,

	__OnTimeout = function(self, player, entryId)
		local playerData = self._PlayerData[player]
		if playerData == nil then
			return
		end

		local threadEntry = playerData.ThreadData[entryId]
		playerData.ThreadData[entryId] = nil
		if threadEntry == nil then
			return
		end

		task.spawn(threadEntry.YieldedThread, false, `Invoke Timed Out`)
	end
}

local ServerRemoteFunction : Typedef.ServerClass = {
	new = function(name)
		if RunService:IsClient() then
			error(`can't make a server remote function on the client`, 2)
		end

		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = RemotesFolder

		local serverRemote = Instance.new("RemoteEvent")
		serverRemote.Name = name .. "Server"
		serverRemote.Parent = folder

		local clientRemote = Instance.new("RemoteEvent")
		clientRemote.Name = name .. "Client"
		clientRemote.Parent = folder

		local self: ServerRemoteFnInternal = {
			Event = nil,

			_Name = name,
			_Destroyed = false,
			_PlayerData = {},
			_ServerRemote = serverRemote,
			_ClientRemote = clientRemote,
			_OnServerEvent = nil,
			_OnClientEvent = nil,
			_PlayerRemoving = nil,

			InvokeClient = ServerPebMet.InvokeClient,
			Destroy = ServerPebMet.Destroy,

			__OnInvoke = ServerPriMet.__OnInvoke,
			__OnResponse = ServerPriMet.__OnResponse,
			__OnTimeout = ServerPriMet.__OnTimeout,

		}

		self._OnServerEvent = serverRemote.OnServerEvent:Connect(function(player: Player, id: number, ...)
			self:__OnResponse(player, id, ...)
		end)

		self._OnClientEvent = clientRemote.OnServerEvent:Connect(function(player: Player, id: number, ...)
			self:__OnInvoke(player, id, ...)
		end)

		self._PlayerRemoving = Players.PlayerRemoving:Connect(function(player: Player, reason: Enum.PlayerExitReason)
			local playerData = self._PlayerData[player]
			if playerData == nil then
				return
			end

			for _, threadEntry in playerData.ThreadData do
				task.cancel(threadEntry.TimeoutThread)
				task.spawn(threadEntry.YieldedThread, false, `player left reason: {reason}`)
			end
			self._PlayerData[player] = nil
		end)

		return self
	end
} 

----- Client Class -----
local ClientPubMet: Typedef.ClientPublicMethods<ClientRemoteFnInternal> = {
	Invoke = function(self, timeout, ...)
		local entryIndex = self._Counter
		self._Counter += 1

		local entry: ThreadEntry = {
			YieldedThread = coroutine.running(),
			TimeoutThread = task.delay(timeout, self.__OnTimeout, self, entryIndex),
		}

		self._Threads[entryIndex] = entry
		self._ClientRemote:FireServer(entryIndex, ...)

		return coroutine.yield()
	end,

	Destroy = function(self)
		if self._Destroyed then
			return
		end
		self._Destroyed = true

		if self._OnClientEvent then
			self._OnClientEvent:Disconnect()
		end
		if self._OnServerEvent then
			self._OnServerEvent:Disconnect()
		end

		for _, threadEntry in self._Threads do
			task.cancel(threadEntry.TimeoutThread)
			task.defer(task.spawn, threadEntry.YieldedThread, false, `remote function destroyed {self._Name}`)
		end
	end,
}

local ClientPriMet: Typedef.ClientPrivateMethods<ClientRemoteFnInternal> = {
	__OnInvoke = function(self, id, ...)
		if self.Event == nil then
			warn(`no event implemented for {self._Name} in the Client`)
			return
		end

		local ok, result = pcall(function(...)
			return table.pack(self.Event(...))
		end, ...)

		
		
		if not ok then
			warn(`event handler errored on the client for {self._Name}: {result}`)
			return
		end

		self._ServerRemote:FireServer(id, table.unpack(result, 1, result.n))
	end,

	__OnResponse = function(self, id, ...)
		local entry = self._Threads[id]
		self._Threads[id] = nil
		if entry == nil then
			return
		end

		task.cancel(entry.TimeoutThread)
		task.spawn(entry.YieldedThread, true, ...)
	end,

	__OnTimeout = function(self, entryIndex)
		local entry = self._Threads[entryIndex]
		self._Threads[entryIndex] = nil
		if entry == nil then
			return
		end

		task.spawn(entry.YieldedThread, false, `Invoke Timed Out`)
	end,
}

local ClientRemoteFunction : Typedef.ClientClass = {
	new = function(name: string): ClientRemoteFn
		if RunService:IsServer() then
			error(`can't make a client remote function on the server`, 2)
		end

		local folder = RemotesFolder:WaitForChild(name)
		local serverRemote = folder:FindFirstChild(name .. "Server") :: RemoteEvent
		local clientRemote = folder:FindFirstChild(name .. "Client") :: RemoteEvent

		local self: ClientRemoteFnInternal = {
			Event = nil,

			_Name = name,
			_Counter = 1,
			_Destroyed = false,
			_Threads = {},
			_ServerRemote = serverRemote,
			_ClientRemote = clientRemote,
			_OnServerEvent = nil,
			_OnClientEvent = nil,

			Invoke = ClientPubMet.Invoke,
			Destroy = ClientPubMet.Destroy,

			__OnInvoke = ClientPriMet.__OnInvoke,
			__OnResponse = ClientPriMet.__OnResponse,
			__OnTimeout = ClientPriMet.__OnTimeout,
		}


		self._OnServerEvent = serverRemote.OnClientEvent:Connect(function(id: number, ...)
			self:__OnResponse(id, ...)
		end)

		self._OnClientEvent = clientRemote.OnClientEvent:Connect(function(id: number, ...)
			self:__OnInvoke(id, ...)
		end)

		return self
	end,
}

----- Return -----

return {
	Server = ServerRemoteFunction,
	Client = ClientRemoteFunction,
}
