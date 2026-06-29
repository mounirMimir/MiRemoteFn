--!strict
const util = require("@self/Util")
type Flatten<t> = util.FlattenTable<t>

type ServerInvokeCallback = (player: Player, ...any) -> ...any
type ClientInvokeCallback = (...any) -> ...any

type PlayerData = {
	ThreadData: { [number]: ThreadEntry },
	CurrentId: number,
}

export type ThreadEntry = {
	YieldedThread: thread,
	TimeoutThread: thread,
}

----- Server -----
type ServerPublicAttributes = {
	Event: ServerInvokeCallback?,
}

type ServerPrivateAttributes = {
	_Name: string,
	_Destroyed: boolean,
	_PlayerData: { [Player]: PlayerData },
	_ServerRemote: RemoteEvent,
	_ClientRemote: RemoteEvent,
	_OnClientEvent: RBXScriptConnection?,
	_OnServerEvent: RBXScriptConnection?,
	_PlayerRemoving: RBXScriptConnection?,
}

export type ServerPublicMethods<self> = {
	read InvokeClient: (self: self, player: Player, timeout: number, ...any) -> (boolean, ...any),
	read Destroy: (self: self) -> (),
}

export type ServerPrivateMethods<self> = {
	__OnTimeout: (self: self, player: Player, entryId: number) -> (),
	__OnResponse: (self: self, player: Player, id: number, ...any) -> (),
	__OnInvoke: (self: self, player: Player, id: number, ...any) -> (),
}

export type ServerRemoteFn = Flatten<ServerPublicAttributes & ServerPublicMethods<any>>
export type ServerRemoteFnInternal = Flatten<ServerRemoteFn & ServerPrivateAttributes & ServerPrivateMethods<any>>

export type ServerClass = {
	new: (name: string) -> ServerRemoteFn,
}

----- Client -----

type ClientPublicAttributes = {
	Event: ClientInvokeCallback?,
}

type ClientPrivateAttributes = {
	_Name: string,
	_Destroyed: boolean,
	_Threads: { [number]: ThreadEntry },
	_Counter: number,
	_ServerRemote: RemoteEvent,
	_ClientRemote: RemoteEvent,
	_OnClientEvent: RBXScriptConnection?,
	_OnServerEvent: RBXScriptConnection?,
}

export type ClientPublicMethods<self> = {
	read Invoke: (self: self, timeout: number, ...any) -> (boolean, ...any),
	read Destroy: (self: self) -> (),
}

export type ClientPrivateMethods<self> = {
	__OnTimeout: (self: self, entryIndex: number) -> (),
	__OnResponse: (self: self, id: number, ...any) -> (),
	__OnInvoke: (self: self, id: number, ...any) -> (),
}

export type ClientRemoteFn = Flatten<ClientPublicAttributes & ClientPublicMethods<any>>
export type ClientRemoteFnInternal = Flatten<ClientRemoteFn & ClientPrivateAttributes & ClientPrivateMethods<any>>

export type ClientClass = {
	new: (name: string) -> ClientRemoteFn,
}

return {}
