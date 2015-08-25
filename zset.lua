--------------------------------------------------------------  
--[[  
redis zset的lua改进版,适合在lua代码中用来做排行榜,删掉了部分函数  
1)支持自定义排序函数,可以很好的支持多字段排序  
2)支持任意非nil的lua类型作为key/value . 可以用table来作为value,保存额外的应用数据,例如玩家id,姓名,等级 etc.  
3)value insert到skiplist后由用户保证不可再做出影响排序的修改  
4)相同排序的元素,先插入的排序靠前  
5)排名(参数/返回值)都是从1开始  
Author : yuliying  
转载请注明出自yuliying的csdn博客 http://blog.csdn.net/yuliying/article/details/47926031  
代码未经严格测试.欢迎提出BUG  
--]]  
--------------------------------------------------------------  
local SKIPLIST_MAXLEVEL = 32  
local SKIPLIST_P        = 0.25  
--  
local skipList_meta     = {}  
skipList_meta.__index   = skipList_meta  
--  
local zset_meta         = {}  
zset_meta.__index       = zset_meta  
local zset              = setmetatable({} , zset_meta)  
--------------------------------------------------------------  
  
local function randomLevel()  
    local level = 1  
    while(math.random(1 , 0xffff) < SKIPLIST_P * 0xffff) do  
        level = level + 1  
    end  
    return level < SKIPLIST_MAXLEVEL and level or SKIPLIST_MAXLEVEL  
end  
  
local function createSkipListNode(level , key , value)  
    local sln = { ["key"] = key , ["value"] = value , ["level"] = {} , ["backward"] = nil}  
    for lv = 1 , level do  
        table.insert(sln["level"] , {["forward"] = nil , ["span"] = 0})  
    end  
    return sln  
end  
  
local function createSkipList(cmpFn)  
    assert(type(cmpFn) == "function")  
    return setmetatable({  
        ["header"]     = createSkipListNode(SKIPLIST_MAXLEVEL) ,  
        ["tail"]       = nil ,  
        ["length"]     = 0 ,  
        ["level"]      = 1 ,  
        ["compareFn"]  = cmpFn ,  
    } , skipList_meta)  
end  
  
---------------------------skipList---------------------------  
  
function skipList_meta:insert(key , value)  
    local update = {}  
    local rank   = {}  
    local x      = self["header"]  
    local level  
    for i = self["level"] , 1 , -1 do   
        -- store rank that is crossed to reach the insert position  
        rank[i] = i == self["level"] and 0 or rank[i+1]  
        while x["level"][i]["forward"] and self.compareFn(x["level"][i]["forward"]["value"] , value) >= 0 do  
            rank[i] = rank[i] + x["level"][i]["span"]  
            x = x["level"][i]["forward"]  
        end  
        update[i] = x  
    end  
    --[[we assume the key is not already inside, since we allow duplicated  
     * scores, and the re-insertion of score and redis object should never  
     * happen since the caller of slInsert() should test in the hash table  
     * if the element is already inside or not.--]]  
    level = randomLevel()  
    if level > self["level"] then  
        for i = self["level"] + 1 , level do  
            rank[i] = 0  
            update[i] = self["header"]  
            update[i]["level"][i]["span"] = self["length"]  
        end  
        self["level"] = level  
    end  
    x = createSkipListNode(level , key , value)  
    for i = 1 , level do  
        x["level"][i]["forward"] = update[i]["level"][i]["forward"]  
        update[i]["level"][i]["forward"] = x  
          
        -- update span covered by update[i] as x is inserted here  
        x["level"][i]["span"] = update[i]["level"][i]["span"] - (rank[1] - rank[i])  
        update[i]["level"][i]["span"] = (rank[1] - rank[i]) + 1  
    end  
      
    -- increment span for untouched levels  
    for i = level + 1 , self["level"] do  
        update[i]["level"][i]["span"] = update[i]["level"][i]["span"] + 1  
    end  
      
    x["backward"] = update[1] ~= self["header"] and update[1]  
    if x["level"][1]["forward"] then  
        x["level"][1]["forward"]["backward"] = x  
    else  
        self["tail"] = x  
    end  
    self["length"] = self["length"] + 1  
end  
  
function skipList_meta:getRank(key , value)  
    local rank = 0  
    local x  
    x = self["header"]  
    for i = self["level"] , 1 , -1 do  
        while x["level"][i]["forward"] and (self.compareFn(x["level"][i]["forward"]["value"] , value) > 0 or (self.compareFn(x["level"][i]["forward"]["value"] , value) == 0 and x["level"][i]["forward"]["key"] ~= key)) do  
            rank = rank + x["level"][i]["span"]  
            x = x["level"][i]["forward"]  
        end   
        if x["level"][i]["forward"] and x["level"][i]["forward"]["value"] and x["level"][i]["forward"]["key"] == key and x["level"][i]["forward"]["value"] == value then  
            rank = rank + x["level"][i]["span"]  
            return rank  
        end  
    end  
    return 0  
end  
  
-- Finds an element by its rank. The rank argument needs to be 1-based.  
function skipList_meta:getNodeByRank(rank)  
    if rank <= 0 or rank > self["length"] then return end  
    local traversed = 0  
    local x = self["header"]  
    for i = self["level"] , 1 , -1 do  
        while x["level"][i]["forward"] and traversed + x["level"][i]["span"] <= rank do  
            traversed = traversed + x["level"][i]["span"]  
            x = x["level"][i]["forward"]  
        end  
        if traversed == rank then  
            return x  
        end  
    end  
