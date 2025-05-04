local reactorMaxOutput = 10000  --反应堆最大功率，如有升级，填入只计算潜艇升级的值(不计算天赋)
local turbineFixed = 100.0  --温度堆模式下固定的涡轮输出，如果用不到反应堆满输出可降低此值以减少温度堆模式下燃料消耗
local reactorOffNewRound = false --新巡回是否关反应堆
local voltage=1.0 --电网电压
local estimatedReactorMaxOutput = reactorMaxOutput  --估计的反应堆功率
local MaxOutputAdjust=0 --反应堆功率预测微调
local temperature = 100 --上一帧温度，修正用
local lastInteriorTurbine = 0 --上一帧涡轮，修正用
local time = 0
local turbineTolerance = 1
local scrollbarSpeed = 5
local temperatureSpeed = 10
local eps = 0.00000001
local magicPara = 0.96
local lastLoad = 0
local lastlastLoad = 0
local interiorFissionRate = -1.0
local targetFissionRate = 0.0
local interiorTurbine = 0.0
local targetTurbine = 0.0
local reacotrMode = 0
local reactorOff = false

local test=0 --测试用

local function clamp(x, min, max)
    if x < min then return min end
    if x > max then return max end
    return x
end

local function sign(x)
    if x <= 0 then return -1 end
    if x > 0 then return 1 end
    --return 0
end

local function sigmoid(x)
    return 1/(1+math.exp(-x))
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

local function tableSerialize(ta)
    local str=""
    for key, value in ipairs(ta) do
        str=str..tostring(value).." "
    end
    return str
end

local function tableDeserialize(ta,str)
    for w in string.gmatch(str, "[^%s]+") do
        table.insert(ta,w)
    end
end

local CorrectTurbineOutput=0
local optimalFissionRateY= 0
local optimalFissionRateX=0
local allowedFissionRateY = 0
--前5秒强制执行的更新:Reactor.cs(250-256)
local function UpdateAutoTemp(speed,deltaTime,power,load)
    local desiredTurbineOutput = CorrectTurbineOutput;
    targetTurbine = targetTurbine + clamp(desiredTurbineOutput - targetTurbine, -speed, speed) * deltaTime
    targetTurbine = clamp(targetTurbine, 0.0, 100.0)

    local desiredFissionRate = (optimalFissionRateX + optimalFissionRateY) / 2.0
    targetFissionRate = targetFissionRate + clamp(desiredFissionRate - targetFissionRate, -speed, speed) * deltaTime

    if (temperature > 50) then
        targetFissionRate = math.min(targetFissionRate - speed * 2 * deltaTime, allowedFissionRateY)
    elseif (power < load) then
        targetFissionRate = math.min(targetFissionRate + speed * 2 * deltaTime, 100.0)
    end
    targetFissionRate = clamp(targetFissionRate, 0.0, 100.0)

    targetFissionRate = clamp(targetFissionRate, interiorFissionRate - 5, interiorFissionRate + 5)
end
local function UpdateAutoTempAfter(fuel,SF,ST,deltaTime,load)
    targetFissionRate=targetFissionRate+clamp(SF-targetFissionRate,-scrollbarSpeed*deltaTime,scrollbarSpeed*deltaTime)
    targetTurbine=targetTurbine+clamp(ST-targetTurbine,-scrollbarSpeed*deltaTime,scrollbarSpeed*deltaTime)

    CorrectTurbineOutput = CorrectTurbineOutput + clamp((load * 100.0) - CorrectTurbineOutput, -20.0, 20.0) * deltaTime
    optimalFissionRateY= fuel - 20
    optimalFissionRateX=math.min(30,optimalFissionRateY-10)
    allowedFissionRateY = fuel

    interiorFissionRate=interiorFissionRate+(targetFissionRate-interiorFissionRate)*deltaTime
    interiorTurbine=interiorTurbine+(targetTurbine-interiorTurbine)*deltaTime
end

