--!strict

---- Services ----
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

---- References ----
local RemotesFolder = Instance.new("Folder")
RemotesFolder.Parent = ReplicatedStorage
RemotesFolder.Name = "MiRemotesFolder"

---- Types ----
const Typedef = require("@self/Typedef")

--> Shared
type ThreadEntry = Typedef.ThreadEntry

--> Server
type ServerPublicMethods<self> = Typedef.ServerPublicMethods<self, ...any, ...any>
type ServerPrivateMethods<self> = Typedef.ServerPrivateMethods<self, ...any, ...any>
type ServerRemoteFnInternal = Typedef.ServerRemoteFnInternal<...any, ...any>
type ServerClass = Typedef.ServerClass
export type ServerRemoteFn<args..., res...> = Typedef.ServerRemoteFn<args..., res...>

--> Client
type ClientPublicMethods<self> = Typedef.ClientPublicMethods<self, ...any, ...any>
type ClientPrivateMethods<self> = Typedef.ClientPrivateMethods<self, ...any, ...any>
type ClientRemoteFnInternal = Typedef.ClientRemoteFnInternal<...any, ...any>
type ClientClass = Typedef.ClientClass
export type ClientRemoteFn<args..., res...> = Typedef.ClientRemoteFn<args..., res...>

---- Server ----

local ServerPublicMethods: ServerPublicMethods<ServerRemoteFnInternal> = {

	InvokeClient = function(self, player, timeout, ...)
		local playerData = self._playerData[player]
		if playerData == nil then
			playerData = {
				CurrentId = 0,
				ThreadData = {},
			}
			self._playerData[player] = playerData
		end

		playerData.CurrentId += 1
		local entryId = playerData.CurrentId

		playerData.ThreadData[entryId] = {
			YieldedThread = coroutine.running(),
			TimeoutThread = task.delay(timeout, self._Timeout, self, player, entryId),
		}

		self._clientRemote:FireClient(player, entryId, ...)

		return coroutine.yield()
	end,

	Destroy = function(self)
		if self._destroyed then
			return
		end
		self._destroyed = true

		if self._onClientEvent then
			self._onClientEvent:Disconnect()
		end
		if self._onServerEvent then
			self._onServerEvent:Disconnect()
		end
		if self._playerRemoving then
			self._playerRemoving:Disconnect()
		end

		self._serverRemote:Destroy()
		self._clientRemote:Destroy()

		for _, data in self._playerData do
			for _, threadEntry in data.ThreadData do
				task.cancel(threadEntry.TimeoutThread)
				task.defer(task.spawn, threadEntry.YieldedThread, false, `remote function destroyed {self._name}`)
			end
		end
		table.clear(self._playerData)
	end,
}

local ServerPrivateMethods: ServerPrivateMethods<ServerRemoteFnInternal> = {

	_Timeout = function(self, player, entryId)
		local playerData = self._playerData[player]
		if playerData == nil then
			return
		end

		local threadEntry = playerData.ThreadData[entryId]
		playerData.ThreadData[entryId] = nil
		if threadEntry == nil then
			return
		end

		task.spawn(threadEntry.YieldedThread, false, `Invoke Timed Out`)
	end,

	_HandleInvoke = function(self, player, id, ...)
		if self.Event == nil then
			warn(`no event implemented for {self._name} in the Server`)
			return
		end

		local ok, result = pcall(function(...)
			return table.pack(self.Event(player, ...))
		end, ...)

		if not ok then
			warn(`event handler errored on the server for {self._name}: {result}`)
			return
		end

		self._serverRemote:FireClient(player, id, table.unpack(result, 1, result.n))
	end,

	_HandleResponse = function(self, player, id, ...)
		local threadEntry = self._playerData[player].ThreadData[id]
		self._playerData[player].ThreadData[id] = nil
		if threadEntry == nil then
			return
		end

		task.cancel(threadEntry.TimeoutThread)
		task.spawn(threadEntry.YieldedThread, true, ...)
	end,
}

