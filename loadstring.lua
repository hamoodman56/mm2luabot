local api = "https://mm2flip.breadservices.workers.dev"
local Bot, You = game.Players.LocalPlayer, game.Players.LocalPlayer

local Players = game:GetService("Players")
local Trade = game:GetService("ReplicatedStorage"):WaitForChild("Trade")
local InventoryModule = require(game:GetService("ReplicatedStorage").Modules.InventoryModule)
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AcceptRequestRe = Trade:WaitForChild("AcceptRequest")
local AcceptTrade = Trade:WaitForChild("AcceptTrade")
local SendRequest = Trade:WaitForChild("SendRequest")
local DeclineTrade = Trade:WaitForChild("DeclineTrade")
local UpdateTrade = Trade:WaitForChild("UpdateTrade")

local HttpService = game:GetService("HttpService")
local Trading = false
local currentTrader
local currentTrade
local currentTraderRandomized

local currentDepo = {}
local currentWithdraw = {}

local SECURITY_KEY = "0e1baef9c519f9716fb75d14da70ed78"
local API_KEY = "0e1baef9c519f9716fb75d47cd48be67"

game:GetService("RunService"):Set3dRenderingEnabled(false)

Bot.PlayerGui.TradeGUI.ResetOnSpawn = false
print("Executed")

task.wait(1)

game:GetService("Lighting").GlobalShadows = false

local ohTable1 = {
    ["1v1Mode"] = false,
    ["Disguises"] = false,
    ["1v1ModeAuto"] = false,
    ["DeadCanTalk"] = false,
    ["LobbyMode"] = true,
    ["RoundTimer"] = 180,
    ["LockFirstPerson"] = false,
    ["Assassin"] = false
}

local remote = game:GetService("ReplicatedStorage").Remotes.CustomGames:FindFirstChild("UpdateServerSettings")

if remote then
    print("Remote found. Firing server with settings:", ohTable1)
    remote:FireServer(ohTable1)
else
    warn("Remote 'UpdateServerSettings' not found")
end

local ReceivingRequest = You.PlayerGui:WaitForChild("MainGUI").Game.Leaderboard.Container.TradeRequest.ReceivingRequest

--Functions
local function pingBotStatus()
    local botName = game.Players.LocalPlayer.Name
    local url = api
    
    while true do
        pcall(function()
            local response = HttpService:GetAsync(url)
            print("Pinged bot status: " .. response)
        end)
        
        wait(30)
    end
end

coroutine.wrap(pingBotStatus)()

function typeChat(str)
	str = tostring(str)
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		TextChatService.TextChannels.RBXGeneral:SendAsync(str)
	else
		ReplicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(str, "All")
	end
end

-- ✅ NEW FUNCTIONS FOR CHECKING WITHDRAW ITEMS
local function checkEligible(Player)
    local traderName = tostring(currentTrader)
    local jsonBody = HttpService:JSONEncode({
        UserId = traderName,
        SecurityKey = SECURITY_KEY,
        key = API_KEY
    })

    local success, res = pcall(function()
        return request({
            Url = api .. "/CheckWithdrawItems",
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = jsonBody
        })
    end)

    if success and res.StatusCode == 200 then
        local data = HttpService:JSONDecode(res.Body)
        if data.Exists then
            print("[Withdraw] ✅ Eligible — Withdraw items exist for", traderName)
        else
            print("[Withdraw] ❌ No withdraw items for", traderName)
        end
        return data.Exists
    else
        warn("[Withdraw] Failed to check eligibility:", res)
        return false
    end
end

local function checkItems(Player)
    local traderName = tostring(currentTrader)
    local jsonBody = HttpService:JSONEncode({
        UserId = traderName,
        SecurityKey = SECURITY_KEY,
        key = API_KEY
    })

    local success, res = pcall(function()
        return request({
            Url = api .. "/CheckWithdrawItems",
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = jsonBody
        })
    end)

    if success and res.StatusCode == 200 then
        local data = HttpService:JSONDecode(res.Body)
        print("checkItems data:", res.Body)
        return data.Items
    else
        warn("Failed to check items:", res)
        return nil
    end
end

local function addItems(items)
    for itemName, quantity in pairs(items) do
        for i = 1, quantity do
            local args = {
                [1] = itemName,
                [2] = "Weapons"
            }
            game:GetService("ReplicatedStorage"):WaitForChild("Trade"):WaitForChild("OfferItem"):FireServer(unpack(args))
            table.insert(currentWithdraw, itemName)
            wait()
        end
    end
end

local function check(datas)
	if datas.Player1.Player == game.Players.LocalPlayer then
		return "Player1", "Player2";
	end
	if datas.Player2.Player ~= game.Players.LocalPlayer then
		return;
	end
	return "Player2", "Player1";
end

local function getName(Name)
    for _, v in pairs(InventoryModule.MyInventory.Data.Weapons) do
        for itemKey, itemData in pairs(v) do
            if type(itemData) == "table" and itemData.ItemName then
                local itemName = itemData.ItemName
                local strippedName = itemName:gsub("Chroma ", "")
                
                if strippedName == Name then
                    if itemName:find("Chroma") then
                        return itemName
                    else
                        return strippedName
                    end
                end
            end
        end
    end
    return Name
