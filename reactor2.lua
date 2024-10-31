local reactorMaxOutput = 10000  --反应堆功率，如有升级变更可更改
local turbineFixed = 100  --温度堆模式下固定的涡轮输出，如果用不到反应堆满输出可降低此值以减少温度堆模式下燃料消耗
local estimatedReactorMaxOutput = reactorMaxOutput  --估计的反应堆功率
local temperature = 100 --上一帧温度，修正用
local lastInteriorTurbine = 0 --上一帧涡轮，修正用
local turbineTolerance = 1
local scrollbarSpeed = 5
local eps = 0.00000001
local magicPara = 0.96
local lastLoad = 0
local interiorFissionRate = -1
local targetFissionRate = 0
local interiorTurbine = 0
local targetTurbine = 0
local reacotrMode = 0

local function clamp(x, min, max)
    if x < min then return min end
    if x > max then return max end
    return x
end

local function sign(x)
    if x < 0 then return -1 end
    if x > 0 then return 1 end
    return 0
end

local function getNumberOrDefault(input,default)
    if type(input) == "number" then
        return input
    end
    return default
end

local function getStaticFissionRate(turbine, temperature, fuelHeat)
    if fuelHeat==0 then return 0 end
    return (turbine+temperature)*50/fuelHeat
end

inp = {}
function upd(deltaTime)

    local highVoltageGridLoad = getNumberOrDefault(inp[10],1) --负载
    local highVoltageGridPower = getNumberOrDefault(inp[11],0) --功率

    --对修正的修正
    if temperature/50>(lastInteriorTurbine-turbineTolerance)/100 and temperature>1 and lastInteriorTurbine>turbineTolerance then
        highVoltageGridPower=highVoltageGridPower*math.min(temperature*100/50,lastInteriorTurbine)/clamp(lastInteriorTurbine-turbineTolerance,0.5*lastInteriorTurbine,lastInteriorTurbine)
    end
    if highVoltageGridPower>highVoltageGridLoad or temperature/50<(lastInteriorTurbine-10*turbineTolerance)/100 then
        estimatedReactorMaxOutput=math.max(estimatedReactorMaxOutput,highVoltageGridPower*50/(temperature+0.01))
    end
    temperature = getNumberOrDefault(inp[9],0)/100 --温度
    lastInteriorTurbine=interiorTurbine
    
    local load=clamp(getNumberOrDefault(inp[1],0)/reactorMaxOutput, 0, 1)
    local heat=getNumberOrDefault(inp[2],0)
    if interiorFissionRate == -1 then
        interiorFissionRate = getNumberOrDefault(inp[7],0)
        interiorTurbine = getNumberOrDefault(inp[8],0)
        targetFissionRate = interiorFissionRate
        targetTurbine = interiorTurbine
    end
    if type(inp[3]) == "number" then
        reacotrMode = inp[3]
    end
    reactorMaxOutput=estimatedReactorMaxOutput
    if type(inp[4]) == "number" then
        if reactorMaxOutput>inp[4]*0.99 then
            reactorMaxOutput = inp[4] --设定反应堆最大输出
        end
    end
    if type(inp[5]) == "number" then
        turbineFixed = inp[5]
    end
    if inp[6] == 1 then
        interiorFissionRate = 0
        targetFissionRate = 0
        interiorTurbine = 0
        targetTurbine = 0
    end
    local Dload=(load-lastLoad)/deltaTime

    local staticFissionRate=getStaticFissionRate(interiorTurbine,50*load,heat)
    local DFissionRate=clamp(getStaticFissionRate(targetTurbine-interiorTurbine,50*Dload,heat),-(scrollbarSpeed-eps),(scrollbarSpeed-eps))
    local fissionRateSign=sign(DFissionRate+interiorFissionRate-targetFissionRate)
    local signalFissionRate = staticFissionRate+DFissionRate-magicPara*(scrollbarSpeed*fissionRateSign-DFissionRate)*math.log((targetFissionRate-interiorFissionRate-fissionRateSign*scrollbarSpeed)/(DFissionRate-fissionRateSign*scrollbarSpeed))
    signalFissionRate = clamp(targetFissionRate+0.5*(1+scrollbarSpeed/clamp(math.abs(interiorFissionRate-targetFissionRate),0.2,scrollbarSpeed))*(signalFissionRate-targetFissionRate),0,100)

    local signalTurbine = turbineFixed
    if reacotrMode==1  then
        local staticTurbine=100*load
        local DTurbine=clamp(100*Dload,-(scrollbarSpeed-eps),(scrollbarSpeed-eps))
        local turbineSign=sign(DTurbine+interiorTurbine-targetTurbine)
        signalTurbine = staticTurbine+DTurbine-magicPara*(scrollbarSpeed*turbineSign-DTurbine)*math.log((targetTurbine-interiorTurbine-turbineSign*scrollbarSpeed)/(DTurbine-turbineSign*scrollbarSpeed))
        signalTurbine = clamp(targetTurbine+0.5*(1+scrollbarSpeed/clamp(math.abs(interiorTurbine-targetTurbine),0.2,scrollbarSpeed))*(signalTurbine-targetTurbine),0,100)
    end

    targetFissionRate=targetFissionRate+clamp(signalFissionRate-targetFissionRate,-scrollbarSpeed*deltaTime,scrollbarSpeed*deltaTime)
    interiorFissionRate=interiorFissionRate+(targetFissionRate-interiorFissionRate)*deltaTime
    targetTurbine=targetTurbine+clamp(signalTurbine-targetTurbine,-scrollbarSpeed*deltaTime,scrollbarSpeed*deltaTime)
    interiorTurbine=interiorTurbine+(targetTurbine-interiorTurbine)*deltaTime
    lastLoad=load
    if inp[6] == 1 then
        signalFissionRate = 0
        signalTurbine = 0
    end
    out[1] = signalFissionRate
    out[2] = signalTurbine
    out[3] = interiorFissionRate
    out[4] = interiorTurbine
    table.clear(inp)
end