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
const Typedef = require("@self/Typedef")
type ThreadEntry = Typedef.ThreadEntry
type ServerRemoteFnInternal = Typedef.ServerRemoteFnInternal
type ClientRemoteFnInternal = Typedef.ClientRemoteFnInternal
export type ServerRemoteFn = Typedef.ServerRemoteFn
export type ClientRemoteFn = Typedef.ClientRemoteFn

----- Server Class -----

local ServerRemoteFunction = {} :: Typedef.ServerClass
ServerRemoteFunction.__index = ServerRemoteFunction

ServerRemoteFunction.new = function(name: string): ServerRemoteFn
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

	local self = setmetatable({}, ServerRemoteFunction) :: ServerRemoteFnInternal

	self._name = name
	self._destroyed = false
	self._playerData = {}
	self._serverRemote = serverRemote
	self._clientRemote = clientRemote
	self._onServerEvent = nil
	self._onClientEvent = nil
	self._playerRemoving = nil
	self.Event = nil

	self._onServerEvent = serverRemote.OnServerEvent:Connect(function(player: Player, id: number, ...)
		self:_onResponse(player, id, ...)
	end)

	self._onClientEvent = clientRemote.OnServerEvent:Connect(function(player: Player, id: number, ...)
		self:_onInvoke(player, id, ...)
	end)

	self._playerRemoving = Players.PlayerRemoving:Connect(function(player: Player, reason: Enum.PlayerExitReason)
		local playerData = self._playerData[player]
		if playerData == nil then
			return
		end

		for _, threadEntry in playerData.threadData do
			task.cancel(threadEntry.timeoutThread)
			task.spawn(threadEntry.yieldedThread, false, `player left reason: {reason}`)
		end
		self._playerData[player] = nil
	end)

	return self
end

function ServerRemoteFunction.InvokeClient(
	self: ServerRemoteFnInternal,
	player: Player,
	timeout: number,
	...
): (boolean, ...any)
	local playerData = self._playerData[player]
	if playerData == nil then
		playerData = {
			currentId = 0,
			threadData = {},
		}
		self._playerData[player] = playerData
	end

	playerData.currentId += 1
	local entryId = playerData.currentId

	playerData.threadData[entryId] = {
		yieldedThread = coroutine.running(),
		timeoutThread = task.delay(timeout, self._onTimeout, self, player, entryId),
	}

	self._clientRemote:FireClient(player, entryId, ...)

	return coroutine.yield()
end

function ServerRemoteFunction.Destroy(self: ServerRemoteFnInternal)
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
		for _, threadEntry in data.threadData do
			task.cancel(threadEntry.timeoutThread)
			task.defer(task.spawn, threadEntry.yieldedThread, false, `remote function destroyed {self._name}`)
		end
	end
	table.clear(self._playerData)
end

function ServerRemoteFunction._onTimeout(self: ServerRemoteFnInternal, player: Player, entryId: number)
	local playerData = self._playerData[player]
	if playerData == nil then
		return
	end

	local threadEntry = playerData.threadData[entryId]
	playerData.threadData[entryId] = nil
	if threadEntry == nil then
		return
	end

	task.spawn(threadEntry.yieldedThread, false, `Invoke Timed Out`)
end

function ServerRemoteFunction._onInvoke(self: ServerRemoteFnInternal, player: Player, id: number, ...)
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
end

function ServerRemoteFunction._onResponse(self: ServerRemoteFnInternal, player: Player, id: number, ...)
	local threadEntry = self._playerData[player].threadData[id]
	self._playerData[player].threadData[id] = nil
	if threadEntry == nil then
		return
	end

	task.cancel(threadEntry.timeoutThread)
	task.spawn(threadEntry.yieldedThread, true, ...)
end

----- Client Class -----

local ClientRemoteFunction = {} :: Typedef.ClientClass
ClientRemoteFunction.__index = ClientRemoteFunction

ClientRemoteFunction.new = function(name: string): ClientRemoteFn
	if RunService:IsServer() then
		error(`can't make a client remote function on the server`, 2)
	end

	local folder = RemotesFolder:WaitForChild(name)
	local serverRemote = folder:FindFirstChild(name .. "Server") :: RemoteEvent
	local clientRemote = folder:FindFirstChild(name .. "Client") :: RemoteEvent

	local self = setmetatable({}, ClientRemoteFunction) :: ClientRemoteFnInternal

	self._name = name
	self._counter = 1
	self._destroyed = false
	self._threads = {}
	self._serverRemote = serverRemote
	self._clientRemote = clientRemote
	self._onServerEvent = nil
	self._onClientEvent = nil
	self.Event = nil

	self._onServerEvent = serverRemote.OnClientEvent:Connect(function(id: number, ...)
		self:_onResponse(id, ...)
	end)

	self._onClientEvent = clientRemote.OnClientEvent:Connect(function(id: number, ...)
		self:_onInvoke(id, ...)
	end)

	return self
end

function ClientRemoteFunction.Invoke(self: ClientRemoteFnInternal, timeout: number, ...): (boolean, ...any)
	local entryIndex = self._counter
	self._counter += 1

	local entry: ThreadEntry = {
		yieldedThread = coroutine.running(),
		timeoutThread = task.delay(timeout, self._onTimeout, self, entryIndex),
	}

	self._threads[entryIndex] = entry
	self._clientRemote:FireServer(entryIndex, ...)

	return coroutine.yield()
end

function ClientRemoteFunction.Destroy(self: ClientRemoteFnInternal)
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
		task.cancel(threadEntry.timeoutThread)
		task.defer(task.spawn, threadEntry.yieldedThread, false, `remote function destroyed {self._name}`)
	end
end

function ClientRemoteFunction._onTimeout(self: ClientRemoteFnInternal, entryIndex: number)
	local entry = self._threads[entryIndex]
	self._threads[entryIndex] = nil
	if entry == nil then
		return
	end

	task.spawn(entry.yieldedThread, false, `Invoke Timed Out`)
end

function ClientRemoteFunction._onInvoke(self: ClientRemoteFnInternal, id: number, ...)
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
end

function ClientRemoteFunction._onResponse(self: ClientRemoteFnInternal, id: number, ...)
	local entry = self._threads[id]
	self._threads[id] = nil
	if entry == nil then
		return
	end

	task.cancel(entry.timeoutThread)
	task.spawn(entry.yieldedThread, true, ...)
end

----- Return -----

return {
	Server = ServerRemoteFunction,
	Client = ClientRemoteFunction,
}