end  
  
-- Internal function used by slDelete, slDeleteByScore  
function skipList_meta:deleteNode(node , update)  
    for i = 1 , self["level"] do  
        if update[i]["level"][i]["forward"] == node then  
            update[i]["level"][i]["span"] = update[i]["level"][i]["span"] + node["level"][i]["span"] - 1  
            update[i]["level"][i]["forward"] = node["level"][i]["forward"]  
        else  
            update[i]["level"][i]["span"] = update[i]["level"][i]["span"] - 1  
        end  
    end  
    if node["level"][1]["forward"] then  
        node["level"][1]["forward"]["backward"] = node["backward"]  
    else  
        self["tail"] = node["backward"]  
    end  
    while self["level"] > 2 and not self["header"]["level"][self["level"] -1]["forward"] do  
        self["level"] = self["level"] - 1  
    end  
    self["length"] = self["length"] - 1  
end  
  
-- Delete an element with matching score/object from the skiplist.  
function skipList_meta:delete(key , value)  
    local update = {}  
    local x = self["header"]  
    for i = self["level"] , 1 , -1 do  
        while x["level"][i]["forward"] and (self.compareFn(x["level"][i]["forward"]["value"] , value) > 0 or (self.compareFn(x["level"][i]["forward"]["value"] , value) == 0 and x["level"][i]["forward"]["key"] ~= key)) do  
            x = x["level"][i]["forward"]  
        end  
        update[i] = x  
    end  
    --[[We may have multiple elements with the same score, what we need  
    is to find the element with both the right score and object. --]]  
    x = x["level"][1]["forward"]  
    if x and x["key"] == key and x["value"] == value then   
        self:deleteNode(x , update)  
        return true  
    end  
    return false  
end  
  
--[[ Delete all the elements with rank between start and end from the skiplist.  
Start and end are inclusive. Note that start and end need to be 1-based --]]  
-- function skipList_meta:deleteByRank(_start , _end)  
--  local update = {}  
--  local x = self["header"]  
--  local traversed = 0  
--  local removed = 0  
--  for i = self["level"] , 1 , -1 do  
--      while x["level"][i]["forward"] and traversed + x["level"][i]["span"] < _start do  
--          traversed = traversed + x["level"][i]["span"]  
--          x = x["level"][i]["forward"]  
--      end  
--      update[i] = x  
--  end  
  
--  traversed = traversed + 1  
--  x = x["level"][1]["forward"]  
--  while x and traversed <= _end do  
--      local next = x["level"][1]["forward"]  
--      self:deleteNode(x , update)  
--      removed = removed + 1  
--      traversed = traversed + 1  
--      x = next  
--  end  
--  return removed  
-- end  
  
function skipList_meta:Range(_start , _end)  
    local node = self:getNodeByRank(_start)  
    local result = {}  
    local len = _end - _start + 1  
    local n = 0  
    while node and n < len do  
        n = n + 1  
        table.insert(result , node["key"])  
        node = node["level"][1]["forward"]  
    end  
    return result  
end  
  
function skipList_meta:get_count()  
    return self["length"]  
end  
  
----------------------------zset-----------------------------  
  
function zset_meta:__call(cmpFn)  
    return setmetatable({  
        sl   = createSkipList(cmpFn),  
        objs = {} ,  
    } , zset_meta)  
end  
  
function zset_meta:add(key , value)  
    assert(key ~= nil and value ~= nil)  
    local old = self["objs"][key]  
    if old then  
        if old == value then return end  
        self.sl:delete(key , old)  
    end  
    self.sl:insert(key , value)  
    self.objs[key] = value  
end  
  
function zset_meta:getByKey(key)  
    return self["objs"][key]  
end  
  
function zset_meta:getByRank(rank)  
    local node = self.sl:getNodeByRank(rank)  
    if not node then return end  
    return node["value"]  
end  
  
function zset_meta:rank(key)  
    local value = self["objs"][key]  
    if not value then return nil end  
    local rank = self.sl:getRank(key , value)  
    assert(rank > 0)  
    return rank  
end  
  
function zset_meta:count()  
    return self.sl:get_count()  
end  
  
function zset_meta:range(start , stop , with_value)  
    local count = self.sl:get_count()  
    --  
    if start < 0 then start = count + start + 1 end  
    if start < 1 then start = 1 end  
    --  
    if stop == nil then stop = count end  
    if stop < 0 then stop = count + stop + 1 end  
    if stop < 1 then stop = 1 end  
    --  
    if start > stop then  
        return {}  
    end  
    --  
    local res = self.sl:Range(start , stop)  
    if not with_value then return res end  
    local res1 = {}  
    for _ , v in ipairs(res) do  
        assert(self.objs[v])  
        table.insert(res1 , {key = v , value = self.objs[v] })  
    end  
    return res1  
end  
  
function zset_meta:rem(key)  
    local old = self["objs"][key]  
    if old then  
        self.sl:delete(key , old)  
        self["objs"][key] = nil  
    end  
end  
  
----------------------------test-----------------------------  
  
function skipList_meta:dump()  
    local x = self["header"]  
    local i = 0  
    while x["level"][1]["forward"] do  
        x = x["level"][1]["forward"]  
        i = i + 1  
        --can only dump number and string for test here  
        print("rank ".. i .."- key ".. x["key"]  .. "- value " .. x["value"])  
    end  
end  
  
function zset_meta:dump()  
    self.sl:dump()  
end 
  
return zset  
