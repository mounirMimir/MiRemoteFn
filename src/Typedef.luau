--!strict
type ServerInvokeCallback = (player: Player, ...any) -> ...any
type ClientInvokeCallback = (...any) -> ...any

type PlayerData = {
	threadData: { [number]: ThreadEntry },
	currentId: number,
}

export type ThreadEntry = {
	yieldedThread: thread,
	timeoutThread: thread,
}

----- Server -----

type ServerPublicAttributes = {
	Event: ServerInvokeCallback?,
}

type ServerPrivateAttributes = {
	_name: string,
	_destroyed: boolean,
	_playerData: { [Player]: PlayerData },
	_serverRemote: RemoteEvent,
	_clientRemote: RemoteEvent,
	_onClientEvent: RBXScriptConnection?,
	_onServerEvent: RBXScriptConnection?,
	_playerRemoving: RBXScriptConnection?,
}

type ServerPublicMethods = {
	InvokeClient: (self: ServerRemoteFnInternal, player: Player, timeout: number, ...any) -> (boolean, ...any),
	Destroy: (self: ServerRemoteFnInternal) -> (),
}

type ServerPrivateMethods = {
	_onTimeout: (self: ServerRemoteFnInternal, player: Player, entryId: number) -> (),
	_onResponse: (self: ServerRemoteFnInternal, player: Player, id: number, ...any) -> (),
	_onInvoke: (self: ServerRemoteFnInternal, player: Player, id: number, ...any) -> (),
}

export type ServerRemoteFn = ServerPublicAttributes & ServerPublicMethods
export type ServerRemoteFnInternal = ServerRemoteFn & ServerPrivateAttributes & ServerPrivateMethods

export type ServerClass = {
	__index: ServerClass,
	new: (name: string) -> ServerRemoteFn,
} & ServerPublicMethods & ServerPrivateMethods

----- Client -----

type ClientPublicAttributes = {
	Event: ClientInvokeCallback?,
}

type ClientPrivateAttributes = {
	_name: string,
	_destroyed: boolean,
	_threads: { [number]: ThreadEntry },
	_counter: number,
	_serverRemote: RemoteEvent,
	_clientRemote: RemoteEvent,
	_onClientEvent: RBXScriptConnection?,
	_onServerEvent: RBXScriptConnection?,
}

type ClientPublicMethods = {
	Invoke: (self: ClientRemoteFnInternal, timeout: number, ...any) -> (boolean, ...any),
	Destroy: (self: ClientRemoteFnInternal) -> (),
}

type ClientPrivateMethods = {
	_onTimeout: (self: ClientRemoteFnInternal, entryIndex: number) -> (),
	_onResponse: (self: ClientRemoteFnInternal, id: number, ...any) -> (),
	_onInvoke: (self: ClientRemoteFnInternal, id: number, ...any) -> (),
}

export type ClientRemoteFn = ClientPublicAttributes & ClientPublicMethods
export type ClientRemoteFnInternal = ClientRemoteFn & ClientPrivateAttributes & ClientPrivateMethods

export type ClientClass = {
	__index: ClientClass,
	new: (name: string) -> ClientRemoteFn,
} & ClientPublicMethods & ClientPrivateMethods

return {}
