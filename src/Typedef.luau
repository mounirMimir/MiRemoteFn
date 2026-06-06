type InvokeCallback = (player: Player, ...any) -> ...any
type ClientInvokeCallback = (...any) -> ...any

type PlayerData = {
	ThreadData: { ThreadEntry },
	CurrentId: number,
}

export type ThreadEntry = {
	YieldedThread: thread,
	TimeoutThread: thread,
}

--- Server ---
type ServerPublicAttributes = {
	Event: InvokeCallback?,
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

export type ServerPublicMethods<self, args..., res...> = {
	InvokeClient: (self: self, player: Player, timeout: number, args...) -> (boolean, res...),
	Destroy: (self: self) -> (),
}

export type ServerPrivateMethods<self, args..., res...> = {
	_Timeout: (self: self, player: Player, entryId: number) -> (),
	_HandleResponse: (self: self, player: Player, id: number, res...) -> (),
	_HandleInvoke: (self: self, player: Player, id: number, args...) -> (),
}

export type ServerRemoteFnInternal<args..., res...> =
	ServerPublicMethods<ServerRemoteFnInternal<args..., res...>, args..., res...>
	& ServerPrivateMethods<ServerRemoteFnInternal<args..., res...>, args..., res...>
	& ServerPublicAttributes
	& ServerPrivateAttributes

export type ServerRemoteFn<args..., res...> =
	ServerPublicMethods<ServerRemoteFnInternal<args..., res...>, args..., res...>
	& ServerPublicAttributes

export type ServerClass = {
	read new: (name: string, invokeCallback: InvokeCallback?) -> ServerRemoteFn<...any, ...any>,
}

--- Client ---
type ClientPublicAttributes = {
	Event: ClientInvokeCallback?,
}

type ClientPrivateAttributes = {
	_name: string,
	_destroyed: boolean,
	_threads: { ThreadEntry },
	_counter: number,
	_serverRemote: RemoteEvent,
	_clientRemote: RemoteEvent,
	_onClientEvent: RBXScriptConnection?,
	_onServerEvent: RBXScriptConnection?,
}

export type ClientPublicMethods<self, args..., res...> = {
	Invoke: (self: self, timeout: number, args...) -> (boolean, res...),
	Destroy: (self: self) -> (),
}

export type ClientPrivateMethods<self, args..., res...> = {
	_Timeout: (self: self, entryId: number) -> (),
	_HandleResponse: (self: self, id: number, res...) -> (),
	_HandleInvoke: (self: self, id: number, args...) -> (),
}

export type ClientRemoteFnInternal<args..., res...> =
	ClientPublicMethods<ClientRemoteFnInternal<args..., res...>, args..., res...>
	& ClientPrivateMethods<ClientRemoteFnInternal<args..., res...>, args..., res...>
	& ClientPrivateAttributes
	& ClientPublicAttributes

export type ClientRemoteFn<args..., res...> =
	ClientPublicAttributes
	& ClientPublicMethods<ClientRemoteFn<args..., res...>, args..., res...>

export type ClientClass = {
	read new: (name: string) -> ClientRemoteFn<...any, ...any>,
}

return {}
