local zset = require "zset"

print("--------------------------【test1】--------------------------")  
  
local zs = zset(function(a , b)   
    if a == b then return 0 end  
    return a > b and 1 or -1  
end)  
zs:add("a" , 100)  
zs:add("b" , 1)  
zs:add("c" , 44)  
zs:add("d" , 66)  
zs:add("e" , 33)  
zs:add(6 , 44)  
zs:dump()  
print("zs:rank('e')-->" .. zs:rank('e'))  
print("zs:getByRank(3)-->" .. zs:getByRank(3))  
print("zs:rem('e')-->" , zs:rem('e'))  
zs:dump()  
print("zs:count()-->" , zs:count())  
print("zs:range(3,4)-->")  
local res = zs:range(3,4)  
for _ , v in ipairs(res) do  
    print(v)  
end  
print("zs:range(3,-1,true)-->")  
local res = zs:range(3,-1,true)  
for _ , v in ipairs(res) do  
    print(v["key"] , v["value"])  
end  
print("zs:getByKey(6)-->" , zs:getByKey(6))  
  
print("--------------------------【test2】--------------------------")  
  
local zs = zset(function(a , b)   
    if a["score"] == b["score"] then return 0 end  
    return a["score"] > b["score"] and 1 or -1  
end)  
zs:add("a" , {["score"] = 1})  
zs:add("b" , {["score"] = 4})  
print("zs:rank('a')-->" .. zs:rank('a'))  
print("zs:getByRank(2)['score']-->" .. zs:getByRank(2)['score'])  
print("zs:count()-->" , zs:count())  
print("zs:range(1,-1,true)-->")  
local res = zs:range(1,-1,true)  
for _ , v in ipairs(res) do  
    print(v["key"] , v["value"]["score"])  
end 