end

local function getItemAssetId(Name)
	for _, v in pairs(InventoryModule.MyInventory.Data.Weapons) do
		if v[Name] and v[Name].ItemName then
			return "rbxassetid://".. string.match(v[Name].Image, '%d+$')
		end
	end
end

local function resetState()
    currentTrader = nil
    currentTrade = nil
    currentTraderRandomized = nil
    Trading = false
    table.clear(currentDepo)
    table.clear(currentWithdraw)
	ReceivingRequest.Visible = false
    print("Reset State")
end

-- Keep logDeposit / logWithdraw the same
local function logWithdraw(PlayerName)
    local jsonBody = HttpService:JSONEncode({
        Data = {
            UserId = PlayerName,
            robloxId = game.Players:GetUserIdFromNameAsync(PlayerName),
            SecurityKey = SECURITY_KEY
        },
        key = API_KEY
    })

    local success = request({
            Url = api.."/Withdraw",
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = jsonBody
        })

    if success then
        print("Withdrawal logged successfully")
    else
        print("Failed to log withdrawal")
    end
end

local function logDeposit(PlayerName)
    local logTable = {}
    for _, v in ipairs(currentDepo) do
        table.insert(logTable, v[1])
    end

    local jsonBody = HttpService:JSONEncode({
        Data = {
            UserId = PlayerName,
            Items = currentDepo,
        },
        SecurityKey = SECURITY_KEY,
        key = API_KEY
    })

    local success = request({
            Url = api.."/Deposit",
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = jsonBody
        })

    if success then
        print("Deposit logged successfully")
    else
        print("Failed to log deposit")
    end
end

-- Trade handler
Trade.SendRequest.OnClientInvoke = function(player)
    print("Trade request received from " .. player.Name)
    
    if not Trading then
        Trading = true
        
        currentTrader = player.Name
        currentTraderRandomized = currentTrader .. tostring(math.random(1,1000))
        
        task.wait(0.5)
        Trade.AcceptRequest:FireServer()
        
        task.spawn(function()
            local traderBefore = currentTraderRandomized
            for i = 1, 30 do
                task.wait(1)
                if i >= 30 and Trading and traderBefore == currentTraderRandomized then
                    resetState()
                    Trade.DeclineTrade:FireServer()
                    typeChat("Time limit ran out")
                    break
                end
                if not Trading then break end
            end
        end)
        
        if checkEligible(player) then
            typeChat(player.Name .. " is withdrawing items")
            currentTrade = "Withdraw"
            task.wait(0.1)
            local Items = checkItems(player)
            if Items then
                addItems(Items)
            else
                print("No items to add")
            end
        else
            typeChat(player.Name .. " is depositing items.")
            typeChat("Please do not deposit pets. They will not be credited.")
            currentTrade = "Deposit"
        end
    else
        print("Declined because already trading")
        Trade.DeclineRequest:FireServer()
    end
    
    return true
end

-- UpdateTrade event
UpdateTrade.OnClientEvent:Connect(function(data)
	if Trading then
		table.clear(currentDepo)
		local you, them = check(data)
		local theirOffer = data[them].Offer
		for i, item in pairs(theirOffer) do
			table.insert(currentDepo, {item[1], item[2]})
		end
	end
end)

-- DeclineTrade event
DeclineTrade.OnClientEvent:Connect(function()
	resetState()
	typeChat("Trade ended")
end)

-- AcceptTrade event
AcceptTrade.OnClientEvent:Connect(function(complete, items_)
	if complete then
		local traderId = currentTrader
		if not items_ then items_ = {} end

        if currentTrade == "Deposit" and #items_ > 0 then
            local BodyTable = {
                key = API_KEY,
                Data = {UserId = tostring(traderId), items = {}},
                SecurityKey = SECURITY_KEY
            }
        
            for i, v in pairs(currentDepo) do
                table.insert(BodyTable.Data.items, {
                    ["name"] = getName(v[1]),
                    ["gameName"] = v[1],
                    ["price"] = 1,
                    ["quantity"] = v[2],
                    ["assetId"] = getItemAssetId(v[1]),
                    ["holder"] = "0gtuy"
                })
            end
        
            local jsonBody = HttpService:JSONEncode(BodyTable)
            local res = request({
                Url = api .. "/Deposit",
                Method = "POST",
                Headers = {['Content-Type'] = 'application/json'},
                Body = jsonBody
            })
            print(res.Body)
        end        

		if currentTrade == "Withdraw" then
			local BodyTable = {
                Data = {UserId = tostring(traderId)},
                SecurityKey = SECURITY_KEY
            }
            local jsonBody = HttpService:JSONEncode(BodyTable)
            local res = request({
				Url = api.."/ConfirmWithdraw",
				Method = "POST",
				Headers = {['Content-Type'] = 'application/json'},
				Body = jsonBody
			})
		end

		typeChat("Trade Completed.")
		task.wait(1)
		resetState()
	elseif Trading and currentTrader and currentTrader ~= "" then
		AcceptTrade:FireServer(285646582)
	else
		typeChat("An Unknown Error Occurred While Processing Your Trade, please contact support.")
		DeclineTrade:FireServer()
		resetState()
	end
end)
