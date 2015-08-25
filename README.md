# pure-lua-zset   
a lua zset(sorted set) looks like redis zset.   
core source code comes from redis.   

1)support for user defined sort function . multisort becomes easier.  
2)any lua variable type exceppt for nil can be key/value.  
3)value can't be modified any more as soon as added to zset in case of breaking the data structure.    
4)when elements have the same score , the ealier added the higher priority.   
5)ranking (params/return) from 1 to n.  
It will be greatly appreciated if you can submit some bug.  



redis zset的纯lua修改版,适合在lua代码中用来做排行榜,删掉了部分函数  
1)支持自定义排序函数,可以很好的支持多字段排序  
2)支持任意非nil的lua类型作为key/value . 可以用table来作为value,保存额外的应用数据,例如玩家id,姓名,等级 etc.  
3)value insert到skiplist后由用户保证不可再做出影响排序的修改  
4)相同排序的元素,先插入的排序靠前  
5)排名(参数/返回值)都是从1开始  

代码未经严格测试.欢迎提出BUG  
