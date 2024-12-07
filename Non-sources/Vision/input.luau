local BuildVersion = "1.1"

local function ArrayToDictionary(Table, ValueOverride)
	ValueOverride = ValueOverride or true

	local tmp = {}

	for _, Key in Table do
		tmp[Key] = ValueOverride
	end

	return tmp
end

local outputs = ArrayToDictionary({
	"httpResponse",
	"readFile",
	"isFile",
	"appendFile",
	"listFiles",
	"isFolder",
	"httpGet",
}, "")

local injectClone = Instance.new("Folder")
injectClone.Name = "BridgeService"
injectClone.Parent = game

local bridgeyService = {
	normalFormat = "%s" .. string.rep("\0", 16_000_000), -- 16 megabytus decimal char limit, wow big
	session = 0,
}

function bridgeyService:new(id, callback)
	local bridgeSender = Instance.new("StringValue") -- 200k char limit, we aint even gonna use this for big string sending
	bridgeSender.Name = id .. "-sender"
	bridgeSender.Value = "-(default)-"
	bridgeSender.Parent = injectClone

	local newStr = string.format(self.normalFormat, id)

	local bridgeListener = game:GetService("RunService").Heartbeat:Connect(function()
		local current = string.match(newStr, "(.-)%\0")

		if string.sub(current, 1, #id) ~= id then
			callback(current, bridgeSender)

			id = current
		end
	end)

	local Bridge = setmetatable({
		Send = function(Self, value)
			self.session += 1
			value.session = self.session

			bridgeSender.Value = game:GetService("HttpService"):JSONEncode(value)
		end,
		Get = function(Self)
			return bridgeSender
		end,
		Communicate = function(Self, Key, Value, WaitTime)
			Self:Send({
				[Key] = Value,
			})

			if WaitTime == false then
				return true
			else
				WaitTime = WaitTime or 5

				local delta = 0;
				while outputs[Key] == "" do
					delta = delta + task.wait()
					if WaitTime <= delta then
						break
					end
				end

				local response = outputs[Key]
				outputs[Key] = ""

				return response
			end
		end,
	}, { __index = bridgeListener }) -- * For Bridge.Disconnect and so on

	return Bridge
end

--

local function TypeError(ArgN, ExpectedType, Type)
	ArgN = ArgN or 0
	ExpectedType = ExpectedType or ""
	
	if not Type then
		return error(
			string.format("missing argument #%d (expected %s)", ArgN, ExpectedType)
		)
	end
	
	return error(
		string.format("invalid argument #%d (expected %s, got %s)", ArgN, ExpectedType, Type)
	)
end

local function TypeCheck(ArgN, Value, ExpectedType, CanBeNil)	
	local CurrentType = (Value == nil and nil) or typeof(Value)
	
	if CanBeNil and CurrentType == nil then
		return
	end
	
	if CurrentType ~= ExpectedType or typeof(ExpectedType) == "table" and (table.find(ExpectedType, CurrentType)) then
		return TypeError(ArgN, typeof(ExpectedType) == 'table' and ExpectedType[1] or ExpectedType, CurrentType)
	end
end

local VisionEnv = {}

local function DefineVEnv(names, value, tableN)
	if not names then return end
	
	if tableN then
		VisionEnv[tableN] = VisionEnv[tableN] or {}

		for _, name in pairs(names) do
			VisionEnv[tableN][name] = value
		end
		
		return
	end
	
	for _, name in pairs(names) do
		VisionEnv[name] = value
	end
end

local GENV = {}

local Ref_typeof = typeof
local Mt_Cache = { DataTypes = {}, Tables = setmetatable({}, { __mode = "vs" }) } --! so that function address are the same ALWAYS
local CacheMT = function(Index, Value)
	-- TODO Account for cases where the person ref's mt to a table but makes it locked so this results us in caching metamethods/mt despite it having chance of being modified and changed later (therefore we might return outdated metamethods)
	local Typeof = Ref_typeof(Index)
	if Value then
		if Typeof == "table" then
			Mt_Cache.Tables[Index] = Value
		else
			Mt_Cache.DataTypes[Typeof] = Value
		end
	else
		local Cached = if Typeof == "table" then Mt_Cache.Tables[Index] else Mt_Cache.DataTypes[Typeof]
		if Cached then
			return Cached
		end
	end
end

local CloneRefs = { Clones = setmetatable({}, { __mode = "ks" }), Originals = setmetatable({}, { __mode = "vs" }) } --*s means shrinkable, weak keys for Clones because structure is {Clone = Originals[OriginalInstance]} so when clone gets garbage collected the only ref to value inside Originals table is garbage collected too because Originals has weak values

local ReturnOriginal = function(instance) --! This function might be needed to call in other functions (testing required)
	local CloneInfo = CloneRefs.Clones[instance] -- *Checks if its a clone and not a real instance

	if CloneInfo then
		return CloneInfo.Original -- *Grabs the original instance then
	end
end

local getrawmetatable = function(Table_or_Userdata)
	local Original = ReturnOriginal(Table_or_Userdata)
	if Original then
		Table_or_Userdata = Original
	end
	local Cached = CacheMT(Table_or_Userdata)
	if Cached then
		return Cached
	end

	--TODO They'll have different memory address; So maybe we should do some caching; but then we gotta avoid memory leaks too

	-- For Full (likely) Metamethod list Refer to - https://github.com/luau-lang/luau/blob/0492ecffdfae8c838067494f5761627b5563cb5a/VM/src/ltm.cpp#L34

	--TODO We can also rebuild many non-dynamic things like len or arithmetic  metamethods since we know what arguments to expect in those usually

	--! PERHAPS WE SHOULD REMOVE SOME METAMETHODS FROM FINAL RETURN IF THEY AREN'T SAFE TO CALL OR INCORRECT (NOT WHAT USER WOULD EXPECT BASICALLY)

	local result = getmetatable(Table_or_Userdata)

	if result == nil then -- No meta
		return
	end

	if type(result) == "table" and pcall(setmetatable, Table_or_Userdata, result) then -- This checks if it's real without overwriting
		return result --* We dont cache this as it will be the same always anyways
	end

	local RealMT = {}
	CacheMT(Table_or_Userdata, RealMT)
	--! Metamethod bruteforcing (WE NEED TO MAKE ALL ERROR)
	xpcall(function()
		return Table_or_Userdata.__PLEASE_ERROR
	end, function()
		RealMT.__index = debug.info(2, "f")
	end)

	xpcall(function()
		Table_or_Userdata.__PLEASE_ERROR = Table_or_Userdata
	end, function()
		RealMT.__newindex = debug.info(2, "f")
	end)

	xpcall(function()
		Table_or_Userdata()
	end, function()
		RealMT.__call = debug.info(2, "f")
	end)

	xpcall(function()
		return Table_or_Userdata .. Table_or_Userdata -- TODO Not sure if this would work on userdata.. (do they even have __concat defined, would it be called)
	end, function()
		RealMT.__concat = debug.info(2, "f")
	end)

	xpcall(function()
		return -Table_or_Userdata
	end, function()
		RealMT.__unm = debug.info(2, "f")
	end)

	xpcall(function()
		return Table_or_Userdata + Table_or_Userdata
	end, function()
		RealMT.__add = debug.info(2, "f")
	end)

	xpcall(function()
		return Table_or_Userdata - Table_or_Userdata
	end, function()
		RealMT.__sub = debug.info(2, "f")
	end)

	xpcall(function()
		return Table_or_Userdata * Table_or_Userdata
	end, function()
		RealMT.__mul = debug.info(2, "f")
	end)

	xpcall(function()
		return Table_or_Userdata / Table_or_Userdata
	end, function()
		RealMT.__div = debug.info(2, "f")
	end)

	-- xpcall(function() -- * LUAU
	-- 	return Table_or_Userdata // Table_or_Userdata
	-- end, function()
	-- 	RealMT.__idiv = debug.info(2, "f")
	-- end)

	xpcall(function()
		return Table_or_Userdata % Table_or_Userdata
	end, function()
		RealMT.__mod = debug.info(2, "f")
	end)

	xpcall(function()
		return Table_or_Userdata ^ Table_or_Userdata
	end, function()
		RealMT.__pow = debug.info(2, "f")
	end)

	-- xpcall(function()
	-- -- !MAKE __tostring  ERROR SOMEHOW..
	-- end, function()
	-- 	RealMT.__tostring = debug.info(2, "f")
	-- end)

	-- FAKE __tostring INBOUND (We wrap it because 1. No rawtostring & B. In case Table_or_Userdata Name changes)
	RealMT.__tostring = function()
		return tostring(Table_or_Userdata)
	end

	-- xpcall(function()
	-- -- !MAKE __type ERROR SOMEHOW..
	-- end, function()
	-- 	RealMT.__type = debug.info(2, "f")
	-- end)

	-- FAKE __type INBOUND
	RealMT.__type = Ref_typeof(Table_or_Userdata)

	RealMT.__metatable = "The metatable is locked"

	xpcall(function()
		return Table_or_Userdata == Table_or_Userdata -- ! This will never error (it calls __eq but we need it to error)
	end, function()
		RealMT.__eq = debug.info(2, "f")
	end)

	xpcall(function()
		return Table_or_Userdata < Table_or_Userdata
	end, function()
		RealMT.__lt = debug.info(2, "f")
	end)

	xpcall(function()
		return Table_or_Userdata <= Table_or_Userdata
	end, function()
		RealMT.__le = debug.info(2, "f")
	end)

	-- xpcall(function()
	-- -- !MAKE __mode ERROR SOMEHOW..
	-- end, function()
	-- 	RealMT.__mode = debug.info(2, "f")
	-- end)

	-- xpcall(function()
	-- -- !MAKE __gc ERROR SOMEHOW..
	-- end, function()
	-- 	RealMT.__gc = debug.info(2, "f")
	-- end)

	xpcall(function()
		return #Table_or_Userdata -- ! This will never error on tables, with userdata the issue is same as __concat - is it even a defined metamethod in that case?
	end, function()
		RealMT.__len = debug.info(2, "f")
	end)

	xpcall(function() -- * LUAU
		for _ in Table_or_Userdata do
		end
	end, function()
		RealMT.__iter = debug.info(2, "f")
	end)

	xpcall(function()
		return Table_or_Userdata:__PLEASE_ERROR()
	end, function()
		RealMT.__namecall = debug.info(2, "f")
	end)

	return table.freeze(RealMT) -- We can't check readonly state of actual metatable sadly
end

DefineVEnv({"hookmetamethod"}, function(object, method, hook)
	TypeCheck(1, {"table", "userdata"}, object)
	TypeCheck(2, "string", method)
	TypeCheck(3, "function", hook)

	local rawMetatable = getrawmetatable(object)

	if not rawMetatable then
		error("Metatable not found", 3)
	end

	local oldMethod = rawMetatable[method]

	rawMetatable[method] = hook

	return oldMethod
end)

DefineVEnv({"isreadonly"}, table.isfrozen)

DefineVEnv({"gethui"}, function()
	return game.Players.LocalPlayer.PlayerGui
end)--
DefineVEnv({"getrenv"}, function()
	return getfenv(0)
end)

DefineVEnv({"_G", "shared"}, {})

DefineVEnv({"getgenv"}, function()
	return setmetatable(table.clone(VisionEnv), {
		__index = GENV,
		__newindex = function(self, index, value)
			GENV[index] = value
		end,
	})
end)

DefineVEnv({"identifyexecutor", "getexecutorname"}, function()
	return "Vision", BuildVersion
end)--
local function EndsWith(a, suffix)
	return string.sub(a, -#suffix) == suffix
end

local blockedExtensions =
	{ ".exe", ".scr", ".bat", ".com", ".csh", ".msi", ".vb", ".vbs", ".vbe", ".ws", ".wsf", ".wsh", ".ps1", ".psy" }
local sanitize_path = function(path)
	assert(type(path) == "string", "Path must be a string")
	local Sanitized = string.gsub(string.gsub(path, "^%.*[/\\]*", ""), '[\\/:*?"<>|]+', "")
	assert(Sanitized ~= "", "Sanitized path cannot be empty")
	return Sanitized
end -- sanitize path both on luau and c++

-- * Filesystem
DefineVEnv({'readfile'}, function(path)
	path = sanitize_path(path)

	return bridgeServer:Communicate("readFile", path)
end)

DefineVEnv({'writefile'}, function(path, content)
	-- TODO Merge this with appendfile ( {path, content, <bool> ToAppend})
	path = sanitize_path(path)

	for _, extension in blockedExtensions do
		if EndsWith(path, extension) then
			return `Blacklisted file extension "{extension}"`
		end
	end

	return bridgeServer:Communicate("writeFile", { path, content }, false) == true
end)

DefineVEnv({'appendfile'}, function(path, content)
	-- TODO Merge this with writefile ( {path, content, <bool> ToAppend})
	path = sanitize_path(path)

	for _, extension in blockedExtensions do
		if EndsWith(path, extension) then
			return `Blacklisted file extension "{extension}"`
		end
	end

	return bridgeServer:Communicate("appendFile", { path, content }, false) == true
end)

DefineVEnv({'appendfile'}, function(path, content)
	-- TODO Merge this with writefile ( {path, content, <bool> ToAppend})
	path = sanitize_path(path)

	for _, extension in blockedExtensions do
		if EndsWith(path, extension) then
			return `Blacklisted file extension "{extension}"`
		end
	end

	return bridgeServer:Communicate("appendFile", { path, content }, false) == true
end)

DefineVEnv({'isfile'}, function(path)
	-- TODO ?Merge this with isfolder (return type - dir or file instead)
	path = sanitize_path(path)

	return bridgeServer:Communicate("isFile", path) == "True"
end)

DefineVEnv({'isfile'}, function(path)
	-- TODO Merge this with delfolder (del object)
	path = sanitize_path(path)

	return bridgeServer:Communicate("delFile", path, false) == true
end)

DefineVEnv({'loadfile'}, function(path)
	return GENV.loadstring(GENV.readfile(path))
end)

DefineVEnv({'listfiles'}, function(path)
	path = sanitize_path(path)

	return game:GetService("HttpService"):JSONDecode(bridgeServer:Communicate("listFiles", path))
end)

DefineVEnv({'isfolder'}, function(path)
	-- TODO ?Merge this with isfile (return type - dir or file instead)
	path = sanitize_path(path)

	return bridgeServer:Communicate("isFolder", path) == "True"
end)

DefineVEnv({'makefolder'}, function(path)
	path = sanitize_path(path)

	return bridgeServer:Communicate("makeFolder", path, false)
end)

DefineVEnv({'delfolder'}, function(path)
	-- TODO Merge this with delfile (del object)
	path = sanitize_path(path)

	return bridgeServer:Communicate("makeFolder", path, false)
end)--

DefineVEnv({"request"}, function(requestData)
	TypeCheck(1, requestData, "table")
	assert((requestData.Url and typeof(requestData.Url) == "string"), "Url must be valid!")
	assert(requestData.Url:sub(1, 4):lower() == "http", "Url must be valid!")
	
	return "test"
end)

local customBehaviour = {
	DataModel = {
		HttpGet = function(self, url)
			TypeCheck(1, url, "string")

			return VisionEnv.request({
				Url = url
			})	
		end,
	}
}

local Wrapped, Connections, InstanceReferences = {}, {}, {}
-- from xAPI
wrap = function(a)
	if type(a) == "userdata" then
		for _, wrapped in Wrapped do
			if wrapped == a then
				return wrapped
			end
		end

		local proxy = newproxy(true)
		local meta = getmetatable(proxy)

		Wrapped[proxy] = a

		meta.__index = function(self, key)
			self = Wrapped[self]

			if typeof(self) == "Instance" then
				for type, value in customBehaviour do
					if self:IsA(type) then
						if value[key] ~= nil then
							return wrap(value[key])
						end
					end
				end
			elseif typeof(self) == "RBXScriptSignal" and key:lower() == "connect" then
				return function(self, func)
					self = Wrapped[self]

					local connection = self:Connect(func)

					if not Connections[self] then
						Connections[self] = {}
					end

					table.insert(Connections[self], {connection, func})
				end
			end

			local target = self[key]

			if type(target) == "function" then
				return function(self, ...)
					self = Wrapped[self]

					return wrap(target(self, ...))
				end
			end

			return wrap(target)
		end

		meta.__tostring = function(self)
			self = Wrapped[self]

			return tostring(self)
		end

		meta.__newindex = function(self, key, value)
			self = Wrapped[self]

			self[key] = Wrapped[value] or value 
		end

		meta.__typeof = typeof(a)

		return proxy
	else
		return a
	end
end

DefineVEnv({"newcclosure"}, function(self, closure)
	TypeCheck(1, closure, {"function"})

	return coroutine.wrap(function(...)
		while true do
			coroutine.yield(closure(...))
		end
	end)
end)

DefineVEnv({"newlclosure"}, function(self, closure)
	TypeCheck(1, closure, {"function"})

	return function(...)
		return closure(...)
	end
end)

DefineVEnv({"iscclosure"}, function(self, closure)
	TypeCheck(1, closure, {"function"})

	return debug.info(closure, "s") == "[C]"
end)

DefineVEnv({"islclosure"}, function(self, closure)
	TypeCheck(1, closure, {"function"})

	return debug.info(closure, "s") ~= "[C]"
end)

DefineVEnv({"isexecutorclosure", "isourclosure", "checkclosure"}, function(func)
	TypeCheck(1, func, "function")

	return debug.info(func, "n") == "" or not VisionEnv.getrenv()[debug.info(func, "n")]
end)

DefineVEnv({"replace"}, function(self, object, newObject)
	TypeCheck(1, object, {"Instance", "userdata"})
	TypeCheck(2, newObject, {"Instance", "userdata"})

	Wrapped[object] = newObject
end, "cache")

DefineVEnv({"invalidate"}, function(self, object)
	TypeCheck(1, object, {"Instance", "userdata"})

	Wrapped[object] = nil
end, "cache")

DefineVEnv({"iscached"}, function(self, object)
	TypeCheck(1, object, {"Instance", "userdata"})

	return Wrapped[object] ~= nil
end, "cache")

DefineVEnv({"cloneref"}, function(self, object)
	TypeCheck(1, object, {"Instance", "userdata"})

	local clone = {}
	local proxy = newproxy(true)
	local meta = getmetatable(proxy)

	meta.__newindex = function(self, key, value)
		object[key] = value
		clone[key] = value
	end

	meta.__index = function(self, key, value)
		local index = object[key]

		if type(index) == "function" then
			return function(self, ...)
				return index(self, ...)
			end
		end

		return index
	end

	meta.__tostring = function(self)
		return tostring(object)
	end

	InstanceReferences[object] = clone

	return proxy
end)--

GENV.game = wrap(game)
GENV.Game = wrap(game)

local WindowFocused = true

game:GetService("UserInputService").WindowFocusReleased:Connect(function()
	WindowFocused = false
end)

game:GetService("UserInputService").WindowFocused:Connect(function()
	WindowFocused = true
end)

local isrbxactive = function()
	return WindowFocused
end

DefineVEnv({"isrbxactive", "isgameactive"}, isrbxactive)

DefineVEnv({"keypress"}, function(keycode)
	return bridgeServer:Communicate("keyPress", keycode, false)
end)

DefineVEnv({"keyrelease"}, function(keycode)
	return bridgeServer:Communicate("keyRelease", keycode, false)
end)

DefineVEnv({"mouse1click"}, function(keycode)
	return bridgeServer:Communicate("mouse1Click", true, false)
end)

DefineVEnv({"mouse1press"}, function(keycode)
	return bridgeServer:Communicate("mouse1Press", true, false)
end)

DefineVEnv({"mouse1release"}, function(keycode)
	return bridgeServer:Communicate("mouse1Release", true, false)
end)

DefineVEnv({"mouse2click"}, function(keycode)
	return bridgeServer:Communicate("mouse2Click", true, false)
end)

DefineVEnv({"mouse2press"}, function(keycode)
	return bridgeServer:Communicate("mouse2Press", true, false)
end)

DefineVEnv({"mouse2release"}, function(keycode)
	return bridgeServer:Communicate("mouse2Release", true, false)
end)--
local Capped, FractionOfASecond, FPSMax, Lock
local Heartbeat = game:GetService("RunService").Heartbeat
local setfpscap = function(FPSCap)
	if FPSCap == 0 or FPSCap == nil or 1e4 <= FPSCap then -- ~7k fps is the highest people have gotten; --?maybe compare to getfpsmax instead? (but we have to ensure getfpsmax is accurate first)
		if Capped then
			task.cancel(Capped)
			Capped = nil
			FractionOfASecond = nil
		end
		return
	end

	FractionOfASecond = 1 / FPSCap
	if Capped then
		return
	end
	local function Capper()
		-- * Modified version of https://github.com/MaximumADHD/Super-Nostalgia-Zone/blob/540221bc945a8fc3a45baf51b40e02272a21329d/Client/FpsCap.client.lua#
		local t0 = os.clock()
		Heartbeat:Wait()
		-- repeat until t0 + t1 < tick()
		-- local count = 0
		while os.clock() <= t0 + FractionOfASecond do -- * not using repeat to avoid unreasonable extra iterations
			-- count+=1
		end
	end
	Capper() -- Yield until it kicks in basically
	Capped = task.spawn(function()
		-- capping = true -- * this works too
		while true do
			Capper()
		end
	end)
end

DefineVEnv({"getfpsmax"}, function()
	if not FPSMax then

		local function step()
			local Sum = 0
			local iterations = 5
			local RenderStepped = game:GetService("RunService").RenderStepped

			RenderStepped:Wait()

			for _ = 1, iterations do
				Sum += 1 / RenderStepped:Wait()
			end

			return Sum / iterations
		end
		Lock = true
		local Current = FractionOfASecond
		if Current then
			FractionOfASecond = -math.huge
		end
		FPSMax = step()
		if Current then
			FractionOfASecond = Current
		end
		Lock = nil
	end
	return FPSMax
end)

DefineVEnv({"setfpscap"}, function(FPSCap)
	if Lock then
		return
	end
	setfpscap(FPSCap)
end)

--
local camera = workspace.CurrentCamera
local drawingContainer = Instance.new("ScreenGui")
drawingContainer.Name = "Drawing\0Container"
drawingContainer.IgnoreGuiInset = true
drawingContainer.ResetOnSpawn = false
drawingContainer.DisplayOrder = 0x7fffffff
drawingContainer.Parent = VisionEnv.gethui()

-- variables
local drawingIndex = 0
local drawingObjsList = setmetatable({}, {__mode = "vs"})
local baseDrawingObj = setmetatable({
	Visible = true,
	ZIndex = 0,
	Transparency = 1,
	Color = Color3.new(),
	Remove = function(self)
		setmetatable(self, nil)

		local listPos = table.find(drawingObjsList, self)
		if listPos then
			table.remove(drawingObjsList, listPos)
		end
	end
}, {
	__add = function(t1, t2)
		local result = table.clone(t1)

		for index, value in t2 do
			result[index] = value
		end
		return result
	end
})
local drawingFontsValue = {
	[0] = Font.fromEnum(Enum.Font.Gotham),
	Font.fromEnum(Enum.Font.Legacy),
	Font.fromEnum(Enum.Font.SourceSans),
	Font.fromEnum(Enum.Font.RobotoMono),
}

-- functions
local function getFontFromIndex(fontIndex: number): Font
	return drawingFontsValue[fontIndex]
end

local function convertTransparency(transparency: number): number
	return math.clamp(1 - transparency, 0, 1)
end

-- main
local drawing_lib = {}
drawing_lib.Fonts = {
	["UI"] = 0,
	["System"] = 1,
	["Plex"] = 2,
	["Monospace"] = 3
}

function drawing_lib.new(drawingType)
	drawingIndex += 1
	local drawingObj = {}
	table.insert(drawingObjsList, drawingObj)

	if drawingType == "Line" then
		local lineObj = ({
			From = Vector2.zero,
			To = Vector2.zero,
			Thickness = 1
		} + baseDrawingObj)

		local lineFrame = Instance.new("Frame")
		lineFrame.Name = drawingIndex
		lineFrame.AnchorPoint = (Vector2.one * .5)
		lineFrame.BorderSizePixel = 0

		lineFrame.BackgroundColor3 = lineObj.Color
		lineFrame.Visible = lineObj.Visible
		lineFrame.ZIndex = lineObj.ZIndex
		lineFrame.BackgroundTransparency = convertTransparency(lineObj.Transparency)

		lineFrame.Size = UDim2.new()

		lineFrame.Parent = drawingContainer
		return setmetatable(drawingObj, {
			__newindex = function(_, index, value)
				if typeof(lineObj[index]) == "nil" then return end

				if index == "From" then
					local direction = (lineObj.To - value)
					local center = (lineObj.To + value) / 2
					local distance = direction.Magnitude
					local theta = math.deg(math.atan2(direction.Y, direction.X))

					lineFrame.Position = UDim2.fromOffset(center.X, center.Y)
					lineFrame.Rotation = theta
					lineFrame.Size = UDim2.fromOffset(distance, lineObj.Thickness)
				elseif index == "To" then
					local direction = (value - lineObj.From)
					local center = (value + lineObj.From) / 2
					local distance = direction.Magnitude
					local theta = math.deg(math.atan2(direction.Y, direction.X))

					lineFrame.Position = UDim2.fromOffset(center.X, center.Y)
					lineFrame.Rotation = theta
					lineFrame.Size = UDim2.fromOffset(distance, lineObj.Thickness)
				elseif index == "Thickness" then
					local distance = (lineObj.To - lineObj.From).Magnitude

					lineFrame.Size = UDim2.fromOffset(distance, value)
				elseif index == "Visible" then
					lineFrame.Visible = value
				elseif index == "ZIndex" then
					lineFrame.ZIndex = value
				elseif index == "Transparency" then
					lineFrame.BackgroundTransparency = convertTransparency(value)
				elseif index == "Color" then
					lineFrame.BackgroundColor3 = value
				end
				lineObj[index] = value
			end,
			__index = function(self, index)
				if (index == "Remove" or index == "Destroy") then
					return function()
						lineFrame:Destroy()
						lineObj.Remove(self)
						return lineObj:Remove()
					end
				end
				return lineObj[index]
			end
		})
	elseif drawingType == "Text" then
		local textObj = ({
			Text = "",
			Font = drawing_lib.Fonts.UI,
			Size = 0,
			Position = Vector2.zero,
			Center = false,
			Outline = false,
			OutlineColor = Color3.new()
		} + baseDrawingObj)

		local textLabel, uiStroke = Instance.new("TextLabel"), Instance.new("UIStroke")
		textLabel.Name = drawingIndex
		textLabel.AnchorPoint = (Vector2.one * .5)
		textLabel.BorderSizePixel = 0
		textLabel.BackgroundTransparency = 1

		textLabel.Visible = textObj.Visible
		textLabel.TextColor3 = textObj.Color
		textLabel.TextTransparency = convertTransparency(textObj.Transparency)
		textLabel.ZIndex = textObj.ZIndex

		textLabel.FontFace = getFontFromIndex(textObj.Font)
		textLabel.TextSize = textObj.Size

		textLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
			local textBounds = textLabel.TextBounds
			local offset = textBounds / 2

			textLabel.Size = UDim2.fromOffset(textBounds.X, textBounds.Y)
			textLabel.Position = UDim2.fromOffset(textObj.Position.X + (if not textObj.Center then offset.X else 0), textObj.Position.Y + offset.Y)
		end)

		uiStroke.Thickness = 1
		uiStroke.Enabled = textObj.Outline
		uiStroke.Color = textObj.Color

		textLabel.Parent, uiStroke.Parent = drawingContainer, textLabel
		return setmetatable(drawingObj, {
			__newindex = function(_, index, value)
				if typeof(textObj[index]) == "nil" then return end

				if index == "Text" then
					textLabel.Text = value
				elseif index == "Font" then
					value = math.clamp(value, 0, 3)
					textLabel.FontFace = getFontFromIndex(value)
				elseif index == "Size" then
					textLabel.TextSize = value
				elseif index == "Position" then
					local offset = textLabel.TextBounds / 2

					textLabel.Position = UDim2.fromOffset(value.X + (if not textObj.Center then offset.X else 0), value.Y + offset.Y)
				elseif index == "Center" then
					local position = (if value then camera.ViewportSize / 2 else textObj.Position)

					textLabel.Position = UDim2.fromOffset(position.X, position.Y)
				elseif index == "Outline" then
					uiStroke.Enabled = value
				elseif index == "OutlineColor" then
					uiStroke.Color = value
				elseif index == "Visible" then
					textLabel.Visible = value
				elseif index == "ZIndex" then
					textLabel.ZIndex = value
				elseif index == "Transparency" then
					local transparency = convertTransparency(value)

					textLabel.TextTransparency = transparency
					uiStroke.Transparency = transparency
				elseif index == "Color" then
					textLabel.TextColor3 = value
				end
				textObj[index] = value
			end,
			__index = function(self, index)
				if (index == "Remove" or index == "Destroy") then
					return function()
						textLabel:Destroy()
						textObj.Remove(self)
						return textObj:Remove()
					end
				elseif index == "TextBounds" then
					return textLabel.TextBounds
				end
				return textObj[index]
			end
		})
	elseif drawingType == "Circle" then
		local circleObj = ({
			Radius = 150,
			Position = Vector2.zero,
			Thickness = .7,
			Filled = false
		} + baseDrawingObj)

		local circleFrame, uiCorner, uiStroke = Instance.new("Frame"), Instance.new("UICorner"), Instance.new("UIStroke")
		circleFrame.Name = drawingIndex
		circleFrame.AnchorPoint = (Vector2.one * .5)
		circleFrame.BorderSizePixel = 0

		circleFrame.BackgroundTransparency = (if circleObj.Filled then convertTransparency(circleObj.Transparency) else 1)
		circleFrame.BackgroundColor3 = circleObj.Color
		circleFrame.Visible = circleObj.Visible
		circleFrame.ZIndex = circleObj.ZIndex

		uiCorner.CornerRadius = UDim.new(1, 0)
		circleFrame.Size = UDim2.fromOffset(circleObj.Radius, circleObj.Radius)

		uiStroke.Thickness = circleObj.Thickness
		uiStroke.Enabled = not circleObj.Filled
		uiStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

		circleFrame.Parent, uiCorner.Parent, uiStroke.Parent = drawingContainer, circleFrame, circleFrame
		return setmetatable(drawingObj, {
			__newindex = function(_, index, value)
				if typeof(circleObj[index]) == "nil" then return end

				if index == "Radius" then
					local radius = value * 2
					circleFrame.Size = UDim2.fromOffset(radius, radius)
				elseif index == "Position" then
					circleFrame.Position = UDim2.fromOffset(value.X, value.Y)
				elseif index == "Thickness" then
					value = math.clamp(value, .6, 0x7fffffff)
					uiStroke.Thickness = value
				elseif index == "Filled" then
					circleFrame.BackgroundTransparency = (if value then convertTransparency(circleObj.Transparency) else 1)
					uiStroke.Enabled = not value
				elseif index == "Visible" then
					circleFrame.Visible = value
				elseif index == "ZIndex" then
					circleFrame.ZIndex = value
				elseif index == "Transparency" then
					local transparency = convertTransparency(value)

					circleFrame.BackgroundTransparency = (if circleObj.Filled then transparency else 1)
					uiStroke.Transparency = transparency
				elseif index == "Color" then
					circleFrame.BackgroundColor3 = value
					uiStroke.Color = value
				end
				circleObj[index] = value
			end,
			__index = function(self, index)
				if (index == "Remove" or index == "Destroy") then
					return function()
						circleFrame:Destroy()
						circleObj.Remove(self)
						return circleObj:Remove()
					end
				end
				return circleObj[index]
			end
		})
	elseif drawingType == "Square" then
		local squareObj = ({
			Size = Vector2.zero,
			Position = Vector2.zero,
			Thickness = .7,
			Filled = false
		} + baseDrawingObj)

		local squareFrame, uiStroke = Instance.new("Frame"), Instance.new("UIStroke")
		squareFrame.Name = drawingIndex
		squareFrame.BorderSizePixel = 0

		squareFrame.BackgroundTransparency = (if squareObj.Filled then convertTransparency(squareObj.Transparency) else 1)
		squareFrame.ZIndex = squareObj.ZIndex
		squareFrame.BackgroundColor3 = squareObj.Color
		squareFrame.Visible = squareObj.Visible

		uiStroke.Thickness = squareObj.Thickness
		uiStroke.Enabled = not squareObj.Filled
		uiStroke.LineJoinMode = Enum.LineJoinMode.Miter

		squareFrame.Parent, uiStroke.Parent = drawingContainer, squareFrame
		return setmetatable(drawingObj, {
			__newindex = function(_, index, value)
				if typeof(squareObj[index]) == "nil" then return end

				if index == "Size" then
					squareFrame.Size = UDim2.fromOffset(value.X, value.Y)
				elseif index == "Position" then
					squareFrame.Position = UDim2.fromOffset(value.X, value.Y)
				elseif index == "Thickness" then
					value = math.clamp(value, 0.6, 0x7fffffff)
					uiStroke.Thickness = value
				elseif index == "Filled" then
					squareFrame.BackgroundTransparency = (if value then convertTransparency(squareObj.Transparency) else 1)
					uiStroke.Enabled = not value
				elseif index == "Visible" then
					squareFrame.Visible = value
				elseif index == "ZIndex" then
					squareFrame.ZIndex = value
				elseif index == "Transparency" then
					local transparency = convertTransparency(value)

					squareFrame.BackgroundTransparency = (if squareObj.Filled then transparency else 1)
					uiStroke.Transparency = transparency
				elseif index == "Color" then
					uiStroke.Color = value
					squareFrame.BackgroundColor3 = value
				end
				squareObj[index] = value
			end,
			__index = function(self, index)
				if (index == "Remove" or index == "Destroy") then
					return function()
						squareFrame:Destroy()
						squareObj.Remove(self)
						return squareObj:Remove()
					end
				end
				return squareObj[index]
			end
		})
	elseif drawingType == "Image" then
		local imageObj = ({
			Data = "",
			DataURL = "rbxassetid://0",
			Size = Vector2.zero,
			Position = Vector2.zero
		} + baseDrawingObj)

		local imageFrame = Instance.new("ImageLabel")
		imageFrame.Name = drawingIndex
		imageFrame.BorderSizePixel = 0
		imageFrame.ScaleType = Enum.ScaleType.Stretch
		imageFrame.BackgroundTransparency = 1

		imageFrame.Visible = imageObj.Visible
		imageFrame.ZIndex = imageObj.ZIndex
		imageFrame.ImageTransparency = convertTransparency(imageObj.Transparency)
		imageFrame.ImageColor3 = imageObj.Color

		imageFrame.Parent = drawingContainer
		return setmetatable(drawingObj, {
			__newindex = function(_, index, value)
				if typeof(imageObj[index]) == "nil" then return end

				if index == "DataURL" then -- temporary property
					imageFrame.Image = value
				elseif index == "Size" then
					imageFrame.Size = UDim2.fromOffset(value.X, value.Y)
				elseif index == "Position" then
					imageFrame.Position = UDim2.fromOffset(value.X, value.Y)
				elseif index == "Visible" then
					imageFrame.Visible = value
				elseif index == "ZIndex" then
					imageFrame.ZIndex = value
				elseif index == "Transparency" then
					imageFrame.ImageTransparency = convertTransparency(value)
				elseif index == "Color" then
					imageFrame.ImageColor3 = value
				end
				imageObj[index] = value
			end,
			__index = function(self, index)
				if (index == "Remove" or index == "Destroy") then
					return function()
						imageFrame:Destroy()
						imageObj.Remove(self)
						return imageObj:Remove()
					end
				end
				return imageObj[index]
			end
		})
	elseif drawingType == "Quad" then
		local quadObj = ({
			PointA = Vector2.zero,
			PointB = Vector2.zero,
			PointC = Vector2.zero,
			PointD = Vector3.zero,
			Thickness = 1,
			Filled = false
		} + baseDrawingObj)

		local _linePoints = {}
		_linePoints.A = drawing_lib.new("Line")
		_linePoints.B = drawing_lib.new("Line")
		_linePoints.C = drawing_lib.new("Line")
		_linePoints.D = drawing_lib.new("Line")
		return setmetatable(drawingObj, {
			__newindex = function(_, index, value)
				if typeof(quadObj[index]) == "nil" then return end

				if index == "PointA" then
					_linePoints.A.From = value
					_linePoints.B.To = value
				elseif index == "PointB" then
					_linePoints.B.From = value
					_linePoints.C.To = value
				elseif index == "PointC" then
					_linePoints.C.From = value
					_linePoints.D.To = value
				elseif index == "PointD" then
					_linePoints.D.From = value
					_linePoints.A.To = value
				elseif (index == "Thickness" or index == "Visible" or index == "Color" or index == "ZIndex") then
					for _, linePoint in _linePoints do
						linePoint[index] = value
					end
				elseif index == "Filled" then
					-- later
				end
				quadObj[index] = value
			end,
			__index = function(self, index)
				if (index == "Remove" or index == "Destroy") then
					return function()
						for _, linePoint in _linePoints do
							linePoint:Remove()
						end

						quadObj.Remove(self)
						return quadObj:Remove()
					end
				end
				return quadObj[index]
			end
		})
	elseif drawingType == "Triangle" then
		local triangleObj = ({
			PointA = Vector2.zero,
			PointB = Vector2.zero,
			PointC = Vector2.zero,
			Thickness = 1,
			Filled = false
		} + baseDrawingObj)

		local _linePoints = {}
		_linePoints.A = drawing_lib.new("Line")
		_linePoints.B = drawing_lib.new("Line")
		_linePoints.C = drawing_lib.new("Line")
		return setmetatable(drawingObj, {
			__newindex = function(_, index, value)
				if typeof(triangleObj[index]) == "nil" then return end

				if index == "PointA" then
					_linePoints.A.From = value
					_linePoints.B.To = value
				elseif index == "PointB" then
					_linePoints.B.From = value
					_linePoints.C.To = value
				elseif index == "PointC" then
					_linePoints.C.From = value
					_linePoints.A.To = value
				elseif (index == "Thickness" or index == "Visible" or index == "Color" or index == "ZIndex") then
					for _, linePoint in _linePoints do
						linePoint[index] = value
					end
				elseif index == "Filled" then
					-- later
				end
				triangleObj[index] = value
			end,
			__index = function(self, index)
				if (index == "Remove" or index == "Destroy") then
					return function()
						for _, linePoint in _linePoints do
							linePoint:Remove()
						end

						triangleObj.Remove(self)
						return triangleObj:Remove()
					end
				end
				return triangleObj[index]
			end
		})
	else
		return error(`invalid render object type`, 2)
	end
end

-- * misc drawing funcs

local function clearDrawCache()
	for _, drawingObj in drawingObjsList do
		if not drawingObj then continue end
		drawingObj:Remove()
	end	
	table.clear(drawingObjsList)
end

local function isRenderObject(object): boolean
	local objPos = table.find(drawingObjsList, object)

	return (if objPos then (typeof(drawingObjsList[objPos]) == "table") else false)
end

local function getRenderProperty(object, property: string): any
	local objPos = table.find(drawingObjsList, object)
	if not objPos then
		return error(`argument #1 not a valid render object.`)
	end

	return object[property]
end

local function setRenderProperty(object, property: string, value: any)
	local objPos = table.find(drawingObjsList, object)
	if not objPos then
		return error(`argument #1 not a valid render object.`)
	end

	if typeof(object[property]) == "nil" then
		return error(`'{property}' is not a valid render property.`)
	end

	object[property] = value
end

DefineVEnv({"cleardrawcache"}, clearDrawCache)
DefineVEnv({"isrenderobj"}, isRenderObject)

DefineVEnv({"getrenderproperty"}, getRenderProperty)
DefineVEnv({"setrenderproperty"}, setRenderProperty)

DefineVEnv({"Drawing"}, drawing_lib)--
local bit = table.clone(bit32)

bit.badd = function(num_first, num_second)
	return num_first + num_second
end

bit.bsub = function(num_first, num_second)
	return num_first - num_second
end

bit.bdiv = function(num_first, num_second)
	return num_first / num_second
end

bit.bmul = function(num_first, num_second)
	return num_first * num_second
end

bit.tobit = function(num)
	num = num % (bit32.bxor(num, 32))
	if num > 0x80000000 then
		num = num - bit32.bxor(num, 32)
	end
	return num
end

bit.bswap = pcall(bit32.byteswap, 1) and bit32.byteswap -- Might be not enabled yet (remove this when it is)
	or function(num)
		local BYTE_SIZE = 8
		local MAX_BYTE_VALUE = 255

		num = num % bit32.bxor(2, 32)

		local a = bit32.band(num, MAX_BYTE_VALUE)
		num = bit32.rshift(num, BYTE_SIZE)

		local b = bit32.band(num, MAX_BYTE_VALUE)
		num = bit32.rshift(num, BYTE_SIZE)

		local c = bit32.band(num, MAX_BYTE_VALUE)
		num = bit32.rshift(num, BYTE_SIZE)

		local d = bit32.band(num, MAX_BYTE_VALUE)
		num = bit.tobit(bit32.lshift(bit32.lshift(bit32.lshift(a, BYTE_SIZE) + b, BYTE_SIZE) + c, BYTE_SIZE) + d)
		return num
	end

bit.extract = function(n, field, width)
	width = width or 1
	return bit32.band(bit32.rshift(n, field), 2 ^ width - 1)
end

bit.replace = function(n, v, field, width)
	width = width or 1
	local mask1 = 2 ^ width - 1
	v = bit32.band(v, mask1)
	local mask = bit32.bnot(bit32.lshift(mask1, field))
	return bit32.band(n, mask) + bit32.lshift(v, field)
end

bit.tohex = function(num, hex)
	if not hex then
		hex = 8
	end
	local up

	if hex <= 0 then
		if hex == 0 then
			return ""
		end
		up = true
		hex = -hex
	end

	num = num % (2 ^ 32)
	num = bit32.band(num, 16 ^ hex - 1)
	return ("%0" .. hex .. (up and "X" or "a")):format(num)
end

bit.ror = function(number, rotateBy)
	return bit.tobit(bit32.rrotate(bit32.bxor(number % 2, 32), rotateBy % 32))
end

bit.rol = function(number, rotateBy)
	return bit.tobit(bit32.lrotate(bit32.bxor(number % 2, 32), rotateBy % 32))
end

DefineVEnv({"bit"}, bit)
table.freeze(VisionEnv.bit)--
-- variables
local CHARACTER_SET = [[QWERTYUIOPASDFGHJKLZXCVBNMqwertyuiopasdfghjklzxcvbnm0123456789!#$%&()*+,./:;<=>?@[]^_`{|}~']]
-- local randomObj = Random.new()
local hashlib_flist = {
	["sha1"] = "sha1",

	["sha224"] = "sha224",
	["sha256"] = "sha256",
	["sha512-224"] = "sha512_224",
	["sha512-256"] = "sha512_256",
	["sha384"] = "sha384",
	["sha512"] = "sha512",

	["sha3-224"] = "sha3_224",
	["sha3-256"] = "sha3_256",
	["sha3-384"] = "sha3_384",
	["sha3-512"] = "sha3_512",
	["shake128"] = "shake128",
	["shake256"] = "shake256",

	["md5"] = "md5",
}

--[=[------------------------------------------------------------------------------------------------------------------------
-- HashLib by Egor Skriptunoff, boatbomber, and howmanysmall

Documentation here: https://devforum.roblox.com/t/open-source-hashlib/416732/1

--------------------------------------------------------------------------------------------------------------------------

Module was originally written by Egor Skriptunoff and distributed under an MIT license.
It can be found here: https://github.com/Egor-Skriptunoff/pure_lua_SHA/blob/master/sha2.lua

That version was around 3000 lines long, and supported Lua versions 5.1, 5.2, 5.3, and 5.4, and LuaJIT.
Although that is super cool, Roblox only uses Lua 5.1, so that was extreme overkill.

I, boatbomber, worked to port it to Roblox in a way that doesn't overcomplicate it with support of unreachable
cases. Then, howmanysmall did some final optimizations that really squeeze out all the performance possible.
It's gotten stupid fast, thanks to her!

After quite a bit of work and benchmarking, this is what we were left with.
Enjoy!

--------------------------------------------------------------------------------------------------------------------------

DESCRIPTION:
	This module contains functions to calculate SHA digest:
		MD5, SHA-1,
		SHA-224, SHA-256, SHA-512/224, SHA-512/256, SHA-384, SHA-512,
		SHA3-224, SHA3-256, SHA3-384, SHA3-512, SHAKE128, SHAKE256,
		HMAC
	Additionally, it has a few extra utility functions:
		hex_to_bin
		base64_to_bin
		bin_to_base64
	Written in pure Lua.
USAGE:
	Input data should be a string
	Result (SHA digest) is returned in hexadecimal representation as a string of lowercase hex digits.
	Simplest usage example:
		local HashLib = require(script.HashLib)
		local your_hash = HashLib.sha256("your string")
API:
		HashLib.md5
		HashLib.sha1
	SHA2 hash functions:
		HashLib.sha224
		HashLib.sha256
		HashLib.sha512_224
		HashLib.sha512_256
		HashLib.sha384
		HashLib.sha512
	SHA3 hash functions:
		HashLib.sha3_224
		HashLib.sha3_256
		HashLib.sha3_384
		HashLib.sha3_512
		HashLib.shake128
		HashLib.shake256
	Misc utilities:
		HashLib.hmac (Applicable to any hash function from this module except SHAKE*)
		HashLib.hex_to_bin
		HashLib.base64_to_bin
		HashLib.bin_to_base64

--]=]---------------------------------------------------------------------------

--!native
-- from: https://github.com/Reselim/Base64/blob/master/Base64.lua

local lookupValueToASCII = {} :: { [number]: number }
local lookupASCIIToValue = {} :: { [number]: number }

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

for index = 1, #alphabet do
	local value = index - 1
	local ascii = string.byte(alphabet, index)

	lookupValueToASCII[value] = ascii
	lookupASCIIToValue[ascii] = value
end

lookupASCIIToValue[string.byte("=")] = 0

local function buildStringFromCodes(values: { number }): string
	local chunks = {} :: { string }

	for index = 1, #values, 4096 do
		table.insert(chunks, string.char(
			unpack(values, index, math.min(index + 4096 - 1, #values))
			))
	end

	return table.concat(chunks, "")
end

local function encode(input: string): string
	local inputLength = #input
	local outputLength = math.ceil(inputLength / 3) * 4

	local remainder = inputLength % 3

	if remainder == 0 then
		-- Since chunks are only 3 characters wide and we're parsing 4 characters, we need
		-- to add an extra 0 on the end (which will be discarded anyway)
		input ..= string.char(0)
	end

	local output = table.create(outputLength, 0) :: { number }

	for chunkIndex = 0, (outputLength / 4) - (if remainder == 0 then 1 else 2) do
		local inputIndex = chunkIndex * 3 + 1
		local outputIndex = chunkIndex * 4 + 1

		-- Parse this as a single 32-bit integer instead of splitting into multiple and combining after
		local chunk = bit32.rshift(string.unpack(">J", input, inputIndex), 8)

		output[outputIndex] = lookupValueToASCII[bit32.rshift(chunk, 18)]
		output[outputIndex + 1] = lookupValueToASCII[bit32.band(bit32.rshift(chunk, 12), 0b111111)]
		output[outputIndex + 2] = lookupValueToASCII[bit32.band(bit32.rshift(chunk, 6), 0b111111)]
		output[outputIndex + 3] = lookupValueToASCII[bit32.band(chunk, 0b111111)]
	end

	if remainder == 1 then -- AA==
		local chunk = string.byte(input, inputLength)

		output[outputLength - 3] = lookupValueToASCII[bit32.rshift(chunk, 2)]
		output[outputLength - 2] = lookupValueToASCII[bit32.band(bit32.lshift(chunk, 4), 0b111111)]
		output[outputLength - 1] = 61
		output[outputLength] = 61
	elseif remainder == 2 then -- AAA=
		local chunk = string.unpack(">H", input, inputLength - 1)

		output[outputLength - 3] = lookupValueToASCII[bit32.rshift(chunk, 10)]
		output[outputLength - 2] = lookupValueToASCII[bit32.band(bit32.rshift(chunk, 4), 0b111111)]
		output[outputLength - 1] = lookupValueToASCII[bit32.band(bit32.lshift(chunk, 2), 0b111111)]
		output[outputLength] = 61
	end

	return buildStringFromCodes(output)
end

local function decode(input: string): string
	local inputLength = #input
	local outputLength = math.ceil(inputLength / 4) * 3

	local padding = 0
	if string.byte(input, inputLength - 1) == 61 then
		padding = 2
	elseif string.byte(input, inputLength) == 61 then
		padding = 1
	end

	local output = table.create(outputLength - padding, 0)

	for chunkIndex = 0, (outputLength / 3) - 1 do
		local inputIndex = chunkIndex * 4 + 1
		local outputIndex = chunkIndex * 3 + 1

		local value1, value2, value3, value4 = string.byte(input, inputIndex, inputIndex + 3)

		-- Combine all variables into one 24-bit variable to be split up
		local compound = bit32.bor(
			bit32.lshift(lookupASCIIToValue[value1], 18),
			bit32.lshift(lookupASCIIToValue[value2], 12),
			bit32.lshift(lookupASCIIToValue[value3], 6),
			lookupASCIIToValue[value4]
		)

		output[outputIndex] = bit32.rshift(compound, 16)
		output[outputIndex + 1] = bit32.band(bit32.rshift(compound, 8), 0b11111111)
		output[outputIndex + 2] = bit32.band(compound, 0b11111111)
	end

	if padding >= 1 then
		output[outputLength] = nil

		if padding >= 2 then
			output[outputLength - 1] = nil
		end
	end

	return buildStringFromCodes(output)
end

local Base64 = {
	encode = encode,
	decode = decode,
}

--------------------------------------------------------------------------------
-- LOCALIZATION FOR VM OPTIMIZATIONS
--------------------------------------------------------------------------------

local ipairs = ipairs

--------------------------------------------------------------------------------
-- 32-BIT BITWISE FUNCTIONS
--------------------------------------------------------------------------------
-- Only low 32 bits of function arguments matter, high bits are ignored
-- The result of all functions (except HEX) is an integer inside "correct range":
-- for "bit" library:    (-TWO_POW_31)..(TWO_POW_31-1)
-- for "bit32" library:        0..(TWO_POW_32-1)
local bit32_band = bit32.band -- 2 arguments
local bit32_bor = bit32.bor -- 2 arguments
local bit32_bxor = bit32.bxor -- 2..5 arguments
local bit32_lshift = bit32.lshift -- second argument is integer 0..31
local bit32_rshift = bit32.rshift -- second argument is integer 0..31
local bit32_lrotate = bit32.lrotate -- second argument is integer 0..31
local bit32_rrotate = bit32.rrotate -- second argument is integer 0..31

--------------------------------------------------------------------------------
-- CREATING OPTIMIZED INNER LOOP
--------------------------------------------------------------------------------
-- Arrays of SHA2 "magic numbers" (in "INT64" and "FFI" branches "*_lo" arrays contain 64-bit values)
local sha2_K_lo, sha2_K_hi, sha2_H_lo, sha2_H_hi, sha3_RC_lo, sha3_RC_hi = {}, {}, {}, {}, {}, {}
local sha2_H_ext256 = {
	[224] = {};
	[256] = sha2_H_hi;
}

local sha2_H_ext512_lo, sha2_H_ext512_hi = {
	[384] = {};
	[512] = sha2_H_lo;
}, {
	[384] = {};
	[512] = sha2_H_hi;
}

local md5_K, md5_sha1_H = {}, {0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0}
local md5_next_shift = {0, 0, 0, 0, 0, 0, 0, 0, 28, 25, 26, 27, 0, 0, 10, 9, 11, 12, 0, 15, 16, 17, 18, 0, 20, 22, 23, 21}
local HEX64, XOR64A5, lanes_index_base -- defined only for branches that internally use 64-bit integers: "INT64" and "FFI"
local common_W = {} -- temporary table shared between all calculations (to avoid creating new temporary table every time)
local K_lo_modulo, hi_factor, hi_factor_keccak = 4294967296, 0, 0

local TWO_POW_NEG_56 = 2 ^ -56
local TWO_POW_NEG_17 = 2 ^ -17

local TWO_POW_2 = 2 ^ 2
local TWO_POW_3 = 2 ^ 3
local TWO_POW_4 = 2 ^ 4
local TWO_POW_5 = 2 ^ 5
local TWO_POW_6 = 2 ^ 6
local TWO_POW_7 = 2 ^ 7
local TWO_POW_8 = 2 ^ 8
local TWO_POW_9 = 2 ^ 9
local TWO_POW_10 = 2 ^ 10
local TWO_POW_11 = 2 ^ 11
local TWO_POW_12 = 2 ^ 12
local TWO_POW_13 = 2 ^ 13
local TWO_POW_14 = 2 ^ 14
local TWO_POW_15 = 2 ^ 15
local TWO_POW_16 = 2 ^ 16
local TWO_POW_17 = 2 ^ 17
local TWO_POW_18 = 2 ^ 18
local TWO_POW_19 = 2 ^ 19
local TWO_POW_20 = 2 ^ 20
local TWO_POW_21 = 2 ^ 21
local TWO_POW_22 = 2 ^ 22
local TWO_POW_23 = 2 ^ 23
local TWO_POW_24 = 2 ^ 24
local TWO_POW_25 = 2 ^ 25
local TWO_POW_26 = 2 ^ 26
local TWO_POW_27 = 2 ^ 27
local TWO_POW_28 = 2 ^ 28
local TWO_POW_29 = 2 ^ 29
local TWO_POW_30 = 2 ^ 30
local TWO_POW_31 = 2 ^ 31
local TWO_POW_32 = 2 ^ 32
local TWO_POW_40 = 2 ^ 40

local TWO56_POW_7 = 256 ^ 7

-- Implementation for Lua 5.1/5.2 (with or without bitwise library available)
local function sha256_feed_64(H, str, offs, size)
	-- offs >= 0, size >= 0, size is multiple of 64
	local W, K = common_W, sha2_K_hi
	local h1, h2, h3, h4, h5, h6, h7, h8 = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
	for pos = offs, offs + size - 1, 64 do
		for j = 1, 16 do
			pos = pos + 4
			local a, b, c, d = string.byte(str, pos - 3, pos)
			W[j] = ((a * 256 + b) * 256 + c) * 256 + d
		end

		for j = 17, 64 do
			local a, b = W[j - 15], W[j - 2]
			W[j] = bit32_bxor(bit32_rrotate(a, 7), bit32_lrotate(a, 14), bit32_rshift(a, 3)) + bit32_bxor(bit32_lrotate(b, 15), bit32_lrotate(b, 13), bit32_rshift(b, 10)) + W[j - 7] + W[j - 16]
		end

		local a, b, c, d, e, f, g, h = h1, h2, h3, h4, h5, h6, h7, h8
		for j = 1, 64 do
			local z = bit32_bxor(bit32_rrotate(e, 6), bit32_rrotate(e, 11), bit32_lrotate(e, 7)) + bit32_band(e, f) + bit32_band(-1 - e, g) + h + K[j] + W[j]
			h = g
			g = f
			f = e
			e = z + d
			d = c
			c = b
			b = a
			a = z + bit32_band(d, c) + bit32_band(a, bit32_bxor(d, c)) + bit32_bxor(bit32_rrotate(a, 2), bit32_rrotate(a, 13), bit32_lrotate(a, 10))
		end

		h1, h2, h3, h4 = (a + h1) % 4294967296, (b + h2) % 4294967296, (c + h3) % 4294967296, (d + h4) % 4294967296
		h5, h6, h7, h8 = (e + h5) % 4294967296, (f + h6) % 4294967296, (g + h7) % 4294967296, (h + h8) % 4294967296
	end

	H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8] = h1, h2, h3, h4, h5, h6, h7, h8
end

local function sha512_feed_128(H_lo, H_hi, str, offs, size)
	-- offs >= 0, size >= 0, size is multiple of 128
	-- W1_hi, W1_lo, W2_hi, W2_lo, ...   Wk_hi = W[2*k-1], Wk_lo = W[2*k]
	local W, K_lo, K_hi = common_W, sha2_K_lo, sha2_K_hi
	local h1_lo, h2_lo, h3_lo, h4_lo, h5_lo, h6_lo, h7_lo, h8_lo = H_lo[1], H_lo[2], H_lo[3], H_lo[4], H_lo[5], H_lo[6], H_lo[7], H_lo[8]
	local h1_hi, h2_hi, h3_hi, h4_hi, h5_hi, h6_hi, h7_hi, h8_hi = H_hi[1], H_hi[2], H_hi[3], H_hi[4], H_hi[5], H_hi[6], H_hi[7], H_hi[8]
	for pos = offs, offs + size - 1, 128 do
		for j = 1, 16 * 2 do
			pos = pos + 4
			local a, b, c, d = string.byte(str, pos - 3, pos)
			W[j] = ((a * 256 + b) * 256 + c) * 256 + d
		end

		for jj = 34, 160, 2 do
			local a_lo, a_hi, b_lo, b_hi = W[jj - 30], W[jj - 31], W[jj - 4], W[jj - 5]
			local tmp1 = bit32_bxor(bit32_rshift(a_lo, 1) + bit32_lshift(a_hi, 31), bit32_rshift(a_lo, 8) + bit32_lshift(a_hi, 24), bit32_rshift(a_lo, 7) + bit32_lshift(a_hi, 25)) % 4294967296 +
				bit32_bxor(bit32_rshift(b_lo, 19) + bit32_lshift(b_hi, 13), bit32_lshift(b_lo, 3) + bit32_rshift(b_hi, 29), bit32_rshift(b_lo, 6) + bit32_lshift(b_hi, 26)) % 4294967296 +
				W[jj - 14] + W[jj - 32]

			local tmp2 = tmp1 % 4294967296
			W[jj - 1] = bit32_bxor(bit32_rshift(a_hi, 1) + bit32_lshift(a_lo, 31), bit32_rshift(a_hi, 8) + bit32_lshift(a_lo, 24), bit32_rshift(a_hi, 7)) +
				bit32_bxor(bit32_rshift(b_hi, 19) + bit32_lshift(b_lo, 13), bit32_lshift(b_hi, 3) + bit32_rshift(b_lo, 29), bit32_rshift(b_hi, 6)) +
				W[jj - 15] + W[jj - 33] + (tmp1 - tmp2) / 4294967296

			W[jj] = tmp2
		end

		local a_lo, b_lo, c_lo, d_lo, e_lo, f_lo, g_lo, h_lo = h1_lo, h2_lo, h3_lo, h4_lo, h5_lo, h6_lo, h7_lo, h8_lo
		local a_hi, b_hi, c_hi, d_hi, e_hi, f_hi, g_hi, h_hi = h1_hi, h2_hi, h3_hi, h4_hi, h5_hi, h6_hi, h7_hi, h8_hi
		for j = 1, 80 do
			local jj = 2 * j
			local tmp1 = bit32_bxor(bit32_rshift(e_lo, 14) + bit32_lshift(e_hi, 18), bit32_rshift(e_lo, 18) + bit32_lshift(e_hi, 14), bit32_lshift(e_lo, 23) + bit32_rshift(e_hi, 9)) % 4294967296 +
				(bit32_band(e_lo, f_lo) + bit32_band(-1 - e_lo, g_lo)) % 4294967296 +
				h_lo + K_lo[j] + W[jj]

			local z_lo = tmp1 % 4294967296
			local z_hi = bit32_bxor(bit32_rshift(e_hi, 14) + bit32_lshift(e_lo, 18), bit32_rshift(e_hi, 18) + bit32_lshift(e_lo, 14), bit32_lshift(e_hi, 23) + bit32_rshift(e_lo, 9)) +
				bit32_band(e_hi, f_hi) + bit32_band(-1 - e_hi, g_hi) +
				h_hi + K_hi[j] + W[jj - 1] +
				(tmp1 - z_lo) / 4294967296

			h_lo = g_lo
			h_hi = g_hi
			g_lo = f_lo
			g_hi = f_hi
			f_lo = e_lo
			f_hi = e_hi
			tmp1 = z_lo + d_lo
			e_lo = tmp1 % 4294967296
			e_hi = z_hi + d_hi + (tmp1 - e_lo) / 4294967296
			d_lo = c_lo
			d_hi = c_hi
			c_lo = b_lo
			c_hi = b_hi
			b_lo = a_lo
			b_hi = a_hi
			tmp1 = z_lo + (bit32_band(d_lo, c_lo) + bit32_band(b_lo, bit32_bxor(d_lo, c_lo))) % 4294967296 + bit32_bxor(bit32_rshift(b_lo, 28) + bit32_lshift(b_hi, 4), bit32_lshift(b_lo, 30) + bit32_rshift(b_hi, 2), bit32_lshift(b_lo, 25) + bit32_rshift(b_hi, 7)) % 4294967296
			a_lo = tmp1 % 4294967296
			a_hi = z_hi + (bit32_band(d_hi, c_hi) + bit32_band(b_hi, bit32_bxor(d_hi, c_hi))) + bit32_bxor(bit32_rshift(b_hi, 28) + bit32_lshift(b_lo, 4), bit32_lshift(b_hi, 30) + bit32_rshift(b_lo, 2), bit32_lshift(b_hi, 25) + bit32_rshift(b_lo, 7)) + (tmp1 - a_lo) / 4294967296
		end

		a_lo = h1_lo + a_lo
		h1_lo = a_lo % 4294967296
		h1_hi = (h1_hi + a_hi + (a_lo - h1_lo) / 4294967296) % 4294967296
		a_lo = h2_lo + b_lo
		h2_lo = a_lo % 4294967296
		h2_hi = (h2_hi + b_hi + (a_lo - h2_lo) / 4294967296) % 4294967296
		a_lo = h3_lo + c_lo
		h3_lo = a_lo % 4294967296
		h3_hi = (h3_hi + c_hi + (a_lo - h3_lo) / 4294967296) % 4294967296
		a_lo = h4_lo + d_lo
		h4_lo = a_lo % 4294967296
		h4_hi = (h4_hi + d_hi + (a_lo - h4_lo) / 4294967296) % 4294967296
		a_lo = h5_lo + e_lo
		h5_lo = a_lo % 4294967296
		h5_hi = (h5_hi + e_hi + (a_lo - h5_lo) / 4294967296) % 4294967296
		a_lo = h6_lo + f_lo
		h6_lo = a_lo % 4294967296
		h6_hi = (h6_hi + f_hi + (a_lo - h6_lo) / 4294967296) % 4294967296
		a_lo = h7_lo + g_lo
		h7_lo = a_lo % 4294967296
		h7_hi = (h7_hi + g_hi + (a_lo - h7_lo) / 4294967296) % 4294967296
		a_lo = h8_lo + h_lo
		h8_lo = a_lo % 4294967296
		h8_hi = (h8_hi + h_hi + (a_lo - h8_lo) / 4294967296) % 4294967296
	end

	H_lo[1], H_lo[2], H_lo[3], H_lo[4], H_lo[5], H_lo[6], H_lo[7], H_lo[8] = h1_lo, h2_lo, h3_lo, h4_lo, h5_lo, h6_lo, h7_lo, h8_lo
	H_hi[1], H_hi[2], H_hi[3], H_hi[4], H_hi[5], H_hi[6], H_hi[7], H_hi[8] = h1_hi, h2_hi, h3_hi, h4_hi, h5_hi, h6_hi, h7_hi, h8_hi
end

local function md5_feed_64(H, str, offs, size)
	-- offs >= 0, size >= 0, size is multiple of 64
	local W, K, md5_next_shift = common_W, md5_K, md5_next_shift
	local h1, h2, h3, h4 = H[1], H[2], H[3], H[4]
	for pos = offs, offs + size - 1, 64 do
		for j = 1, 16 do
			pos = pos + 4
			local a, b, c, d = string.byte(str, pos - 3, pos)
			W[j] = ((d * 256 + c) * 256 + b) * 256 + a
		end

		local a, b, c, d = h1, h2, h3, h4
		local s = 25
		for j = 1, 16 do
			local F = bit32_rrotate(bit32_band(b, c) + bit32_band(-1 - b, d) + a + K[j] + W[j], s) + b
			s = md5_next_shift[s]
			a = d
			d = c
			c = b
			b = F
		end

		s = 27
		for j = 17, 32 do
			local F = bit32_rrotate(bit32_band(d, b) + bit32_band(-1 - d, c) + a + K[j] + W[(5 * j - 4) % 16 + 1], s) + b
			s = md5_next_shift[s]
			a = d
			d = c
			c = b
			b = F
		end

		s = 28
		for j = 33, 48 do
			local F = bit32_rrotate(bit32_bxor(bit32_bxor(b, c), d) + a + K[j] + W[(3 * j + 2) % 16 + 1], s) + b
			s = md5_next_shift[s]
			a = d
			d = c
			c = b
			b = F
		end

		s = 26
		for j = 49, 64 do
			local F = bit32_rrotate(bit32_bxor(c, bit32_bor(b, -1 - d)) + a + K[j] + W[(j * 7 - 7) % 16 + 1], s) + b
			s = md5_next_shift[s]
			a = d
			d = c
			c = b
			b = F
		end

		h1 = (a + h1) % 4294967296
		h2 = (b + h2) % 4294967296
		h3 = (c + h3) % 4294967296
		h4 = (d + h4) % 4294967296
	end

	H[1], H[2], H[3], H[4] = h1, h2, h3, h4
end

local function sha1_feed_64(H, str, offs, size)
	-- offs >= 0, size >= 0, size is multiple of 64
	local W = common_W
	local h1, h2, h3, h4, h5 = H[1], H[2], H[3], H[4], H[5]
	for pos = offs, offs + size - 1, 64 do
		for j = 1, 16 do
			pos = pos + 4
			local a, b, c, d = string.byte(str, pos - 3, pos)
			W[j] = ((a * 256 + b) * 256 + c) * 256 + d
		end

		for j = 17, 80 do
			W[j] = bit32_lrotate(bit32_bxor(W[j - 3], W[j - 8], W[j - 14], W[j - 16]), 1)
		end

		local a, b, c, d, e = h1, h2, h3, h4, h5
		for j = 1, 20 do
			local z = bit32_lrotate(a, 5) + bit32_band(b, c) + bit32_band(-1 - b, d) + 0x5A827999 + W[j] + e -- constant = math.floor(TWO_POW_30 * sqrt(2))
			e = d
			d = c
			c = bit32_rrotate(b, 2)
			b = a
			a = z
		end

		for j = 21, 40 do
			local z = bit32_lrotate(a, 5) + bit32_bxor(b, c, d) + 0x6ED9EBA1 + W[j] + e -- TWO_POW_30 * sqrt(3)
			e = d
			d = c
			c = bit32_rrotate(b, 2)
			b = a
			a = z
		end

		for j = 41, 60 do
			local z = bit32_lrotate(a, 5) + bit32_band(d, c) + bit32_band(b, bit32_bxor(d, c)) + 0x8F1BBCDC + W[j] + e -- TWO_POW_30 * sqrt(5)
			e = d
			d = c
			c = bit32_rrotate(b, 2)
			b = a
			a = z
		end

		for j = 61, 80 do
			local z = bit32_lrotate(a, 5) + bit32_bxor(b, c, d) + 0xCA62C1D6 + W[j] + e -- TWO_POW_30 * sqrt(10)
			e = d
			d = c
			c = bit32_rrotate(b, 2)
			b = a
			a = z
		end

		h1 = (a + h1) % 4294967296
		h2 = (b + h2) % 4294967296
		h3 = (c + h3) % 4294967296
		h4 = (d + h4) % 4294967296
		h5 = (e + h5) % 4294967296
	end

	H[1], H[2], H[3], H[4], H[5] = h1, h2, h3, h4, h5
end

local function keccak_feed(lanes_lo, lanes_hi, str, offs, size, block_size_in_bytes)
	-- This is an example of a Lua function having 79 local variables :-)
	-- offs >= 0, size >= 0, size is multiple of block_size_in_bytes, block_size_in_bytes is positive multiple of 8
	local RC_lo, RC_hi = sha3_RC_lo, sha3_RC_hi
	local qwords_qty = block_size_in_bytes / 8
	for pos = offs, offs + size - 1, block_size_in_bytes do
		for j = 1, qwords_qty do
			local a, b, c, d = string.byte(str, pos + 1, pos + 4)
			lanes_lo[j] = bit32_bxor(lanes_lo[j], ((d * 256 + c) * 256 + b) * 256 + a)
			pos = pos + 8
			a, b, c, d = string.byte(str, pos - 3, pos)
			lanes_hi[j] = bit32_bxor(lanes_hi[j], ((d * 256 + c) * 256 + b) * 256 + a)
		end

		local L01_lo, L01_hi, L02_lo, L02_hi, L03_lo, L03_hi, L04_lo, L04_hi, L05_lo, L05_hi, L06_lo, L06_hi, L07_lo, L07_hi, L08_lo, L08_hi, L09_lo, L09_hi, L10_lo, L10_hi, L11_lo, L11_hi, L12_lo, L12_hi, L13_lo, L13_hi, L14_lo, L14_hi, L15_lo, L15_hi, L16_lo, L16_hi, L17_lo, L17_hi, L18_lo, L18_hi, L19_lo, L19_hi, L20_lo, L20_hi, L21_lo, L21_hi, L22_lo, L22_hi, L23_lo, L23_hi, L24_lo, L24_hi, L25_lo, L25_hi = lanes_lo[1], lanes_hi[1], lanes_lo[2], lanes_hi[2], lanes_lo[3], lanes_hi[3], lanes_lo[4], lanes_hi[4], lanes_lo[5], lanes_hi[5], lanes_lo[6], lanes_hi[6], lanes_lo[7], lanes_hi[7], lanes_lo[8], lanes_hi[8], lanes_lo[9], lanes_hi[9], lanes_lo[10], lanes_hi[10], lanes_lo[11], lanes_hi[11], lanes_lo[12], lanes_hi[12], lanes_lo[13], lanes_hi[13], lanes_lo[14], lanes_hi[14], lanes_lo[15], lanes_hi[15], lanes_lo[16], lanes_hi[16], lanes_lo[17], lanes_hi[17], lanes_lo[18], lanes_hi[18], lanes_lo[19], lanes_hi[19], lanes_lo[20], lanes_hi[20], lanes_lo[21], lanes_hi[21], lanes_lo[22], lanes_hi[22], lanes_lo[23], lanes_hi[23], lanes_lo[24], lanes_hi[24], lanes_lo[25], lanes_hi[25]

		for round_idx = 1, 24 do
			local C1_lo = bit32_bxor(L01_lo, L06_lo, L11_lo, L16_lo, L21_lo)
			local C1_hi = bit32_bxor(L01_hi, L06_hi, L11_hi, L16_hi, L21_hi)
			local C2_lo = bit32_bxor(L02_lo, L07_lo, L12_lo, L17_lo, L22_lo)
			local C2_hi = bit32_bxor(L02_hi, L07_hi, L12_hi, L17_hi, L22_hi)
			local C3_lo = bit32_bxor(L03_lo, L08_lo, L13_lo, L18_lo, L23_lo)
			local C3_hi = bit32_bxor(L03_hi, L08_hi, L13_hi, L18_hi, L23_hi)
			local C4_lo = bit32_bxor(L04_lo, L09_lo, L14_lo, L19_lo, L24_lo)
			local C4_hi = bit32_bxor(L04_hi, L09_hi, L14_hi, L19_hi, L24_hi)
			local C5_lo = bit32_bxor(L05_lo, L10_lo, L15_lo, L20_lo, L25_lo)
			local C5_hi = bit32_bxor(L05_hi, L10_hi, L15_hi, L20_hi, L25_hi)

			local D_lo = bit32_bxor(C1_lo, C3_lo * 2 + (C3_hi % TWO_POW_32 - C3_hi % TWO_POW_31) / TWO_POW_31)
			local D_hi = bit32_bxor(C1_hi, C3_hi * 2 + (C3_lo % TWO_POW_32 - C3_lo % TWO_POW_31) / TWO_POW_31)

			local T0_lo = bit32_bxor(D_lo, L02_lo)
			local T0_hi = bit32_bxor(D_hi, L02_hi)
			local T1_lo = bit32_bxor(D_lo, L07_lo)
			local T1_hi = bit32_bxor(D_hi, L07_hi)
			local T2_lo = bit32_bxor(D_lo, L12_lo)
			local T2_hi = bit32_bxor(D_hi, L12_hi)
			local T3_lo = bit32_bxor(D_lo, L17_lo)
			local T3_hi = bit32_bxor(D_hi, L17_hi)
			local T4_lo = bit32_bxor(D_lo, L22_lo)
			local T4_hi = bit32_bxor(D_hi, L22_hi)

			L02_lo = (T1_lo % TWO_POW_32 - T1_lo % TWO_POW_20) / TWO_POW_20 + T1_hi * TWO_POW_12
			L02_hi = (T1_hi % TWO_POW_32 - T1_hi % TWO_POW_20) / TWO_POW_20 + T1_lo * TWO_POW_12
			L07_lo = (T3_lo % TWO_POW_32 - T3_lo % TWO_POW_19) / TWO_POW_19 + T3_hi * TWO_POW_13
			L07_hi = (T3_hi % TWO_POW_32 - T3_hi % TWO_POW_19) / TWO_POW_19 + T3_lo * TWO_POW_13
			L12_lo = T0_lo * 2 + (T0_hi % TWO_POW_32 - T0_hi % TWO_POW_31) / TWO_POW_31
			L12_hi = T0_hi * 2 + (T0_lo % TWO_POW_32 - T0_lo % TWO_POW_31) / TWO_POW_31
			L17_lo = T2_lo * TWO_POW_10 + (T2_hi % TWO_POW_32 - T2_hi % TWO_POW_22) / TWO_POW_22
			L17_hi = T2_hi * TWO_POW_10 + (T2_lo % TWO_POW_32 - T2_lo % TWO_POW_22) / TWO_POW_22
			L22_lo = T4_lo * TWO_POW_2 + (T4_hi % TWO_POW_32 - T4_hi % TWO_POW_30) / TWO_POW_30
			L22_hi = T4_hi * TWO_POW_2 + (T4_lo % TWO_POW_32 - T4_lo % TWO_POW_30) / TWO_POW_30

			D_lo = bit32_bxor(C2_lo, C4_lo * 2 + (C4_hi % TWO_POW_32 - C4_hi % TWO_POW_31) / TWO_POW_31)
			D_hi = bit32_bxor(C2_hi, C4_hi * 2 + (C4_lo % TWO_POW_32 - C4_lo % TWO_POW_31) / TWO_POW_31)

			T0_lo = bit32_bxor(D_lo, L03_lo)
			T0_hi = bit32_bxor(D_hi, L03_hi)
			T1_lo = bit32_bxor(D_lo, L08_lo)
			T1_hi = bit32_bxor(D_hi, L08_hi)
			T2_lo = bit32_bxor(D_lo, L13_lo)
			T2_hi = bit32_bxor(D_hi, L13_hi)
			T3_lo = bit32_bxor(D_lo, L18_lo)
			T3_hi = bit32_bxor(D_hi, L18_hi)
			T4_lo = bit32_bxor(D_lo, L23_lo)
			T4_hi = bit32_bxor(D_hi, L23_hi)

			L03_lo = (T2_lo % TWO_POW_32 - T2_lo % TWO_POW_21) / TWO_POW_21 + T2_hi * TWO_POW_11
			L03_hi = (T2_hi % TWO_POW_32 - T2_hi % TWO_POW_21) / TWO_POW_21 + T2_lo * TWO_POW_11
			L08_lo = (T4_lo % TWO_POW_32 - T4_lo % TWO_POW_3) / TWO_POW_3 + T4_hi * TWO_POW_29 % TWO_POW_32
			L08_hi = (T4_hi % TWO_POW_32 - T4_hi % TWO_POW_3) / TWO_POW_3 + T4_lo * TWO_POW_29 % TWO_POW_32
			L13_lo = T1_lo * TWO_POW_6 + (T1_hi % TWO_POW_32 - T1_hi % TWO_POW_26) / TWO_POW_26
			L13_hi = T1_hi * TWO_POW_6 + (T1_lo % TWO_POW_32 - T1_lo % TWO_POW_26) / TWO_POW_26
			L18_lo = T3_lo * TWO_POW_15 + (T3_hi % TWO_POW_32 - T3_hi % TWO_POW_17) / TWO_POW_17
			L18_hi = T3_hi * TWO_POW_15 + (T3_lo % TWO_POW_32 - T3_lo % TWO_POW_17) / TWO_POW_17
			L23_lo = (T0_lo % TWO_POW_32 - T0_lo % TWO_POW_2) / TWO_POW_2 + T0_hi * TWO_POW_30 % TWO_POW_32
			L23_hi = (T0_hi % TWO_POW_32 - T0_hi % TWO_POW_2) / TWO_POW_2 + T0_lo * TWO_POW_30 % TWO_POW_32

			D_lo = bit32_bxor(C3_lo, C5_lo * 2 + (C5_hi % TWO_POW_32 - C5_hi % TWO_POW_31) / TWO_POW_31)
			D_hi = bit32_bxor(C3_hi, C5_hi * 2 + (C5_lo % TWO_POW_32 - C5_lo % TWO_POW_31) / TWO_POW_31)

			T0_lo = bit32_bxor(D_lo, L04_lo)
			T0_hi = bit32_bxor(D_hi, L04_hi)
			T1_lo = bit32_bxor(D_lo, L09_lo)
			T1_hi = bit32_bxor(D_hi, L09_hi)
			T2_lo = bit32_bxor(D_lo, L14_lo)
			T2_hi = bit32_bxor(D_hi, L14_hi)
			T3_lo = bit32_bxor(D_lo, L19_lo)
			T3_hi = bit32_bxor(D_hi, L19_hi)
			T4_lo = bit32_bxor(D_lo, L24_lo)
			T4_hi = bit32_bxor(D_hi, L24_hi)

			L04_lo = T3_lo * TWO_POW_21 % TWO_POW_32 + (T3_hi % TWO_POW_32 - T3_hi % TWO_POW_11) / TWO_POW_11
			L04_hi = T3_hi * TWO_POW_21 % TWO_POW_32 + (T3_lo % TWO_POW_32 - T3_lo % TWO_POW_11) / TWO_POW_11
			L09_lo = T0_lo * TWO_POW_28 % TWO_POW_32 + (T0_hi % TWO_POW_32 - T0_hi % TWO_POW_4) / TWO_POW_4
			L09_hi = T0_hi * TWO_POW_28 % TWO_POW_32 + (T0_lo % TWO_POW_32 - T0_lo % TWO_POW_4) / TWO_POW_4
			L14_lo = T2_lo * TWO_POW_25 % TWO_POW_32 + (T2_hi % TWO_POW_32 - T2_hi % TWO_POW_7) / TWO_POW_7
			L14_hi = T2_hi * TWO_POW_25 % TWO_POW_32 + (T2_lo % TWO_POW_32 - T2_lo % TWO_POW_7) / TWO_POW_7
			L19_lo = (T4_lo % TWO_POW_32 - T4_lo % TWO_POW_8) / TWO_POW_8 + T4_hi * TWO_POW_24 % TWO_POW_32
			L19_hi = (T4_hi % TWO_POW_32 - T4_hi % TWO_POW_8) / TWO_POW_8 + T4_lo * TWO_POW_24 % TWO_POW_32
			L24_lo = (T1_lo % TWO_POW_32 - T1_lo % TWO_POW_9) / TWO_POW_9 + T1_hi * TWO_POW_23 % TWO_POW_32
			L24_hi = (T1_hi % TWO_POW_32 - T1_hi % TWO_POW_9) / TWO_POW_9 + T1_lo * TWO_POW_23 % TWO_POW_32

			D_lo = bit32_bxor(C4_lo, C1_lo * 2 + (C1_hi % TWO_POW_32 - C1_hi % TWO_POW_31) / TWO_POW_31)
			D_hi = bit32_bxor(C4_hi, C1_hi * 2 + (C1_lo % TWO_POW_32 - C1_lo % TWO_POW_31) / TWO_POW_31)

			T0_lo = bit32_bxor(D_lo, L05_lo)
			T0_hi = bit32_bxor(D_hi, L05_hi)
			T1_lo = bit32_bxor(D_lo, L10_lo)
			T1_hi = bit32_bxor(D_hi, L10_hi)
			T2_lo = bit32_bxor(D_lo, L15_lo)
			T2_hi = bit32_bxor(D_hi, L15_hi)
			T3_lo = bit32_bxor(D_lo, L20_lo)
			T3_hi = bit32_bxor(D_hi, L20_hi)
			T4_lo = bit32_bxor(D_lo, L25_lo)
			T4_hi = bit32_bxor(D_hi, L25_hi)

			L05_lo = T4_lo * TWO_POW_14 + (T4_hi % TWO_POW_32 - T4_hi % TWO_POW_18) / TWO_POW_18
			L05_hi = T4_hi * TWO_POW_14 + (T4_lo % TWO_POW_32 - T4_lo % TWO_POW_18) / TWO_POW_18
			L10_lo = T1_lo * TWO_POW_20 % TWO_POW_32 + (T1_hi % TWO_POW_32 - T1_hi % TWO_POW_12) / TWO_POW_12
			L10_hi = T1_hi * TWO_POW_20 % TWO_POW_32 + (T1_lo % TWO_POW_32 - T1_lo % TWO_POW_12) / TWO_POW_12
			L15_lo = T3_lo * TWO_POW_8 + (T3_hi % TWO_POW_32 - T3_hi % TWO_POW_24) / TWO_POW_24
			L15_hi = T3_hi * TWO_POW_8 + (T3_lo % TWO_POW_32 - T3_lo % TWO_POW_24) / TWO_POW_24
			L20_lo = T0_lo * TWO_POW_27 % TWO_POW_32 + (T0_hi % TWO_POW_32 - T0_hi % TWO_POW_5) / TWO_POW_5
			L20_hi = T0_hi * TWO_POW_27 % TWO_POW_32 + (T0_lo % TWO_POW_32 - T0_lo % TWO_POW_5) / TWO_POW_5
			L25_lo = (T2_lo % TWO_POW_32 - T2_lo % TWO_POW_25) / TWO_POW_25 + T2_hi * TWO_POW_7
			L25_hi = (T2_hi % TWO_POW_32 - T2_hi % TWO_POW_25) / TWO_POW_25 + T2_lo * TWO_POW_7

			D_lo = bit32_bxor(C5_lo, C2_lo * 2 + (C2_hi % TWO_POW_32 - C2_hi % TWO_POW_31) / TWO_POW_31)
			D_hi = bit32_bxor(C5_hi, C2_hi * 2 + (C2_lo % TWO_POW_32 - C2_lo % TWO_POW_31) / TWO_POW_31)

			T1_lo = bit32_bxor(D_lo, L06_lo)
			T1_hi = bit32_bxor(D_hi, L06_hi)
			T2_lo = bit32_bxor(D_lo, L11_lo)
			T2_hi = bit32_bxor(D_hi, L11_hi)
			T3_lo = bit32_bxor(D_lo, L16_lo)
			T3_hi = bit32_bxor(D_hi, L16_hi)
			T4_lo = bit32_bxor(D_lo, L21_lo)
			T4_hi = bit32_bxor(D_hi, L21_hi)

			L06_lo = T2_lo * TWO_POW_3 + (T2_hi % TWO_POW_32 - T2_hi % TWO_POW_29) / TWO_POW_29
			L06_hi = T2_hi * TWO_POW_3 + (T2_lo % TWO_POW_32 - T2_lo % TWO_POW_29) / TWO_POW_29
			L11_lo = T4_lo * TWO_POW_18 + (T4_hi % TWO_POW_32 - T4_hi % TWO_POW_14) / TWO_POW_14
			L11_hi = T4_hi * TWO_POW_18 + (T4_lo % TWO_POW_32 - T4_lo % TWO_POW_14) / TWO_POW_14
			L16_lo = (T1_lo % TWO_POW_32 - T1_lo % TWO_POW_28) / TWO_POW_28 + T1_hi * TWO_POW_4
			L16_hi = (T1_hi % TWO_POW_32 - T1_hi % TWO_POW_28) / TWO_POW_28 + T1_lo * TWO_POW_4
			L21_lo = (T3_lo % TWO_POW_32 - T3_lo % TWO_POW_23) / TWO_POW_23 + T3_hi * TWO_POW_9
			L21_hi = (T3_hi % TWO_POW_32 - T3_hi % TWO_POW_23) / TWO_POW_23 + T3_lo * TWO_POW_9

			L01_lo = bit32_bxor(D_lo, L01_lo)
			L01_hi = bit32_bxor(D_hi, L01_hi)
			L01_lo, L02_lo, L03_lo, L04_lo, L05_lo = bit32_bxor(L01_lo, bit32_band(-1 - L02_lo, L03_lo)), bit32_bxor(L02_lo, bit32_band(-1 - L03_lo, L04_lo)), bit32_bxor(L03_lo, bit32_band(-1 - L04_lo, L05_lo)), bit32_bxor(L04_lo, bit32_band(-1 - L05_lo, L01_lo)), bit32_bxor(L05_lo, bit32_band(-1 - L01_lo, L02_lo))
			L01_hi, L02_hi, L03_hi, L04_hi, L05_hi = bit32_bxor(L01_hi, bit32_band(-1 - L02_hi, L03_hi)), bit32_bxor(L02_hi, bit32_band(-1 - L03_hi, L04_hi)), bit32_bxor(L03_hi, bit32_band(-1 - L04_hi, L05_hi)), bit32_bxor(L04_hi, bit32_band(-1 - L05_hi, L01_hi)), bit32_bxor(L05_hi, bit32_band(-1 - L01_hi, L02_hi))
			L06_lo, L07_lo, L08_lo, L09_lo, L10_lo = bit32_bxor(L09_lo, bit32_band(-1 - L10_lo, L06_lo)), bit32_bxor(L10_lo, bit32_band(-1 - L06_lo, L07_lo)), bit32_bxor(L06_lo, bit32_band(-1 - L07_lo, L08_lo)), bit32_bxor(L07_lo, bit32_band(-1 - L08_lo, L09_lo)), bit32_bxor(L08_lo, bit32_band(-1 - L09_lo, L10_lo))
			L06_hi, L07_hi, L08_hi, L09_hi, L10_hi = bit32_bxor(L09_hi, bit32_band(-1 - L10_hi, L06_hi)), bit32_bxor(L10_hi, bit32_band(-1 - L06_hi, L07_hi)), bit32_bxor(L06_hi, bit32_band(-1 - L07_hi, L08_hi)), bit32_bxor(L07_hi, bit32_band(-1 - L08_hi, L09_hi)), bit32_bxor(L08_hi, bit32_band(-1 - L09_hi, L10_hi))
			L11_lo, L12_lo, L13_lo, L14_lo, L15_lo = bit32_bxor(L12_lo, bit32_band(-1 - L13_lo, L14_lo)), bit32_bxor(L13_lo, bit32_band(-1 - L14_lo, L15_lo)), bit32_bxor(L14_lo, bit32_band(-1 - L15_lo, L11_lo)), bit32_bxor(L15_lo, bit32_band(-1 - L11_lo, L12_lo)), bit32_bxor(L11_lo, bit32_band(-1 - L12_lo, L13_lo))
			L11_hi, L12_hi, L13_hi, L14_hi, L15_hi = bit32_bxor(L12_hi, bit32_band(-1 - L13_hi, L14_hi)), bit32_bxor(L13_hi, bit32_band(-1 - L14_hi, L15_hi)), bit32_bxor(L14_hi, bit32_band(-1 - L15_hi, L11_hi)), bit32_bxor(L15_hi, bit32_band(-1 - L11_hi, L12_hi)), bit32_bxor(L11_hi, bit32_band(-1 - L12_hi, L13_hi))
			L16_lo, L17_lo, L18_lo, L19_lo, L20_lo = bit32_bxor(L20_lo, bit32_band(-1 - L16_lo, L17_lo)), bit32_bxor(L16_lo, bit32_band(-1 - L17_lo, L18_lo)), bit32_bxor(L17_lo, bit32_band(-1 - L18_lo, L19_lo)), bit32_bxor(L18_lo, bit32_band(-1 - L19_lo, L20_lo)), bit32_bxor(L19_lo, bit32_band(-1 - L20_lo, L16_lo))
			L16_hi, L17_hi, L18_hi, L19_hi, L20_hi = bit32_bxor(L20_hi, bit32_band(-1 - L16_hi, L17_hi)), bit32_bxor(L16_hi, bit32_band(-1 - L17_hi, L18_hi)), bit32_bxor(L17_hi, bit32_band(-1 - L18_hi, L19_hi)), bit32_bxor(L18_hi, bit32_band(-1 - L19_hi, L20_hi)), bit32_bxor(L19_hi, bit32_band(-1 - L20_hi, L16_hi))
			L21_lo, L22_lo, L23_lo, L24_lo, L25_lo = bit32_bxor(L23_lo, bit32_band(-1 - L24_lo, L25_lo)), bit32_bxor(L24_lo, bit32_band(-1 - L25_lo, L21_lo)), bit32_bxor(L25_lo, bit32_band(-1 - L21_lo, L22_lo)), bit32_bxor(L21_lo, bit32_band(-1 - L22_lo, L23_lo)), bit32_bxor(L22_lo, bit32_band(-1 - L23_lo, L24_lo))
			L21_hi, L22_hi, L23_hi, L24_hi, L25_hi = bit32_bxor(L23_hi, bit32_band(-1 - L24_hi, L25_hi)), bit32_bxor(L24_hi, bit32_band(-1 - L25_hi, L21_hi)), bit32_bxor(L25_hi, bit32_band(-1 - L21_hi, L22_hi)), bit32_bxor(L21_hi, bit32_band(-1 - L22_hi, L23_hi)), bit32_bxor(L22_hi, bit32_band(-1 - L23_hi, L24_hi))
			L01_lo = bit32_bxor(L01_lo, RC_lo[round_idx])
			L01_hi = L01_hi + RC_hi[round_idx] -- RC_hi[] is either 0 or 0x80000000, so we could use fast addition instead of slow XOR
		end

		lanes_lo[1] = L01_lo
		lanes_hi[1] = L01_hi
		lanes_lo[2] = L02_lo
		lanes_hi[2] = L02_hi
		lanes_lo[3] = L03_lo
		lanes_hi[3] = L03_hi
		lanes_lo[4] = L04_lo
		lanes_hi[4] = L04_hi
		lanes_lo[5] = L05_lo
		lanes_hi[5] = L05_hi
		lanes_lo[6] = L06_lo
		lanes_hi[6] = L06_hi
		lanes_lo[7] = L07_lo
		lanes_hi[7] = L07_hi
		lanes_lo[8] = L08_lo
		lanes_hi[8] = L08_hi
		lanes_lo[9] = L09_lo
		lanes_hi[9] = L09_hi
		lanes_lo[10] = L10_lo
		lanes_hi[10] = L10_hi
		lanes_lo[11] = L11_lo
		lanes_hi[11] = L11_hi
		lanes_lo[12] = L12_lo
		lanes_hi[12] = L12_hi
		lanes_lo[13] = L13_lo
		lanes_hi[13] = L13_hi
		lanes_lo[14] = L14_lo
		lanes_hi[14] = L14_hi
		lanes_lo[15] = L15_lo
		lanes_hi[15] = L15_hi
		lanes_lo[16] = L16_lo
		lanes_hi[16] = L16_hi
		lanes_lo[17] = L17_lo
		lanes_hi[17] = L17_hi
		lanes_lo[18] = L18_lo
		lanes_hi[18] = L18_hi
		lanes_lo[19] = L19_lo
		lanes_hi[19] = L19_hi
		lanes_lo[20] = L20_lo
		lanes_hi[20] = L20_hi
		lanes_lo[21] = L21_lo
		lanes_hi[21] = L21_hi
		lanes_lo[22] = L22_lo
		lanes_hi[22] = L22_hi
		lanes_lo[23] = L23_lo
		lanes_hi[23] = L23_hi
		lanes_lo[24] = L24_lo
		lanes_hi[24] = L24_hi
		lanes_lo[25] = L25_lo
		lanes_hi[25] = L25_hi
	end
end

--------------------------------------------------------------------------------
-- MAGIC NUMBERS CALCULATOR
--------------------------------------------------------------------------------
-- Q:
--    Is 53-bit "double" math enough to calculate square roots and cube roots of primes with 64 correct bits after decimal point?
-- A:
--    Yes, 53-bit "double" arithmetic is enough.
--    We could obtain first 40 bits by direct calculation of p^(1/3) and next 40 bits by one step of Newton's method.
do
	local function mul(src1, src2, factor, result_length)
		-- src1, src2 - long integers (arrays of digits in base TWO_POW_24)
		-- factor - small integer
		-- returns long integer result (src1 * src2 * factor) and its floating point approximation
		local result, carry, value, weight = table.create(result_length), 0, 0, 1
		for j = 1, result_length do
			for k = math.max(1, j + 1 - #src2), math.min(j, #src1) do
				carry = carry + factor * src1[k] * src2[j + 1 - k] -- "int32" is not enough for multiplication result, that's why "factor" must be of type "double"
			end

			local digit = carry % TWO_POW_24
			result[j] = math.floor(digit)
			carry = (carry - digit) / TWO_POW_24
			value = value + digit * weight
			weight = weight * TWO_POW_24
		end

		return result, value
	end

	local idx, step, p, one, sqrt_hi, sqrt_lo = 0, {4, 1, 2, -2, 2}, 4, {1}, sha2_H_hi, sha2_H_lo
	repeat
		p = p + step[p % 6]
		local d = 1
		repeat
			d = d + step[d % 6]
			if d * d > p then
				-- next prime number is found
				local root = p ^ (1 / 3)
				local R = root * TWO_POW_40
				R = mul(table.create(1, math.floor(R)), one, 1, 2)
				local _, delta = mul(R, mul(R, R, 1, 4), -1, 4)
				local hi = R[2] % 65536 * 65536 + math.floor(R[1] / 256)
				local lo = R[1] % 256 * 16777216 + math.floor(delta * (TWO_POW_NEG_56 / 3) * root / p)

				if idx < 16 then
					root = math.sqrt(p)
					R = root * TWO_POW_40
					R = mul(table.create(1, math.floor(R)), one, 1, 2)
					_, delta = mul(R, R, -1, 2)
					local hi = R[2] % 65536 * 65536 + math.floor(R[1] / 256)
					local lo = R[1] % 256 * 16777216 + math.floor(delta * TWO_POW_NEG_17 / root)
					local idx = idx % 8 + 1
					sha2_H_ext256[224][idx] = lo
					sqrt_hi[idx], sqrt_lo[idx] = hi, lo + hi * hi_factor
					if idx > 7 then
						sqrt_hi, sqrt_lo = sha2_H_ext512_hi[384], sha2_H_ext512_lo[384]
					end
				end

				idx = idx + 1
				sha2_K_hi[idx], sha2_K_lo[idx] = hi, lo % K_lo_modulo + hi * hi_factor
				break
			end
		until p % d == 0
	until idx > 79
end

-- Calculating IVs for SHA512/224 and SHA512/256
for width = 224, 256, 32 do
	local H_lo, H_hi = {}, nil
	if XOR64A5 then
		for j = 1, 8 do
			H_lo[j] = XOR64A5(sha2_H_lo[j])
		end
	else
		H_hi = {}
		for j = 1, 8 do
			H_lo[j] = bit32_bxor(sha2_H_lo[j], 0xA5A5A5A5) % 4294967296
			H_hi[j] = bit32_bxor(sha2_H_hi[j], 0xA5A5A5A5) % 4294967296
		end
	end

	sha512_feed_128(H_lo, H_hi, "SHA-512/" .. tostring(width) .. "\128" .. string.rep("\0", 115) .. "\88", 0, 128)
	sha2_H_ext512_lo[width] = H_lo
	sha2_H_ext512_hi[width] = H_hi
end

-- Constants for MD5
do
	for idx = 1, 64 do
		-- we can't use formula math.floor(abs(sin(idx))*TWO_POW_32) because its result may be beyond integer range on Lua built with 32-bit integers
		local hi, lo = math.modf(math.abs(math.sin(idx)) * TWO_POW_16)
		md5_K[idx] = hi * 65536 + math.floor(lo * TWO_POW_16)
	end
end

-- Constants for SHA3
do
	local sh_reg = 29
	local function next_bit()
		local r = sh_reg % 2
		sh_reg = bit32_bxor((sh_reg - r) / 2, 142 * r)
		return r
	end

	for idx = 1, 24 do
		local lo, m = 0, nil
		for _ = 1, 6 do
			m = m and m * m * 2 or 1
			lo = lo + next_bit() * m
		end

		local hi = next_bit() * m
		sha3_RC_hi[idx], sha3_RC_lo[idx] = hi, lo + hi * hi_factor_keccak
	end
end

--------------------------------------------------------------------------------
-- MAIN FUNCTIONS
--------------------------------------------------------------------------------
local function sha256ext(width, message)
	-- Create an instance (private objects for current calculation)
	local Array256 = sha2_H_ext256[width] -- # == 8
	local length, tail = 0, ""
	local H = table.create(8)
	H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8] = Array256[1], Array256[2], Array256[3], Array256[4], Array256[5], Array256[6], Array256[7], Array256[8]

	local function partial(message_part)
		if message_part then
			local partLength = #message_part
			if tail then
				length = length + partLength
				local offs = 0
				local tailLength = #tail
				if tail ~= "" and tailLength + partLength >= 64 then
					offs = 64 - tailLength
					sha256_feed_64(H, tail .. string.sub(message_part, 1, offs), 0, 64)
					tail = ""
				end

				local size = partLength - offs
				local size_tail = size % 64
				sha256_feed_64(H, message_part, offs, size - size_tail)
				tail = tail .. string.sub(message_part, partLength + 1 - size_tail)
				return partial
			else
				error("Adding more chunks is not allowed after receiving the result", 2)
			end
		else
			if tail then
				local final_blocks = table.create(10) --{tail, "\128", string.rep("\0", (-9 - length) % 64 + 1)}
				final_blocks[1] = tail
				final_blocks[2] = "\128"
				final_blocks[3] = string.rep("\0", (-9 - length) % 64 + 1)

				tail = nil
				-- Assuming user data length is shorter than (TWO_POW_53)-9 bytes
				-- Anyway, it looks very unrealistic that someone would spend more than a year of calculations to process TWO_POW_53 bytes of data by using this Lua script :-)
				-- TWO_POW_53 bytes = TWO_POW_56 bits, so "bit-counter" fits in 7 bytes
				length = length * (8 / TWO56_POW_7) -- convert "byte-counter" to "bit-counter" and move decimal point to the left
				for j = 4, 10 do
					length = length % 1 * 256
					final_blocks[j] = string.char(math.floor(length))
				end

				final_blocks = table.concat(final_blocks)
				sha256_feed_64(H, final_blocks, 0, #final_blocks)
				local max_reg = width / 32
				for j = 1, max_reg do
					H[j] = string.format("%08x", H[j] % 4294967296)
				end

				H = table.concat(H, "", 1, max_reg)
			end

			return H
		end
	end

	if message then
		-- Actually perform calculations and return the SHA256 digest of a message
		return partial(message)()
	else
		-- Return function for chunk-by-chunk loading
		-- User should feed every chunk of input data as single argument to this function and finally get SHA256 digest by invoking this function without an argument
		return partial
	end
end

local function sha512ext(width, message)

	-- Create an instance (private objects for current calculation)
	local length, tail, H_lo, H_hi = 0, "", table.pack(table.unpack(sha2_H_ext512_lo[width])), not HEX64 and table.pack(table.unpack(sha2_H_ext512_hi[width]))

	local function partial(message_part)
		if message_part then
			local partLength = #message_part
			if tail then
				length = length + partLength
				local offs = 0
				if tail ~= "" and #tail + partLength >= 128 then
					offs = 128 - #tail
					sha512_feed_128(H_lo, H_hi, tail .. string.sub(message_part, 1, offs), 0, 128)
					tail = ""
				end

				local size = partLength - offs
				local size_tail = size % 128
				sha512_feed_128(H_lo, H_hi, message_part, offs, size - size_tail)
				tail = tail .. string.sub(message_part, partLength + 1 - size_tail)
				return partial
			else
				error("Adding more chunks is not allowed after receiving the result", 2)
			end
		else
			if tail then
				local final_blocks = table.create(3) --{tail, "\128", string.rep("\0", (-17-length) % 128 + 9)}
				final_blocks[1] = tail
				final_blocks[2] = "\128"
				final_blocks[3] = string.rep("\0", (-17 - length) % 128 + 9)

				tail = nil
				-- Assuming user data length is shorter than (TWO_POW_53)-17 bytes
				-- TWO_POW_53 bytes = TWO_POW_56 bits, so "bit-counter" fits in 7 bytes
				length = length * (8 / TWO56_POW_7) -- convert "byte-counter" to "bit-counter" and move floating point to the left
				for j = 4, 10 do
					length = length % 1 * 256
					final_blocks[j] = string.char(math.floor(length))
				end

				final_blocks = table.concat(final_blocks)
				sha512_feed_128(H_lo, H_hi, final_blocks, 0, #final_blocks)
				local max_reg = math.ceil(width / 64)

				if HEX64 then
					for j = 1, max_reg do
						H_lo[j] = HEX64(H_lo[j])
					end
				else
					for j = 1, max_reg do
						H_lo[j] = string.format("%08x", H_hi[j] % 4294967296) .. string.format("%08x", H_lo[j] % 4294967296)
					end

					H_hi = nil
				end

				H_lo = string.sub(table.concat(H_lo, "", 1, max_reg), 1, width / 4)
			end

			return H_lo
		end
	end

	if message then
		-- Actually perform calculations and return the SHA512 digest of a message
		return partial(message)()
	else
		-- Return function for chunk-by-chunk loading
		-- User should feed every chunk of input data as single argument to this function and finally get SHA512 digest by invoking this function without an argument
		return partial
	end
end

local function md5(message)

	-- Create an instance (private objects for current calculation)
	local H, length, tail = table.create(4), 0, ""
	H[1], H[2], H[3], H[4] = md5_sha1_H[1], md5_sha1_H[2], md5_sha1_H[3], md5_sha1_H[4]

	local function partial(message_part)
		if message_part then
			local partLength = #message_part
			if tail then
				length = length + partLength
				local offs = 0
				if tail ~= "" and #tail + partLength >= 64 then
					offs = 64 - #tail
					md5_feed_64(H, tail .. string.sub(message_part, 1, offs), 0, 64)
					tail = ""
				end

				local size = partLength - offs
				local size_tail = size % 64
				md5_feed_64(H, message_part, offs, size - size_tail)
				tail = tail .. string.sub(message_part, partLength + 1 - size_tail)
				return partial
			else
				error("Adding more chunks is not allowed after receiving the result", 2)
			end
		else
			if tail then
				local final_blocks = table.create(3) --{tail, "\128", string.rep("\0", (-9 - length) % 64)}
				final_blocks[1] = tail
				final_blocks[2] = "\128"
				final_blocks[3] = string.rep("\0", (-9 - length) % 64)
				tail = nil
				length = length * 8 -- convert "byte-counter" to "bit-counter"
				for j = 4, 11 do
					local low_byte = length % 256
					final_blocks[j] = string.char(low_byte)
					length = (length - low_byte) / 256
				end

				final_blocks = table.concat(final_blocks)
				md5_feed_64(H, final_blocks, 0, #final_blocks)
				for j = 1, 4 do
					H[j] = string.format("%08x", H[j] % 4294967296)
				end

				H = string.gsub(table.concat(H), "(..)(..)(..)(..)", "%4%3%2%1")
			end

			return H
		end
	end

	if message then
		-- Actually perform calculations and return the MD5 digest of a message
		return partial(message)()
	else
		-- Return function for chunk-by-chunk loading
		-- User should feed every chunk of input data as single argument to this function and finally get MD5 digest by invoking this function without an argument
		return partial
	end
end

local function sha1(message)
	-- Create an instance (private objects for current calculation)
	local H, length, tail = table.pack(table.unpack(md5_sha1_H)), 0, ""

	local function partial(message_part)
		if message_part then
			local partLength = #message_part
			if tail then
				length = length + partLength
				local offs = 0
				if tail ~= "" and #tail + partLength >= 64 then
					offs = 64 - #tail
					sha1_feed_64(H, tail .. string.sub(message_part, 1, offs), 0, 64)
					tail = ""
				end

				local size = partLength - offs
				local size_tail = size % 64
				sha1_feed_64(H, message_part, offs, size - size_tail)
				tail = tail .. string.sub(message_part, partLength + 1 - size_tail)
				return partial
			else
				error("Adding more chunks is not allowed after receiving the result", 2)
			end
		else
			if tail then
				local final_blocks = table.create(10) --{tail, "\128", string.rep("\0", (-9 - length) % 64 + 1)}
				final_blocks[1] = tail
				final_blocks[2] = "\128"
				final_blocks[3] = string.rep("\0", (-9 - length) % 64 + 1)
				tail = nil

				-- Assuming user data length is shorter than (TWO_POW_53)-9 bytes
				-- TWO_POW_53 bytes = TWO_POW_56 bits, so "bit-counter" fits in 7 bytes
				length = length * (8 / TWO56_POW_7) -- convert "byte-counter" to "bit-counter" and move decimal point to the left
				for j = 4, 10 do
					length = length % 1 * 256
					final_blocks[j] = string.char(math.floor(length))
				end

				final_blocks = table.concat(final_blocks)
				sha1_feed_64(H, final_blocks, 0, #final_blocks)
				for j = 1, 5 do
					H[j] = string.format("%08x", H[j] % 4294967296)
				end

				H = table.concat(H)
			end

			return H
		end
	end

	if message then
		-- Actually perform calculations and return the SHA-1 digest of a message
		return partial(message)()
	else
		-- Return function for chunk-by-chunk loading
		-- User should feed every chunk of input data as single argument to this function and finally get SHA-1 digest by invoking this function without an argument
		return partial
	end
end

local function keccak(block_size_in_bytes, digest_size_in_bytes, is_SHAKE, message)
	-- "block_size_in_bytes" is multiple of 8
	if type(digest_size_in_bytes) ~= "number" then
		-- arguments in SHAKE are swapped:
		--    NIST FIPS 202 defines SHAKE(message,num_bits)
		--    this module   defines SHAKE(num_bytes,message)
		-- it's easy to forget about this swap, hence the check
		error("Argument 'digest_size_in_bytes' must be a number", 2)
	end

	-- Create an instance (private objects for current calculation)
	local tail, lanes_lo, lanes_hi = "", table.create(25, 0), hi_factor_keccak == 0 and table.create(25, 0)
	local result

	--~     pad the input N using the pad function, yielding a padded bit string P with a length divisible by r (such that n = len(P)/r is integer),
	--~     break P into n consecutive r-bit pieces P0, ..., Pn-1 (last is zero-padded)
	--~     initialize the state S to a string of b 0 bits.
	--~     absorb the input into the state: For each block Pi,
	--~         extend Pi at the end by a string of c 0 bits, yielding one of length b,
	--~         XOR that with S and
	--~         apply the block permutation f to the result, yielding a new state S
	--~     initialize Z to be the empty string
	--~     while the length of Z is less than d:
	--~         append the first r bits of S to Z
	--~         if Z is still less than d bits long, apply f to S, yielding a new state S.
	--~     truncate Z to d bits
	local function partial(message_part)
		if message_part then
			local partLength = #message_part
			if tail then
				local offs = 0
				if tail ~= "" and #tail + partLength >= block_size_in_bytes then
					offs = block_size_in_bytes - #tail
					keccak_feed(lanes_lo, lanes_hi, tail .. string.sub(message_part, 1, offs), 0, block_size_in_bytes, block_size_in_bytes)
					tail = ""
				end

				local size = partLength - offs
				local size_tail = size % block_size_in_bytes
				keccak_feed(lanes_lo, lanes_hi, message_part, offs, size - size_tail, block_size_in_bytes)
				tail = tail .. string.sub(message_part, partLength + 1 - size_tail)
				return partial
			else
				error("Adding more chunks is not allowed after receiving the result", 2)
			end
		else
			if tail then
				-- append the following bits to the message: for usual SHA3: 011(0*)1, for SHAKE: 11111(0*)1
				local gap_start = is_SHAKE and 31 or 6
				tail = tail .. (#tail + 1 == block_size_in_bytes and string.char(gap_start + 128) or string.char(gap_start) .. string.rep("\0", (-2 - #tail) % block_size_in_bytes) .. "\128")
				keccak_feed(lanes_lo, lanes_hi, tail, 0, #tail, block_size_in_bytes)
				tail = nil

				local lanes_used = 0
				local total_lanes = math.floor(block_size_in_bytes / 8)
				local qwords = {}

				local function get_next_qwords_of_digest(qwords_qty)
					-- returns not more than 'qwords_qty' qwords ('qwords_qty' might be non-integer)
					-- doesn't go across keccak-buffer boundary
					-- block_size_in_bytes is a multiple of 8, so, keccak-buffer contains integer number of qwords
					if lanes_used >= total_lanes then
						keccak_feed(lanes_lo, lanes_hi, "\0\0\0\0\0\0\0\0", 0, 8, 8)
						lanes_used = 0
					end

					qwords_qty = math.floor(math.min(qwords_qty, total_lanes - lanes_used))
					if hi_factor_keccak ~= 0 then
						for j = 1, qwords_qty do
							qwords[j] = HEX64(lanes_lo[lanes_used + j - 1 + lanes_index_base])
						end
					else
						for j = 1, qwords_qty do
							qwords[j] = string.format("%08x", lanes_hi[lanes_used + j] % 4294967296) .. string.format("%08x", lanes_lo[lanes_used + j] % 4294967296)
						end
					end

					lanes_used = lanes_used + qwords_qty
					return string.gsub(table.concat(qwords, "", 1, qwords_qty), "(..)(..)(..)(..)(..)(..)(..)(..)", "%8%7%6%5%4%3%2%1"), qwords_qty * 8
				end

				local parts = {} -- digest parts
				local last_part, last_part_size = "", 0

				local function get_next_part_of_digest(bytes_needed)
					-- returns 'bytes_needed' bytes, for arbitrary integer 'bytes_needed'
					bytes_needed = bytes_needed or 1
					if bytes_needed <= last_part_size then
						last_part_size = last_part_size - bytes_needed
						local part_size_in_nibbles = bytes_needed * 2
						local result = string.sub(last_part, 1, part_size_in_nibbles)
						last_part = string.sub(last_part, part_size_in_nibbles + 1)
						return result
					end

					local parts_qty = 0
					if last_part_size > 0 then
						parts_qty = 1
						parts[parts_qty] = last_part
						bytes_needed = bytes_needed - last_part_size
					end

					-- repeats until the length is enough
					while bytes_needed >= 8 do
						local next_part, next_part_size = get_next_qwords_of_digest(bytes_needed / 8)
						parts_qty = parts_qty + 1
						parts[parts_qty] = next_part
						bytes_needed = bytes_needed - next_part_size
					end

					if bytes_needed > 0 then
						last_part, last_part_size = get_next_qwords_of_digest(1)
						parts_qty = parts_qty + 1
						parts[parts_qty] = get_next_part_of_digest(bytes_needed)
					else
						last_part, last_part_size = "", 0
					end

					return table.concat(parts, "", 1, parts_qty)
				end

				if digest_size_in_bytes < 0 then
					result = get_next_part_of_digest
				else
					result = get_next_part_of_digest(digest_size_in_bytes)
				end

			end

			return result
		end
	end

	if message then
		-- Actually perform calculations and return the SHA3 digest of a message
		return partial(message)()
	else
		-- Return function for chunk-by-chunk loading
		-- User should feed every chunk of input data as single argument to this function and finally get SHA3 digest by invoking this function without an argument
		return partial
	end
end

local function HexToBinFunction(hh)
	return string.char(tonumber(hh, 16))
end

local function hex2bin(hex_string)
	return (string.gsub(hex_string, "%x%x", HexToBinFunction))
end

local base64_symbols = {
	["+"] = 62, ["-"] = 62, [62] = "+";
	["/"] = 63, ["_"] = 63, [63] = "/";
	["="] = -1, ["."] = -1, [-1] = "=";
}

local symbol_index = 0
for j, pair in ipairs{"AZ", "az", "09"} do
	for ascii = string.byte(pair), string.byte(pair, 2) do
		local ch = string.char(ascii)
		base64_symbols[ch] = symbol_index
		base64_symbols[symbol_index] = ch
		symbol_index = symbol_index + 1
	end
end

local function bin2base64(binary_string)
	local stringLength = #binary_string
	local result = table.create(math.ceil(stringLength / 3))
	local length = 0

	for pos = 1, #binary_string, 3 do
		local c1, c2, c3, c4 = string.byte(string.sub(binary_string, pos, pos + 2) .. '\0', 1, -1)
		length = length + 1
		result[length] =
			base64_symbols[math.floor(c1 / 4)] ..
			base64_symbols[c1 % 4 * 16 + math.floor(c2 / 16)] ..
			base64_symbols[c3 and c2 % 16 * 4 + math.floor(c3 / 64) or -1] ..
			base64_symbols[c4 and c3 % 64 or -1]
	end

	return table.concat(result)
end

local function base642bin(base64_string)
	local result, chars_qty = {}, 3
	for pos, ch in string.gmatch(string.gsub(base64_string, "%s+", ""), "()(.)") do
		local code = base64_symbols[ch]
		if code < 0 then
			chars_qty = chars_qty - 1
			code = 0
		end

		local idx = pos % 4
		if idx > 0 then
			result[-idx] = code
		else
			local c1 = result[-1] * 4 + math.floor(result[-2] / 16)
			local c2 = (result[-2] % 16) * 16 + math.floor(result[-3] / 4)
			local c3 = (result[-3] % 4) * 64 + code
			result[#result + 1] = string.sub(string.char(c1, c2, c3), 1, chars_qty)
		end
	end

	return table.concat(result)
end

local block_size_for_HMAC -- this table will be initialized at the end of the module
--local function pad_and_xor(str, result_length, byte_for_xor)
--	return string.gsub(str, ".", function(c)
--		return string.char(bit32_bxor(string.byte(c), byte_for_xor))
--	end) .. string.rep(string.char(byte_for_xor), result_length - #str)
--end

-- For the sake of speed of converting hexes to strings, there's a map of the conversions here
local BinaryStringMap = {}
for Index = 0, 255 do
	BinaryStringMap[string.format("%02x", Index)] = string.char(Index)
end

-- Update 02.14.20 - added AsBinary for easy GameAnalytics replacement.
local function hmac(hash_func, key, message, AsBinary)
	-- Create an instance (private objects for current calculation)
	local block_size = block_size_for_HMAC[hash_func]
	if not block_size then
		error("Unknown hash function", 2)
	end

	local KeyLength = #key
	if KeyLength > block_size then
		key = string.gsub(hash_func(key), "%x%x", HexToBinFunction)
		KeyLength = #key
	end

	local append = hash_func()(string.gsub(key, ".", function(c)
		return string.char(bit32_bxor(string.byte(c), 0x36))
	end) .. string.rep("6", block_size - KeyLength)) -- 6 = string.char(0x36)

	local result

	local function partial(message_part)
		if not message_part then
			result = result or hash_func(
				string.gsub(key, ".", function(c)
					return string.char(bit32_bxor(string.byte(c), 0x5c))
				end) .. string.rep("\\", block_size - KeyLength) -- \ = string.char(0x5c)
					.. (string.gsub(append(), "%x%x", HexToBinFunction))
			)

			return result
		elseif result then
			error("Adding more chunks is not allowed after receiving the result", 2)
		else
			append(message_part)
			return partial
		end
	end

	if message then
		-- Actually perform calculations and return the HMAC of a message
		local FinalMessage = partial(message)()
		return AsBinary and (string.gsub(FinalMessage, "%x%x", BinaryStringMap)) or FinalMessage
	else
		-- Return function for chunk-by-chunk loading of a message
		-- User should feed every chunk of the message as single argument to this function and finally get HMAC by invoking this function without an argument
		return partial
	end
end

local sha = {
	md5 = md5,
	sha1 = sha1,
	-- SHA2 hash functions:
	sha224 = function(message)
		return sha256ext(224, message)
	end;

	sha256 = function(message)
		return sha256ext(256, message)
	end;

	sha512_224 = function(message)
		return sha512ext(224, message)
	end;

	sha512_256 = function(message)
		return sha512ext(256, message)
	end;

	sha384 = function(message)
		return sha512ext(384, message)
	end;

	sha512 = function(message)
		return sha512ext(512, message)
	end;

	-- SHA3 hash functions:
	sha3_224 = function(message)
		return keccak((1600 - 2 * 224) / 8, 224 / 8, false, message)
	end;

	sha3_256 = function(message)
		return keccak((1600 - 2 * 256) / 8, 256 / 8, false, message)
	end;

	sha3_384 = function(message)
		return keccak((1600 - 2 * 384) / 8, 384 / 8, false, message)
	end;

	sha3_512 = function(message)
		return keccak((1600 - 2 * 512) / 8, 512 / 8, false, message)
	end;

	shake128 = function(message, digest_size_in_bytes)
		return keccak((1600 - 2 * 128) / 8, digest_size_in_bytes, true, message)
	end;

	shake256 = function(message, digest_size_in_bytes)
		return keccak((1600 - 2 * 256) / 8, digest_size_in_bytes, true, message)
	end;

	-- misc utilities:
	hmac = hmac; -- HMAC(hash_func, key, message) is applicable to any hash function from this module except SHAKE*
	hex_to_bin = hex2bin; -- converts hexadecimal representation to binary string
	base64_to_bin = base642bin; -- converts base64 representation to binary string
	bin_to_base64 = bin2base64; -- converts binary string to base64 representation
	base64_encode = Base64.encode;
	base64_decode = Base64.decode;
}

block_size_for_HMAC = {
	[sha.md5] = 64;
	[sha.sha1] = 64;
	[sha.sha224] = 64;
	[sha.sha256] = 64;
	[sha.sha512_224] = 128;
	[sha.sha512_256] = 128;
	[sha.sha384] = 128;
	[sha.sha512] = 128;
	[sha.sha3_224] = (1600 - 2 * 224) / 8;
	[sha.sha3_256] = (1600 - 2 * 256) / 8;
	[sha.sha3_384] = (1600 - 2 * 384) / 8;
	[sha.sha3_512] = (1600 - 2 * 512) / 8;
}

local HashLib = sha

-- metatablecat 2022
-- from https://gist.github.com/metatablecat/92345df2fd6d450da288c28272555faf
local LZ4 = {}

type Streamer = {
	Offset: number,
	Source: string,
	Length: number,
	IsFinished: boolean,
	LastUnreadBytes: number,

	read: (Streamer, len: number?, shiftOffset: boolean?) -> string,
	seek: (Streamer, len: number) -> (),
	append: (Streamer, newData: string) -> (),
	toEnd: (Streamer) -> ()
}

type BlockData = {
	[number]: {
		Literal: string,
		LiteralLength: number,
		MatchOffset: number?,
		MatchLength: number?
	}
}

local function plainFind(str, pat)
	return string.find(str, pat, 0, true)
end

local function streamer(str): Streamer
	local Stream = {}
	Stream.Offset = 0
	Stream.Source = str
	Stream.Length = string.len(str)
	Stream.IsFinished = false	
	Stream.LastUnreadBytes = 0

	function Stream.read(self: Streamer, len: number?, shift: boolean?): string
		local len = len or 1
		local shift = if shift ~= nil then shift else true
		local dat = string.sub(self.Source, self.Offset + 1, self.Offset + len)

		local dataLength = string.len(dat)
		local unreadBytes = len - dataLength

		if shift then
			self:seek(len)
		end

		self.LastUnreadBytes = unreadBytes
		return dat
	end

	function Stream.seek(self: Streamer, len: number)
		local len = len or 1

		self.Offset = math.clamp(self.Offset + len, 0, self.Length)
		self.IsFinished = self.Offset >= self.Length
	end

	function Stream.append(self: Streamer, newData: string)
		-- adds new data to the end of a stream
		self.Source ..= newData
		self.Length = string.len(self.Source)
		self:seek(0) --hacky but forces a recalculation of the isFinished flag
	end

	function Stream.toEnd(self: Streamer)
		self:seek(self.Length)
	end

	return Stream
end

function LZ4.compress(str: string): string
	local blocks: BlockData = {}
	local iostream = streamer(str)

	if iostream.Length > 12 then
		local firstFour = iostream:read(4)

		local processed = firstFour
		local lit = firstFour
		local match = ""
		local LiteralPushValue = ""
		local pushToLiteral = true

		repeat
			pushToLiteral = true
			local nextByte = iostream:read()

			if plainFind(processed, nextByte) then
				local next3 = iostream:read(3, false)

				if string.len(next3) < 3 then
					--push bytes to literal block then break
					LiteralPushValue = nextByte .. next3
					iostream:seek(3)
				else
					match = nextByte .. next3

					local matchPos = plainFind(processed, match)
					if matchPos then
						iostream:seek(3)
						repeat
							local nextMatchByte = iostream:read(1, false)
							local newResult = match .. nextMatchByte

							local repos = plainFind(processed, newResult) 
							if repos then
								match = newResult
								matchPos = repos
								iostream:seek(1)
							end
						until not plainFind(processed, newResult) or iostream.IsFinished

						local matchLen = string.len(match)
						local pushMatch = true

						if iostream.Length - iostream.Offset <= 5 then
							LiteralPushValue = match
							pushMatch = false
							--better safe here, dont bother pushing to match ever
						end

						if pushMatch then
							pushToLiteral = false

							-- gets the position from the end of processed, then slaps it onto processed
							local realPosition = string.len(processed) - matchPos
							processed = processed .. match

							table.insert(blocks, {
								Literal = lit,
								LiteralLength = string.len(lit),
								MatchOffset = realPosition + 1,
								MatchLength = matchLen,
							})
							lit = ""
						end
					else
						LiteralPushValue = nextByte
					end
				end
			else
				LiteralPushValue = nextByte
			end

			if pushToLiteral then
				lit = lit .. LiteralPushValue
				processed = processed .. nextByte
			end
		until iostream.IsFinished
		table.insert(blocks, {
			Literal = lit,
			LiteralLength = string.len(lit)
		})
	else
		local str = iostream.Source
		blocks[1] = {
			Literal = str,
			LiteralLength = string.len(str)
		}
	end

	-- generate the output chunk
	-- %s is for adding header
	local output = string.rep("\x00", 4)
	local function write(char)
		output = output .. char
	end
	-- begin working through chunks
	for chunkNum, chunk in blocks do
		local litLen = chunk.LiteralLength
		local matLen = (chunk.MatchLength or 4) - 4

		-- create token
		local tokenLit = math.clamp(litLen, 0, 15)
		local tokenMat = math.clamp(matLen, 0, 15)

		local token = bit32.lshift(tokenLit, 4) + tokenMat
		write(string.pack("<I1", token))

		if litLen >= 15 then
			litLen = litLen - 15
			--begin packing extra bytes
			repeat
				local nextToken = math.clamp(litLen, 0, 0xFF)
				write(string.pack("<I1", nextToken))
				if nextToken == 0xFF then
					litLen = litLen - 255
				end
			until nextToken < 0xFF
		end

		-- push raw lit data
		write(chunk.Literal)

		if chunkNum ~= #blocks then
			-- push offset as u16
			write(string.pack("<I2", chunk.MatchOffset))

			-- pack extra match bytes
			if matLen >= 15 then
				matLen = matLen - 15

				repeat
					local nextToken = math.clamp(matLen, 0, 0xFF)
					write(string.pack("<I1", nextToken))
					if nextToken == 0xFF then
						matLen = matLen - 255
					end
				until nextToken < 0xFF
			end
		end
	end
	--append chunks
	local compLen = string.len(output) - 4
	local decompLen = iostream.Length

	return string.pack("<I4", compLen) .. string.pack("<I4", decompLen) .. output
end

function LZ4.decompress(LZ4data: string): string
	local inputStream = streamer(LZ4data)

	local compressedLen = string.unpack("<I4", inputStream:read(4))
	local decompressedLen = string.unpack("<I4", inputStream:read(4))
	local reserved = string.unpack("<I4", inputStream:read(4))

	if compressedLen == 0 then
		return inputStream:read(decompressedLen)
	end

	local outputStream = streamer("")

	repeat
		local token = string.byte(inputStream:read())
		local litLen = bit32.rshift(token, 4)
		local matLen = bit32.band(token, 15) + 4

		if litLen >= 15 then
			repeat
				local nextByte = string.byte(inputStream:read())
				litLen += nextByte
			until nextByte ~= 0xFF
		end

		local literal = inputStream:read(litLen)
		outputStream:append(literal)
		outputStream:toEnd()
		if outputStream.Length < decompressedLen then
			--match
			local offset = string.unpack("<I2", inputStream:read(2))
			if matLen >= 19 then
				repeat
					local nextByte = string.byte(inputStream:read())
					matLen += nextByte
				until nextByte ~= 0xFF
			end

			outputStream:seek(-offset)
			local pos = outputStream.Offset
			local match = outputStream:read(matLen)
			local unreadBytes = outputStream.LastUnreadBytes
			local extra
			if unreadBytes then
				repeat
					outputStream.Offset = pos
					extra = outputStream:read(unreadBytes)
					unreadBytes = outputStream.LastUnreadBytes
					match ..= extra
				until unreadBytes <= 0
			end

			outputStream:append(match)
			outputStream:toEnd()
		end

	until outputStream.Length >= decompressedLen

	return outputStream.Source
end

local s_box 	= { 99, 124, 119, 123, 242, 107, 111, 197,  48,   1, 103,  43, 254, 215, 171, 118, 202,
	130, 201, 125, 250,  89,  71, 240, 173, 212, 162, 175, 156, 164, 114, 192, 183, 253, 147,  38,  54,
	63, 247, 204,  52, 165, 229, 241, 113, 216,  49,  21,   4, 199,  35, 195,  24, 150,   5, 154,   7,
	18, 128, 226, 235,  39, 178, 117,   9, 131,  44,  26,  27, 110,  90, 160,  82,  59, 214, 179,  41,
	227,  47, 132,  83, 209,   0, 237,  32, 252, 177,  91, 106, 203, 190,  57,  74,  76,  88, 207, 208,
	239, 170, 251,  67,  77,  51, 133,  69, 249,   2, 127,  80,  60, 159, 168,  81, 163,  64, 143, 146,
	157,  56, 245, 188, 182, 218,  33,  16, 255, 243, 210, 205,  12,  19, 236,  95, 151,  68,  23, 196,
	167, 126,  61, 100,  93,  25, 115,  96, 129,  79, 220,  34,  42, 144, 136,  70, 238, 184,  20, 222,
	94,  11, 219, 224,  50,  58,  10,  73,   6,  36,  92, 194, 211, 172,  98, 145, 149, 228, 121, 231,
	200,  55, 109, 141, 213,  78, 169, 108,  86, 244, 234, 101, 122, 174,   8, 186, 120,  37,  46,  28,
	166, 180, 198, 232, 221, 116,  31,  75, 189, 139, 138, 112,  62, 181, 102,  72,   3, 246,  14,  97,
	53,  87, 185, 134, 193,  29, 158, 225, 248, 152,  17, 105, 217, 142, 148, 155,  30, 135, 233, 206,
	85,  40, 223, 140, 161, 137,  13, 191, 230,  66, 104,  65, 153,  45,  15, 176,  84, 187,  22}
local inv_s_box	= { 82,   9, 106, 213,  48,  54, 165,  56, 191,  64, 163, 158, 129, 243, 215, 251, 124,
	227,  57, 130, 155,  47, 255, 135,  52, 142,  67,  68, 196, 222, 233, 203,  84, 123, 148,  50, 166,
	194,  35,  61, 238,  76, 149,  11,  66, 250, 195,  78,   8,  46, 161, 102,  40, 217,  36, 178, 118,
	91, 162,  73, 109, 139, 209,  37, 114, 248, 246, 100, 134, 104, 152,  22, 212, 164,  92, 204,  93,
	101, 182, 146, 108, 112,  72,  80, 253, 237, 185, 218,  94,  21,  70,  87, 167, 141, 157, 132, 144,
	216, 171,   0, 140, 188, 211,  10, 247, 228,  88,   5, 184, 179,  69,   6, 208,  44,  30, 143, 202,
	63,  15,   2, 193, 175, 189,   3,   1,  19, 138, 107,  58, 145,  17,  65,  79, 103, 220, 234, 151,
	242, 207, 206, 240, 180, 230, 115, 150, 172, 116,  34, 231, 173,  53, 133, 226, 249,  55, 232,  28,
	117, 223, 110,  71, 241,  26, 113,  29,  41, 197, 137, 111, 183,  98,  14, 170,  24, 190,  27, 252,
	86,  62,  75, 198, 210, 121,  32, 154, 219, 192, 254, 120, 205,  90, 244,  31, 221, 168,  51, 136,
	7, 199,  49, 177,  18,  16,  89,  39, 128, 236,  95,  96,  81, 127, 169,  25, 181,  74,  13,  45,
	229, 122, 159, 147, 201, 156, 239, 160, 224,  59,  77, 174,  42, 245, 176, 200, 235, 187,  60, 131,
	83, 153,  97,  23,  43,   4, 126, 186, 119, 214,  38, 225, 105,  20,  99,  85,  33,  12, 125}

-- ROUND CONSTANTS ARRAY
local rcon = {  0,   1,   2,   4,   8,  16,  32,  64, 128,  27,  54, 108, 216, 171,  77, 154,  47,  94,
	188,  99, 198, 151,  53, 106, 212, 179, 125, 250, 239, 197, 145,  57}
-- MULTIPLICATION OF BINARY POLYNOMIAL
local function xtime(x)
	local i = bit32.lshift(x, 1)
	return if bit32.band(x, 128) == 0 then i else bit32.bxor(i, 27) % 256
end

-- TRANSFORMATION FUNCTIONS
local function subBytes		(s, inv) 		-- Processes State using the S-box
	inv = if inv then inv_s_box else s_box
	for i = 1, 4 do
		for j = 1, 4 do
			s[i][j] = inv[s[i][j] + 1]
		end
	end
end
local function shiftRows		(s, inv) 	-- Processes State by circularly shifting rows
	s[1][3], s[2][3], s[3][3], s[4][3] = s[3][3], s[4][3], s[1][3], s[2][3]
	if inv then
		s[1][2], s[2][2], s[3][2], s[4][2] = s[4][2], s[1][2], s[2][2], s[3][2]
		s[1][4], s[2][4], s[3][4], s[4][4] = s[2][4], s[3][4], s[4][4], s[1][4]
	else
		s[1][2], s[2][2], s[3][2], s[4][2] = s[2][2], s[3][2], s[4][2], s[1][2]
		s[1][4], s[2][4], s[3][4], s[4][4] = s[4][4], s[1][4], s[2][4], s[3][4]
	end
end
local function addRoundKey	(s, k) 			-- Processes Cipher by adding a round key to the State
	for i = 1, 4 do
		for j = 1, 4 do
			s[i][j] = bit32.bxor(s[i][j], k[i][j])
		end
	end
end
local function mixColumns	(s, inv) 		-- Processes Cipher by taking and mixing State columns
	local t, u
	if inv then
		for i = 1, 4 do
			t = xtime(xtime(bit32.bxor(s[i][1], s[i][3])))
			u = xtime(xtime(bit32.bxor(s[i][2], s[i][4])))
			s[i][1], s[i][2] = bit32.bxor(s[i][1], t), bit32.bxor(s[i][2], u)
			s[i][3], s[i][4] = bit32.bxor(s[i][3], t), bit32.bxor(s[i][4], u)
		end
	end

	local i
	for j = 1, 4 do
		i = s[j]
		t, u = bit32.bxor		(i[1], i[2], i[3], i[4]), i[1]
		for k = 1, 4 do
			i[k] = bit32.bxor	(i[k], t, xtime(bit32.bxor(i[k], i[k + 1] or u)))
		end
	end
end

-- BYTE ARRAY UTILITIES
local function bytesToMatrix	(t, c, inv) -- Converts a byte array to a 4x4 matrix
	if inv then
		table.move		(c[1], 1, 4, 1, t)
		table.move		(c[2], 1, 4, 5, t)
		table.move		(c[3], 1, 4, 9, t)
		table.move		(c[4], 1, 4, 13, t)
	else
		for i = 1, #c / 4 do
			table.clear	(t[i])
			table.move	(c, i * 4 - 3, i * 4, 1, t[i])
		end
	end

	return t
end
local function xorBytes		(t, a, b) 		-- Returns bitwise XOR of all their bytes
	table.clear		(t)

	for i = 1, math.min(#a, #b) do
		table.insert(t, bit32.bxor(a[i], b[i]))
	end
	return t
end
local function incBytes		(a, inv)		-- Increment byte array by one
	local o = true
	for i = if inv then 1 else #a, if inv then #a else 1, if inv then 1 else - 1 do
		if a[i] == 255 then
			a[i] = 0
		else
			a[i] += 1
			o = false
			break
		end
	end

	return o, a
end

-- MAIN ALGORITHM
local function expandKey	(key) 				-- Key expansion
	local kc = bytesToMatrix(if #key == 16 then {{}, {}, {}, {}} elseif #key == 24 then {{}, {}, {}, {}
		, {}, {}} else {{}, {}, {}, {}, {}, {}, {}, {}}, key)
	local is = #key / 4
	local i, t, w = 2, {}, nil

	while #kc < (#key / 4 + 7) * 4 do
		w = table.clone	(kc[#kc])
		if #kc % is == 0 then
			table.insert(w, table.remove(w, 1))
			for j = 1, 4 do
				w[j] = s_box[w[j] + 1]
			end
			w[1]	 = bit32.bxor(w[1], rcon[i])
			i 	+= 1
		elseif #key == 32 and #kc % is == 4 then
			for j = 1, 4 do
				w[j] = s_box[w[j] + 1]
			end
		end

		table.clear	(t)
		xorBytes	(w, table.move(w, 1, 4, 1, t), kc[#kc - is + 1])
		table.insert(kc, w)
	end

	table.clear		(t)
	for i = 1, #kc / 4 do
		table.insert(t, {})
		table.move	(kc, i * 4 - 3, i * 4, 1, t[#t])
	end
	return t
end
local function encrypt	(key, km, pt, ps, r) 	-- Block cipher encryption
	bytesToMatrix	(ps, pt)
	addRoundKey		(ps, km[1])

	for i = 2, #key / 4 + 6 do
		subBytes	(ps)
		shiftRows	(ps)
		mixColumns	(ps)
		addRoundKey	(ps, km[i])
	end
	subBytes		(ps)
	shiftRows		(ps)
	addRoundKey		(ps, km[#km])

	return bytesToMatrix(r, ps, true)
end
local function decrypt	(key, km, ct, cs, r) 	-- Block cipher decryption
	bytesToMatrix	(cs, ct)

	addRoundKey		(cs, km[#km])
	shiftRows		(cs, true)
	subBytes		(cs, true)
	for i = #key / 4 + 6, 2, - 1 do
		addRoundKey	(cs, km[i])
		mixColumns	(cs, true)
		shiftRows	(cs, true)
		subBytes	(cs, true)
	end

	addRoundKey		(cs, km[1])
	return bytesToMatrix(r, cs, true)
end

-- INITIALIZATION FUNCTIONS
local function convertType	(a) 					-- Converts data to bytes if possible
	if type(a) == "string" then
		local r = {}

		for i = 1, string.len(a), 7997 do
			table.move({string.byte(a, i, i + 7996)}, 1, 7997, i, r)
		end
		return r
	elseif type(a) == "table" then
		for _, i in ipairs(a) do
			assert(type(i) == "number" and math.floor(i) == i and 0 <= i and i < 256,
				"Unable to cast value to bytes")
		end
		return a
	else
		error("Unable to cast value to bytes")
	end
end
local function deepCopy(Original)
	local copy = {}
	for key, val in next, Original do
		local Type = typeof(val)
		if Type == "table" then
			val = deepCopy(val)
		end
		copy[key] = val
	end
	return copy
end
local function init			(key, txt, m, iv, s) 	-- Initializes functions if possible
	key = convertType(key)
	assert(#key == 16 or #key == 24 or #key == 32, "Key must be either 16, 24 or 32 bytes long")
	txt = convertType(txt)
	assert(#txt % (s or 16) == 0, "Input must be a multiple of " .. (if s then "segment size " .. s
		else "16") .. " bytes in length")
	if m then
		if type(iv) == "table" then
			iv = table.clone(iv)
			local l, e 		= iv.Length, iv.LittleEndian
			assert(type(l) == "number" and 0 < l and l <= 16,
				"Counter value length must be between 1 and 16 bytes")
			iv.Prefix 		= convertType(iv.Prefix or {})
			iv.Suffix 		= convertType(iv.Suffix or {})
			assert(#iv.Prefix + #iv.Suffix + l == 16, "Counter must be 16 bytes long")
			iv.InitValue 	= if iv.InitValue == nil then {1} else table.clone(convertType(iv.InitValue
			))
			assert(#iv.InitValue <= l, "Initial value length must be of the counter value")
			iv.InitOverflow = if iv.InitOverflow == nil then table.create(l, 0) else table.clone(
			convertType(iv.InitOverflow))
			assert(#iv.InitOverflow <= l,
				"Initial overflow value length must be of the counter value")
			for _ = 1, l - #iv.InitValue do
				table.insert(iv.InitValue, 1 + if e then #iv.InitValue else 0, 0)
			end
			for _ = 1, l - #iv.InitOverflow do
				table.insert(iv.InitOverflow, 1 + if e then #iv.InitOverflow else 0, 0)
			end
		elseif type(iv) ~= "function" then
			local i, t = if iv then convertType(iv) else table.create(16, 0), {}
			assert(#i == 16, "Counter must be 16 bytes long")
			iv = {Length = 16, Prefix = t, Suffix = t, InitValue = i,
				InitOverflow = table.create(16, 0)}
		end
	elseif m == false then
		iv 	= if iv == nil then  table.create(16, 0) else convertType(iv)
		assert(#iv == 16, "Initialization vector must be 16 bytes long")
	end
	if s then
		s = math.floor(tonumber(s) or 1)
		assert(type(s) == "number" and 0 < s and s <= 16, "Segment size must be between 1 and 16 bytes"
		)
	end

	return key, txt, expandKey(key), iv, s
end
type bytes = {number} -- Type instance of a valid bytes object

-- CIPHER MODES OF OPERATION
local AES = {
	-- Electronic codebook (ECB)
	encrypt_ECB = function(key : bytes, plainText : bytes, initVector : bytes?) 									: bytes
		local km
		key, plainText, km, initVector = init(key, plainText, false, initVector)

		local iv = deepCopy(initVector)
		local b, k, s, t = {}, {}, {{}, {}, {}, {}}, {}
		for i = 1, #plainText, 16 do
			table.move(plainText, i, i + 15, 1, k)
			table.move(encrypt(key, km, k, s, t), 1, 16, i, b)
		end

		return b, iv
	end,
	decrypt_ECB = function(key : bytes, cipherText : bytes, initVector : bytes?) 								: bytes
		local km
		key, cipherText, km = init(key, cipherText, false, initVector)

		local b, k, s, t = {}, {}, {{}, {}, {}, {}}, {}
		for i = 1, #cipherText, 16 do
			table.move(cipherText, i, i + 15, 1, k)
			table.move(decrypt(key, km, k, s, t), 1, 16, i, b)
		end

		return b
	end,
	-- Cipher block chaining (CBC)
	encrypt_CBC = function(key : bytes, plainText : bytes, initVector : bytes?) 			: bytes
		local km
		key, plainText, km, initVector = init(key, plainText, false, initVector)
		local iv = deepCopy(initVector)
		local b, k, p, s, t = {}, {}, initVector, {{}, {}, {}, {}}, {}
		for i = 1, #plainText, 16 do
			table.move(plainText, i, i + 15, 1, k)
			table.move(encrypt(key, km, xorBytes(t, k, p), s, p), 1, 16, i, b)
		end

		return b, iv
	end,
	decrypt_CBC = function(key : bytes, cipherText : bytes, initVector : bytes?) 			: bytes
		local km
		key, cipherText, km, initVector = init(key, cipherText, false, initVector)

		local b, k, p, s, t = {}, {}, initVector, {{}, {}, {}, {}}, {}
		for i = 1, #cipherText, 16 do
			table.move(cipherText, i, i + 15, 1, k)
			table.move(xorBytes(k, decrypt(key, km, k, s, t), p), 1, 16, i, b)
			table.move(cipherText, i, i + 15, 1, p)
		end

		return b
	end,
	-- Propagating cipher block chaining (PCBC)
	encrypt_PCBC = function(key : bytes, plainText : bytes, initVector : bytes?) 			: bytes
		local km
		key, plainText, km, initVector = init(key, plainText, false, initVector)
		local iv = deepCopy(initVector)
		local b, k, c, p, s, t = {}, {}, initVector, table.create(16, 0), {{}, {}, {}, {}}, {}
		for i = 1, #plainText, 16 do
			table.move(plainText, i, i + 15, 1, k)
			table.move(encrypt(key, km, xorBytes(k, xorBytes(t, c, k), p), s, c), 1, 16, i, b)
			table.move(plainText, i, i + 15, 1, p)
		end

		return b, iv
	end,
	decrypt_PCBC = function(key : bytes, cipherText : bytes, initVector : bytes?) 			: bytes
		local km
		key, cipherText, km, initVector = init(key, cipherText, false, initVector)

		local b, k, c, p, s, t = {}, {}, initVector, table.create(16, 0), {{}, {}, {}, {}}, {}
		for i = 1, #cipherText, 16 do
			table.move(cipherText, i, i + 15, 1, k)
			table.move(xorBytes(p, decrypt(key, km, k, s, t), xorBytes(k, c, p)), 1, 16, i, b)
			table.move(cipherText, i, i + 15, 1, c)
		end

		return b
	end,
	-- Cipher feedback (CFB)
	encrypt_CFB = function(key : bytes, plainText : bytes, initVector : bytes?, segmentSize : number?)
		: bytes
		local km
		key, plainText, km, initVector, segmentSize = init(key, plainText, false, initVector,
			if segmentSize == nil then 1 else segmentSize)
		local iv = deepCopy(initVector)
		local b, k, p, q, s, t = {}, {}, initVector, {}, {{}, {}, {}, {}}, {}
		for i = 1, #plainText, segmentSize do
			table.move(plainText, i, i + segmentSize - 1, 1, k)
			table.move(xorBytes(q, encrypt(key, km, p, s, t), k), 1, segmentSize, i, b)
			for j = 16, segmentSize + 1, - 1 do
				table.insert(q, 1, p[j])
			end
			table.move(q, 1, 16, 1, p)
		end

		return b, iv
	end,
	decrypt_CFB = function(key : bytes, cipherText : bytes, initVector : bytes, segmentSize : number?)
		: bytes
		local km
		key, cipherText, km, initVector, segmentSize = init(key, cipherText, false, initVector,
			if segmentSize == nil then 1 else segmentSize)

		local b, k, p, q, s, t = {}, {}, initVector, {}, {{}, {}, {}, {}}, {}
		for i = 1, #cipherText, segmentSize do
			table.move(cipherText, i, i + segmentSize - 1, 1, k)
			table.move(xorBytes(q, encrypt(key, km, p, s, t), k), 1, segmentSize, i, b)
			for j = 16, segmentSize + 1, - 1 do
				table.insert(k, 1, p[j])
			end
			table.move(k, 1, 16, 1, p)
		end

		return b
	end,
	-- Output feedback (OFB)
	encrypt_OFB = function(key : bytes, plainText : bytes, initVector : bytes?) 			: bytes
		local km
		key, plainText, km, initVector = init(key, plainText, false, initVector)
		local iv = deepCopy(initVector)
		local b, k, p, s, t = {}, {}, initVector, {{}, {}, {}, {}}, {}
		for i = 1, #plainText, 16 do
			table.move(plainText, i, i + 15, 1, k)
			table.move(encrypt(key, km, p, s, t), 1, 16, 1, p)
			table.move(xorBytes(t, k, p), 1, 16, i, b)
		end

		return b, iv
	end,
	-- Counter (CTR)
	encrypt_CTR = function(key : bytes, plainText : bytes, counter : ((bytes) -> bytes) | bytes | { [
		string]: any }?) : bytes
		local km
		key, plainText, km, counter = init(key, plainText, true, counter)
		local iv = deepCopy(counter)
		local b, k, c, s, t, r, n = {}, {}, {}, {{}, {}, {}, {}}, {}, type(counter) == "table", nil
		for i = 1, #plainText, 16 do
			if r then
				if i > 1 and incBytes(counter.InitValue, counter.LittleEndian) then
					table.move(counter.InitOverflow, 1, 16, 1, counter.InitValue)
				end
				table.clear	(c)
				table.move	(counter.Prefix, 1, #counter.Prefix, 1, c)
				table.move	(counter.InitValue, 1, counter.Length, #c + 1, c)
				table.move	(counter.Suffix, 1, #counter.Suffix, #c + 1, c)
			else
				n = convertType(counter(c, (i + 15) / 16))
				assert		(#n == 16, "Counter must be 16 bytes long")
				table.move	(n, 1, 16, 1, c)
			end
			table.move(plainText, i, i + 15, 1, k)
			table.move(xorBytes(c, encrypt(key, km, c, s, t), k), 1, 16, i, b)
		end

		return b, iv
	end
} -- Returns the library
local Base64 = {
	encode = HashLib.base64_encode,
	decode = HashLib.base64_decode,
}
local modes = {}

for _, ciphermode in { "ECB", "CBC", "PCBC", "CFB", "OFB", "CTR" } do -- Missing: gcm (important)
	local en = AES["encrypt_" .. ciphermode]
	local de = AES["decrypt_" .. ciphermode]

	modes[string.lower(ciphermode)] = if de then { en, de } else en
end

-- Function to add PKCS#7 padding to a string
local function addPKCS7Padding(inputString)
	local blockSize = 16
	local length = (#inputString % blockSize)

	-- Only add padding if needed
	if 0 == length then
		return inputString
	end

	local paddingSize = blockSize - length

	local padding = string.rep(string.char(paddingSize), paddingSize)
	return inputString .. padding
end

-- Function to remove PKCS#7 padding from a padded string
local function removePKCS7Padding(paddedString)
	local lastByte = string.byte(paddedString, -1)

	-- Check if padding is present
	if lastByte <= 16 and 0 < lastByte then
		return string.sub(paddedString, 1, -lastByte - 1)
	else
		return paddedString
	end
end
local function GetTableType(t)
	local ct = 1
	for i in t do
		if i ~= ct then
			return "dictionary"
		end
		ct += 1
	end
	return "array"
end

local function BytesToChars(t)
	return string.char(unpack(t))
end


-- Encoding/Encryption Library
-- imports
local function CryptGeneralized(action: string?)
	return function(data: string, key: string, iv: string?, mode: string?): (string, string)
		if mode and type(mode) == "string" then
			mode = string.lower(mode)
			mode = modes[mode]
		else
			mode = modes.cbc -- Default
		end
		local crypt_f = if type(mode) == "table" then mode[action] else mode

		if iv then
			iv = Base64.decode(iv)
			pcall(function()
				iv = game:GetService("HttpService"):JSONDecode(iv)
			end)
			if 16 < #iv then
				iv = string.sub(iv, 1, 16)
			elseif #iv < 16 then
				iv = addPKCS7Padding(iv)
			end
		end

		pcall(function()
			key = Base64.decode(key)
		end)

		-- TODO This code below is even worse

		data, iv = crypt_f(key, if action == 1 then addPKCS7Padding(data) else Base64.decode(data), iv)
		data = BytesToChars(data)
		if action == 2 then
			data = removePKCS7Padding(data)
		else
			if GetTableType(iv) == "array" then
				iv = BytesToChars(iv)
			else
				iv = game:GetService("HttpService"):JSONEncode(iv)
			end
			iv = Base64.encode(iv)
			data = Base64.encode(data)
		end
		return data, iv
	end
end
-- main
local Crypt = {}


function Crypt.encrypt(text, key)
	local encryptedText = ""
	local keyLength = #key
	for i = 1, #text do
		local char = text:sub(i, i)
		local keyChar = key:sub((i - 1) % keyLength + 1, (i - 1) % keyLength + 1)
		local shifted = string.char((char:byte() + keyChar:byte()) % 256)
		encryptedText = encryptedText .. shifted
	end
	return encryptedText
end

function Crypt.decrypt(cipher, key)
	local decryptedText = ""
	local keyLength = #key
	for i = 1, #cipher do
		local char = cipher:sub(i, i)
		local keyChar = key:sub((i - 1) % keyLength + 1, (i - 1) % keyLength + 1)
		local shifted = string.char((char:byte() - keyChar:byte() + 256) % 256)
		decryptedText = decryptedText .. shifted
	end
	return decryptedText
end

function Crypt.generatebytes(size: number): string
	if type(size) ~= "number" then
		error(string.format("Invalid argument #1 (number expected, got %s)", type(size)), 2)
	end

	size = math.max(size, 1)

	local result = ""

	for _ = 1, size do
		local charPos =  math.random(1, #CHARACTER_SET)
		result ..= string.sub(CHARACTER_SET, charPos, charPos)
	end

	return Base64.encode(result)
end

function Crypt.generatekey()
	return Crypt.generatebytes(32)
end

function Crypt.hash(data: string, algorithm: string): string
	local hash_funcname = hashlib_flist[algorithm]
	if not hash_funcname then
		return error(`invalid argument #2 (algorithm {algorithm} not found)`, 2)
	end

	return HashLib[hash_funcname](data)
end

function Crypt.hmac(data: string, key: string, asBinary: boolean): string
	--* sha512_256 because synapse uses it - https://web.archive.org/web/20231030192906/https://synllc.github.io/synapse-x-documentation/reference/namespace/syn.crypt.html#hmac - https://libsodium.gitbook.io/doc/secret-key_cryptography/secret-key_authentication#algorithm-details

	return HashLib.hmac(HashLib.sha512_256, data, key, asBinary)
end

Crypt.base64 = Base64
Crypt.LZ4 = LZ4

local LZ4_Compress, LZ4_Decompress = LZ4.compress, LZ4.decompress


Crypt.encrypt = CryptGeneralized(1)
Crypt.decrypt = CryptGeneralized(2)

Crypt.LZ4compress = LZ4_Compress
Crypt.LZ4decompress = LZ4_Decompress

DefineVEnv({"crypt", "crypto"}, Crypt)--
local Debug = table.clone(debug)

Debug.getinfo = function(f, options)
	if options then
		options = string.lower(options) -- if some mf adds "L" for activelines and "l" ffor currentline then thats on him (it will just slow down this function because duplicate debug.infos lol)
	else
		options = "sflnu" -- haha snuf
	end

	local result = {}

	-- local Descriptors = { f = "func", l = "currentline", n = "name" }

	for index = 1, #options do
		local option = string.sub(options, index, index)
		if "s" == option then
			local short_src = debug.info(f, "s")

			result.short_src = short_src
			result.source = "@" .. short_src
			result.what = short_src == "[C]" and "C" or "Lua"
		elseif "f" == option then
			result.func = debug.info(f, "f")
		elseif "l" == option then
			result.currentline = debug.info(f, "l")
		elseif "n" == option then
			result.name = debug.info(f, "n")
		elseif "u" == option or option == "a" then
			local numparams, is_vararg = debug.info(f, "a")
			result.numparams = numparams
			result.is_vararg = if is_vararg then 1 else 0
			if "u" == option then
				result.nups = 0 --#debug.getupvalues(f)
			end

			-- else
			-- 	local Descriptor = Descriptors[option]
			-- 	if Descriptor then
			-- 		result[Descriptor] = debug.info(f, option)
			-- 	end
		end
	end

	return result
end

DefineVEnv({"debug"}, debug)
table.freeze(Debug) -- This should always be at the bottom--


local LoadstringENV = setmetatable({script = Instance.new("LocalScript")}, {
	__index = function(self, key)
		return VisionEnv[key] or GENV[key] or getfenv(2)[key]
	end
})

--!native

-- Adapted from the amazing Yueliang project
-- http://yueliang.luaforge.net/


--[[--------------------------------------------------------------------

luac.lua
Primitive luac in Lua
This file is part of Yueliang.

Copyright (c) 2005-2007 Kein-Hong Man <khman@users.sf.net>
The COPYRIGHT file describes the conditions
under which this software may be distributed.

See the ChangeLog for more information.

----------------------------------------------------------------------]]

--[[--------------------------------------------------------------------
-- Notes:
-- * based on luac.lua in the test directory of the 5.1.2 distribution
-- * usage: lua luac.lua file.lua
----------------------------------------------------------------------]]

------------------------------------------------------------------------
-- load and initialize the required modules
------------------------------------------------------------------------
local luaZ = {}
local luaY = {}
local luaX = {}
local luaP = {}
local luaU = {}
local luaK = {}
local size_size_t = 8


-- currently asserts are enabled because the codebase hasn't been tested
-- much (if you don't want asserts, just comment them out)
local function lua_assert(test)
	if not test then error("assertion failed!") end
end



-- dofile("lzio.lua")


------------------------------------------------------------------------
-- * reader() should return a string, or nil if nothing else to parse.
--   Additional data can be set only during stream initialization
-- * Readers are handled in lauxlib.c, see luaL_load(file|buffer|string)
-- * LUAL_BUFFERSIZE=BUFSIZ=512 in make_getF() (located in luaconf.h)
-- * Original Reader typedef:
--   const char * (*lua_Reader) (lua_State *L, void *ud, size_t *sz);
-- * This Lua chunk reader implementation:
--   returns string or nil, no arguments to function
------------------------------------------------------------------------

------------------------------------------------------------------------
-- create a chunk reader from a source string
------------------------------------------------------------------------
function luaZ:make_getS(buff)
	local b = buff
	return function() -- chunk reader anonymous function here
		if not b then return nil end
		local data = b
		b = nil
		return data
	end
end

------------------------------------------------------------------------
-- create a chunk reader from a source file
------------------------------------------------------------------------
-- function luaZ:make_getF(filename)
--   local LUAL_BUFFERSIZE = 512
--   local h = io.open(filename, "r")
--   if not h then return nil end
--   return function() -- chunk reader anonymous function here
--     if not h or io.type(h) == "closed file" then return nil end
--     local buff = h:read(LUAL_BUFFERSIZE)
--     if not buff then h:close(); h = nil end
--     return buff
--   end
-- end

function luaZ:make_getF(source)
	local LUAL_BUFFERSIZE = 512
	local pos = 1

	return function() -- chunk reader anonymous function here
		local buff = source:sub(pos, pos + LUAL_BUFFERSIZE - 1)
		pos = math.min(#source + 1, pos + LUAL_BUFFERSIZE)
		return buff
	end
end


------------------------------------------------------------------------
-- creates a zio input stream
-- returns the ZIO structure, z
------------------------------------------------------------------------
function luaZ:init(reader, data)
	if not reader then return end
	local z = {}
	z.reader = reader
	z.data = data or ""
	z.name = name
	-- set up additional data for reading
	if not data or data == "" then z.n = 0 else z.n = #data end
	z.p = 0
	return z
end

------------------------------------------------------------------------
-- fill up input buffer
------------------------------------------------------------------------
function luaZ:fill(z)
	local buff = z.reader()
	z.data = buff
	if not buff or buff == "" then return "EOZ" end
	z.n, z.p = #buff - 1, 1
	return string.sub(buff, 1, 1)
end

------------------------------------------------------------------------
-- get next character from the input stream
-- * local n, p are used to optimize code generation
------------------------------------------------------------------------
function luaZ:zgetc(z)
	local n, p = z.n, z.p + 1
	if n > 0 then
		z.n, z.p = n - 1, p
		return string.sub(z.data, p, p)
	else
		return self:fill(z)
	end
end





-- dofile("llex.lua")

-- FIRST_RESERVED is not required as tokens are manipulated as strings
-- TOKEN_LEN deleted; maximum length of a reserved word not needed

------------------------------------------------------------------------
-- "ORDER RESERVED" deleted; enumeration in one place: luaX.RESERVED
------------------------------------------------------------------------

-- terminal symbols denoted by reserved words: TK_AND to TK_WHILE
-- other terminal symbols: TK_NAME to TK_EOS
luaX.RESERVED = [[
TK_AND and
TK_BREAK break
TK_DO do
TK_ELSE else
TK_ELSEIF elseif
TK_END end
TK_FALSE false
TK_FOR for
TK_FUNCTION function
TK_IF if
TK_IN in
TK_LOCAL local
TK_NIL nil
TK_NOT not
TK_OR or
TK_REPEAT repeat
TK_RETURN return
TK_THEN then
TK_TRUE true
TK_UNTIL until
TK_WHILE while
TK_CONCAT ..
TK_DOTS ...
TK_EQ ==
TK_GE >=
TK_LE <=
TK_NE ~=
TK_NAME <name>
TK_NUMBER <number>
TK_STRING <string>
TK_EOS <eof>]]

-- NUM_RESERVED is not required; number of reserved words

--[[--------------------------------------------------------------------
-- Instead of passing seminfo, the Token struct (e.g. ls.t) is passed
-- so that lexer functions can use its table element, ls.t.seminfo
--
-- SemInfo (struct no longer needed, a mixed-type value is used)
--
-- Token (struct of ls.t and ls.lookahead):
--   token  -- token symbol
--   seminfo  -- semantics information
--
-- LexState (struct of ls; ls is initialized by luaX:setinput):
--   current  -- current character (charint)
--   linenumber  -- input line counter
--   lastline  -- line of last token 'consumed'
--   t  -- current token (table: struct Token)
--   lookahead  -- look ahead token (table: struct Token)
--   fs  -- 'FuncState' is private to the parser
--   L -- LuaState
--   z  -- input stream
--   buff  -- buffer for tokens
--   source  -- current source name
--   decpoint -- locale decimal point
--   nestlevel  -- level of nested non-terminals
----------------------------------------------------------------------]]

-- luaX.tokens (was luaX_tokens) is now a hash; see luaX:init

luaX.MAXSRC = 80
luaX.MAX_INT = 2147483645       -- constants from elsewhere (see above)
luaX.LUA_QS = "'%s'"
luaX.LUA_COMPAT_LSTR = 1
--luaX.MAX_SIZET = 4294967293

------------------------------------------------------------------------
-- initialize lexer
-- * original luaX_init has code to create and register token strings
-- * luaX.tokens: TK_* -> token
-- * luaX.enums:  token -> TK_* (used in luaX:llex)
------------------------------------------------------------------------
function luaX:init()
	local tokens, enums = {}, {}
	for v in string.gmatch(self.RESERVED, "[^\n]+") do
		local _, _, tok, str = string.find(v, "(%S+)%s+(%S+)")
		tokens[tok] = str
		enums[str] = tok
	end
	self.tokens = tokens
	self.enums = enums
end

------------------------------------------------------------------------
-- returns a suitably-formatted chunk name or id
-- * from lobject.c, used in llex.c and ldebug.c
-- * the result, out, is returned (was first argument)
------------------------------------------------------------------------
function luaX:chunkid(source, bufflen)
	local out
	local first = string.sub(source, 1, 1)
	if first == "=" then
		out = string.sub(source, 2, bufflen)  -- remove first char
	else  -- out = "source", or "...source"
		if first == "@" then
			source = string.sub(source, 2)  -- skip the '@'
			bufflen = bufflen - #" '...' "
			local l = #source
			out = ""
			if l > bufflen then
				source = string.sub(source, 1 + l - bufflen)  -- get last part of file name
				out = out.."..."
			end
			out = out..source
		else  -- out = [string "string"]
			local len = string.find(source, "[\n\r]")  -- stop at first newline
			len = len and (len - 1) or #source
			bufflen = bufflen - #(" [string \"...\"] ")
			if len > bufflen then len = bufflen end
			out = "[string \""
			if len < #source then  -- must truncate?
				out = out..string.sub(source, 1, len).."..."
			else
				out = out..source
			end
			out = out.."\"]"
		end
	end
	return out
end

--[[--------------------------------------------------------------------
-- Support functions for lexer
-- * all lexer errors eventually reaches lexerror:
		 syntaxerror -> lexerror
----------------------------------------------------------------------]]

------------------------------------------------------------------------
-- look up token and return keyword if found (also called by parser)
------------------------------------------------------------------------
function luaX:token2str(ls, token)
	if string.sub(token, 1, 3) ~= "TK_" then
		if string.find(token, "%c") then
			return string.format("char(%d)", string.byte(token))
		end
		return token
	else
		return self.tokens[token]
	end
end

------------------------------------------------------------------------
-- throws a lexer error
-- * txtToken has been made local to luaX:lexerror
-- * can't communicate LUA_ERRSYNTAX, so it is unimplemented
------------------------------------------------------------------------
function luaX:lexerror(ls, msg, token)
	local function txtToken(ls, token)
		if token == "TK_NAME" or
			token == "TK_STRING" or
			token == "TK_NUMBER" then
			return ls.buff
		else
			return self:token2str(ls, token)
		end
	end
	local buff = self:chunkid(ls.source, self.MAXSRC)
	local msg = string.format("%s:%d: %s", buff, ls.linenumber, msg)
	if token then
		msg = string.format("%s near "..self.LUA_QS, msg, txtToken(ls, token))
	end
	-- luaD_throw(ls->L, LUA_ERRSYNTAX)
	error(msg)
end

------------------------------------------------------------------------
-- throws a syntax error (mainly called by parser)
-- * ls.t.token has to be set by the function calling luaX:llex
--   (see luaX:next and luaX:lookahead elsewhere in this file)
------------------------------------------------------------------------
function luaX:syntaxerror(ls, msg)
	self:lexerror(ls, msg, ls.t.token)
end

------------------------------------------------------------------------
-- move on to next line
------------------------------------------------------------------------
function luaX:currIsNewline(ls)
	return ls.current == "\n" or ls.current == "\r"
end

function luaX:inclinenumber(ls)
	local old = ls.current
	-- lua_assert(currIsNewline(ls))
	self:nextc(ls)  -- skip '\n' or '\r'
	if self:currIsNewline(ls) and ls.current ~= old then
		self:nextc(ls)  -- skip '\n\r' or '\r\n'
	end
	ls.linenumber = ls.linenumber + 1
	if ls.linenumber >= self.MAX_INT then
		self:syntaxerror(ls, "chunk has too many lines")
	end
end

------------------------------------------------------------------------
-- initializes an input stream for lexing
-- * if ls (the lexer state) is passed as a table, then it is filled in,
--   otherwise it has to be retrieved as a return value
-- * LUA_MINBUFFER not used; buffer handling not required any more
------------------------------------------------------------------------
function luaX:setinput(L, ls, z, source)
	if not ls then ls = {} end  -- create struct
	if not ls.lookahead then ls.lookahead = {} end
	if not ls.t then ls.t = {} end
	ls.decpoint = "."
	ls.L = L
	ls.lookahead.token = "TK_EOS"  -- no look-ahead token
	ls.z = z
	ls.fs = nil
	ls.linenumber = 1
	ls.lastline = 1
	ls.source = source
	self:nextc(ls)  -- read first char
end

--[[--------------------------------------------------------------------
-- LEXICAL ANALYZER
----------------------------------------------------------------------]]

------------------------------------------------------------------------
-- checks if current character read is found in the set 'set'
------------------------------------------------------------------------
function luaX:check_next(ls, set)
	if not string.find(set, ls.current, 1, 1) then
		return false
	end
	self:save_and_next(ls)
	return true
end

------------------------------------------------------------------------
-- retrieve next token, checking the lookahead buffer if necessary
-- * note that the macro next(ls) in llex.c is now luaX:nextc
-- * utilized used in lparser.c (various places)
------------------------------------------------------------------------
function luaX:next(ls)
	ls.lastline = ls.linenumber
	if ls.lookahead.token ~= "TK_EOS" then  -- is there a look-ahead token?
		-- this must be copy-by-value
		ls.t.seminfo = ls.lookahead.seminfo  -- use this one
		ls.t.token = ls.lookahead.token
		ls.lookahead.token = "TK_EOS"  -- and discharge it
	else
		ls.t.token = self:llex(ls, ls.t)  -- read next token
	end
end

------------------------------------------------------------------------
-- fill in the lookahead buffer
-- * utilized used in lparser.c:constructor
------------------------------------------------------------------------
function luaX:lookahead(ls)
	-- lua_assert(ls.lookahead.token == "TK_EOS")
	ls.lookahead.token = self:llex(ls, ls.lookahead)
end

------------------------------------------------------------------------
-- gets the next character and returns it
-- * this is the next() macro in llex.c; see notes at the beginning
------------------------------------------------------------------------
function luaX:nextc(ls)
	local c = luaZ:zgetc(ls.z)
	ls.current = c
	return c
end

------------------------------------------------------------------------
-- saves the given character into the token buffer
-- * buffer handling code removed, not used in this implementation
-- * test for maximum token buffer length not used, makes things faster
------------------------------------------------------------------------

function luaX:save(ls, c)
	local buff = ls.buff
	-- if you want to use this, please uncomment luaX.MAX_SIZET further up
	--if #buff > self.MAX_SIZET then
	--  self:lexerror(ls, "lexical element too long")
	--end
	ls.buff = buff..c
end

------------------------------------------------------------------------
-- save current character into token buffer, grabs next character
-- * like luaX:nextc, returns the character read for convenience
------------------------------------------------------------------------
function luaX:save_and_next(ls)
	self:save(ls, ls.current)
	return self:nextc(ls)
end

------------------------------------------------------------------------
-- LUA_NUMBER
-- * luaX:read_numeral is the main lexer function to read a number
-- * luaX:str2d, luaX:buffreplace, luaX:trydecpoint are support functions
------------------------------------------------------------------------

------------------------------------------------------------------------
-- string to number converter (was luaO_str2d from lobject.c)
-- * returns the number, nil if fails (originally returns a boolean)
-- * conversion function originally lua_str2number(s,p), a macro which
--   maps to the strtod() function by default (from luaconf.h)
------------------------------------------------------------------------
function luaX:str2d(s)
	local result = tonumber(s)
	if result then return result end
	-- conversion failed
	if string.lower(string.sub(s, 1, 2)) == "0x" then  -- maybe an hexadecimal constant?
		result = tonumber(s, 16)
		if result then return result end  -- most common case
		-- Was: invalid trailing characters?
		-- In C, this function then skips over trailing spaces.
		-- true is returned if nothing else is found except for spaces.
		-- If there is still something else, then it returns a false.
		-- All this is not necessary using Lua's tonumber.
	end
	return nil
end

------------------------------------------------------------------------
-- single-character replacement, for locale-aware decimal points
------------------------------------------------------------------------
function luaX:buffreplace(ls, from, to)
	local result, buff = "", ls.buff
	for p = 1, #buff do
		local c = string.sub(buff, p, p)
		if c == from then c = to end
		result = result..c
	end
	ls.buff = result
end

------------------------------------------------------------------------
-- Attempt to convert a number by translating '.' decimal points to
-- the decimal point character used by the current locale. This is not
-- needed in Yueliang as Lua's tonumber() is already locale-aware.
-- Instead, the code is here in case the user implements localeconv().
------------------------------------------------------------------------
function luaX:trydecpoint(ls, Token)
	-- format error: try to update decimal point separator
	local old = ls.decpoint
	-- translate the following to Lua if you implement localeconv():
	-- struct lconv *cv = localeconv();
	-- ls->decpoint = (cv ? cv->decimal_point[0] : '.');
	self:buffreplace(ls, old, ls.decpoint)  -- try updated decimal separator
	local seminfo = self:str2d(ls.buff)
	Token.seminfo = seminfo
	if not seminfo then
		-- format error with correct decimal point: no more options
		self:buffreplace(ls, ls.decpoint, ".")  -- undo change (for error message)
		self:lexerror(ls, "malformed number", "TK_NUMBER")
	end
end

------------------------------------------------------------------------
-- main number conversion function
-- * "^%w$" needed in the scan in order to detect "EOZ"
------------------------------------------------------------------------
function luaX:read_numeral(ls, Token)
	-- lua_assert(string.find(ls.current, "%d"))
	repeat
		self:save_and_next(ls)
	until string.find(ls.current, "%D") and ls.current ~= "."
	if self:check_next(ls, "Ee") then  -- 'E'?
		self:check_next(ls, "+-")  -- optional exponent sign
	end
	while string.find(ls.current, "^%w$") or ls.current == "_" do
		self:save_and_next(ls)
	end
	self:buffreplace(ls, ".", ls.decpoint)  -- follow locale for decimal point
	local seminfo = self:str2d(ls.buff)
	Token.seminfo = seminfo
	if not seminfo then  -- format error?
		self:trydecpoint(ls, Token) -- try to update decimal point separator
	end
end

------------------------------------------------------------------------
-- count separators ("=") in a long string delimiter
-- * used by luaX:read_long_string
------------------------------------------------------------------------
function luaX:skip_sep(ls)
	local count = 0
	local s = ls.current
	-- lua_assert(s == "[" or s == "]")
	self:save_and_next(ls)
	while ls.current == "=" do
		self:save_and_next(ls)
		count = count + 1
	end
	return (ls.current == s) and count or (-count) - 1
end

------------------------------------------------------------------------
-- reads a long string or long comment
------------------------------------------------------------------------
function luaX:read_long_string(ls, Token, sep)
	local cont = 0
	self:save_and_next(ls)  -- skip 2nd '['
	if self:currIsNewline(ls) then  -- string starts with a newline?
		self:inclinenumber(ls)  -- skip it
	end
	while true do
		local c = ls.current
		if c == "EOZ" then
			self:lexerror(ls, Token and "unfinished long string" or
				"unfinished long comment", "TK_EOS")
		elseif c == "[" then
			--# compatibility code start
			if self.LUA_COMPAT_LSTR then
				if self:skip_sep(ls) == sep then
					self:save_and_next(ls)  -- skip 2nd '['
					cont = cont + 1
					--# compatibility code start
					if self.LUA_COMPAT_LSTR == 1 then
						if sep == 0 then
							self:lexerror(ls, "nesting of [[...]] is deprecated", "[")
						end
					end
					--# compatibility code end
				end
			end
			--# compatibility code end
		elseif c == "]" then
			if self:skip_sep(ls) == sep then
				self:save_and_next(ls)  -- skip 2nd ']'
				--# compatibility code start
				if self.LUA_COMPAT_LSTR and self.LUA_COMPAT_LSTR == 2 then
					cont = cont - 1
					if sep == 0 and cont >= 0 then break end
				end
				--# compatibility code end
				break
			end
		elseif self:currIsNewline(ls) then
			self:save(ls, "\n")
			self:inclinenumber(ls)
			if not Token then ls.buff = "" end -- avoid wasting space
		else  -- default
			if Token then
				self:save_and_next(ls)
			else
				self:nextc(ls)
			end
		end--if c
	end--while
	if Token then
		local p = 3 + sep
		Token.seminfo = string.sub(ls.buff, p, -p)
	end
end

------------------------------------------------------------------------
-- reads a string
-- * has been restructured significantly compared to the original C code
------------------------------------------------------------------------

function luaX:read_string(ls, del, Token)
	self:save_and_next(ls)
	while ls.current ~= del do
		local c = ls.current
		if c == "EOZ" then
			self:lexerror(ls, "unfinished string", "TK_EOS")
		elseif self:currIsNewline(ls) then
			self:lexerror(ls, "unfinished string", "TK_STRING")
		elseif c == "\\" then
			c = self:nextc(ls)  -- do not save the '\'
			if self:currIsNewline(ls) then  -- go through
				self:save(ls, "\n")
				self:inclinenumber(ls)
			elseif c ~= "EOZ" then -- will raise an error next loop
				-- escapes handling greatly simplified here:
				local i = string.find("abfnrtv", c, 1, 1)
				if i then
					self:save(ls, string.sub("\a\b\f\n\r\t\v", i, i))
					self:nextc(ls)
				elseif not string.find(c, "%d") then
					self:save_and_next(ls)  -- handles \\, \", \', and \?
				else  -- \xxx
					c, i = 0, 0
					repeat
						c = 10 * c + ls.current
						self:nextc(ls)
						i = i + 1
					until i >= 3 or not string.find(ls.current, "%d")
					if c > 255 then  -- UCHAR_MAX
						self:lexerror(ls, "escape sequence too large", "TK_STRING")
					end
					self:save(ls, string.char(c))
				end
			end
		else
			self:save_and_next(ls)
		end--if c
	end--while
	self:save_and_next(ls)  -- skip delimiter
	Token.seminfo = string.sub(ls.buff, 2, -2)
end

------------------------------------------------------------------------
-- main lexer function
------------------------------------------------------------------------
function luaX:llex(ls, Token)
	ls.buff = ""
	while true do
		local c = ls.current
		----------------------------------------------------------------
		if self:currIsNewline(ls) then
			self:inclinenumber(ls)
			----------------------------------------------------------------
		elseif c == "-" then
			c = self:nextc(ls)
			if c ~= "-" then return "-" end
			-- else is a comment
			local sep = -1
			if self:nextc(ls) == '[' then
				sep = self:skip_sep(ls)
				ls.buff = ""  -- 'skip_sep' may dirty the buffer
			end
			if sep >= 0 then
				self:read_long_string(ls, nil, sep)  -- long comment
				ls.buff = ""
			else  -- else short comment
				while not self:currIsNewline(ls) and ls.current ~= "EOZ" do
					self:nextc(ls)
				end
			end
			----------------------------------------------------------------
		elseif c == "[" then
			local sep = self:skip_sep(ls)
			if sep >= 0 then
				self:read_long_string(ls, Token, sep)
				return "TK_STRING"
			elseif sep == -1 then
				return "["
			else
				self:lexerror(ls, "invalid long string delimiter", "TK_STRING")
			end
			----------------------------------------------------------------
		elseif c == "=" then
			c = self:nextc(ls)
			if c ~= "=" then return "="
			else self:nextc(ls); return "TK_EQ" end
			----------------------------------------------------------------
		elseif c == "<" then
			c = self:nextc(ls)
			if c ~= "=" then return "<"
			else self:nextc(ls); return "TK_LE" end
			----------------------------------------------------------------
		elseif c == ">" then
			c = self:nextc(ls)
			if c ~= "=" then return ">"
			else self:nextc(ls); return "TK_GE" end
			----------------------------------------------------------------
		elseif c == "~" then
			c = self:nextc(ls)
			if c ~= "=" then return "~"
			else self:nextc(ls); return "TK_NE" end
			----------------------------------------------------------------
		elseif c == "\"" or c == "'" then
			self:read_string(ls, c, Token)
			return "TK_STRING"
			----------------------------------------------------------------
		elseif c == "." then
			c = self:save_and_next(ls)
			if self:check_next(ls, ".") then
				if self:check_next(ls, ".") then
					return "TK_DOTS"   -- ...
				else return "TK_CONCAT"   -- ..
				end
			elseif not string.find(c, "%d") then
				return "."
			else
				self:read_numeral(ls, Token)
				return "TK_NUMBER"
			end
			----------------------------------------------------------------
		elseif c == "EOZ" then
			return "TK_EOS"
			----------------------------------------------------------------
		else  -- default
			if string.find(c, "%s") then
				-- lua_assert(self:currIsNewline(ls))
				self:nextc(ls)
			elseif string.find(c, "%d") then
				self:read_numeral(ls, Token)
				return "TK_NUMBER"
			elseif string.find(c, "[_%a]") then
				-- identifier or reserved word
				repeat
					c = self:save_and_next(ls)
				until c == "EOZ" or not string.find(c, "[_%w]")
				local ts = ls.buff
				local tok = self.enums[ts]
				if tok then return tok end  -- reserved word?
				Token.seminfo = ts
				return "TK_NAME"
			else
				self:nextc(ls)
				return c  -- single-char tokens (+ - / ...)
			end
			----------------------------------------------------------------
		end--if c
	end--while
end





--dofile("lopcodes.lua")


--[[
===========================================================================
	We assume that instructions are unsigned numbers.
	All instructions have an opcode in the first 6 bits.
	Instructions can have the following fields:
				'A' : 8 bits
				'B' : 9 bits
				'C' : 9 bits
				'Bx' : 18 bits ('B' and 'C' together)
				'sBx' : signed Bx

	A signed argument is represented in excess K; that is, the number
	value is the unsigned value minus K. K is exactly the maximum value
	for that argument (so that -max is represented by 0, and +max is
	represented by 2*max), which is half the maximum for the corresponding
	unsigned argument.
===========================================================================
--]]

luaP.OpMode = { iABC = 0, iABx = 1, iAsBx = 2 }  -- basic instruction format

------------------------------------------------------------------------
-- size and position of opcode arguments.
-- * WARNING size and position is hard-coded elsewhere in this script
------------------------------------------------------------------------
luaP.SIZE_C  = 9
luaP.SIZE_B  = 9
luaP.SIZE_Bx = luaP.SIZE_C + luaP.SIZE_B
luaP.SIZE_A  = 8

luaP.SIZE_OP = 6

luaP.POS_OP = 0
luaP.POS_A  = luaP.POS_OP + luaP.SIZE_OP
luaP.POS_C  = luaP.POS_A + luaP.SIZE_A
luaP.POS_B  = luaP.POS_C + luaP.SIZE_C
luaP.POS_Bx = luaP.POS_C

------------------------------------------------------------------------
-- limits for opcode arguments.
-- we use (signed) int to manipulate most arguments,
-- so they must fit in LUAI_BITSINT-1 bits (-1 for sign)
------------------------------------------------------------------------
-- removed "#if SIZE_Bx < BITS_INT-1" test, assume this script is
-- running on a Lua VM with double or int as LUA_NUMBER

luaP.MAXARG_Bx  = math.ldexp(1, luaP.SIZE_Bx) - 1
luaP.MAXARG_sBx = math.floor(luaP.MAXARG_Bx / 2)  -- 'sBx' is signed

luaP.MAXARG_A = math.ldexp(1, luaP.SIZE_A) - 1
luaP.MAXARG_B = math.ldexp(1, luaP.SIZE_B) - 1
luaP.MAXARG_C = math.ldexp(1, luaP.SIZE_C) - 1

-- creates a mask with 'n' 1 bits at position 'p'
-- MASK1(n,p) deleted, not required
-- creates a mask with 'n' 0 bits at position 'p'
-- MASK0(n,p) deleted, not required

--[[--------------------------------------------------------------------
	Visual representation for reference:

	 31    |    |     |            0      bit position
		+-----+-----+-----+----------+
		|  B  |  C  |  A  |  Opcode  |      iABC format
		+-----+-----+-----+----------+
		-  9  -  9  -  8  -    6     -      field sizes
		+-----+-----+-----+----------+
		|   [s]Bx   |  A  |  Opcode  |      iABx | iAsBx format
		+-----+-----+-----+----------+

----------------------------------------------------------------------]]

------------------------------------------------------------------------
-- the following macros help to manipulate instructions
-- * changed to a table object representation, very clean compared to
--   the [nightmare] alternatives of using a number or a string
-- * Bx is a separate element from B and C, since there is never a need
--   to split Bx in the parser or code generator
------------------------------------------------------------------------

-- these accept or return opcodes in the form of string names
function luaP:GET_OPCODE(i) return self.ROpCode[i.OP] end
function luaP:SET_OPCODE(i, o) i.OP = self.OpCode[o] end

function luaP:GETARG_A(i) return i.A end
function luaP:SETARG_A(i, u) i.A = u end

function luaP:GETARG_B(i) return i.B end
function luaP:SETARG_B(i, b) i.B = b end

function luaP:GETARG_C(i) return i.C end
function luaP:SETARG_C(i, b) i.C = b end

function luaP:GETARG_Bx(i) return i.Bx end
function luaP:SETARG_Bx(i, b) i.Bx = b end

function luaP:GETARG_sBx(i) return i.Bx - self.MAXARG_sBx end
function luaP:SETARG_sBx(i, b) i.Bx = b + self.MAXARG_sBx end

function luaP:CREATE_ABC(o,a,b,c)
	return {OP = self.OpCode[o], A = a, B = b, C = c}
end

function luaP:CREATE_ABx(o,a,bc)
	return {OP = self.OpCode[o], A = a, Bx = bc}
end

------------------------------------------------------------------------
-- create an instruction from a number (for OP_SETLIST)
------------------------------------------------------------------------
function luaP:CREATE_Inst(c)
	local o = c % 64
	c = (c - o) / 64
	local a = c % 256
	c = (c - a) / 256
	return self:CREATE_ABx(o, a, c)
end

------------------------------------------------------------------------
-- returns a 4-char string little-endian encoded form of an instruction
------------------------------------------------------------------------
function luaP:Instruction(i)
	if i.Bx then
		-- change to OP/A/B/C format
		i.C = i.Bx % 512
		i.B = (i.Bx - i.C) / 512
	end
	local I = i.A * 64 + i.OP
	local c0 = I % 256
	I = i.C * 64 + (I - c0) / 256  -- 6 bits of A left
	local c1 = I % 256
	I = i.B * 128 + (I - c1) / 256  -- 7 bits of C left
	local c2 = I % 256
	local c3 = (I - c2) / 256
	return string.char(c0, c1, c2, c3)
end

------------------------------------------------------------------------
-- decodes a 4-char little-endian string into an instruction struct
------------------------------------------------------------------------
function luaP:DecodeInst(x)
	local byte = string.byte
	local i = {}
	local I = byte(x, 1)
	local op = I % 64
	i.OP = op
	I = byte(x, 2) * 4 + (I - op) / 64  -- 2 bits of c0 left
	local a = I % 256
	i.A = a
	I = byte(x, 3) * 4 + (I - a) / 256  -- 2 bits of c1 left
	local c = I % 512
	i.C = c
	i.B = byte(x, 4) * 2 + (I - c) / 512 -- 1 bits of c2 left
	local opmode = self.OpMode[tonumber(string.sub(self.opmodes[op + 1], 7, 7))]
	if opmode ~= "iABC" then
		i.Bx = i.B * 512 + i.C
	end
	return i
end

------------------------------------------------------------------------
-- Macros to operate RK indices
-- * these use arithmetic instead of bit ops
------------------------------------------------------------------------

-- this bit 1 means constant (0 means register)
luaP.BITRK = math.ldexp(1, luaP.SIZE_B - 1)

-- test whether value is a constant
function luaP:ISK(x) return x >= self.BITRK end

-- gets the index of the constant
function luaP:INDEXK(r) return x - self.BITRK end

luaP.MAXINDEXRK = luaP.BITRK - 1

-- code a constant index as a RK value
function luaP:RKASK(x) return x + self.BITRK end

------------------------------------------------------------------------
-- invalid register that fits in 8 bits
------------------------------------------------------------------------
luaP.NO_REG = luaP.MAXARG_A

------------------------------------------------------------------------
-- R(x) - register
-- Kst(x) - constant (in constant table)
-- RK(x) == if ISK(x) then Kst(INDEXK(x)) else R(x)
------------------------------------------------------------------------

------------------------------------------------------------------------
-- grep "ORDER OP" if you change these enums
------------------------------------------------------------------------

--[[--------------------------------------------------------------------
Lua virtual machine opcodes (enum OpCode):
------------------------------------------------------------------------
name          args    description
------------------------------------------------------------------------
OP_MOVE       A B     R(A) := R(B)
OP_LOADK      A Bx    R(A) := Kst(Bx)
OP_LOADBOOL   A B C   R(A) := (Bool)B; if (C) pc++
OP_LOADNIL    A B     R(A) := ... := R(B) := nil
OP_GETUPVAL   A B     R(A) := UpValue[B]
OP_GETGLOBAL  A Bx    R(A) := Gbl[Kst(Bx)]
OP_GETTABLE   A B C   R(A) := R(B)[RK(C)]
OP_SETGLOBAL  A Bx    Gbl[Kst(Bx)] := R(A)
OP_SETUPVAL   A B     UpValue[B] := R(A)
OP_SETTABLE   A B C   R(A)[RK(B)] := RK(C)
OP_NEWTABLE   A B C   R(A) := {} (size = B,C)
OP_SELF       A B C   R(A+1) := R(B); R(A) := R(B)[RK(C)]
OP_ADD        A B C   R(A) := RK(B) + RK(C)
OP_SUB        A B C   R(A) := RK(B) - RK(C)
OP_MUL        A B C   R(A) := RK(B) * RK(C)
OP_DIV        A B C   R(A) := RK(B) / RK(C)
OP_MOD        A B C   R(A) := RK(B) % RK(C)
OP_POW        A B C   R(A) := RK(B) ^ RK(C)
OP_UNM        A B     R(A) := -R(B)
OP_NOT        A B     R(A) := not R(B)
OP_LEN        A B     R(A) := length of R(B)
OP_CONCAT     A B C   R(A) := R(B).. ... ..R(C)
OP_JMP        sBx     pc+=sBx
OP_EQ         A B C   if ((RK(B) == RK(C)) ~= A) then pc++
OP_LT         A B C   if ((RK(B) <  RK(C)) ~= A) then pc++
OP_LE         A B C   if ((RK(B) <= RK(C)) ~= A) then pc++
OP_TEST       A C     if not (R(A) <=> C) then pc++
OP_TESTSET    A B C   if (R(B) <=> C) then R(A) := R(B) else pc++
OP_CALL       A B C   R(A), ... ,R(A+C-2) := R(A)(R(A+1), ... ,R(A+B-1))
OP_TAILCALL   A B C   return R(A)(R(A+1), ... ,R(A+B-1))
OP_RETURN     A B     return R(A), ... ,R(A+B-2)  (see note)
OP_FORLOOP    A sBx   R(A)+=R(A+2);
											if R(A) <?= R(A+1) then { pc+=sBx; R(A+3)=R(A) }
OP_FORPREP    A sBx   R(A)-=R(A+2); pc+=sBx
OP_TFORLOOP   A C     R(A+3), ... ,R(A+2+C) := R(A)(R(A+1), R(A+2));
											if R(A+3) ~= nil then R(A+2)=R(A+3) else pc++
OP_SETLIST    A B C   R(A)[(C-1)*FPF+i] := R(A+i), 1 <= i <= B
OP_CLOSE      A       close all variables in the stack up to (>=) R(A)
OP_CLOSURE    A Bx    R(A) := closure(KPROTO[Bx], R(A), ... ,R(A+n))
OP_VARARG     A B     R(A), R(A+1), ..., R(A+B-1) = vararg
----------------------------------------------------------------------]]

luaP.opnames = {}  -- opcode names
luaP.OpCode = {}   -- lookup name -> number
luaP.ROpCode = {}  -- lookup number -> name

------------------------------------------------------------------------
-- ORDER OP
------------------------------------------------------------------------
local i = 0
for v in string.gmatch([[
MOVE LOADK LOADBOOL LOADNIL GETUPVAL
GETGLOBAL GETTABLE SETGLOBAL SETUPVAL SETTABLE
NEWTABLE SELF ADD SUB MUL
DIV MOD POW UNM NOT
LEN CONCAT JMP EQ LT
LE TEST TESTSET CALL TAILCALL
RETURN FORLOOP FORPREP TFORLOOP SETLIST
CLOSE CLOSURE VARARG
]], "%S+") do
	local n = "OP_"..v
	luaP.opnames[i] = v
	luaP.OpCode[n] = i
	luaP.ROpCode[i] = n
	i = i + 1
end
luaP.NUM_OPCODES = i

--[[
===========================================================================
	Notes:
	(*) In OP_CALL, if (B == 0) then B = top. C is the number of returns - 1,
			and can be 0: OP_CALL then sets 'top' to last_result+1, so
			next open instruction (OP_CALL, OP_RETURN, OP_SETLIST) may use 'top'.
	(*) In OP_VARARG, if (B == 0) then use actual number of varargs and
			set top (like in OP_CALL with C == 0).
	(*) In OP_RETURN, if (B == 0) then return up to 'top'
	(*) In OP_SETLIST, if (B == 0) then B = 'top';
			if (C == 0) then next 'instruction' is real C
	(*) For comparisons, A specifies what condition the test should accept
			(true or false).
	(*) All 'skips' (pc++) assume that next instruction is a jump
===========================================================================
--]]

--[[--------------------------------------------------------------------
	masks for instruction properties. The format is:
	bits 0-1: op mode
	bits 2-3: C arg mode
	bits 4-5: B arg mode
	bit 6: instruction set register A
	bit 7: operator is a test

	for OpArgMask:
	OpArgN - argument is not used
	OpArgU - argument is used
	OpArgR - argument is a register or a jump offset
	OpArgK - argument is a constant or register/constant
----------------------------------------------------------------------]]

-- was enum OpArgMask
luaP.OpArgMask = { OpArgN = 0, OpArgU = 1, OpArgR = 2, OpArgK = 3 }

------------------------------------------------------------------------
-- e.g. to compare with symbols, luaP:getOpMode(...) == luaP.OpCode.iABC
-- * accepts opcode parameter as strings, e.g. "OP_MOVE"
------------------------------------------------------------------------

function luaP:getOpMode(m)
	return self.opmodes[self.OpCode[m]] % 4
end

function luaP:getBMode(m)
	return math.floor(self.opmodes[self.OpCode[m]] / 16) % 4
end

function luaP:getCMode(m)
	return math.floor(self.opmodes[self.OpCode[m]] / 4) % 4
end

function luaP:testAMode(m)
	return math.floor(self.opmodes[self.OpCode[m]] / 64) % 2
end

function luaP:testTMode(m)
	return math.floor(self.opmodes[self.OpCode[m]] / 128)
end

-- luaP_opnames[] is set above, as the luaP.opnames table

-- number of list items to accumulate before a SETLIST instruction
luaP.LFIELDS_PER_FLUSH = 50

------------------------------------------------------------------------
-- build instruction properties array
-- * deliberately coded to look like the C equivalent
------------------------------------------------------------------------
local function opmode(t, a, b, c, m)
	local luaP = luaP
	return t * 128 + a * 64 +
		luaP.OpArgMask[b] * 16 + luaP.OpArgMask[c] * 4 + luaP.OpMode[m]
end

-- ORDER OP
luaP.opmodes = {
	-- T A B C mode opcode
	opmode(0, 1, "OpArgK", "OpArgN", "iABx"),     -- OP_LOADK
	opmode(0, 1, "OpArgU", "OpArgU", "iABC"),     -- OP_LOADBOOL
	opmode(0, 1, "OpArgR", "OpArgN", "iABC"),     -- OP_LOADNIL
	opmode(0, 1, "OpArgU", "OpArgN", "iABC"),     -- OP_GETUPVAL
	opmode(0, 1, "OpArgK", "OpArgN", "iABx"),     -- OP_GETGLOBAL
	opmode(0, 1, "OpArgR", "OpArgK", "iABC"),     -- OP_GETTABLE
	opmode(0, 0, "OpArgK", "OpArgN", "iABx"),     -- OP_SETGLOBAL
	opmode(0, 0, "OpArgU", "OpArgN", "iABC"),     -- OP_SETUPVAL
	opmode(0, 0, "OpArgK", "OpArgK", "iABC"),     -- OP_SETTABLE
	opmode(0, 1, "OpArgU", "OpArgU", "iABC"),     -- OP_NEWTABLE
	opmode(0, 1, "OpArgR", "OpArgK", "iABC"),     -- OP_SELF
	opmode(0, 1, "OpArgK", "OpArgK", "iABC"),     -- OP_ADD
	opmode(0, 1, "OpArgK", "OpArgK", "iABC"),     -- OP_SUB
	opmode(0, 1, "OpArgK", "OpArgK", "iABC"),     -- OP_MUL
	opmode(0, 1, "OpArgK", "OpArgK", "iABC"),     -- OP_DIV
	opmode(0, 1, "OpArgK", "OpArgK", "iABC"),     -- OP_MOD
	opmode(0, 1, "OpArgK", "OpArgK", "iABC"),     -- OP_POW
	opmode(0, 1, "OpArgR", "OpArgN", "iABC"),     -- OP_UNM
	opmode(0, 1, "OpArgR", "OpArgN", "iABC"),     -- OP_NOT
	opmode(0, 1, "OpArgR", "OpArgN", "iABC"),     -- OP_LEN
	opmode(0, 1, "OpArgR", "OpArgR", "iABC"),     -- OP_CONCAT
	opmode(0, 0, "OpArgR", "OpArgN", "iAsBx"),    -- OP_JMP
	opmode(1, 0, "OpArgK", "OpArgK", "iABC"),     -- OP_EQ
	opmode(1, 0, "OpArgK", "OpArgK", "iABC"),     -- OP_LT
	opmode(1, 0, "OpArgK", "OpArgK", "iABC"),     -- OP_LE
	opmode(1, 1, "OpArgR", "OpArgU", "iABC"),     -- OP_TEST
	opmode(1, 1, "OpArgR", "OpArgU", "iABC"),     -- OP_TESTSET
	opmode(0, 1, "OpArgU", "OpArgU", "iABC"),     -- OP_CALL
	opmode(0, 1, "OpArgU", "OpArgU", "iABC"),     -- OP_TAILCALL
	opmode(0, 0, "OpArgU", "OpArgN", "iABC"),     -- OP_RETURN
	opmode(0, 1, "OpArgR", "OpArgN", "iAsBx"),    -- OP_FORLOOP
	opmode(0, 1, "OpArgR", "OpArgN", "iAsBx"),    -- OP_FORPREP
	opmode(1, 0, "OpArgN", "OpArgU", "iABC"),     -- OP_TFORLOOP
	opmode(0, 0, "OpArgU", "OpArgU", "iABC"),     -- OP_SETLIST
	opmode(0, 0, "OpArgN", "OpArgN", "iABC"),     -- OP_CLOSE
	opmode(0, 1, "OpArgU", "OpArgN", "iABx"),     -- OP_CLOSURE
	opmode(0, 1, "OpArgU", "OpArgN", "iABC"),     -- OP_VARARG
}
-- an awkward way to set a zero-indexed table...
luaP.opmodes[0] =
	opmode(0, 1, "OpArgR", "OpArgN", "iABC")      -- OP_MOVE



--dofile("ldump.lua")

--requires luaP

-- mark for precompiled code ('<esc>Lua') (from lua.h)
luaU.LUA_SIGNATURE = "\27Lua"

-- constants used by dumper (from lua.h)
luaU.LUA_TNUMBER  = 3
luaU.LUA_TSTRING  = 4
luaU.LUA_TNIL     = 0
luaU.LUA_TBOOLEAN = 1
luaU.LUA_TNONE    = -1

-- constants for header of binary files (from lundump.h)
luaU.LUAC_VERSION    = 0x51     -- this is Lua 5.1
luaU.LUAC_FORMAT     = 0        -- this is the official format
luaU.LUAC_HEADERSIZE = 12       -- size of header of binary files

--[[--------------------------------------------------------------------
-- Additional functions to handle chunk writing
-- * to use make_setS and make_setF, see test_ldump.lua elsewhere
----------------------------------------------------------------------]]

------------------------------------------------------------------------
-- create a chunk writer that writes to a string
-- * returns the writer function and a table containing the string
-- * to get the final result, look in buff.data
------------------------------------------------------------------------
function luaU:make_setS()
	local buff = {}
	buff.data = ""
	local writer =
		function(s, buff)  -- chunk writer
			if not s then return 0 end
			buff.data = buff.data..s
			-- print (#buff.data, #s, string.byte(s,1,1), s)
			return 0
		end
	return writer, buff
end

------------------------------------------------------------------------
-- create a chunk writer that writes to a file
-- * returns the writer function and a table containing the file handle
-- * if a nil is passed, then writer should close the open file
------------------------------------------------------------------------
function luaU:make_setF(filename)
	local buff = {}
	buff.h = io.open(filename, "wb")
	if not buff.h then return nil end
	local writer =
		function(s, buff)  -- chunk writer
			if not buff.h then return 0 end
			if not s then
			if buff.h:close() then return 0 end
		else
			if buff.h:write(s) then return 0 end
		end
			return 1
		end
	return writer, buff
end

------------------------------------------------------------------------
-- works like the lobject.h version except that TObject used in these
-- scripts only has a 'value' field, no 'tt' field (native types used)
------------------------------------------------------------------------
function luaU:ttype(o)
	local tt = type(o.value)
	if tt == "number" then return self.LUA_TNUMBER
	elseif tt == "string" then return self.LUA_TSTRING
	elseif tt == "nil" then return self.LUA_TNIL
	elseif tt == "boolean" then return self.LUA_TBOOLEAN
	else
		return self.LUA_TNONE  -- the rest should not appear
	end
end

-----------------------------------------------------------------------
-- converts a IEEE754 double number to an 8-byte little-endian string
-- * luaU:from_double() and luaU:from_int() are adapted from ChunkBake
-- * supports +/- Infinity, but not denormals or NaNs
-----------------------------------------------------------------------
function luaU:from_double(x)
	local function grab_byte(v)
		local c = v % 256
		return (v - c) / 256, string.char(c)
	end
	local sign = 0
	if x < 0 then sign = 1; x = -x end
	local mantissa, exponent = math.frexp(x)
	if x == 0 then -- zero
		mantissa, exponent = 0, 0
	elseif x == 1/0 then
		mantissa, exponent = 0, 2047
	else
		mantissa = (mantissa * 2 - 1) * math.ldexp(0.5, 53)
		exponent = exponent + 1022
	end
	local v, byte = "" -- convert to bytes
	x = math.floor(mantissa)
	for i = 1,6 do
		x, byte = grab_byte(x); v = v..byte -- 47:0
	end
	x, byte = grab_byte(exponent * 16 + x); v = v..byte -- 55:48
	x, byte = grab_byte(sign * 128 + x); v = v..byte -- 63:56
	return v
end

-----------------------------------------------------------------------
-- converts a number to a little-endian 32-bit integer string
-- * input value assumed to not overflow, can be signed/unsigned
-----------------------------------------------------------------------
function luaU:from_int(x)
	local v = ""
	x = math.floor(x)
	if x < 0 then x = 4294967296 + x end  -- ULONG_MAX+1
	for i = 1, 4 do
		local c = x % 256
		v = v..string.char(c); x = math.floor(x / 256)
	end
	return v
end

--[[--------------------------------------------------------------------
-- Functions to make a binary chunk
-- * many functions have the size parameter removed, since output is
--   in the form of a string and some sizes are implicit or hard-coded
----------------------------------------------------------------------]]

--[[--------------------------------------------------------------------
-- struct DumpState:
--   L  -- lua_State (not used in this script)
--   writer  -- lua_Writer (chunk writer function)
--   data  -- void* (chunk writer context or data already written)
--   strip  -- if true, don't write any debug information
--   status  -- if non-zero, an error has occured
----------------------------------------------------------------------]]

------------------------------------------------------------------------
-- dumps a block of bytes
-- * lua_unlock(D.L), lua_lock(D.L) unused
------------------------------------------------------------------------
function luaU:DumpBlock(b, D)
	if D.status == 0 then
		-- lua_unlock(D->L);
		D.status = D.write(b, D.data)
		-- lua_lock(D->L);
	end
end

------------------------------------------------------------------------
-- dumps a char
------------------------------------------------------------------------
function luaU:DumpChar(y, D)
	self:DumpBlock(string.char(y), D)
end

------------------------------------------------------------------------
-- dumps a 32-bit signed or unsigned integer (for int) (hard-coded)
------------------------------------------------------------------------
function luaU:DumpInt(x, D)
	self:DumpBlock(self:from_int(x), D)
end

------------------------------------------------------------------------
-- dumps a 32-bit signed or unsigned integer (for int) (hard-coded)
------------------------------------------------------------------------
function luaU:DumpSizeT(x, D)
	self:DumpBlock(self:from_int(x), D)
	if size_size_t == 8 then
		self:DumpBlock(self:from_int(0), D)
	end
end

------------------------------------------------------------------------
-- dumps a lua_Number (hard-coded as a double)
------------------------------------------------------------------------
function luaU:DumpNumber(x, D)
	self:DumpBlock(self:from_double(x), D)
end

------------------------------------------------------------------------
-- dumps a Lua string (size type is hard-coded)
------------------------------------------------------------------------
function luaU:DumpString(s, D)
	if s == nil then
		self:DumpSizeT(0, D)
	else
		s = s.."\0"  -- include trailing '\0'
		self:DumpSizeT(#s, D)
		self:DumpBlock(s, D)
	end
end

------------------------------------------------------------------------
-- dumps instruction block from function prototype
------------------------------------------------------------------------
function luaU:DumpCode(f, D)
	local n = f.sizecode
	--was DumpVector
	self:DumpInt(n, D)
	for i = 0, n - 1 do
		self:DumpBlock(luaP:Instruction(f.code[i]), D)
	end
end

------------------------------------------------------------------------
-- dump constant pool from function prototype
-- * bvalue(o), nvalue(o) and rawtsvalue(o) macros removed
------------------------------------------------------------------------
function luaU:DumpConstants(f, D)
	local n = f.sizek
	self:DumpInt(n, D)
	for i = 0, n - 1 do
		local o = f.k[i]  -- TValue
		local tt = self:ttype(o)
		self:DumpChar(tt, D)
		if tt == self.LUA_TNIL then
		elseif tt == self.LUA_TBOOLEAN then
			self:DumpChar(o.value and 1 or 0, D)
		elseif tt == self.LUA_TNUMBER then
			self:DumpNumber(o.value, D)
		elseif tt == self.LUA_TSTRING then
			self:DumpString(o.value, D)
		else
			--lua_assert(0)  -- cannot happen
		end
	end
	n = f.sizep
	self:DumpInt(n, D)
	for i = 0, n - 1 do
		self:DumpFunction(f.p[i], f.source, D)
	end
end

------------------------------------------------------------------------
-- dump debug information
------------------------------------------------------------------------
function luaU:DumpDebug(f, D)
	local n
	n = D.strip and 0 or f.sizelineinfo           -- dump line information
	--was DumpVector
	self:DumpInt(n, D)
	for i = 0, n - 1 do
		self:DumpInt(f.lineinfo[i], D)
	end
	n = D.strip and 0 or f.sizelocvars            -- dump local information
	self:DumpInt(n, D)
	for i = 0, n - 1 do
		self:DumpString(f.locvars[i].varname, D)
		self:DumpInt(f.locvars[i].startpc, D)
		self:DumpInt(f.locvars[i].endpc, D)
	end
	n = D.strip and 0 or f.sizeupvalues           -- dump upvalue information
	self:DumpInt(n, D)
	for i = 0, n - 1 do
		self:DumpString(f.upvalues[i], D)
	end
end

------------------------------------------------------------------------
-- dump child function prototypes from function prototype
------------------------------------------------------------------------
function luaU:DumpFunction(f, p, D)
	local source = f.source
	if source == p or D.strip then source = nil end
	self:DumpString(source, D)
	self:DumpInt(f.lineDefined, D)
	self:DumpInt(f.lastlinedefined, D)
	self:DumpChar(f.nups, D)
	self:DumpChar(f.numparams, D)
	self:DumpChar(f.is_vararg, D)
	self:DumpChar(f.maxstacksize, D)
	self:DumpCode(f, D)
	self:DumpConstants(f, D)
	self:DumpDebug(f, D)
end

------------------------------------------------------------------------
-- dump Lua header section (some sizes hard-coded)
------------------------------------------------------------------------
function luaU:DumpHeader(D)
	local h = self:header()
	assert(#h == self.LUAC_HEADERSIZE) -- fixed buffer now an assert
	self:DumpBlock(h, D)
end

------------------------------------------------------------------------
-- make header (from lundump.c)
-- returns the header string
------------------------------------------------------------------------
function luaU:header()
	local x = 1
	return self.LUA_SIGNATURE..
		string.char(
			self.LUAC_VERSION,
			self.LUAC_FORMAT,
			x,                    -- endianness (1=little)
			4,                    -- sizeof(int)
			size_size_t,                    -- sizeof(size_t)
			4,                    -- sizeof(Instruction)
			8,                    -- sizeof(lua_Number)
			0)                    -- is lua_Number integral?
end

------------------------------------------------------------------------
-- dump Lua function as precompiled chunk
-- (lua_State* L, const Proto* f, lua_Writer w, void* data, int strip)
-- * w, data are created from make_setS, make_setF
------------------------------------------------------------------------
function luaU:dump(L, f, w, data, strip)
	local D = {}  -- DumpState
	D.L = L
	D.write = w
	D.data = data
	D.strip = strip
	D.status = 0
	self:DumpHeader(D)
	self:DumpFunction(f, nil, D)
	-- added: for a chunk writer writing to a file, this final call with
	-- nil data is to indicate to the writer to close the file
	D.write(nil, D.data)
	return D.status
end




--dofile("lcode.lua")

------------------------------------------------------------------------
-- constants used by code generator
------------------------------------------------------------------------
-- maximum stack for a Lua function
luaK.MAXSTACK = 250  -- (from llimits.h)

--[[--------------------------------------------------------------------
-- other functions
----------------------------------------------------------------------]]

------------------------------------------------------------------------
-- emulation of TValue macros (these are from lobject.h)
-- * TValue is a table since lcode passes references around
-- * tt member field removed, using Lua's type() instead
-- * for setsvalue, sethvalue, parameter L (deleted here) in lobject.h
--   is used in an assert for testing, see checkliveness(g,obj)
------------------------------------------------------------------------
function luaK:ttisnumber(o)
	if o then return type(o.value) == "number" else return false end
end
function luaK:nvalue(o) return o.value end
function luaK:setnilvalue(o) o.value = nil end
function luaK:setsvalue(o, x) o.value = x end
luaK.setnvalue = luaK.setsvalue
luaK.sethvalue = luaK.setsvalue
luaK.setbvalue = luaK.setsvalue

------------------------------------------------------------------------
-- The luai_num* macros define the primitive operations over numbers.
-- * this is not the entire set of primitive operations from luaconf.h
-- * used in luaK:constfolding()
------------------------------------------------------------------------
function luaK:numadd(a, b) return a + b end
function luaK:numsub(a, b) return a - b end
function luaK:nummul(a, b) return a * b end
function luaK:numdiv(a, b) return a / b end
function luaK:nummod(a, b) return a % b end
-- ((a) - floor((a)/(b))*(b)) /* actual, for reference */
function luaK:numpow(a, b) return a ^ b end
function luaK:numunm(a) return -a end
function luaK:numisnan(a) return not a == a end
-- a NaN cannot equal another NaN

--[[--------------------------------------------------------------------
-- code generator functions
----------------------------------------------------------------------]]

------------------------------------------------------------------------
-- Marks the end of a patch list. It is an invalid value both as an absolute
-- address, and as a list link (would link an element to itself).
------------------------------------------------------------------------
luaK.NO_JUMP = -1

------------------------------------------------------------------------
-- grep "ORDER OPR" if you change these enums
------------------------------------------------------------------------
luaK.BinOpr = {
	OPR_ADD = 0, OPR_SUB = 1, OPR_MUL = 2, OPR_DIV = 3, OPR_MOD = 4, OPR_POW = 5,
	OPR_CONCAT = 6,
	OPR_NE = 7, OPR_EQ = 8,
	OPR_LT = 9, OPR_LE = 10, OPR_GT = 11, OPR_GE = 12,
	OPR_AND = 13, OPR_OR = 14,
	OPR_NOBINOPR = 15,
}

-- * UnOpr is used by luaK:prefix's op argument, but not directly used
--   because the function receives the symbols as strings, e.g. "OPR_NOT"
luaK.UnOpr = {
	OPR_MINUS = 0, OPR_NOT = 1, OPR_LEN = 2, OPR_NOUNOPR = 3
}

------------------------------------------------------------------------
-- returns the instruction object for given e (expdesc), was a macro
------------------------------------------------------------------------
function luaK:getcode(fs, e)
	return fs.f.code[e.info]
end

------------------------------------------------------------------------
-- codes an instruction with a signed Bx (sBx) field, was a macro
-- * used in luaK:jump(), (lparser) luaY:forbody()
------------------------------------------------------------------------
function luaK:codeAsBx(fs, o, A, sBx)
	return self:codeABx(fs, o, A, sBx + luaP.MAXARG_sBx)
end

------------------------------------------------------------------------
-- set the expdesc e instruction for multiple returns, was a macro
------------------------------------------------------------------------
function luaK:setmultret(fs, e)
	self:setreturns(fs, e, luaY.LUA_MULTRET)
end

------------------------------------------------------------------------
-- there is a jump if patch lists are not identical, was a macro
-- * used in luaK:exp2reg(), luaK:exp2anyreg(), luaK:exp2val()
------------------------------------------------------------------------
function luaK:hasjumps(e)
	return e.t ~= e.f
end

------------------------------------------------------------------------
-- true if the expression is a constant number (for constant folding)
-- * used in constfolding(), infix()
------------------------------------------------------------------------
function luaK:isnumeral(e)
	return e.k == "VKNUM" and e.t == self.NO_JUMP and e.f == self.NO_JUMP
end

------------------------------------------------------------------------
-- codes loading of nil, optimization done if consecutive locations
-- * used in luaK:discharge2reg(), (lparser) luaY:adjust_assign()
------------------------------------------------------------------------
function luaK:_nil(fs, from, n)
	if fs.pc > fs.lasttarget then  -- no jumps to current position?
		if fs.pc == 0 then  -- function start?
			if from >= fs.nactvar then
				return  -- positions are already clean
			end
		else
			local previous = fs.f.code[fs.pc - 1]
			if luaP:GET_OPCODE(previous) == "OP_LOADNIL" then
				local pfrom = luaP:GETARG_A(previous)
				local pto = luaP:GETARG_B(previous)
				if pfrom <= from and from <= pto + 1 then  -- can connect both?
					if from + n - 1 > pto then
						luaP:SETARG_B(previous, from + n - 1)
					end
					return
				end
			end
		end
	end
	self:codeABC(fs, "OP_LOADNIL", from, from + n - 1, 0)  -- else no optimization
end

------------------------------------------------------------------------
--
-- * used in multiple locations
------------------------------------------------------------------------
function luaK:jump(fs)
	local jpc = fs.jpc  -- save list of jumps to here
	fs.jpc = self.NO_JUMP
	local j = self:codeAsBx(fs, "OP_JMP", 0, self.NO_JUMP)
	j = self:concat(fs, j, jpc)  -- keep them on hold
	return j
end

------------------------------------------------------------------------
-- codes a RETURN instruction
-- * used in luaY:close_func(), luaY:retstat()
------------------------------------------------------------------------
function luaK:ret(fs, first, nret)
	self:codeABC(fs, "OP_RETURN", first, nret + 1, 0)
end

------------------------------------------------------------------------
--
-- * used in luaK:jumponcond(), luaK:codecomp()
------------------------------------------------------------------------
function luaK:condjump(fs, op, A, B, C)
	self:codeABC(fs, op, A, B, C)
	return self:jump(fs)
end

------------------------------------------------------------------------
--
-- * used in luaK:patchlistaux(), luaK:concat()
------------------------------------------------------------------------
function luaK:fixjump(fs, pc, dest)
	local jmp = fs.f.code[pc]
	local offset = dest - (pc + 1)
	lua_assert(dest ~= self.NO_JUMP)
	if math.abs(offset) > luaP.MAXARG_sBx then
		luaX:syntaxerror(fs.ls, "control structure too long")
	end
	luaP:SETARG_sBx(jmp, offset)
end

------------------------------------------------------------------------
-- returns current 'pc' and marks it as a jump target (to avoid wrong
-- optimizations with consecutive instructions not in the same basic block).
-- * used in multiple locations
-- * fs.lasttarget tested only by luaK:_nil() when optimizing OP_LOADNIL
------------------------------------------------------------------------
function luaK:getlabel(fs)
	fs.lasttarget = fs.pc
	return fs.pc
end

------------------------------------------------------------------------
--
-- * used in luaK:need_value(), luaK:removevalues(), luaK:patchlistaux(),
--   luaK:concat()
------------------------------------------------------------------------
function luaK:getjump(fs, pc)
	local offset = luaP:GETARG_sBx(fs.f.code[pc])
	if offset == self.NO_JUMP then  -- point to itself represents end of list
		return self.NO_JUMP  -- end of list
	else
		return (pc + 1) + offset  -- turn offset into absolute position
	end
end

------------------------------------------------------------------------
--
-- * used in luaK:need_value(), luaK:patchtestreg(), luaK:invertjump()
------------------------------------------------------------------------
function luaK:getjumpcontrol(fs, pc)
	local pi = fs.f.code[pc]
	local ppi = fs.f.code[pc - 1]
	if pc >= 1 and luaP:testTMode(luaP:GET_OPCODE(ppi)) ~= 0 then
		return ppi
	else
		return pi
	end
end

------------------------------------------------------------------------
-- check whether list has any jump that do not produce a value
-- (or produce an inverted value)
-- * return value changed to boolean
-- * used only in luaK:exp2reg()
------------------------------------------------------------------------
function luaK:need_value(fs, list)
	while list ~= self.NO_JUMP do
		local i = self:getjumpcontrol(fs, list)
		if luaP:GET_OPCODE(i) ~= "OP_TESTSET" then return true end
		list = self:getjump(fs, list)
	end
	return false  -- not found
end

------------------------------------------------------------------------
--
-- * used in luaK:removevalues(), luaK:patchlistaux()
------------------------------------------------------------------------
function luaK:patchtestreg(fs, node, reg)
	local i = self:getjumpcontrol(fs, node)
	if luaP:GET_OPCODE(i) ~= "OP_TESTSET" then
		return false  -- cannot patch other instructions
	end
	if reg ~= luaP.NO_REG and reg ~= luaP:GETARG_B(i) then
		luaP:SETARG_A(i, reg)
	else  -- no register to put value or register already has the value
		-- due to use of a table as i, i cannot be replaced by another table
		-- so the following is required; there is no change to ARG_C
		luaP:SET_OPCODE(i, "OP_TEST")
		local b = luaP:GETARG_B(i)
		luaP:SETARG_A(i, b)
		luaP:SETARG_B(i, 0)
		-- *i = CREATE_ABC(OP_TEST, GETARG_B(*i), 0, GETARG_C(*i)); /* C */
	end
	return true
end

------------------------------------------------------------------------
--
-- * used only in luaK:codenot()
------------------------------------------------------------------------
function luaK:removevalues(fs, list)
	while list ~= self.NO_JUMP do
		self:patchtestreg(fs, list, luaP.NO_REG)
		list = self:getjump(fs, list)
	end
end

------------------------------------------------------------------------
--
-- * used in luaK:dischargejpc(), luaK:patchlist(), luaK:exp2reg()
------------------------------------------------------------------------
function luaK:patchlistaux(fs, list, vtarget, reg, dtarget)
	while list ~= self.NO_JUMP do
		local _next = self:getjump(fs, list)
		if self:patchtestreg(fs, list, reg) then
			self:fixjump(fs, list, vtarget)
		else
			self:fixjump(fs, list, dtarget)  -- jump to default target
		end
		list = _next
	end
end

------------------------------------------------------------------------
--
-- * used only in luaK:code()
------------------------------------------------------------------------
function luaK:dischargejpc(fs)
	self:patchlistaux(fs, fs.jpc, fs.pc, luaP.NO_REG, fs.pc)
	fs.jpc = self.NO_JUMP
end

------------------------------------------------------------------------
--
-- * used in (lparser) luaY:whilestat(), luaY:repeatstat(), luaY:forbody()
------------------------------------------------------------------------
function luaK:patchlist(fs, list, target)
	if target == fs.pc then
		self:patchtohere(fs, list)
	else
		lua_assert(target < fs.pc)
		self:patchlistaux(fs, list, target, luaP.NO_REG, target)
	end
end

------------------------------------------------------------------------
--
-- * used in multiple locations
------------------------------------------------------------------------
function luaK:patchtohere(fs, list)
	self:getlabel(fs)
	fs.jpc = self:concat(fs, fs.jpc, list)
end

------------------------------------------------------------------------
-- * l1 was a pointer, now l1 is returned and callee assigns the value
-- * used in multiple locations
------------------------------------------------------------------------
function luaK:concat(fs, l1, l2)
	if l2 == self.NO_JUMP then return l1
	elseif l1 == self.NO_JUMP then
		return l2
	else
		local list = l1
		local _next = self:getjump(fs, list)
		while _next ~= self.NO_JUMP do  -- find last element
			list = _next
			_next = self:getjump(fs, list)
		end
		self:fixjump(fs, list, l2)
	end
	return l1
end

------------------------------------------------------------------------
--
-- * used in luaK:reserveregs(), (lparser) luaY:forlist()
------------------------------------------------------------------------
function luaK:checkstack(fs, n)
	local newstack = fs.freereg + n
	if newstack > fs.f.maxstacksize then
		if newstack >= self.MAXSTACK then
			luaX:syntaxerror(fs.ls, "function or expression too complex")
		end
		fs.f.maxstacksize = newstack
	end
end

------------------------------------------------------------------------
--
-- * used in multiple locations
------------------------------------------------------------------------
function luaK:reserveregs(fs, n)
	self:checkstack(fs, n)
	fs.freereg = fs.freereg + n
end

------------------------------------------------------------------------
--
-- * used in luaK:freeexp(), luaK:dischargevars()
------------------------------------------------------------------------
function luaK:freereg(fs, reg)
	if not luaP:ISK(reg) and reg >= fs.nactvar then
		fs.freereg = fs.freereg - 1
		lua_assert(reg == fs.freereg)
	end
end

------------------------------------------------------------------------
--
-- * used in multiple locations
------------------------------------------------------------------------
function luaK:freeexp(fs, e)
	if e.k == "VNONRELOC" then
		self:freereg(fs, e.info)
	end
end

------------------------------------------------------------------------
-- * TODO NOTE implementation is not 100% correct, since the assert fails
-- * luaH_set, setobj deleted; direct table access used instead
-- * used in luaK:stringK(), luaK:numberK(), luaK:boolK(), luaK:nilK()
------------------------------------------------------------------------
function luaK:addk(fs, k, v)
	local L = fs.L
	local idx = fs.h[k.value]
	--TValue *idx = luaH_set(L, fs->h, k); /* C */
	local f = fs.f
	if self:ttisnumber(idx) then
		--TODO this assert currently FAILS (last tested for 5.0.2)
		--lua_assert(fs.f.k[self:nvalue(idx)] == v)
		--lua_assert(luaO_rawequalObj(&fs->f->k[cast_int(nvalue(idx))], v)); /* C */
		return self:nvalue(idx)
	else -- constant not found; create a new entry
		idx = {}
		self:setnvalue(idx, fs.nk)
		fs.h[k.value] = idx
		-- setnvalue(idx, cast_num(fs->nk)); /* C */
		luaY:growvector(L, f.k, fs.nk, f.sizek, nil,
			luaP.MAXARG_Bx, "constant table overflow")
		-- loop to initialize empty f.k positions not required
		f.k[fs.nk] = v
		-- setobj(L, &f->k[fs->nk], v); /* C */
		-- luaC_barrier(L, f, v); /* GC */
		local nk = fs.nk
		fs.nk = fs.nk + 1
		return nk
	end

end

------------------------------------------------------------------------
-- creates and sets a string object
-- * used in (lparser) luaY:codestring(), luaY:singlevar()
------------------------------------------------------------------------
function luaK:stringK(fs, s)
	local o = {}  -- TValue
	self:setsvalue(o, s)
	return self:addk(fs, o, o)
end

------------------------------------------------------------------------
-- creates and sets a number object
-- * used in luaK:prefix() for negative (or negation of) numbers
-- * used in (lparser) luaY:simpleexp(), luaY:fornum()
------------------------------------------------------------------------
function luaK:numberK(fs, r)
	local o = {}  -- TValue
	self:setnvalue(o, r)
	return self:addk(fs, o, o)
end

------------------------------------------------------------------------
-- creates and sets a boolean object
-- * used only in luaK:exp2RK()
------------------------------------------------------------------------
function luaK:boolK(fs, b)
	local o = {}  -- TValue
	self:setbvalue(o, b)
	return self:addk(fs, o, o)
end

------------------------------------------------------------------------
-- creates and sets a nil object
-- * used only in luaK:exp2RK()
------------------------------------------------------------------------
function luaK:nilK(fs)
	local k, v = {}, {}  -- TValue
	self:setnilvalue(v)
	-- cannot use nil as key; instead use table itself to represent nil
	self:sethvalue(k, fs.h)
	return self:addk(fs, k, v)
end

------------------------------------------------------------------------
--
-- * used in luaK:setmultret(), (lparser) luaY:adjust_assign()
------------------------------------------------------------------------
function luaK:setreturns(fs, e, nresults)
	if e.k == "VCALL" then  -- expression is an open function call?
		luaP:SETARG_C(self:getcode(fs, e), nresults + 1)
	elseif e.k == "VVARARG" then
		luaP:SETARG_B(self:getcode(fs, e), nresults + 1);
		luaP:SETARG_A(self:getcode(fs, e), fs.freereg);
		luaK:reserveregs(fs, 1)
	end
end

------------------------------------------------------------------------
--
-- * used in luaK:dischargevars(), (lparser) luaY:assignment()
------------------------------------------------------------------------
function luaK:setoneret(fs, e)
	if e.k == "VCALL" then  -- expression is an open function call?
		e.k = "VNONRELOC"
		e.info = luaP:GETARG_A(self:getcode(fs, e))
	elseif e.k == "VVARARG" then
		luaP:SETARG_B(self:getcode(fs, e), 2)
		e.k = "VRELOCABLE"  -- can relocate its simple result
	end
end

------------------------------------------------------------------------
--
-- * used in multiple locations
------------------------------------------------------------------------
function luaK:dischargevars(fs, e)
	local k = e.k
	if k == "VLOCAL" then
		e.k = "VNONRELOC"
	elseif k == "VUPVAL" then
		e.info = self:codeABC(fs, "OP_GETUPVAL", 0, e.info, 0)
		e.k = "VRELOCABLE"
	elseif k == "VGLOBAL" then
		e.info = self:codeABx(fs, "OP_GETGLOBAL", 0, e.info)
		e.k = "VRELOCABLE"
	elseif k == "VINDEXED" then
		self:freereg(fs, e.aux)
		self:freereg(fs, e.info)
		e.info = self:codeABC(fs, "OP_GETTABLE", 0, e.info, e.aux)
		e.k = "VRELOCABLE"
	elseif k == "VVARARG" or k == "VCALL" then
		self:setoneret(fs, e)
	else
		-- there is one value available (somewhere)
	end
end

------------------------------------------------------------------------
--
-- * used only in luaK:exp2reg()
------------------------------------------------------------------------
function luaK:code_label(fs, A, b, jump)
	self:getlabel(fs)  -- those instructions may be jump targets
	return self:codeABC(fs, "OP_LOADBOOL", A, b, jump)
end

------------------------------------------------------------------------
--
-- * used in luaK:discharge2anyreg(), luaK:exp2reg()
------------------------------------------------------------------------
function luaK:discharge2reg(fs, e, reg)
	self:dischargevars(fs, e)
	local k = e.k
	if k == "VNIL" then
		self:_nil(fs, reg, 1)
	elseif k == "VFALSE" or k == "VTRUE" then
		self:codeABC(fs, "OP_LOADBOOL", reg, (e.k == "VTRUE") and 1 or 0, 0)
	elseif k == "VK" then
		self:codeABx(fs, "OP_LOADK", reg, e.info)
	elseif k == "VKNUM" then
		self:codeABx(fs, "OP_LOADK", reg, self:numberK(fs, e.nval))
	elseif k == "VRELOCABLE" then
		local pc = self:getcode(fs, e)
		luaP:SETARG_A(pc, reg)
	elseif k == "VNONRELOC" then
		if reg ~= e.info then
			self:codeABC(fs, "OP_MOVE", reg, e.info, 0)
		end
	else
		lua_assert(e.k == "VVOID" or e.k == "VJMP")
		return  -- nothing to do...
	end
	e.info = reg
	e.k = "VNONRELOC"
end

------------------------------------------------------------------------
--
-- * used in luaK:jumponcond(), luaK:codenot()
------------------------------------------------------------------------
function luaK:discharge2anyreg(fs, e)
	if e.k ~= "VNONRELOC" then
		self:reserveregs(fs, 1)
		self:discharge2reg(fs, e, fs.freereg - 1)
	end
end

------------------------------------------------------------------------
--
-- * used in luaK:exp2nextreg(), luaK:exp2anyreg(), luaK:storevar()
------------------------------------------------------------------------
function luaK:exp2reg(fs, e, reg)
	self:discharge2reg(fs, e, reg)
	if e.k == "VJMP" then
		e.t = self:concat(fs, e.t, e.info)  -- put this jump in 't' list
	end
	if self:hasjumps(e) then
		local final  -- position after whole expression
		local p_f = self.NO_JUMP  -- position of an eventual LOAD false
		local p_t = self.NO_JUMP  -- position of an eventual LOAD true
		if self:need_value(fs, e.t) or self:need_value(fs, e.f) then
			local fj = (e.k == "VJMP") and self.NO_JUMP or self:jump(fs)
			p_f = self:code_label(fs, reg, 0, 1)
			p_t = self:code_label(fs, reg, 1, 0)
			self:patchtohere(fs, fj)
		end
		final = self:getlabel(fs)
		self:patchlistaux(fs, e.f, final, reg, p_f)
		self:patchlistaux(fs, e.t, final, reg, p_t)
	end
	e.f, e.t = self.NO_JUMP, self.NO_JUMP
	e.info = reg
	e.k = "VNONRELOC"
end

------------------------------------------------------------------------
--
-- * used in multiple locations
------------------------------------------------------------------------
function luaK:exp2nextreg(fs, e)
	self:dischargevars(fs, e)
	self:freeexp(fs, e)
	self:reserveregs(fs, 1)
	self:exp2reg(fs, e, fs.freereg - 1)
end

------------------------------------------------------------------------
--
-- * used in multiple locations
------------------------------------------------------------------------
function luaK:exp2anyreg(fs, e)
	self:dischargevars(fs, e)
	if e.k == "VNONRELOC" then
		if not self:hasjumps(e) then  -- exp is already in a register
			return e.info
		end
		if e.info >= fs.nactvar then  -- reg. is not a local?
			self:exp2reg(fs, e, e.info)  -- put value on it
			return e.info
		end
	end
	self:exp2nextreg(fs, e)  -- default
	return e.info
end

------------------------------------------------------------------------
--
-- * used in luaK:exp2RK(), luaK:prefix(), luaK:posfix()
-- * used in (lparser) luaY:yindex()
------------------------------------------------------------------------
function luaK:exp2val(fs, e)
	if self:hasjumps(e) then
		self:exp2anyreg(fs, e)
	else
		self:dischargevars(fs, e)
	end
end

------------------------------------------------------------------------
--
-- * used in multiple locations
------------------------------------------------------------------------
function luaK:exp2RK(fs, e)
	self:exp2val(fs, e)
	local k = e.k
	if k == "VKNUM" or k == "VTRUE" or k == "VFALSE" or k == "VNIL" then
		if fs.nk <= luaP.MAXINDEXRK then  -- constant fit in RK operand?
			-- converted from a 2-deep ternary operator expression
			if e.k == "VNIL" then
				e.info = self:nilK(fs)
			else
				e.info = (e.k == "VKNUM") and self:numberK(fs, e.nval)
					or self:boolK(fs, e.k == "VTRUE")
			end
			e.k = "VK"
			return luaP:RKASK(e.info)
		end
	elseif k == "VK" then
		if e.info <= luaP.MAXINDEXRK then  -- constant fit in argC?
			return luaP:RKASK(e.info)
		end
	else
		-- default
	end
	-- not a constant in the right range: put it in a register
	return self:exp2anyreg(fs, e)
end

------------------------------------------------------------------------
--
-- * used in (lparser) luaY:assignment(), luaY:localfunc(), luaY:funcstat()
------------------------------------------------------------------------
function luaK:storevar(fs, var, ex)
	local k = var.k
	if k == "VLOCAL" then
		self:freeexp(fs, ex)
		self:exp2reg(fs, ex, var.info)
		return
	elseif k == "VUPVAL" then
		local e = self:exp2anyreg(fs, ex)
		self:codeABC(fs, "OP_SETUPVAL", e, var.info, 0)
	elseif k == "VGLOBAL" then
		local e = self:exp2anyreg(fs, ex)
		self:codeABx(fs, "OP_SETGLOBAL", e, var.info)
	elseif k == "VINDEXED" then
		local e = self:exp2RK(fs, ex)
		self:codeABC(fs, "OP_SETTABLE", var.info, var.aux, e)
	else
		lua_assert(0)  -- invalid var kind to store
	end
	self:freeexp(fs, ex)
end

------------------------------------------------------------------------
--
-- * used only in (lparser) luaY:primaryexp()
------------------------------------------------------------------------
function luaK:_self(fs, e, key)
	self:exp2anyreg(fs, e)
	self:freeexp(fs, e)
	local func = fs.freereg
	self:reserveregs(fs, 2)
	self:codeABC(fs, "OP_SELF", func, e.info, self:exp2RK(fs, key))
	self:freeexp(fs, key)
	e.info = func
	e.k = "VNONRELOC"
end

------------------------------------------------------------------------
--
-- * used in luaK:goiftrue(), luaK:codenot()
------------------------------------------------------------------------
function luaK:invertjump(fs, e)
	local pc = self:getjumpcontrol(fs, e.info)
	lua_assert(luaP:testTMode(luaP:GET_OPCODE(pc)) ~= 0 and
		luaP:GET_OPCODE(pc) ~= "OP_TESTSET" and
		luaP:GET_OPCODE(pc) ~= "OP_TEST")
	luaP:SETARG_A(pc, (luaP:GETARG_A(pc) == 0) and 1 or 0)
end

------------------------------------------------------------------------
--
-- * used in luaK:goiftrue(), luaK:goiffalse()
------------------------------------------------------------------------
function luaK:jumponcond(fs, e, cond)
	if e.k == "VRELOCABLE" then
		local ie = self:getcode(fs, e)
		if luaP:GET_OPCODE(ie) == "OP_NOT" then
			fs.pc = fs.pc - 1  -- remove previous OP_NOT
			return self:condjump(fs, "OP_TEST", luaP:GETARG_B(ie), 0, cond and 0 or 1)
		end
		-- else go through
	end
	self:discharge2anyreg(fs, e)
	self:freeexp(fs, e)
	return self:condjump(fs, "OP_TESTSET", luaP.NO_REG, e.info, cond and 1 or 0)
end

------------------------------------------------------------------------
--
-- * used in luaK:infix(), (lparser) luaY:cond()
------------------------------------------------------------------------
function luaK:goiftrue(fs, e)
	local pc  -- pc of last jump
	self:dischargevars(fs, e)
	local k = e.k
	if k == "VK" or k == "VKNUM" or k == "VTRUE" then
		pc = self.NO_JUMP  -- always true; do nothing
	elseif k == "VFALSE" then
		pc = self:jump(fs)  -- always jump
	elseif k == "VJMP" then
		self:invertjump(fs, e)
		pc = e.info
	else
		pc = self:jumponcond(fs, e, false)
	end
	e.f = self:concat(fs, e.f, pc)  -- insert last jump in `f' list
	self:patchtohere(fs, e.t)
	e.t = self.NO_JUMP
end

------------------------------------------------------------------------
--
-- * used in luaK:infix()
------------------------------------------------------------------------
function luaK:goiffalse(fs, e)
	local pc  -- pc of last jump
	self:dischargevars(fs, e)
	local k = e.k
	if k == "VNIL" or k == "VFALSE"then
		pc = self.NO_JUMP  -- always false; do nothing
	elseif k == "VTRUE" then
		pc = self:jump(fs)  -- always jump
	elseif k == "VJMP" then
		pc = e.info
	else
		pc = self:jumponcond(fs, e, true)
	end
	e.t = self:concat(fs, e.t, pc)  -- insert last jump in `t' list
	self:patchtohere(fs, e.f)
	e.f = self.NO_JUMP
end

------------------------------------------------------------------------
--
-- * used only in luaK:prefix()
------------------------------------------------------------------------
function luaK:codenot(fs, e)
	self:dischargevars(fs, e)
	local k = e.k
	if k == "VNIL" or k == "VFALSE" then
		e.k = "VTRUE"
	elseif k == "VK" or k == "VKNUM" or k == "VTRUE" then
		e.k = "VFALSE"
	elseif k == "VJMP" then
		self:invertjump(fs, e)
	elseif k == "VRELOCABLE" or k == "VNONRELOC" then
		self:discharge2anyreg(fs, e)
		self:freeexp(fs, e)
		e.info = self:codeABC(fs, "OP_NOT", 0, e.info, 0)
		e.k = "VRELOCABLE"
	else
		lua_assert(0)  -- cannot happen
	end
	-- interchange true and false lists
	e.f, e.t = e.t, e.f
	self:removevalues(fs, e.f)
	self:removevalues(fs, e.t)
end

------------------------------------------------------------------------
--
-- * used in (lparser) luaY:field(), luaY:primaryexp()
------------------------------------------------------------------------
function luaK:indexed(fs, t, k)
	t.aux = self:exp2RK(fs, k)
	t.k = "VINDEXED"
end

------------------------------------------------------------------------
--
-- * used only in luaK:codearith()
------------------------------------------------------------------------
function luaK:constfolding(op, e1, e2)
	local r
	if not self:isnumeral(e1) or not self:isnumeral(e2) then return false end
	local v1 = e1.nval
	local v2 = e2.nval
	if op == "OP_ADD" then
		r = self:numadd(v1, v2)
	elseif op == "OP_SUB" then
		r = self:numsub(v1, v2)
	elseif op == "OP_MUL" then
		r = self:nummul(v1, v2)
	elseif op == "OP_DIV" then
		if v2 == 0 then return false end  -- do not attempt to divide by 0
		r = self:numdiv(v1, v2)
	elseif op == "OP_MOD" then
		if v2 == 0 then return false end  -- do not attempt to divide by 0
		r = self:nummod(v1, v2)
	elseif op == "OP_POW" then
		r = self:numpow(v1, v2)
	elseif op == "OP_UNM" then
		r = self:numunm(v1)
	elseif op == "OP_LEN" then
		return false  -- no constant folding for 'len'
	else
		lua_assert(0)
		r = 0
	end
	if self:numisnan(r) then return false end  -- do not attempt to produce NaN
	e1.nval = r
	return true
end

------------------------------------------------------------------------
--
-- * used in luaK:prefix(), luaK:posfix()
------------------------------------------------------------------------
function luaK:codearith(fs, op, e1, e2)
	if self:constfolding(op, e1, e2) then
		return
	else
		local o2 = (op ~= "OP_UNM" and op ~= "OP_LEN") and self:exp2RK(fs, e2) or 0
		local o1 = self:exp2RK(fs, e1)
		if o1 > o2 then
			self:freeexp(fs, e1)
			self:freeexp(fs, e2)
		else
			self:freeexp(fs, e2)
			self:freeexp(fs, e1)
		end
		e1.info = self:codeABC(fs, op, 0, o1, o2)
		e1.k = "VRELOCABLE"
	end
end

------------------------------------------------------------------------
--
-- * used only in luaK:posfix()
------------------------------------------------------------------------
function luaK:codecomp(fs, op, cond, e1, e2)
	local o1 = self:exp2RK(fs, e1)
	local o2 = self:exp2RK(fs, e2)
	self:freeexp(fs, e2)
	self:freeexp(fs, e1)
	if cond == 0 and op ~= "OP_EQ" then
		-- exchange args to replace by `<' or `<='
		o1, o2 = o2, o1  -- o1 <==> o2
		cond = 1
	end
	e1.info = self:condjump(fs, op, cond, o1, o2)
	e1.k = "VJMP"
end

------------------------------------------------------------------------
--
-- * used only in (lparser) luaY:subexpr()
------------------------------------------------------------------------
function luaK:prefix(fs, op, e)
	local e2 = {}  -- expdesc
	e2.t, e2.f = self.NO_JUMP, self.NO_JUMP
	e2.k = "VKNUM"
	e2.nval = 0
	if op == "OPR_MINUS" then
		if not self:isnumeral(e) then
			self:exp2anyreg(fs, e)  -- cannot operate on non-numeric constants
		end
		self:codearith(fs, "OP_UNM", e, e2)
	elseif op == "OPR_NOT" then
		self:codenot(fs, e)
	elseif op == "OPR_LEN" then
		self:exp2anyreg(fs, e)  -- cannot operate on constants
		self:codearith(fs, "OP_LEN", e, e2)
	else
		lua_assert(0)
	end
end

------------------------------------------------------------------------
--
-- * used only in (lparser) luaY:subexpr()
------------------------------------------------------------------------
function luaK:infix(fs, op, v)
	if op == "OPR_AND" then
		self:goiftrue(fs, v)
	elseif op == "OPR_OR" then
		self:goiffalse(fs, v)
	elseif op == "OPR_CONCAT" then
		self:exp2nextreg(fs, v)  -- operand must be on the 'stack'
	elseif op == "OPR_ADD" or op == "OPR_SUB" or
		op == "OPR_MUL" or op == "OPR_DIV" or
		op == "OPR_MOD" or op == "OPR_POW" then
		if not self:isnumeral(v) then self:exp2RK(fs, v) end
	else
		self:exp2RK(fs, v)
	end
end

------------------------------------------------------------------------
--
-- * used only in (lparser) luaY:subexpr()
------------------------------------------------------------------------
-- table lookups to simplify testing
luaK.arith_op = {
	OPR_ADD = "OP_ADD", OPR_SUB = "OP_SUB", OPR_MUL = "OP_MUL",
	OPR_DIV = "OP_DIV", OPR_MOD = "OP_MOD", OPR_POW = "OP_POW",
}
luaK.comp_op = {
	OPR_EQ = "OP_EQ", OPR_NE = "OP_EQ", OPR_LT = "OP_LT",
	OPR_LE = "OP_LE", OPR_GT = "OP_LT", OPR_GE = "OP_LE",
}
luaK.comp_cond = {
	OPR_EQ = 1, OPR_NE = 0, OPR_LT = 1,
	OPR_LE = 1, OPR_GT = 0, OPR_GE = 0,
}
function luaK:posfix(fs, op, e1, e2)
	-- needed because e1 = e2 doesn't copy values...
	-- * in 5.0.x, only k/info/aux/t/f copied, t for AND, f for OR
	--   but here, all elements are copied for completeness' sake
	local function copyexp(e1, e2)
		e1.k = e2.k
		e1.info = e2.info; e1.aux = e2.aux
		e1.nval = e2.nval
		e1.t = e2.t; e1.f = e2.f
	end
	if op == "OPR_AND" then
		lua_assert(e1.t == self.NO_JUMP)  -- list must be closed
		self:dischargevars(fs, e2)
		e2.f = self:concat(fs, e2.f, e1.f)
		copyexp(e1, e2)
	elseif op == "OPR_OR" then
		lua_assert(e1.f == self.NO_JUMP)  -- list must be closed
		self:dischargevars(fs, e2)
		e2.t = self:concat(fs, e2.t, e1.t)
		copyexp(e1, e2)
	elseif op == "OPR_CONCAT" then
		self:exp2val(fs, e2)
		if e2.k == "VRELOCABLE" and luaP:GET_OPCODE(self:getcode(fs, e2)) == "OP_CONCAT" then
			lua_assert(e1.info == luaP:GETARG_B(self:getcode(fs, e2)) - 1)
			self:freeexp(fs, e1)
			luaP:SETARG_B(self:getcode(fs, e2), e1.info)
			e1.k = "VRELOCABLE"
			e1.info = e2.info
		else
			self:exp2nextreg(fs, e2)  -- operand must be on the 'stack'
			self:codearith(fs, "OP_CONCAT", e1, e2)
		end
	else
		-- the following uses a table lookup in place of conditionals
		local arith = self.arith_op[op]
		if arith then
			self:codearith(fs, arith, e1, e2)
		else
			local comp = self.comp_op[op]
			if comp then
				self:codecomp(fs, comp, self.comp_cond[op], e1, e2)
			else
				lua_assert(0)
			end
		end--if arith
	end--if op
end

------------------------------------------------------------------------
-- adjusts debug information for last instruction written, in order to
-- change the line where item comes into existence
-- * used in (lparser) luaY:funcargs(), luaY:forbody(), luaY:funcstat()
------------------------------------------------------------------------
function luaK:fixline(fs, line)
	fs.f.lineinfo[fs.pc - 1] = line
end

------------------------------------------------------------------------
-- general function to write an instruction into the instruction buffer,
-- sets debug information too
-- * used in luaK:codeABC(), luaK:codeABx()
-- * called directly by (lparser) luaY:whilestat()
------------------------------------------------------------------------
function luaK:code(fs, i, line)
	local f = fs.f
	self:dischargejpc(fs)  -- 'pc' will change
	-- put new instruction in code array
	luaY:growvector(fs.L, f.code, fs.pc, f.sizecode, nil,
		luaY.MAX_INT, "code size overflow")
	f.code[fs.pc] = i
	-- save corresponding line information
	luaY:growvector(fs.L, f.lineinfo, fs.pc, f.sizelineinfo, nil,
		luaY.MAX_INT, "code size overflow")
	f.lineinfo[fs.pc] = line
	local pc = fs.pc
	fs.pc = fs.pc + 1
	return pc
end

------------------------------------------------------------------------
-- writes an instruction of type ABC
-- * calls luaK:code()
------------------------------------------------------------------------
function luaK:codeABC(fs, o, a, b, c)
	lua_assert(luaP:getOpMode(o) == luaP.OpMode.iABC)
	lua_assert(luaP:getBMode(o) ~= luaP.OpArgMask.OpArgN or b == 0)
	lua_assert(luaP:getCMode(o) ~= luaP.OpArgMask.OpArgN or c == 0)
	return self:code(fs, luaP:CREATE_ABC(o, a, b, c), fs.ls.lastline)
end

------------------------------------------------------------------------
-- writes an instruction of type ABx
-- * calls luaK:code(), called by luaK:codeAsBx()
------------------------------------------------------------------------
function luaK:codeABx(fs, o, a, bc)
	lua_assert(luaP:getOpMode(o) == luaP.OpMode.iABx or
		luaP:getOpMode(o) == luaP.OpMode.iAsBx)
	lua_assert(luaP:getCMode(o) == luaP.OpArgMask.OpArgN)
	return self:code(fs, luaP:CREATE_ABx(o, a, bc), fs.ls.lastline)
end

------------------------------------------------------------------------
--
-- * used in (lparser) luaY:closelistfield(), luaY:lastlistfield()
------------------------------------------------------------------------
function luaK:setlist(fs, base, nelems, tostore)
	local c = math.floor((nelems - 1)/luaP.LFIELDS_PER_FLUSH) + 1
	local b = (tostore == luaY.LUA_MULTRET) and 0 or tostore
	lua_assert(tostore ~= 0)
	if c <= luaP.MAXARG_C then
		self:codeABC(fs, "OP_SETLIST", base, b, c)
	else
		self:codeABC(fs, "OP_SETLIST", base, b, 0)
		self:code(fs, luaP:CREATE_Inst(c), fs.ls.lastline)
	end
	fs.freereg = base + 1  -- free registers with list values
end




--dofile("lparser.lua")

--[[--------------------------------------------------------------------
-- Expression descriptor
-- * expkind changed to string constants; luaY:assignment was the only
--   function to use a relational operator with this enumeration
-- VVOID       -- no value
-- VNIL        -- no value
-- VTRUE       -- no value
-- VFALSE      -- no value
-- VK          -- info = index of constant in 'k'
-- VKNUM       -- nval = numerical value
-- VLOCAL      -- info = local register
-- VUPVAL,     -- info = index of upvalue in 'upvalues'
-- VGLOBAL     -- info = index of table; aux = index of global name in 'k'
-- VINDEXED    -- info = table register; aux = index register (or 'k')
-- VJMP        -- info = instruction pc
-- VRELOCABLE  -- info = instruction pc
-- VNONRELOC   -- info = result register
-- VCALL       -- info = instruction pc
-- VVARARG     -- info = instruction pc
} ----------------------------------------------------------------------]]

--[[--------------------------------------------------------------------
-- * expdesc in Lua 5.1.x has a union u and another struct s; this Lua
--   implementation ignores all instances of u and s usage
-- struct expdesc:
--   k  -- (enum: expkind)
--   info, aux -- (int, int)
--   nval -- (lua_Number)
--   t  -- patch list of 'exit when true'
--   f  -- patch list of 'exit when false'
----------------------------------------------------------------------]]

--[[--------------------------------------------------------------------
-- struct upvaldesc:
--   k  -- (lu_byte)
--   info -- (lu_byte)
----------------------------------------------------------------------]]

--[[--------------------------------------------------------------------
-- state needed to generate code for a given function
-- struct FuncState:
--   f  -- current function header (table: Proto)
--   h  -- table to find (and reuse) elements in 'k' (table: Table)
--   prev  -- enclosing function (table: FuncState)
--   ls  -- lexical state (table: LexState)
--   L  -- copy of the Lua state (table: lua_State)
--   bl  -- chain of current blocks (table: BlockCnt)
--   pc  -- next position to code (equivalent to 'ncode')
--   lasttarget   -- 'pc' of last 'jump target'
--   jpc  -- list of pending jumps to 'pc'
--   freereg  -- first free register
--   nk  -- number of elements in 'k'
--   np  -- number of elements in 'p'
--   nlocvars  -- number of elements in 'locvars'
--   nactvar  -- number of active local variables
--   upvalues[LUAI_MAXUPVALUES]  -- upvalues (table: upvaldesc)
--   actvar[LUAI_MAXVARS]  -- declared-variable stack
----------------------------------------------------------------------]]

------------------------------------------------------------------------
-- constants used by parser
-- * picks up duplicate values from luaX if required
------------------------------------------------------------------------
luaY.LUA_QS = luaX.LUA_QS or "'%s'"  -- (from luaconf.h)

luaY.SHRT_MAX = 32767 -- (from <limits.h>)
luaY.LUAI_MAXVARS = 200  -- (luaconf.h)
luaY.LUAI_MAXUPVALUES = 60  -- (luaconf.h)
luaY.MAX_INT = luaX.MAX_INT or 2147483645  -- (from llimits.h)
-- * INT_MAX-2 for 32-bit systems
luaY.LUAI_MAXCCALLS = 200  -- (from luaconf.h)

luaY.VARARG_HASARG = 1  -- (from lobject.h)
-- NOTE: HASARG_MASK is value-specific
luaY.HASARG_MASK = 2 -- this was added for a bitop in parlist()
luaY.VARARG_ISVARARG = 2
-- NOTE: there is some value-specific code that involves VARARG_NEEDSARG
luaY.VARARG_NEEDSARG = 4

luaY.LUA_MULTRET = -1  -- (lua.h)

--[[--------------------------------------------------------------------
-- other functions
----------------------------------------------------------------------]]

------------------------------------------------------------------------
-- LUA_QL describes how error messages quote program elements.
-- CHANGE it if you want a different appearance. (from luaconf.h)
------------------------------------------------------------------------
function luaY:LUA_QL(x)
	return "'"..x.."'"
end

------------------------------------------------------------------------
-- this is a stripped-down luaM_growvector (from lmem.h) which is a
-- macro based on luaM_growaux (in lmem.c); all the following does is
-- reproduce the size limit checking logic of the original function
-- so that error behaviour is identical; all arguments preserved for
-- convenience, even those which are unused
-- * set the t field to nil, since this originally does a sizeof(t)
-- * size (originally a pointer) is never updated, their final values
--   are set by luaY:close_func(), so overall things should still work
------------------------------------------------------------------------
function luaY:growvector(L, v, nelems, size, t, limit, e)
	if nelems >= limit then
		error(e)  -- was luaG_runerror
	end
end

------------------------------------------------------------------------
-- initialize a new function prototype structure (from lfunc.c)
-- * used only in open_func()
------------------------------------------------------------------------
function luaY:newproto(L)
	local f = {} -- Proto
	-- luaC_link(L, obj2gco(f), LUA_TPROTO); /* GC */
	f.k = {}
	f.sizek = 0
	f.p = {}
	f.sizep = 0
	f.code = {}
	f.sizecode = 0
	f.sizelineinfo = 0
	f.sizeupvalues = 0
	f.nups = 0
	f.upvalues = {}
	f.numparams = 0
	f.is_vararg = 0
	f.maxstacksize = 0
	f.lineinfo = {}
	f.sizelocvars = 0
	f.locvars = {}
	f.lineDefined = 0
	f.lastlinedefined = 0
	f.source = nil
	return f
end

------------------------------------------------------------------------
-- converts an integer to a "floating point byte", represented as
-- (eeeeexxx), where the real value is (1xxx) * 2^(eeeee - 1) if
-- eeeee != 0 and (xxx) otherwise.
------------------------------------------------------------------------
function luaY:int2fb(x)
	local e = 0  -- exponent
	while x >= 16 do
		x = math.floor((x + 1) / 2)
		e = e + 1
	end
	if x < 8 then
		return x
	else
		return ((e + 1) * 8) + (x - 8)
	end
end

--[[--------------------------------------------------------------------
-- parser functions
----------------------------------------------------------------------]]

------------------------------------------------------------------------
-- true of the kind of expression produces multiple return values
------------------------------------------------------------------------
function luaY:hasmultret(k)
	return k == "VCALL" or k == "VVARARG"
end

------------------------------------------------------------------------
-- convenience function to access active local i, returns entry
------------------------------------------------------------------------
function luaY:getlocvar(fs, i)
	return fs.f.locvars[ fs.actvar[i] ]
end

------------------------------------------------------------------------
-- check a limit, string m provided as an error message
------------------------------------------------------------------------
function luaY:checklimit(fs, v, l, m)
	if v > l then self:errorlimit(fs, l, m) end
end

--[[--------------------------------------------------------------------
-- nodes for block list (list of active blocks)
-- struct BlockCnt:
--   previous  -- chain (table: BlockCnt)
--   breaklist  -- list of jumps out of this loop
--   nactvar  -- # active local variables outside the breakable structure
--   upval  -- true if some variable in the block is an upvalue (boolean)
--   isbreakable  -- true if 'block' is a loop (boolean)
----------------------------------------------------------------------]]

------------------------------------------------------------------------
-- prototypes for recursive non-terminal functions
------------------------------------------------------------------------
-- prototypes deleted; not required in Lua

------------------------------------------------------------------------
-- reanchor if last token is has a constant string, see close_func()
-- * used only in close_func()
------------------------------------------------------------------------
function luaY:anchor_token(ls)
	if ls.t.token == "TK_NAME" or ls.t.token == "TK_STRING" then
		-- not relevant to Lua implementation of parser
		-- local ts = ls.t.seminfo
		-- luaX_newstring(ls, getstr(ts), ts->tsv.len); /* C */
	end
end

------------------------------------------------------------------------
-- throws a syntax error if token expected is not there
------------------------------------------------------------------------
function luaY:error_expected(ls, token)
	luaX:syntaxerror(ls,
		string.format(self.LUA_QS.." expected", luaX:token2str(ls, token)))
end

------------------------------------------------------------------------
-- prepares error message for display, for limits exceeded
-- * used only in checklimit()
------------------------------------------------------------------------
function luaY:errorlimit(fs, limit, what)
	local msg = (fs.f.linedefined == 0) and
		string.format("main function has more than %d %s", limit, what) or
		string.format("function at line %d has more than %d %s",
			fs.f.linedefined, limit, what)
	luaX:lexerror(fs.ls, msg, 0)
end

------------------------------------------------------------------------
-- tests for a token, returns outcome
-- * return value changed to boolean
------------------------------------------------------------------------
function luaY:testnext(ls, c)
	if ls.t.token == c then
		luaX:next(ls)
		return true
	else
		return false
	end
end

------------------------------------------------------------------------
-- check for existence of a token, throws error if not found
------------------------------------------------------------------------
function luaY:check(ls, c)
	if ls.t.token ~= c then
		self:error_expected(ls, c)
	end
end

------------------------------------------------------------------------
-- verify existence of a token, then skip it
------------------------------------------------------------------------
function luaY:checknext(ls, c)
	self:check(ls, c)
	luaX:next(ls)
end

------------------------------------------------------------------------
-- throws error if condition not matched
------------------------------------------------------------------------
function luaY:check_condition(ls, c, msg)
	if not c then luaX:syntaxerror(ls, msg) end
end

------------------------------------------------------------------------
-- verifies token conditions are met or else throw error
------------------------------------------------------------------------
function luaY:check_match(ls, what, who, where)
	if not self:testnext(ls, what) then
		if where == ls.linenumber then
			self:error_expected(ls, what)
		else
			luaX:syntaxerror(ls, string.format(
				self.LUA_QS.." expected (to close "..self.LUA_QS.." at line %d)",
				luaX:token2str(ls, what), luaX:token2str(ls, who), where))
		end
	end
end

------------------------------------------------------------------------
-- expect that token is a name, return the name
------------------------------------------------------------------------
function luaY:str_checkname(ls)
	self:check(ls, "TK_NAME")
	local ts = ls.t.seminfo
	luaX:next(ls)
	return ts
end

------------------------------------------------------------------------
-- initialize a struct expdesc, expression description data structure
------------------------------------------------------------------------
function luaY:init_exp(e, k, i)
	e.f, e.t = luaK.NO_JUMP, luaK.NO_JUMP
	e.k = k
	e.info = i
end

------------------------------------------------------------------------
-- adds given string s in string pool, sets e as VK
------------------------------------------------------------------------
function luaY:codestring(ls, e, s)
	self:init_exp(e, "VK", luaK:stringK(ls.fs, s))
end

------------------------------------------------------------------------
-- consume a name token, adds it to string pool, sets e as VK
------------------------------------------------------------------------
function luaY:checkname(ls, e)
	self:codestring(ls, e, self:str_checkname(ls))
end

------------------------------------------------------------------------
-- creates struct entry for a local variable
-- * used only in new_localvar()
------------------------------------------------------------------------
function luaY:registerlocalvar(ls, varname)
	local fs = ls.fs
	local f = fs.f
	self:growvector(ls.L, f.locvars, fs.nlocvars, f.sizelocvars,
		nil, self.SHRT_MAX, "too many local variables")
	-- loop to initialize empty f.locvar positions not required
	f.locvars[fs.nlocvars] = {} -- LocVar
	f.locvars[fs.nlocvars].varname = varname
	-- luaC_objbarrier(ls.L, f, varname) /* GC */
	local nlocvars = fs.nlocvars
	fs.nlocvars = fs.nlocvars + 1
	return nlocvars
end

------------------------------------------------------------------------
-- creates a new local variable given a name and an offset from nactvar
-- * used in fornum(), forlist(), parlist(), body()
------------------------------------------------------------------------
function luaY:new_localvarliteral(ls, v, n)
	self:new_localvar(ls, v, n)
end

------------------------------------------------------------------------
-- register a local variable, set in active variable list
------------------------------------------------------------------------
function luaY:new_localvar(ls, name, n)
	local fs = ls.fs
	self:checklimit(fs, fs.nactvar + n + 1, self.LUAI_MAXVARS, "local variables")
	fs.actvar[fs.nactvar + n] = self:registerlocalvar(ls, name)
end

------------------------------------------------------------------------
-- adds nvars number of new local variables, set debug information
------------------------------------------------------------------------
function luaY:adjustlocalvars(ls, nvars)
	local fs = ls.fs
	fs.nactvar = fs.nactvar + nvars
	for i = nvars, 1, -1 do
		self:getlocvar(fs, fs.nactvar - i).startpc = fs.pc
	end
end

------------------------------------------------------------------------
-- removes a number of locals, set debug information
------------------------------------------------------------------------
function luaY:removevars(ls, tolevel)
	local fs = ls.fs
	while fs.nactvar > tolevel do
		fs.nactvar = fs.nactvar - 1
		self:getlocvar(fs, fs.nactvar).endpc = fs.pc
	end
end

------------------------------------------------------------------------
-- returns an existing upvalue index based on the given name, or
-- creates a new upvalue struct entry and returns the new index
-- * used only in singlevaraux()
------------------------------------------------------------------------
function luaY:indexupvalue(fs, name, v)
	local f = fs.f
	for i = 0, f.nups - 1 do
		if fs.upvalues[i].k == v.k and fs.upvalues[i].info == v.info then
			lua_assert(f.upvalues[i] == name)
			return i
		end
	end
	-- new one
	self:checklimit(fs, f.nups + 1, self.LUAI_MAXUPVALUES, "upvalues")
	self:growvector(fs.L, f.upvalues, f.nups, f.sizeupvalues,
		nil, self.MAX_INT, "")
	-- loop to initialize empty f.upvalues positions not required
	f.upvalues[f.nups] = name
	-- luaC_objbarrier(fs->L, f, name); /* GC */
	lua_assert(v.k == "VLOCAL" or v.k == "VUPVAL")
	-- this is a partial copy; only k & info fields used
	fs.upvalues[f.nups] = { k = v.k, info = v.info }
	local nups = f.nups
	f.nups = f.nups + 1
	return nups
end

------------------------------------------------------------------------
-- search the local variable namespace of the given fs for a match
-- * used only in singlevaraux()
------------------------------------------------------------------------
function luaY:searchvar(fs, n)
	for i = fs.nactvar - 1, 0, -1 do
		if n == self:getlocvar(fs, i).varname then
			return i
		end
	end
	return -1  -- not found
end

------------------------------------------------------------------------
-- * mark upvalue flags in function states up to a given level
-- * used only in singlevaraux()
------------------------------------------------------------------------
function luaY:markupval(fs, level)
	local bl = fs.bl
	while bl and bl.nactvar > level do bl = bl.previous end
	if bl then bl.upval = true end
end

------------------------------------------------------------------------
-- handle locals, globals and upvalues and related processing
-- * search mechanism is recursive, calls itself to search parents
-- * used only in singlevar()
------------------------------------------------------------------------
function luaY:singlevaraux(fs, n, var, base)
	if fs == nil then  -- no more levels?
		self:init_exp(var, "VGLOBAL", luaP.NO_REG)  -- default is global variable
		return "VGLOBAL"
	else
		local v = self:searchvar(fs, n)  -- look up at current level
		if v >= 0 then
			self:init_exp(var, "VLOCAL", v)
			if base == 0 then
				self:markupval(fs, v)  -- local will be used as an upval
			end
			return "VLOCAL"
		else  -- not found at current level; try upper one
			if self:singlevaraux(fs.prev, n, var, 0) == "VGLOBAL" then
				return "VGLOBAL"
			end
			var.info = self:indexupvalue(fs, n, var)  -- else was LOCAL or UPVAL
			var.k = "VUPVAL"  -- upvalue in this level
			return "VUPVAL"
		end--if v
	end--if fs
end

------------------------------------------------------------------------
-- consume a name token, creates a variable (global|local|upvalue)
-- * used in prefixexp(), funcname()
------------------------------------------------------------------------
function luaY:singlevar(ls, var)
	local varname = self:str_checkname(ls)
	local fs = ls.fs
	if self:singlevaraux(fs, varname, var, 1) == "VGLOBAL" then
		var.info = luaK:stringK(fs, varname)  -- info points to global name
	end
end

------------------------------------------------------------------------
-- adjust RHS to match LHS in an assignment
-- * used in assignment(), forlist(), localstat()
------------------------------------------------------------------------
function luaY:adjust_assign(ls, nvars, nexps, e)
	local fs = ls.fs
	local extra = nvars - nexps
	if self:hasmultret(e.k) then
		extra = extra + 1  -- includes call itself
		if extra <= 0 then extra = 0 end
		luaK:setreturns(fs, e, extra)  -- last exp. provides the difference
		if extra > 1 then luaK:reserveregs(fs, extra - 1) end
	else
		if e.k ~= "VVOID" then luaK:exp2nextreg(fs, e) end  -- close last expression
		if extra > 0 then
			local reg = fs.freereg
			luaK:reserveregs(fs, extra)
			luaK:_nil(fs, reg, extra)
		end
	end
end

------------------------------------------------------------------------
-- tracks and limits parsing depth, assert check at end of parsing
------------------------------------------------------------------------
function luaY:enterlevel(ls)
	ls.L.nCcalls = ls.L.nCcalls + 1
	if ls.L.nCcalls > self.LUAI_MAXCCALLS then
		luaX:lexerror(ls, "chunk has too many syntax levels", 0)
	end
end

------------------------------------------------------------------------
-- tracks parsing depth, a pair with luaY:enterlevel()
------------------------------------------------------------------------
function luaY:leavelevel(ls)
	ls.L.nCcalls = ls.L.nCcalls - 1
end

------------------------------------------------------------------------
-- enters a code unit, initializes elements
------------------------------------------------------------------------
function luaY:enterblock(fs, bl, isbreakable)
	bl.breaklist = luaK.NO_JUMP
	bl.isbreakable = isbreakable
	bl.nactvar = fs.nactvar
	bl.upval = false
	bl.previous = fs.bl
	fs.bl = bl
	lua_assert(fs.freereg == fs.nactvar)
end

------------------------------------------------------------------------
-- leaves a code unit, close any upvalues
------------------------------------------------------------------------
function luaY:leaveblock(fs)
	local bl = fs.bl
	fs.bl = bl.previous
	self:removevars(fs.ls, bl.nactvar)
	if bl.upval then
		luaK:codeABC(fs, "OP_CLOSE", bl.nactvar, 0, 0)
	end
	-- a block either controls scope or breaks (never both)
	lua_assert(not bl.isbreakable or not bl.upval)
	lua_assert(bl.nactvar == fs.nactvar)
	fs.freereg = fs.nactvar  -- free registers
	luaK:patchtohere(fs, bl.breaklist)
end

------------------------------------------------------------------------
-- implement the instantiation of a function prototype, append list of
-- upvalues after the instantiation instruction
-- * used only in body()
------------------------------------------------------------------------
function luaY:pushclosure(ls, func, v)
	local fs = ls.fs
	local f = fs.f
	self:growvector(ls.L, f.p, fs.np, f.sizep, nil,
		luaP.MAXARG_Bx, "constant table overflow")
	-- loop to initialize empty f.p positions not required
	f.p[fs.np] = func.f
	fs.np = fs.np + 1
	-- luaC_objbarrier(ls->L, f, func->f); /* C */
	self:init_exp(v, "VRELOCABLE", luaK:codeABx(fs, "OP_CLOSURE", 0, fs.np - 1))
	for i = 0, func.f.nups - 1 do
		local o = (func.upvalues[i].k == "VLOCAL") and "OP_MOVE" or "OP_GETUPVAL"
		luaK:codeABC(fs, o, 0, func.upvalues[i].info, 0)
	end
end

------------------------------------------------------------------------
-- opening of a function
------------------------------------------------------------------------
function luaY:open_func(ls, fs)
	local L = ls.L
	local f = self:newproto(ls.L)
	fs.f = f
	fs.prev = ls.fs  -- linked list of funcstates
	fs.ls = ls
	fs.L = L
	ls.fs = fs
	fs.pc = 0
	fs.lasttarget = -1
	fs.jpc = luaK.NO_JUMP
	fs.freereg = 0
	fs.nk = 0
	fs.np = 0
	fs.nlocvars = 0
	fs.nactvar = 0
	fs.bl = nil
	f.source = ls.source
	f.maxstacksize = 2  -- registers 0/1 are always valid
	fs.h = {}  -- constant table; was luaH_new call
	-- anchor table of constants and prototype (to avoid being collected)
	-- sethvalue2s(L, L->top, fs->h); incr_top(L); /* C */
	-- setptvalue2s(L, L->top, f); incr_top(L);
end

------------------------------------------------------------------------
-- closing of a function
------------------------------------------------------------------------
function luaY:close_func(ls)
	local L = ls.L
	local fs = ls.fs
	local f = fs.f
	self:removevars(ls, 0)
	luaK:ret(fs, 0, 0)  -- final return
	-- luaM_reallocvector deleted for f->code, f->lineinfo, f->k, f->p,
	-- f->locvars, f->upvalues; not required for Lua table arrays
	f.sizecode = fs.pc
	f.sizelineinfo = fs.pc
	f.sizek = fs.nk
	f.sizep = fs.np
	f.sizelocvars = fs.nlocvars
	f.sizeupvalues = f.nups
	--lua_assert(luaG_checkcode(f))  -- currently not implemented
	lua_assert(fs.bl == nil)
	ls.fs = fs.prev
	-- the following is not required for this implementation; kept here
	-- for completeness
	-- L->top -= 2;  /* remove table and prototype from the stack */
	-- last token read was anchored in defunct function; must reanchor it
	if fs then self:anchor_token(ls) end
end

------------------------------------------------------------------------
-- parser initialization function
-- * note additional sub-tables needed for LexState, FuncState
------------------------------------------------------------------------
function luaY:parser(L, z, buff, name)
	local lexstate = {}  -- LexState
	lexstate.t = {}
	lexstate.lookahead = {}
	local funcstate = {}  -- FuncState
	funcstate.upvalues = {}
	funcstate.actvar = {}
	-- the following nCcalls initialization added for convenience
	L.nCcalls = 0
	lexstate.buff = buff
	luaX:setinput(L, lexstate, z, name)
	self:open_func(lexstate, funcstate)
	funcstate.f.is_vararg = self.VARARG_ISVARARG  -- main func. is always vararg
	luaX:next(lexstate)  -- read first token
	self:chunk(lexstate)
	self:check(lexstate, "TK_EOS")
	self:close_func(lexstate)
	lua_assert(funcstate.prev == nil)
	lua_assert(funcstate.f.nups == 0)
	lua_assert(lexstate.fs == nil)
	return funcstate.f
end

--[[--------------------------------------------------------------------
-- GRAMMAR RULES
----------------------------------------------------------------------]]

------------------------------------------------------------------------
-- parse a function name suffix, for function call specifications
-- * used in primaryexp(), funcname()
------------------------------------------------------------------------
function luaY:field(ls, v)
	-- field -> ['.' | ':'] NAME
	local fs = ls.fs
	local key = {}  -- expdesc
	luaK:exp2anyreg(fs, v)
	luaX:next(ls)  -- skip the dot or colon
	self:checkname(ls, key)
	luaK:indexed(fs, v, key)
end

------------------------------------------------------------------------
-- parse a table indexing suffix, for constructors, expressions
-- * used in recfield(), primaryexp()
------------------------------------------------------------------------
function luaY:yindex(ls, v)
	-- index -> '[' expr ']'
	luaX:next(ls)  -- skip the '['
	self:expr(ls, v)
	luaK:exp2val(ls.fs, v)
	self:checknext(ls, "]")
end

--[[--------------------------------------------------------------------
-- Rules for Constructors
----------------------------------------------------------------------]]

--[[--------------------------------------------------------------------
-- struct ConsControl:
--   v  -- last list item read (table: struct expdesc)
--   t  -- table descriptor (table: struct expdesc)
--   nh  -- total number of 'record' elements
--   na  -- total number of array elements
--   tostore  -- number of array elements pending to be stored
----------------------------------------------------------------------]]

------------------------------------------------------------------------
-- parse a table record (hash) field
-- * used in constructor()
------------------------------------------------------------------------
function luaY:recfield(ls, cc)
	-- recfield -> (NAME | '['exp1']') = exp1
	local fs = ls.fs
	local reg = ls.fs.freereg
	local key, val = {}, {}  -- expdesc
	if ls.t.token == "TK_NAME" then
		self:checklimit(fs, cc.nh, self.MAX_INT, "items in a constructor")
		self:checkname(ls, key)
	else  -- ls->t.token == '['
		self:yindex(ls, key)
	end
	cc.nh = cc.nh + 1
	self:checknext(ls, "=")
	local rkkey = luaK:exp2RK(fs, key)
	self:expr(ls, val)
	luaK:codeABC(fs, "OP_SETTABLE", cc.t.info, rkkey, luaK:exp2RK(fs, val))
	fs.freereg = reg  -- free registers
end

------------------------------------------------------------------------
-- emit a set list instruction if enough elements (LFIELDS_PER_FLUSH)
-- * used in constructor()
------------------------------------------------------------------------
function luaY:closelistfield(fs, cc)
	if cc.v.k == "VVOID" then return end  -- there is no list item
	luaK:exp2nextreg(fs, cc.v)
	cc.v.k = "VVOID"
	if cc.tostore == luaP.LFIELDS_PER_FLUSH then
		luaK:setlist(fs, cc.t.info, cc.na, cc.tostore)  -- flush
		cc.tostore = 0  -- no more items pending
	end
end

------------------------------------------------------------------------
-- emit a set list instruction at the end of parsing list constructor
-- * used in constructor()
------------------------------------------------------------------------
function luaY:lastlistfield(fs, cc)
	if cc.tostore == 0 then return end
	if self:hasmultret(cc.v.k) then
		luaK:setmultret(fs, cc.v)
		luaK:setlist(fs, cc.t.info, cc.na, self.LUA_MULTRET)
		cc.na = cc.na - 1  -- do not count last expression (unknown number of elements)
	else
		if cc.v.k ~= "VVOID" then
			luaK:exp2nextreg(fs, cc.v)
		end
		luaK:setlist(fs, cc.t.info, cc.na, cc.tostore)
	end
end

------------------------------------------------------------------------
-- parse a table list (array) field
-- * used in constructor()
------------------------------------------------------------------------
function luaY:listfield(ls, cc)
	self:expr(ls, cc.v)
	self:checklimit(ls.fs, cc.na, self.MAX_INT, "items in a constructor")
	cc.na = cc.na + 1
	cc.tostore = cc.tostore + 1
end

------------------------------------------------------------------------
-- parse a table constructor
-- * used in funcargs(), simpleexp()
------------------------------------------------------------------------
function luaY:constructor(ls, t)
	-- constructor -> '{' [ field { fieldsep field } [ fieldsep ] ] '}'
	-- field -> recfield | listfield
	-- fieldsep -> ',' | ';'
	local fs = ls.fs
	local line = ls.linenumber
	local pc = luaK:codeABC(fs, "OP_NEWTABLE", 0, 0, 0)
	local cc = {}  -- ConsControl
	cc.v = {}
	cc.na, cc.nh, cc.tostore = 0, 0, 0
	cc.t = t
	self:init_exp(t, "VRELOCABLE", pc)
	self:init_exp(cc.v, "VVOID", 0)  -- no value (yet)
	luaK:exp2nextreg(ls.fs, t)  -- fix it at stack top (for gc)
	self:checknext(ls, "{")
	repeat
		lua_assert(cc.v.k == "VVOID" or cc.tostore > 0)
		if ls.t.token == "}" then break end
		self:closelistfield(fs, cc)
		local c = ls.t.token

		if c == "TK_NAME" then  -- may be listfields or recfields
			luaX:lookahead(ls)
			if ls.lookahead.token ~= "=" then  -- expression?
				self:listfield(ls, cc)
			else
				self:recfield(ls, cc)
			end
		elseif c == "[" then  -- constructor_item -> recfield
			self:recfield(ls, cc)
		else  -- constructor_part -> listfield
			self:listfield(ls, cc)
		end
	until not self:testnext(ls, ",") and not self:testnext(ls, ";")
	self:check_match(ls, "}", "{", line)
	self:lastlistfield(fs, cc)
	luaP:SETARG_B(fs.f.code[pc], self:int2fb(cc.na)) -- set initial array size
	luaP:SETARG_C(fs.f.code[pc], self:int2fb(cc.nh)) -- set initial table size
end

-- }======================================================================

------------------------------------------------------------------------
-- parse the arguments (parameters) of a function declaration
-- * used in body()
------------------------------------------------------------------------
function luaY:parlist(ls)
	-- parlist -> [ param { ',' param } ]
	local fs = ls.fs
	local f = fs.f
	local nparams = 0
	f.is_vararg = 0
	if ls.t.token ~= ")" then  -- is 'parlist' not empty?
		repeat
			local c = ls.t.token
			if c == "TK_NAME" then  -- param -> NAME
				self:new_localvar(ls, self:str_checkname(ls), nparams)
				nparams = nparams + 1
			elseif c == "TK_DOTS" then  -- param -> `...'
				luaX:next(ls)
				-- [[
				-- #if defined(LUA_COMPAT_VARARG)
				-- use `arg' as default name
				self:new_localvarliteral(ls, "arg", nparams)
				nparams = nparams + 1
				f.is_vararg = self.VARARG_HASARG + self.VARARG_NEEDSARG
				-- #endif
				--]]
				f.is_vararg = f.is_vararg + self.VARARG_ISVARARG
			else
				luaX:syntaxerror(ls, "<name> or "..self:LUA_QL("...").." expected")
			end
		until f.is_vararg ~= 0 or not self:testnext(ls, ",")
	end--if
	self:adjustlocalvars(ls, nparams)
	-- NOTE: the following works only when HASARG_MASK is 2!
	f.numparams = fs.nactvar - (f.is_vararg % self.HASARG_MASK)
	luaK:reserveregs(fs, fs.nactvar)  -- reserve register for parameters
end

------------------------------------------------------------------------
-- parse function declaration body
-- * used in simpleexp(), localfunc(), funcstat()
------------------------------------------------------------------------
function luaY:body(ls, e, needself, line)
	-- body ->  '(' parlist ')' chunk END
	local new_fs = {}  -- FuncState
	new_fs.upvalues = {}
	new_fs.actvar = {}
	self:open_func(ls, new_fs)
	new_fs.f.lineDefined = line
	self:checknext(ls, "(")
	if needself then
		self:new_localvarliteral(ls, "self", 0)
		self:adjustlocalvars(ls, 1)
	end
	self:parlist(ls)
	self:checknext(ls, ")")
	self:chunk(ls)
	new_fs.f.lastlinedefined = ls.linenumber
	self:check_match(ls, "TK_END", "TK_FUNCTION", line)
	self:close_func(ls)
	self:pushclosure(ls, new_fs, e)
end

------------------------------------------------------------------------
-- parse a list of comma-separated expressions
-- * used is multiple locations
------------------------------------------------------------------------
function luaY:explist1(ls, v)
	-- explist1 -> expr { ',' expr }
	local n = 1  -- at least one expression
	self:expr(ls, v)
	while self:testnext(ls, ",") do
		luaK:exp2nextreg(ls.fs, v)
		self:expr(ls, v)
		n = n + 1
	end
	return n
end

------------------------------------------------------------------------
-- parse the parameters of a function call
-- * contrast with parlist(), used in function declarations
-- * used in primaryexp()
------------------------------------------------------------------------
function luaY:funcargs(ls, f)
	local fs = ls.fs
	local args = {}  -- expdesc
	local nparams
	local line = ls.linenumber
	local c = ls.t.token
	if c == "(" then  -- funcargs -> '(' [ explist1 ] ')'
		if line ~= ls.lastline then
			luaX:syntaxerror(ls, "ambiguous syntax (function call x new statement)")
		end
		luaX:next(ls)
		if ls.t.token == ")" then  -- arg list is empty?
			args.k = "VVOID"
		else
			self:explist1(ls, args)
			luaK:setmultret(fs, args)
		end
		self:check_match(ls, ")", "(", line)
	elseif c == "{" then  -- funcargs -> constructor
		self:constructor(ls, args)
	elseif c == "TK_STRING" then  -- funcargs -> STRING
		self:codestring(ls, args, ls.t.seminfo)
		luaX:next(ls)  -- must use 'seminfo' before 'next'
	else
		luaX:syntaxerror(ls, "function arguments expected")
		return
	end
	lua_assert(f.k == "VNONRELOC")
	local base = f.info  -- base register for call
	if self:hasmultret(args.k) then
		nparams = self.LUA_MULTRET  -- open call
	else
		if args.k ~= "VVOID" then
			luaK:exp2nextreg(fs, args)  -- close last argument
		end
		nparams = fs.freereg - (base + 1)
	end
	self:init_exp(f, "VCALL", luaK:codeABC(fs, "OP_CALL", base, nparams + 1, 2))
	luaK:fixline(fs, line)
	fs.freereg = base + 1  -- call remove function and arguments and leaves
	-- (unless changed) one result
end

--[[--------------------------------------------------------------------
-- Expression parsing
----------------------------------------------------------------------]]

------------------------------------------------------------------------
-- parses an expression in parentheses or a single variable
-- * used in primaryexp()
------------------------------------------------------------------------
function luaY:prefixexp(ls, v)
	-- prefixexp -> NAME | '(' expr ')'
	local c = ls.t.token
	if c == "(" then
		local line = ls.linenumber
		luaX:next(ls)
		self:expr(ls, v)
		self:check_match(ls, ")", "(", line)
		luaK:dischargevars(ls.fs, v)
	elseif c == "TK_NAME" then
		self:singlevar(ls, v)
	else
		luaX:syntaxerror(ls, "unexpected symbol")
	end--if c
	return
end

------------------------------------------------------------------------
-- parses a prefixexp (an expression in parentheses or a single variable)
-- or a function call specification
-- * used in simpleexp(), assignment(), exprstat()
------------------------------------------------------------------------
function luaY:primaryexp(ls, v)
	-- primaryexp ->
	--    prefixexp { '.' NAME | '[' exp ']' | ':' NAME funcargs | funcargs }
	local fs = ls.fs
	self:prefixexp(ls, v)
	while true do
		local c = ls.t.token
		if c == "." then  -- field
			self:field(ls, v)
		elseif c == "[" then  -- '[' exp1 ']'
			local key = {}  -- expdesc
			luaK:exp2anyreg(fs, v)
			self:yindex(ls, key)
			luaK:indexed(fs, v, key)
		elseif c == ":" then  -- ':' NAME funcargs
			local key = {}  -- expdesc
			luaX:next(ls)
			self:checkname(ls, key)
			luaK:_self(fs, v, key)
			self:funcargs(ls, v)
		elseif c == "(" or c == "TK_STRING" or c == "{" then  -- funcargs
			luaK:exp2nextreg(fs, v)
			self:funcargs(ls, v)
		else
			return
		end--if c
	end--while
end

------------------------------------------------------------------------
-- parses general expression types, constants handled here
-- * used in subexpr()
------------------------------------------------------------------------
function luaY:simpleexp(ls, v)
	-- simpleexp -> NUMBER | STRING | NIL | TRUE | FALSE | ... |
	--              constructor | FUNCTION body | primaryexp
	local c = ls.t.token
	if c == "TK_NUMBER" then
		self:init_exp(v, "VKNUM", 0)
		v.nval = ls.t.seminfo
	elseif c == "TK_STRING" then
		self:codestring(ls, v, ls.t.seminfo)
	elseif c == "TK_NIL" then
		self:init_exp(v, "VNIL", 0)
	elseif c == "TK_TRUE" then
		self:init_exp(v, "VTRUE", 0)
	elseif c == "TK_FALSE" then
		self:init_exp(v, "VFALSE", 0)
	elseif c == "TK_DOTS" then  -- vararg
		local fs = ls.fs
		self:check_condition(ls, fs.f.is_vararg ~= 0,
			"cannot use "..self:LUA_QL("...").." outside a vararg function");
		-- NOTE: the following substitutes for a bitop, but is value-specific
		local is_vararg = fs.f.is_vararg
		if is_vararg >= self.VARARG_NEEDSARG then
			fs.f.is_vararg = is_vararg - self.VARARG_NEEDSARG  -- don't need 'arg'
		end
		self:init_exp(v, "VVARARG", luaK:codeABC(fs, "OP_VARARG", 0, 1, 0))
	elseif c == "{" then  -- constructor
		self:constructor(ls, v)
		return
	elseif c == "TK_FUNCTION" then
		luaX:next(ls)
		self:body(ls, v, false, ls.linenumber)
		return
	else
		self:primaryexp(ls, v)
		return
	end--if c
	luaX:next(ls)
end

------------------------------------------------------------------------
-- Translates unary operators tokens if found, otherwise returns
-- OPR_NOUNOPR. getunopr() and getbinopr() are used in subexpr().
-- * used in subexpr()
------------------------------------------------------------------------
function luaY:getunopr(op)
	if op == "TK_NOT" then
		return "OPR_NOT"
	elseif op == "-" then
		return "OPR_MINUS"
	elseif op == "#" then
		return "OPR_LEN"
	else
		return "OPR_NOUNOPR"
	end
end

------------------------------------------------------------------------
-- Translates binary operator tokens if found, otherwise returns
-- OPR_NOBINOPR. Code generation uses OPR_* style tokens.
-- * used in subexpr()
------------------------------------------------------------------------
luaY.getbinopr_table = {
	["+"] = "OPR_ADD",
	["-"] = "OPR_SUB",
	["*"] = "OPR_MUL",
	["/"] = "OPR_DIV",
	["%"] = "OPR_MOD",
	["^"] = "OPR_POW",
	["TK_CONCAT"] = "OPR_CONCAT",
	["TK_NE"] = "OPR_NE",
	["TK_EQ"] = "OPR_EQ",
	["<"] = "OPR_LT",
	["TK_LE"] = "OPR_LE",
	[">"] = "OPR_GT",
	["TK_GE"] = "OPR_GE",
	["TK_AND"] = "OPR_AND",
	["TK_OR"] = "OPR_OR",
}
function luaY:getbinopr(op)
	local opr = self.getbinopr_table[op]
	if opr then return opr else return "OPR_NOBINOPR" end
end

------------------------------------------------------------------------
-- the following priority table consists of pairs of left/right values
-- for binary operators (was a static const struct); grep for ORDER OPR
-- * the following struct is replaced:
--   static const struct {
--     lu_byte left;  /* left priority for each binary operator */
--     lu_byte right; /* right priority */
--   } priority[] = {  /* ORDER OPR */
------------------------------------------------------------------------
luaY.priority = {
	{6, 6}, {6, 6}, {7, 7}, {7, 7}, {7, 7}, -- `+' `-' `/' `%'
	{10, 9}, {5, 4},                 -- power and concat (right associative)
	{3, 3}, {3, 3},                  -- equality
	{3, 3}, {3, 3}, {3, 3}, {3, 3},  -- order
	{2, 2}, {1, 1}                   -- logical (and/or)
}

luaY.UNARY_PRIORITY = 8  -- priority for unary operators

------------------------------------------------------------------------
-- Parse subexpressions. Includes handling of unary operators and binary
-- operators. A subexpr is given the rhs priority level of the operator
-- immediately left of it, if any (limit is -1 if none,) and if a binop
-- is found, limit is compared with the lhs priority level of the binop
-- in order to determine which executes first.
------------------------------------------------------------------------

------------------------------------------------------------------------
-- subexpr -> (simpleexp | unop subexpr) { binop subexpr }
-- where 'binop' is any binary operator with a priority higher than 'limit'
-- * for priority lookups with self.priority[], 1=left and 2=right
-- * recursively called
-- * used in expr()
------------------------------------------------------------------------
function luaY:subexpr(ls, v, limit)
	self:enterlevel(ls)
	local uop = self:getunopr(ls.t.token)
	if uop ~= "OPR_NOUNOPR" then
		luaX:next(ls)
		self:subexpr(ls, v, self.UNARY_PRIORITY)
		luaK:prefix(ls.fs, uop, v)
	else
		self:simpleexp(ls, v)
	end
	-- expand while operators have priorities higher than 'limit'
	local op = self:getbinopr(ls.t.token)
	while op ~= "OPR_NOBINOPR" and self.priority[luaK.BinOpr[op] + 1][1] > limit do
		local v2 = {}  -- expdesc
		luaX:next(ls)
		luaK:infix(ls.fs, op, v)
		-- read sub-expression with higher priority
		local nextop = self:subexpr(ls, v2, self.priority[luaK.BinOpr[op] + 1][2])
		luaK:posfix(ls.fs, op, v, v2)
		op = nextop
	end
	self:leavelevel(ls)
	return op  -- return first untreated operator
end

------------------------------------------------------------------------
-- Expression parsing starts here. Function subexpr is entered with the
-- left operator (which is non-existent) priority of -1, which is lower
-- than all actual operators. Expr information is returned in parm v.
-- * used in multiple locations
------------------------------------------------------------------------
function luaY:expr(ls, v)
	self:subexpr(ls, v, 0)
end

-- }====================================================================

--[[--------------------------------------------------------------------
-- Rules for Statements
----------------------------------------------------------------------]]

------------------------------------------------------------------------
-- checks next token, used as a look-ahead
-- * returns boolean instead of 0|1
-- * used in retstat(), chunk()
------------------------------------------------------------------------
function luaY:block_follow(token)
	if token == "TK_ELSE" or token == "TK_ELSEIF" or token == "TK_END"
		or token == "TK_UNTIL" or token == "TK_EOS" then
		return true
	else
		return false
	end
end

------------------------------------------------------------------------
-- parse a code block or unit
-- * used in multiple functions
------------------------------------------------------------------------
function luaY:block(ls)
	-- block -> chunk
	local fs = ls.fs
	local bl = {}  -- BlockCnt
	self:enterblock(fs, bl, false)
	self:chunk(ls)
	lua_assert(bl.breaklist == luaK.NO_JUMP)
	self:leaveblock(fs)
end

------------------------------------------------------------------------
-- structure to chain all variables in the left-hand side of an
-- assignment
-- struct LHS_assign:
--   prev  -- (table: struct LHS_assign)
--   v  -- variable (global, local, upvalue, or indexed) (table: expdesc)
------------------------------------------------------------------------

------------------------------------------------------------------------
-- check whether, in an assignment to a local variable, the local variable
-- is needed in a previous assignment (to a table). If so, save original
-- local value in a safe place and use this safe copy in the previous
-- assignment.
-- * used in assignment()
------------------------------------------------------------------------
function luaY:check_conflict(ls, lh, v)
	local fs = ls.fs
	local extra = fs.freereg  -- eventual position to save local variable
	local conflict = false
	while lh do
		if lh.v.k == "VINDEXED" then
			if lh.v.info == v.info then  -- conflict?
				conflict = true
				lh.v.info = extra  -- previous assignment will use safe copy
			end
			if lh.v.aux == v.info then  -- conflict?
				conflict = true
				lh.v.aux = extra  -- previous assignment will use safe copy
			end
		end
		lh = lh.prev
	end
	if conflict then
		luaK:codeABC(fs, "OP_MOVE", fs.freereg, v.info, 0)  -- make copy
		luaK:reserveregs(fs, 1)
	end
end

------------------------------------------------------------------------
-- parse a variable assignment sequence
-- * recursively called
-- * used in exprstat()
------------------------------------------------------------------------
function luaY:assignment(ls, lh, nvars)
	local e = {}  -- expdesc
	-- test was: VLOCAL <= lh->v.k && lh->v.k <= VINDEXED
	local c = lh.v.k
	self:check_condition(ls, c == "VLOCAL" or c == "VUPVAL" or c == "VGLOBAL"
		or c == "VINDEXED", "syntax error")
	if self:testnext(ls, ",") then  -- assignment -> ',' primaryexp assignment
		local nv = {}  -- LHS_assign
		nv.v = {}
		nv.prev = lh
		self:primaryexp(ls, nv.v)
		if nv.v.k == "VLOCAL" then
			self:check_conflict(ls, lh, nv.v)
		end
		self:checklimit(ls.fs, nvars, self.LUAI_MAXCCALLS - ls.L.nCcalls,
			"variables in assignment")
		self:assignment(ls, nv, nvars + 1)
	else  -- assignment -> '=' explist1
		self:checknext(ls, "=")
		local nexps = self:explist1(ls, e)
		if nexps ~= nvars then
			self:adjust_assign(ls, nvars, nexps, e)
			if nexps > nvars then
				ls.fs.freereg = ls.fs.freereg - (nexps - nvars)  -- remove extra values
			end
		else
			luaK:setoneret(ls.fs, e)  -- close last expression
			luaK:storevar(ls.fs, lh.v, e)
			return  -- avoid default
		end
	end
	self:init_exp(e, "VNONRELOC", ls.fs.freereg - 1)  -- default assignment
	luaK:storevar(ls.fs, lh.v, e)
end

------------------------------------------------------------------------
-- parse condition in a repeat statement or an if control structure
-- * used in repeatstat(), test_then_block()
------------------------------------------------------------------------
function luaY:cond(ls)
	-- cond -> exp
	local v = {}  -- expdesc
	self:expr(ls, v)  -- read condition
	if v.k == "VNIL" then v.k = "VFALSE" end  -- 'falses' are all equal here
	luaK:goiftrue(ls.fs, v)
	return v.f
end

------------------------------------------------------------------------
-- parse a break statement
-- * used in statements()
------------------------------------------------------------------------
function luaY:breakstat(ls)
	-- stat -> BREAK
	local fs = ls.fs
	local bl = fs.bl
	local upval = false
	while bl and not bl.isbreakable do
		if bl.upval then upval = true end
		bl = bl.previous
	end
	if not bl then
		luaX:syntaxerror(ls, "no loop to break")
	end
	if upval then
		luaK:codeABC(fs, "OP_CLOSE", bl.nactvar, 0, 0)
	end
	bl.breaklist = luaK:concat(fs, bl.breaklist, luaK:jump(fs))
end

------------------------------------------------------------------------
-- parse a while-do control structure, body processed by block()
-- * with dynamic array sizes, MAXEXPWHILE + EXTRAEXP limits imposed by
--   the function's implementation can be removed
-- * used in statements()
------------------------------------------------------------------------
function luaY:whilestat(ls, line)
	-- whilestat -> WHILE cond DO block END
	local fs = ls.fs
	local bl = {}  -- BlockCnt
	luaX:next(ls)  -- skip WHILE
	local whileinit = luaK:getlabel(fs)
	local condexit = self:cond(ls)
	self:enterblock(fs, bl, true)
	self:checknext(ls, "TK_DO")
	self:block(ls)
	luaK:patchlist(fs, luaK:jump(fs), whileinit)
	self:check_match(ls, "TK_END", "TK_WHILE", line)
	self:leaveblock(fs)
	luaK:patchtohere(fs, condexit)  -- false conditions finish the loop
end

------------------------------------------------------------------------
-- parse a repeat-until control structure, body parsed by chunk()
-- * used in statements()
------------------------------------------------------------------------
function luaY:repeatstat(ls, line)
	-- repeatstat -> REPEAT block UNTIL cond
	local fs = ls.fs
	local repeat_init = luaK:getlabel(fs)
	local bl1, bl2 = {}, {}  -- BlockCnt
	self:enterblock(fs, bl1, true)  -- loop block
	self:enterblock(fs, bl2, false)  -- scope block
	luaX:next(ls)  -- skip REPEAT
	self:chunk(ls)
	self:check_match(ls, "TK_UNTIL", "TK_REPEAT", line)
	local condexit = self:cond(ls)  -- read condition (inside scope block)
	if not bl2.upval then  -- no upvalues?
		self:leaveblock(fs)  -- finish scope
		luaK:patchlist(ls.fs, condexit, repeat_init)  -- close the loop
	else  -- complete semantics when there are upvalues
		self:breakstat(ls)  -- if condition then break
		luaK:patchtohere(ls.fs, condexit)  -- else...
		self:leaveblock(fs)  -- finish scope...
		luaK:patchlist(ls.fs, luaK:jump(fs), repeat_init)  -- and repeat
	end
	self:leaveblock(fs)  -- finish loop
end

------------------------------------------------------------------------
-- parse the single expressions needed in numerical for loops
-- * used in fornum()
------------------------------------------------------------------------
function luaY:exp1(ls)
	local e = {}  -- expdesc
	self:expr(ls, e)
	local k = e.k
	luaK:exp2nextreg(ls.fs, e)
	return k
end

------------------------------------------------------------------------
-- parse a for loop body for both versions of the for loop
-- * used in fornum(), forlist()
------------------------------------------------------------------------
function luaY:forbody(ls, base, line, nvars, isnum)
	-- forbody -> DO block
	local bl = {}  -- BlockCnt
	local fs = ls.fs
	self:adjustlocalvars(ls, 3)  -- control variables
	self:checknext(ls, "TK_DO")
	local prep = isnum and luaK:codeAsBx(fs, "OP_FORPREP", base, luaK.NO_JUMP)
		or luaK:jump(fs)
	self:enterblock(fs, bl, false)  -- scope for declared variables
	self:adjustlocalvars(ls, nvars)
	luaK:reserveregs(fs, nvars)
	self:block(ls)
	self:leaveblock(fs)  -- end of scope for declared variables
	luaK:patchtohere(fs, prep)
	local endfor = isnum and luaK:codeAsBx(fs, "OP_FORLOOP", base, luaK.NO_JUMP)
		or luaK:codeABC(fs, "OP_TFORLOOP", base, 0, nvars)
	luaK:fixline(fs, line)  -- pretend that `OP_FOR' starts the loop
	luaK:patchlist(fs, isnum and endfor or luaK:jump(fs), prep + 1)
end

------------------------------------------------------------------------
-- parse a numerical for loop, calls forbody()
-- * used in forstat()
------------------------------------------------------------------------
function luaY:fornum(ls, varname, line)
	-- fornum -> NAME = exp1,exp1[,exp1] forbody
	local fs = ls.fs
	local base = fs.freereg
	self:new_localvarliteral(ls, "(for index)", 0)
	self:new_localvarliteral(ls, "(for limit)", 1)
	self:new_localvarliteral(ls, "(for step)", 2)
	self:new_localvar(ls, varname, 3)
	self:checknext(ls, '=')
	self:exp1(ls)  -- initial value
	self:checknext(ls, ",")
	self:exp1(ls)  -- limit
	if self:testnext(ls, ",") then
		self:exp1(ls)  -- optional step
	else  -- default step = 1
		luaK:codeABx(fs, "OP_LOADK", fs.freereg, luaK:numberK(fs, 1))
		luaK:reserveregs(fs, 1)
	end
	self:forbody(ls, base, line, 1, true)
end

------------------------------------------------------------------------
-- parse a generic for loop, calls forbody()
-- * used in forstat()
------------------------------------------------------------------------
function luaY:forlist(ls, indexname)
	-- forlist -> NAME {,NAME} IN explist1 forbody
	local fs = ls.fs
	local e = {}  -- expdesc
	local nvars = 0
	local base = fs.freereg
	-- create control variables
	self:new_localvarliteral(ls, "(for generator)", nvars)
	nvars = nvars + 1
	self:new_localvarliteral(ls, "(for state)", nvars)
	nvars = nvars + 1
	self:new_localvarliteral(ls, "(for control)", nvars)
	nvars = nvars + 1
	-- create declared variables
	self:new_localvar(ls, indexname, nvars)
	nvars = nvars + 1
	while self:testnext(ls, ",") do
		self:new_localvar(ls, self:str_checkname(ls), nvars)
		nvars = nvars + 1
	end
	self:checknext(ls, "TK_IN")
	local line = ls.linenumber
	self:adjust_assign(ls, 3, self:explist1(ls, e), e)
	luaK:checkstack(fs, 3)  -- extra space to call generator
	self:forbody(ls, base, line, nvars - 3, false)
end

------------------------------------------------------------------------
-- initial parsing for a for loop, calls fornum() or forlist()
-- * used in statements()
------------------------------------------------------------------------
function luaY:forstat(ls, line)
	-- forstat -> FOR (fornum | forlist) END
	local fs = ls.fs
	local bl = {}  -- BlockCnt
	self:enterblock(fs, bl, true)  -- scope for loop and control variables
	luaX:next(ls)  -- skip `for'
	local varname = self:str_checkname(ls)  -- first variable name
	local c = ls.t.token
	if c == "=" then
		self:fornum(ls, varname, line)
	elseif c == "," or c == "TK_IN" then
		self:forlist(ls, varname)
	else
		luaX:syntaxerror(ls, self:LUA_QL("=").." or "..self:LUA_QL("in").." expected")
	end
	self:check_match(ls, "TK_END", "TK_FOR", line)
	self:leaveblock(fs)  -- loop scope (`break' jumps to this point)
end

------------------------------------------------------------------------
-- parse part of an if control structure, including the condition
-- * used in ifstat()
------------------------------------------------------------------------
function luaY:test_then_block(ls)
	-- test_then_block -> [IF | ELSEIF] cond THEN block
	luaX:next(ls)  -- skip IF or ELSEIF
	local condexit = self:cond(ls)
	self:checknext(ls, "TK_THEN")
	self:block(ls)  -- `then' part
	return condexit
end

------------------------------------------------------------------------
-- parse an if control structure
-- * used in statements()
------------------------------------------------------------------------
function luaY:ifstat(ls, line)
	-- ifstat -> IF cond THEN block {ELSEIF cond THEN block} [ELSE block] END
	local fs = ls.fs
	local escapelist = luaK.NO_JUMP
	local flist = self:test_then_block(ls)  -- IF cond THEN block
	while ls.t.token == "TK_ELSEIF" do
		escapelist = luaK:concat(fs, escapelist, luaK:jump(fs))
		luaK:patchtohere(fs, flist)
		flist = self:test_then_block(ls)  -- ELSEIF cond THEN block
	end
	if ls.t.token == "TK_ELSE" then
		escapelist = luaK:concat(fs, escapelist, luaK:jump(fs))
		luaK:patchtohere(fs, flist)
		luaX:next(ls)  -- skip ELSE (after patch, for correct line info)
		self:block(ls)  -- 'else' part
	else
		escapelist = luaK:concat(fs, escapelist, flist)
	end
	luaK:patchtohere(fs, escapelist)
	self:check_match(ls, "TK_END", "TK_IF", line)
end

------------------------------------------------------------------------
-- parse a local function statement
-- * used in statements()
------------------------------------------------------------------------
function luaY:localfunc(ls)
	local v, b = {}, {}  -- expdesc
	local fs = ls.fs
	self:new_localvar(ls, self:str_checkname(ls), 0)
	self:init_exp(v, "VLOCAL", fs.freereg)
	luaK:reserveregs(fs, 1)
	self:adjustlocalvars(ls, 1)
	self:body(ls, b, false, ls.linenumber)
	luaK:storevar(fs, v, b)
	-- debug information will only see the variable after this point!
	self:getlocvar(fs, fs.nactvar - 1).startpc = fs.pc
end

------------------------------------------------------------------------
-- parse a local variable declaration statement
-- * used in statements()
------------------------------------------------------------------------
function luaY:localstat(ls)
	-- stat -> LOCAL NAME {',' NAME} ['=' explist1]
	local nvars = 0
	local nexps
	local e = {}  -- expdesc
	repeat
		self:new_localvar(ls, self:str_checkname(ls), nvars)
		nvars = nvars + 1
	until not self:testnext(ls, ",")
	if self:testnext(ls, "=") then
		nexps = self:explist1(ls, e)
	else
		e.k = "VVOID"
		nexps = 0
	end
	self:adjust_assign(ls, nvars, nexps, e)
	self:adjustlocalvars(ls, nvars)
end

------------------------------------------------------------------------
-- parse a function name specification
-- * used in funcstat()
------------------------------------------------------------------------
function luaY:funcname(ls, v)
	-- funcname -> NAME {field} [':' NAME]
	local needself = false
	self:singlevar(ls, v)
	while ls.t.token == "." do
		self:field(ls, v)
	end
	if ls.t.token == ":" then
		needself = true
		self:field(ls, v)
	end
	return needself
end

------------------------------------------------------------------------
-- parse a function statement
-- * used in statements()
------------------------------------------------------------------------
function luaY:funcstat(ls, line)
	-- funcstat -> FUNCTION funcname body
	local v, b = {}, {}  -- expdesc
	luaX:next(ls)  -- skip FUNCTION
	local needself = self:funcname(ls, v)
	self:body(ls, b, needself, line)
	luaK:storevar(ls.fs, v, b)
	luaK:fixline(ls.fs, line)  -- definition 'happens' in the first line
end

------------------------------------------------------------------------
-- parse a function call with no returns or an assignment statement
-- * used in statements()
------------------------------------------------------------------------
function luaY:exprstat(ls)
	-- stat -> func | assignment
	local fs = ls.fs
	local v = {}  -- LHS_assign
	v.v = {}
	self:primaryexp(ls, v.v)
	if v.v.k == "VCALL" then  -- stat -> func
		luaP:SETARG_C(luaK:getcode(fs, v.v), 1)  -- call statement uses no results
	else  -- stat -> assignment
		v.prev = nil
		self:assignment(ls, v, 1)
	end
end

------------------------------------------------------------------------
-- parse a return statement
-- * used in statements()
------------------------------------------------------------------------
function luaY:retstat(ls)
	-- stat -> RETURN explist
	local fs = ls.fs
	local e = {}  -- expdesc
	local first, nret  -- registers with returned values
	luaX:next(ls)  -- skip RETURN
	if self:block_follow(ls.t.token) or ls.t.token == ";" then
		first, nret = 0, 0  -- return no values
	else
		nret = self:explist1(ls, e)  -- optional return values
		if self:hasmultret(e.k) then
			luaK:setmultret(fs, e)
			if e.k == "VCALL" and nret == 1 then  -- tail call?
				luaP:SET_OPCODE(luaK:getcode(fs, e), "OP_TAILCALL")
				lua_assert(luaP:GETARG_A(luaK:getcode(fs, e)) == fs.nactvar)
			end
			first = fs.nactvar
			nret = self.LUA_MULTRET  -- return all values
		else
			if nret == 1 then  -- only one single value?
				first = luaK:exp2anyreg(fs, e)
			else
				luaK:exp2nextreg(fs, e)  -- values must go to the 'stack'
				first = fs.nactvar  -- return all 'active' values
				lua_assert(nret == fs.freereg - first)
			end
		end--if
	end--if
	luaK:ret(fs, first, nret)
end

------------------------------------------------------------------------
-- initial parsing for statements, calls a lot of functions
-- * returns boolean instead of 0|1
-- * used in chunk()
------------------------------------------------------------------------
function luaY:statement(ls)
	local line = ls.linenumber  -- may be needed for error messages
	local c = ls.t.token
	if c == "TK_IF" then  -- stat -> ifstat
		self:ifstat(ls, line)
		return false
	elseif c == "TK_WHILE" then  -- stat -> whilestat
		self:whilestat(ls, line)
		return false
	elseif c == "TK_DO" then  -- stat -> DO block END
		luaX:next(ls)  -- skip DO
		self:block(ls)
		self:check_match(ls, "TK_END", "TK_DO", line)
		return false
	elseif c == "TK_FOR" then  -- stat -> forstat
		self:forstat(ls, line)
		return false
	elseif c == "TK_REPEAT" then  -- stat -> repeatstat
		self:repeatstat(ls, line)
		return false
	elseif c == "TK_FUNCTION" then  -- stat -> funcstat
		self:funcstat(ls, line)
		return false
	elseif c == "TK_LOCAL" then  -- stat -> localstat
		luaX:next(ls)  -- skip LOCAL
		if self:testnext(ls, "TK_FUNCTION") then  -- local function?
			self:localfunc(ls)
		else
			self:localstat(ls)
		end
		return false
	elseif c == "TK_RETURN" then  -- stat -> retstat
		self:retstat(ls)
		return true  -- must be last statement
	elseif c == "TK_BREAK" then  -- stat -> breakstat
		luaX:next(ls)  -- skip BREAK
		self:breakstat(ls)
		return true  -- must be last statement
	else
		self:exprstat(ls)
		return false  -- to avoid warnings
	end--if c
end

------------------------------------------------------------------------
-- parse a chunk, which consists of a bunch of statements
-- * used in parser(), body(), block(), repeatstat()
------------------------------------------------------------------------
function luaY:chunk(ls)
	-- chunk -> { stat [';'] }
	local islast = false
	self:enterlevel(ls)
	while not islast and not self:block_follow(ls.t.token) do
		islast = self:statement(ls)
		self:testnext(ls, ";")
		lua_assert(ls.fs.f.maxstacksize >= ls.fs.freereg and
			ls.fs.freereg >= ls.fs.nactvar)
		ls.fs.freereg = ls.fs.nactvar  -- free registers
	end
	self:leavelevel(ls)
end

-- }======================================================================





luaX:init()  -- required by llex
local LuaState = {}  -- dummy, not actually used, but retained since
-- the intention is to complete a straight port

------------------------------------------------------------------------
-- interfacing to yueliang
------------------------------------------------------------------------


local compile = function (source, name)
	name = name or 'compiled-lua'
	-- luaZ:make_getF returns a file chunk reader
	-- luaZ:init returns a zio input stream
	local zio = luaZ:init(luaZ:make_getF(source), nil)
	if not zio then return end
	-- luaY:parser parses the input stream
	-- func is the function prototype in tabular form; in C, func can
	-- now be used directly by the VM, this can't be done in Lua

	local func = luaY:parser(LuaState, zio, nil, "@"..name)
	-- luaU:make_setS returns a string chunk writer
	local writer, buff = luaU:make_setS()
	-- luaU:dump builds a binary chunk
	luaU:dump(LuaState, func, writer, buff)
	-- a string.dump equivalent in returned

	return buff.data
end

-- https://github.com/JustAPerson/lbi/blob/master/src/lbi.lua

local lua_opcode_types = {
	"ABC",  "ABx", "ABC",  "ABC",
	"ABC",  "ABx", "ABC",  "ABx",
	"ABC",  "ABC", "ABC",  "ABC",
	"ABC",  "ABC", "ABC",  "ABC",
	"ABC",  "ABC", "ABC",  "ABC",
	"ABC",  "ABC", "AsBx", "ABC",
	"ABC",  "ABC", "ABC",  "ABC",
	"ABC",  "ABC", "ABC",  "AsBx",
	"AsBx", "ABC", "ABC", "ABC",
	"ABx",  "ABC",
}

local lua_opcode_names = {
	"MOVE",     "LOADK",     "LOADBOOL", "LOADNIL",
	"GETUPVAL", "GETGLOBAL", "GETTABLE", "SETGLOBAL",
	"SETUPVAL", "SETTABLE",  "NEWTABLE", "SELF",
	"ADD",      "SUB",       "MUL",      "DIV",
	"MOD",      "POW",       "UNM",      "NOT",
	"LEN",      "CONCAT",    "JMP",      "EQ",
	"LT",       "LE",        "TEST",     "TESTSET",
	"CALL",     "TAILCALL",  "RETURN",   "FORLOOP",
	"FORPREP",  "TFORLOOP",  "SETLIST",  "CLOSE",
	"CLOSURE",  "VARARG"
};

--[[
local lua_opcode_numbers = {};
for number, name in next, lua_opcode_names do
	lua_opcode_numbers[name] = number;
end
--]]

--- Extract bits from an integer
--@author: Stravant
local function get_bits(input, n, n2)
	if n2 then
		local total = 0
		local digitn = 0
		for i = n, n2 do
			total = total + 2^digitn*get_bits(input, i)
			digitn = digitn + 1
		end
		return total
	else
		local pn = 2^(n-1)
		return (input % (pn + pn) >= pn) and 1 or 0
	end
end

local function decode_bytecode(bytecode)
	local index = 1
	local big_endian = false
	local int_size;
	local size_t;

	-- Actual binary decoding functions. Dependant on the bytecode.
	local get_int, get_size_t;

	-- Binary decoding helper functions
	local get_int8, get_int32, get_int64, get_float64, get_string;
	do
		function get_int8()
			local a = bytecode:byte(index, index);
			index = index + 1
			return a
		end
		function get_int32()
			local a, b, c, d = bytecode:byte(index, index + 3);
			index = index + 4;
			return d*16777216 + c*65536 + b*256 + a
		end
		function get_int64()
			local a = get_int32();
			local b = get_int32();
			return b*4294967296 + a;
		end
		function get_float64()
			local a = get_int32()
			local b = get_int32()
			return (-2*get_bits(b, 32)+1)*(2^(get_bits(b, 21, 31)-1023))*
				((get_bits(b, 1, 20)*(2^32) + a)/(2^52)+1)
		end
		function get_string(len)
			local str;
			if len then
				str = bytecode:sub(index, index + len - 1);
				index = index + len;
			else
				len = get_size_t();
				if len == 0 then return; end
				str = bytecode:sub(index, index + len - 1);
				index = index + len;
			end
			return str;
		end
	end

	local function decode_chunk()
		local chunk;
		local instructions = {};
		local constants    = {};
		local prototypes   = {};
		local debug = {
			lines = {};
		};

		chunk = {
			instructions = instructions;
			constants    = constants;
			prototypes   = prototypes;
			debug = debug;
		};

		local num;

		chunk.name       = get_string();-- Function name
		chunk.first_line = get_int();	-- First line
		chunk.last_line  = get_int();	-- Last  line

		if chunk.name then chunk.name = chunk.name:sub(1, -2); end

		chunk.upvalues  = get_int8();
		chunk.arguments = get_int8();
		chunk.varg      = get_int8();
		chunk.stack     = get_int8();

		-- TODO: realign lists to 1
		-- Decode instructions
		do
			num = get_int();
			for i = 1, num do
				local instruction = {
					-- opcode = opcode number;
					-- type   = [ABC, ABx, AsBx]
					-- A, B, C, Bx, or sBx depending on type
				};

				local data   = get_int32();
				local opcode = get_bits(data, 1, 6);
				local type   = lua_opcode_types[opcode + 1];

				instruction.opcode = opcode;
				instruction.type   = type;

				instruction.A = get_bits(data, 7, 14);
				if type == "ABC" then
					instruction.B = get_bits(data, 24, 32);
					instruction.C = get_bits(data, 15, 23);
				elseif type == "ABx" then
					instruction.Bx = get_bits(data, 15, 32);
				elseif type == "AsBx" then
					instruction.sBx = get_bits(data, 15, 32) - 131071;
				end

				instructions[i] = instruction;
			end
		end

		-- Decode constants
		do
			num = get_int();
			for i = 1, num do
				local constant = {
					-- type = constant type;
					-- data = constant data;
				};
				local type = get_int8();
				constant.type = type;

				if type == 1 then
					constant.data = (get_int8() ~= 0);
				elseif type == 3 then
					constant.data = get_float64();
				elseif type == 4 then
					constant.data = get_string():sub(1, -2);
				end

				constants[i-1] = constant;
			end
		end

		-- Decode Prototypes
		do
			num = get_int();
			for i = 1, num do
				prototypes[i-1] = decode_chunk();
			end
		end

		-- Decode debug info
		-- Not all of which is used yet.
		do
			-- line numbers
			local data = debug.lines
			num = get_int();
			for i = 1, num do
				data[i] = get_int32();
			end

			-- locals
			num = get_int();
			for i = 1, num do
				get_string():sub(1, -2);	-- local name
				get_int32();	-- local start PC
				get_int32();	-- local end   PC
			end

			-- upvalues
			num = get_int();
			for i = 1, num do
				get_string();	-- upvalue name
			end
		end

		return chunk;
	end

	-- Verify bytecode header
	do
		assert(get_string(4) == "\27Lua", "Lua bytecode expected.");
		assert(get_int8() == 0x51, "Only Lua 5.1 is supported.");
		get_int8(); 	-- Oficial bytecode
		big_endian = (get_int8() == 0);
		int_size = get_int8();
		size_t   = get_int8();

		if int_size == 4 then
			get_int = get_int32;
		elseif int_size == 8 then
			get_int = get_int64;
		else
			-- TODO: refactor errors into table
			error("Unsupported bytecode target platform");
		end

		if size_t == 4 then
			get_size_t = get_int32;
		elseif size_t == 8 then
			get_size_t = get_int64;
		else
			error("Unsupported bytecode target platform");
		end

		assert(get_string(3) == "\4\8\0",
			"Unsupported bytecode target platform");
	end

	return decode_chunk();
end

local function handle_return(...)
	local c = select("#", ...)
	local t = {...}
	return c, t
end

local function create_wrapper(cache, upvalues)
	local instructions = cache.instructions;
	local constants    = cache.constants;
	local prototypes   = cache.prototypes;

	local stack, top
	local environment
	local IP = 1;	-- instruction pointer
	local vararg, vararg_size

	local opcode_funcs = {
		[0]  = function(instruction)	-- MOVE
			stack[instruction.A] = stack[instruction.B];
		end,
		[1]  = function(instruction)	-- LOADK
			stack[instruction.A] = constants[instruction.Bx].data;
		end,
		[2]  = function(instruction)	-- LOADBOOL
			stack[instruction.A] = instruction.B ~= 0
			if instruction.C ~= 0 then
				IP = IP + 1
			end
		end,
		[3]  = function(instruction)	-- LOADNIL
			local stack = stack
			for i = instruction.A, instruction.B do
				stack[i] = nil
			end
		end,
		[4] = function(instruction)		-- GETUPVAL
			stack[instruction.A] = upvalues[instruction.B]
		end,
		[5]  = function(instruction)	-- GETGLOBAL
			local key = constants[instruction.Bx].data;
			stack[instruction.A] = environment[key];
		end,
		[6]  = function(instruction)	-- GETTABLE
			local C = instruction.C
			local stack = stack
			C = C > 255 and constants[C-256].data or stack[C]
			stack[instruction.A] = stack[instruction.B][C];
		end,
		[7]  = function(instruction)	-- SETGLOBAL
			local key = constants[instruction.Bx].data;
			environment[key] = stack[instruction.A];
		end,
		[8] = function (instruction)	-- SETUPVAL
			upvalues[instruction.B] = stack[instruction.A]
		end,
		[9] = function (instruction)	-- SETTABLE
			local B = instruction.B;
			local C = instruction.C;
			local stack, constants = stack, constants;

			B = B > 255 and constants[B-256].data or stack[B];
			C = C > 255 and constants[C-256].data or stack[C];

			stack[instruction.A][B] = C
		end,
		[10] = function (instruction)	-- NEWTABLE
			stack[instruction.A] = {}
		end,
		[11] = function (instruction)	-- SELF
			local A = instruction.A
			local B = instruction.B
			local C = instruction.C
			local stack = stack

			B = stack[B]
			C = C > 255 and constants[C-256].data or stack[C]

			stack[A+1] = B
			stack[A]   = B[C]
		end,
		[12] = function(instruction)	-- ADD
			local B = instruction.B;
			local C = instruction.C;
			local stack, constants = stack, constants;

			B = B > 255 and constants[B-256].data or stack[B];
			C = C > 255 and constants[C-256].data or stack[C];

			stack[instruction.A] = B+C;
		end,
		[13] = function(instruction)	-- SUB
			local B = instruction.B;
			local C = instruction.C;
			local stack, constants = stack, constants;

			B = B > 255 and constants[B-256].data or stack[B];
			C = C > 255 and constants[C-256].data or stack[C];

			stack[instruction.A] = B - C;
		end,
		[14] = function(instruction)	-- MUL
			local B = instruction.B;
			local C = instruction.C;
			local stack, constants = stack, constants;

			B = B > 255 and constants[B-256].data or stack[B];
			C = C > 255 and constants[C-256].data or stack[C];

			stack[instruction.A] = B * C;
		end,
		[15] = function(instruction)	--DIV
			local B = instruction.B;
			local C = instruction.C;
			local stack, constants = stack, constants;

			B = B > 255 and constants[B-256].data or stack[B];
			C = C > 255 and constants[C-256].data or stack[C];

			stack[instruction.A] = B / C;
		end,
		[16] = function(instruction) 	-- MOD
			local B = instruction.B;
			local C = instruction.C;
			local stack, constants = stack, constants;

			B = B > 255 and constants[B-256].data or stack[B];
			C = C > 255 and constants[C-256].data or stack[C];

			stack[instruction.A] = B % C;
		end,
		[17] = function(instruction)	-- POW
			local B = instruction.B;
			local C = instruction.C;
			local stack, constants = stack, constants;

			B = B > 255 and constants[B-256].data or stack[B];
			C = C > 255 and constants[C-256].data or stack[C];

			stack[instruction.A] = B ^ C;
		end,
		[18] = function(instruction)	-- UNM
			stack[instruction.A] = -stack[instruction.B]
		end,
		[19] = function(instruction)	-- NOT
			stack[instruction.A] = not stack[instruction.B]
		end,
		[20] = function(instruction)	-- LEN
			stack[instruction.A] = #stack[instruction.B]
		end,
		[21] = function(instruction)	-- CONCAT
			local B = instruction.B
			local result = stack[B]
			for i = B+1, instruction.C do
				result = result .. stack[i]
			end
			stack[instruction.A] = result
		end,
		[22] = function(instruction)	-- JUMP
			IP = IP + instruction.sBx
		end,
		[23] = function(instruction)	-- EQ
			local A = instruction.A
			local B = instruction.B
			local C = instruction.C
			local stack, constants = stack, constants

			A = A ~= 0
			if (B > 255) then B = constants[B-256].data else B = stack[B] end
			if (C > 255) then C = constants[C-256].data else C = stack[C] end
			if (B == C) ~= A then
				IP = IP + 1
			end
		end,
		[24] = function(instruction)	-- LT
			local A = instruction.A
			local B = instruction.B
			local C = instruction.C
			local stack, constants = stack, constants

			A = A ~= 0
			B = B > 255 and constants[B-256].data or stack[B]
			C = C > 255 and constants[C-256].data or stack[C]
			if (B < C) ~= A then
				IP = IP + 1
			end
		end,
		[25] = function(instruction)	-- LT
			local A = instruction.A
			local B = instruction.B
			local C = instruction.C
			local stack, constants = stack, constants

			A = A ~= 0
			B = B > 255 and constants[B-256].data or stack[B]
			C = C > 255 and constants[C-256].data or stack[C]
			if (B <= C) ~= A then
				IP = IP + 1
			end
		end,
		[26] = function(instruction)	-- TEST
			local A = stack[instruction.A];
			if (not not A) == (instruction.C == 0) then
				IP = IP + 1
			end
		end,
		[27] = function(instruction)	-- TESTSET
			local stack = stack
			local B = stack[instruction.B]

			if (not not B) == (instruction.C == 0) then
				IP = IP + 1
			else
				stack[instruction.A] = B
			end
		end,
		[28] = function(instruction)	-- CALL
			local A = instruction.A;
			local B = instruction.B;
			local C = instruction.C;
			local stack = stack;
			local args, results;
			local limit, loop

			args = {};
			if B ~= 1 then
				if B ~= 0 then
					limit = A+B-1;
				else
					limit = top
				end

				loop = 0
				for i = A+1, limit do
					loop = loop + 1
					args[loop] = stack[i];
				end

				limit, results = handle_return(stack[A](unpack(args, 1, limit-A)))
			else
				limit, results = handle_return(stack[A]())
			end

			top = A - 1

			if C ~= 1 then
				if C ~= 0 then
					limit = A+C-2;
				else
					limit = limit+A
				end

				loop = 0;
				for i = A, limit do
					loop = loop + 1;
					stack[i] = results[loop];
				end
			end
		end,
		[29] = function (instruction)	-- TAILCALL
			local A = instruction.A;
			local B = instruction.B;
			local C = instruction.C;
			local stack = stack;
			local args, results;
			local top, limit, loop = top

			args = {};
			if B ~= 1 then
				if B ~= 0 then
					limit = A+B-1;
				else
					limit = top
				end

				loop = 0
				for i = A+1, limit do
					loop = loop + 1
					args[#args+1] = stack[i];
				end

				results = {stack[A](unpack(args, 1, limit-A))};
			else
				results = {stack[A]()};
			end

			return true, results
		end,
		[30] = function(instruction) -- RETURN
			--TODO: CLOSE
			local A = instruction.A;
			local B = instruction.B;
			local stack = stack;
			local limit;
			local loop, output;

			if B == 1 then
				return true;
			end
			if B == 0 then
				limit = top
			else
				limit = A + B - 2;
			end

			output = {};
			local loop = 0
			for i = A, limit do
				loop = loop + 1
				output[loop] = stack[i];
			end
			return true, output;
		end,
		[31] = function(instruction)	-- FORLOOP
			local A = instruction.A
			local stack = stack

			local step = stack[A+2]
			local index = stack[A] + step
			stack[A] = index

			if step > 0 then
				if index <= stack[A+1] then
					IP = IP + instruction.sBx
					stack[A+3] = index
				end
			else
				if index >= stack[A+1] then
					IP = IP + instruction.sBx
					stack[A+3] = index
				end
			end
		end,
		[32] = function(instruction)	-- FORPREP
			local A = instruction.A
			local stack = stack

			stack[A] = stack[A] - stack[A+2]
			IP = IP + instruction.sBx
		end,
		[33] = function(instruction)	-- TFORLOOP
			local A = instruction.A
			local B = instruction.B
			local C = instruction.C
			local stack = stack

			local offset = A+2
			local result = {stack[A](stack[A+1], stack[A+2])}
			for i = 1, C do
				stack[offset+i] = result[i]
			end

			if stack[A+3] ~= nil then
				stack[A+2] = stack[A+3]
			else
				IP = IP + 1
			end
		end,
		[34] = function(instruction)	-- SETLIST
			local A = instruction.A
			local B = instruction.B
			local C = instruction.C
			local stack = stack

			if C == 0 then
				error("NYI: extended SETLIST")
			else
				local offset = (C - 1) * 50
				local t = stack[A]

				if B == 0 then
					B = top
				end
				for i = 1, B do
					t[offset+i] = stack[A+i]
				end
			end
		end,
		[35] = function(instruction)	-- CLOSE
			io.stderr:write("NYI: CLOSE")
			io.stderr:flush()
		end,
		[36] = function(instruction)	-- CLOSURE
			local proto = prototypes[instruction.Bx]
			local instructions = instructions
			local stack = stack

			local indices = {}
			local new_upvals = setmetatable({},
			{
				__index = function(t, k)
					local upval = indices[k]
					return upval.segment[upval.offset]
				end,
				__newindex = function(t, k, v)
					local upval = indices[k]
					upval.segment[upval.offset] = v
				end
			}
			)
			for i = 1, proto.upvalues do
				local movement = instructions[IP]
				if movement.opcode == 0 then -- MOVE
					indices[i-1] = {segment = stack, offset = movement.B}
				elseif instructions[IP].opcode == 4 then -- GETUPVAL
					indices[i-1] = {segment = upvalues, offset = movement.B}
				end
				IP = IP + 1
			end

			local _, func = create_wrapper(proto, new_upvals)
			stack[instruction.A] = func
		end,
		[37] = function(instruction)	-- VARARG
			local A = instruction.A
			local B = instruction.B
			local stack, vararg = stack, vararg

			for i = A, A + (B > 0 and B - 1 or vararg_size) do
				stack[i] = vararg[i - A]
			end
		end,
	}

	local function loop()
		local instructions = instructions
		local instruction, a, b

		while true do
			instruction = instructions[IP];
			IP = IP + 1
			a, b = opcode_funcs[instruction.opcode](instruction);
			if a then
				return b;
			end
		end
	end

	local debugging = {
		get_stack = function()
			return stack;
		end;
		get_IP = function()
			return IP;
		end
	};

	local function func(...)
		local local_stack = {};
		local ghost_stack = {};

		top = -1
		stack = setmetatable(local_stack, {
			__index = ghost_stack;
			__newindex = function(t, k, v)
				if k > top and v then
					top = k
				end
				ghost_stack[k] = v
			end;
		})
		local args = {...};
		vararg = {}
		vararg_size = select("#", ...) - 1
		for i = 0, vararg_size do
			local_stack[i] = args[i+1];
			vararg[i] = args[i+1]
		end

		environment = getfenv();
		IP = 1;
		local thread = coroutine.create(loop)
		local a, b = coroutine.resume(thread)

		if a then
			if b then
				return unpack(b);
			end
			return;
		else
			if advanced_debug then
				--TODO advanced debugging
			else
				--TODO error converting
				local name = cache.name;
				local line = cache.debug.lines[IP];
				local err  = b:gsub("(.-:)", "");
				local output = "";

				output = output .. (name and name .. ":" or "");
				output = output .. (line and line .. ":" or "");
				output = output .. b
				--[[
				output = ("%s (Instruction=%s)"):format(output,
					lua_opcode_names[select(2,debug.getlocal(loop,1, 1)).opcode+1])
				--]]
				error(output, 0);
			end
		end
	end

	return debugging, func;
end

local interpret = function(bytecode)
	local cache = decode_bytecode(bytecode);
	local _, func = create_wrapper(cache);
	return func;
end;

local newLoadstring = function(source, chunkName)
	local f = interpret(compile(source, chunkName))

	if f and typeof(f) == "function" then
		setfenv(f, LoadstringENV)
		return f
	end

	return f
end

DefineVEnv({"loadstring"}, newLoadstring)--

table.foreach(GENV, warn)
table.foreach(VisionEnv, warn)

bridgeServer = bridgeyService:new("visionLoad", function(output, obj)
	local session, command, sub = string.match(output, "--%[%[(.-)%]%] %[(.-)%] (.+)")

	if command and sub then
		if command == "reset" and sub == "sender" then
			obj.Value = "-(default)-"
		elseif command == "connected" then

		elseif sub and outputs[command] then
			outputs[command] = sub
		end
	else
		local f, ErrorsCache = newLoadstring(output)
		if f then
			f, ErrorsCache = pcall(f)
			if not f then
				error("Failed Running Loaded String", ErrorsCache)
			end
		else
			for _, LoaderError in ErrorsCache do
				error(unpack(LoaderError))
			end
		end
	end
end)