inp = {}
function upd(deltaTime)

    local highVoltageGridLoad = getNumberOrDefault(inp[3],0.5) --负载
    local highVoltageGridPower = getNumberOrDefault(inp[2],0) --功率

    local powerAdjusted=highVoltageGridPower
    --对修正的修正
    if temperature/50>(lastInteriorTurbine-turbineTolerance)/100 and temperature>1 and lastInteriorTurbine>turbineTolerance and highVoltageGridPower-highVoltageGridLoad>3 then
        powerAdjusted=highVoltageGridPower*math.min(temperature*100/50,lastInteriorTurbine)/clamp(lastInteriorTurbine-turbineTolerance,0.5*lastInteriorTurbine,lastInteriorTurbine)
    end
    if powerAdjusted>highVoltageGridLoad or temperature/50<(lastInteriorTurbine-10*turbineTolerance)/100 then
        local preEstimatedReactorMaxOutput=math.max(estimatedReactorMaxOutput,powerAdjusted*50/(temperature+0.01))
        MaxOutputAdjust=clamp(MaxOutputAdjust-(preEstimatedReactorMaxOutput-estimatedReactorMaxOutput),0,5)
        estimatedReactorMaxOutput=preEstimatedReactorMaxOutput
    end
    temperature = getNumberOrDefault(inp[1],0)/100 --温度
    lastInteriorTurbine=interiorTurbine
    
    local load=clamp((getNumberOrDefault(inp[8],highVoltageGridLoad*voltage)+0.25)/(reactorMaxOutput+MaxOutputAdjust), 0, 1) --自定义负载
    local heat=getNumberOrDefault(inp[4],0) --燃料
    if interiorFissionRate < -0.5 then
        local mem={}
        tableDeserialize(mem,inp[5]) --巡回间存储
        interiorFissionRate=clamp(getNumberOrDefault(tonumber(mem[1]),0),0,100)
        interiorTurbine=clamp(getNumberOrDefault(tonumber(mem[1]),0),0,100)
        targetFissionRate = interiorFissionRate
        targetTurbine = interiorTurbine
    end
    if type(inp[6]) == "number" then
        reacotrMode = inp[6] --反应堆模式
    end
    reactorMaxOutput=estimatedReactorMaxOutput
    if math.abs(highVoltageGridPower-highVoltageGridLoad)<5 and math.abs(load-lastLoad)*reactorMaxOutput<2.5 then
        MaxOutputAdjust=clamp(MaxOutputAdjust+sigmoid(1*(-math.abs(deltaTime*(targetFissionRate-interiorFissionRate)*heat/50)*reactorMaxOutput+1))*(highVoltageGridPower-highVoltageGridLoad)*deltaTime,0,5)
    end
    if type(inp[7]) == "number" then
        if reactorMaxOutput>inp[7]*0.99 then
            MaxOutputAdjust=0
            reactorMaxOutput = inp[7] --设定反应堆最大输出
        end
    end
    if type(inp[9]) == "number" then
        turbineFixed = inp[9] --涡轮固定值
    end
    if ((not reactorOff) and temperature==0 and highVoltageGridLoad>1 and interiorFissionRate>getStaticFissionRate(interiorTurbine,0.1,heat)) then
        reactorOff = true
    end
    if reactorOff and temperature>0.015 then
        reactorOff = false
    end
    if reactorOff then
        interiorFissionRate = getStaticFissionRate(0,0.015,heat)
        targetFissionRate = getStaticFissionRate(0,0.015,heat)
        interiorTurbine = 0
        targetTurbine = 0
    end
    local Dload=(load-lastLoad)/deltaTime
    local signalFissionRate=0.0
    local signalTurbine = turbineFixed

    if time>=0 and time<60*5-3 then
        UpdateAutoTemp(100.0,deltaTime*10,highVoltageGridPower/reactorMaxOutput,highVoltageGridLoad/reactorMaxOutput)
        UpdateAutoTempAfter(heat,signalFissionRate,signalTurbine,deltaTime,highVoltageGridLoad/reactorMaxOutput)
    elseif(time>=6) then
        local staticFissionRate=getStaticFissionRate(interiorTurbine,50*load,heat)
        local DFissionRate=clamp(getStaticFissionRate(targetTurbine-interiorTurbine,50*Dload,heat),-(scrollbarSpeed-eps),(scrollbarSpeed-eps))
        if math.abs(load-lastLoad+(targetTurbine-interiorTurbine)*deltaTime/50)*reactorMaxOutput>2.5 and math.abs(load-2*lastLoad+lastlastLoad)<temperatureSpeed/50*deltaTime/1.0 then
            local prefix=sigmoid(3*((load-2*lastLoad+lastlastLoad)*2/(clamp(math.abs(load-lastLoad),1/reactorMaxOutput,1)*sign(load-lastLoad))+1))
            staticFissionRate=clamp(staticFissionRate+(prefix*2.5*clamp(getStaticFissionRate((targetTurbine-interiorTurbine)*0.5/2.5,50*Dload,heat),-(scrollbarSpeed-eps),(scrollbarSpeed-eps)))*deltaTime*(1+1*deltaTime),0,100) --从收到负载到输出有2帧间隔
        end
        local fissionRateSign=sign(DFissionRate+interiorFissionRate-targetFissionRate)
        signalFissionRate = staticFissionRate+DFissionRate-magicPara*(scrollbarSpeed*fissionRateSign-DFissionRate)*math.log((targetFissionRate-interiorFissionRate-fissionRateSign*scrollbarSpeed)/(DFissionRate-fissionRateSign*scrollbarSpeed))
        signalFissionRate = clamp(targetFissionRate+0.5*(1+scrollbarSpeed/clamp(math.abs(interiorFissionRate-targetFissionRate),0.2,scrollbarSpeed))*(signalFissionRate-targetFissionRate),0,100)

        if reacotrMode==1  then
            local staticTurbine=100*load
            local DTurbine=clamp(100*Dload,-(scrollbarSpeed-eps),(scrollbarSpeed-eps))
            if math.abs(load-lastLoad)*reactorMaxOutput>2.5 and math.abs(load-2*lastLoad+lastlastLoad)<temperatureSpeed/50*deltaTime/1.0 then --todo导数条件
                staticTurbine=clamp(staticTurbine+1*DTurbine*deltaTime,0,100) --从收到负载到输出有1帧间隔
            end
            local turbineSign=sign(DTurbine+interiorTurbine-targetTurbine)
            signalTurbine = staticTurbine+DTurbine-magicPara*(scrollbarSpeed*turbineSign-DTurbine)*math.log((targetTurbine-interiorTurbine-turbineSign*scrollbarSpeed)/(DTurbine-turbineSign*scrollbarSpeed))
            signalTurbine = clamp(targetTurbine+0.5*(1+scrollbarSpeed/clamp(math.abs(interiorTurbine-targetTurbine),0.2,scrollbarSpeed))*(signalTurbine-targetTurbine),0,100)
        end
        --单铀棒适配
        signalFissionRate=clamp(signalFissionRate,0,heat)
        signalTurbine=clamp(signalTurbine,0,heat*heat/75)

        targetFissionRate=targetFissionRate+clamp(signalFissionRate-targetFissionRate,-scrollbarSpeed*deltaTime,scrollbarSpeed*deltaTime)
        interiorFissionRate=interiorFissionRate+(targetFissionRate-interiorFissionRate)*deltaTime
        targetTurbine=targetTurbine+clamp(signalTurbine-targetTurbine,-scrollbarSpeed*deltaTime,scrollbarSpeed*deltaTime)
        interiorTurbine=interiorTurbine+(targetTurbine-interiorTurbine)*deltaTime
    end
    
    lastlastLoad=lastLoad
    lastLoad=load
    time=time+1
    if reactorOff then
        signalFissionRate = getStaticFissionRate(0,0.05,heat)
        signalTurbine = 0
    end
    out[1] = signalFissionRate --裂变速率
    out[2] = signalTurbine --涡轮输出
    out[3] = tableSerialize({interiorFissionRate,interiorTurbine}) --巡回间存储
    if time<10 and reactorOffNewRound then
        out[4] = 1 --停堆信号
    end
    test=reactorMaxOutput+MaxOutputAdjust--测试用
    out[5] = math.ceil(test*100000)/100000--测试用
    table.clear(inp)
end