local ServerRemoteFunction: ServerClass = table.freeze({
	new = function(name)
		if RunService:IsClient() then
			error(`can't make a server remote function on the client`, 2)
		end

		local remoteFolder = Instance.new("Folder")
		remoteFolder.Name = name
		remoteFolder.Parent = RemotesFolder

		local serverRemote = Instance.new("RemoteEvent")
		serverRemote.Name = name .. "Server"
		serverRemote.Parent = remoteFolder

		local clientRemote = Instance.new("RemoteEvent")
		clientRemote.Name = name .. "Client"
		clientRemote.Parent = remoteFolder

		local self: ServerRemoteFnInternal = {
			_name = name,
			_destroyed = false,
			_playerData = {},
			_serverRemote = serverRemote,
			_clientRemote = clientRemote,
			_onServerEvent = nil,
			_onClientEvent = nil,
			_playerRemoving = nil,
			Event = nil,

			InvokeClient = ServerPublicMethods.InvokeClient,
			Destroy = ServerPublicMethods.Destroy,

			_Timeout = ServerPrivateMethods._Timeout,
			_HandleInvoke = ServerPrivateMethods._HandleInvoke,
			_HandleResponse = ServerPrivateMethods._HandleResponse,
		}

		self._onServerEvent = serverRemote.OnServerEvent:Connect(function(player: Player, id: number, ...)
			self:_HandleResponse(player, id, ...)
		end)

		self._onClientEvent = clientRemote.OnServerEvent:Connect(function(player: Player, id: number, ...)
			self:_HandleInvoke(player, id, ...)
		end)

		self._playerRemoving = Players.PlayerRemoving:Connect(function(player: Player, reason: Enum.PlayerExitReason)
			local playerData = self._playerData[player]
			if playerData == nil then
				return
			end

			for _, threadEntry in playerData.ThreadData do
				task.cancel(threadEntry.TimeoutThread)
				task.spawn(threadEntry.YieldedThread, false, `player left reason: {reason}`)
			end
			self._playerData[player] = nil
		end)

		return self
	end,
})

---- Client ----

local ClientPrivateMethods: ClientPrivateMethods<ClientRemoteFnInternal> = {

	_Timeout = function(self, entryIndex)
		local entry = self._threads[entryIndex]
		self._threads[entryIndex] = nil
		if entry == nil then
			return
		end

		task.spawn(entry.YieldedThread, false, `Invoke Timed out`)
	end,

	_HandleInvoke = function(self, id, ...)
		if self.Event == nil then
			warn(`no event implemented for {self._name} in the Client`)
			return
		end

		local ok, result = pcall(function(...)
			return table.pack(self.Event(...))
		end, ...)

		if not ok then
			warn(`event handler errored on the client for {self._name}: {result}`)
			return
		end

		self._serverRemote:FireServer(id, table.unpack(result, 1, result.n))
	end,

	_HandleResponse = function(self, id, ...)
		local entry = self._threads[id]
		self._threads[id] = nil
		if entry == nil then
			return
		end

		task.cancel(entry.TimeoutThread)
		task.spawn(entry.YieldedThread, true, ...)
	end,
}

local ClientPublicMethods: ClientPublicMethods<ClientRemoteFnInternal> = {

	Invoke = function(self, timeout, ...)
		local entryIndex = self._counter
		self._counter += 1

		local entry: ThreadEntry = {
			YieldedThread = coroutine.running(),
			TimeoutThread = task.delay(timeout, self._Timeout, self, entryIndex),
		}

		self._threads[entryIndex] = entry
		self._clientRemote:FireServer(entryIndex, ...)

		return coroutine.yield()
	end,

	Destroy = function(self)
		if self._destroyed then
			return
		end
		self._destroyed = true

		if self._onClientEvent then
			self._onClientEvent:Disconnect()
		end
		if self._onServerEvent then
			self._onServerEvent:Disconnect()
		end

		for _, threadEntry in self._threads do
			task.cancel(threadEntry.TimeoutThread)
			task.defer(task.spawn, threadEntry.YieldedThread, false, `remote function destroyed {self._name}`)
		end
	end,
}

local ClientRemoteFunction: ClientClass = table.freeze({
	new = function(name)
		if RunService:IsServer() then
			error(`can't make a client remote function on the server`)
		end

		local remoteFolder = RemotesFolder:WaitForChild(name)
		local serverRemote = remoteFolder:FindFirstChild(name .. "Server") :: RemoteEvent
		local clientRemote = remoteFolder:FindFirstChild(name .. "Client") :: RemoteEvent

		local self: ClientRemoteFnInternal = {
			_name = name,
			_counter = 1,
			_destroyed = false,
			_threads = {},
			_serverRemote = serverRemote,
			_clientRemote = clientRemote,
			_onServerEvent = nil,
			_onClientEvent = nil,
			Event = nil,

			Invoke = ClientPublicMethods.Invoke,
			Destroy = ClientPublicMethods.Destroy,

			_Timeout = ClientPrivateMethods._Timeout,
			_HandleInvoke = ClientPrivateMethods._HandleInvoke,
			_HandleResponse = ClientPrivateMethods._HandleResponse,
		}

		self._onServerEvent = self._serverRemote.OnClientEvent:Connect(function(id: number, ...)
			self:_HandleResponse(id, ...)
		end)

		self._onClientEvent = self._clientRemote.OnClientEvent:Connect(function(id: number, ...)
			self:_HandleInvoke(id, ...)
		end)

		return self
	end,
})

---- Return ----

return table.freeze({
	Server = ServerRemoteFunction,
	Client = ClientRemoteFunction,
})
