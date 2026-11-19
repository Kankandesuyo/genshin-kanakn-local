package localfix;
import com.google.gson.*;
import emu.grasscutter.game.player.Player;
import emu.grasscutter.game.inventory.*;
import java.util.*;

final class LocalRecycle {
    static int[] rewardPlan(int ore,int count,int per){int total=Math.multiplyExact(count,per);int received=Math.min(Math.max(0,99999-ore),total);return new int[]{received,total-received};}
    static JsonObject run(Player player,JsonObject request,boolean preview)throws Exception{
        int rank=request.get("rank").getAsInt();if(rank!=3&&rank!=4)throw new IllegalArgumentException("仅允许清理三星或四星武器");
        var ids=request.getAsJsonArray("guids");if(ids==null||ids.size()>2000)throw new IllegalArgumentException("每次最多处理 2000 把武器");
        var seen=new LinkedHashSet<Long>();for(var value:ids)seen.add(Long.parseLong(value.getAsString()));
        var inventory=player.getInventory();synchronized(inventory){
            var eligible=new ArrayList<GameItem>();int skipped=0;
            for(long guid:seen){var item=inventory.getItemByGuid(guid);if(item==null||item.getItemType()!=ItemType.ITEM_WEAPON||item.getItemData().getRankLevel()!=rank||!item.isDestroyable()){skipped++;continue;}eligible.add(item);}
            int per=rank==3?3:10;int ore=inventory.getItemCountById(104013);int reward=per*eligible.size();
            int[] plan=rewardPlan(ore,eligible.size(),per);int overflow=plan[1];
            if(!preview&&overflow>0&&(!request.has("allowOverflow")||!request.get("allowOverflow").getAsBoolean()||!request.has("maxOverflow")||overflow>request.get("maxOverflow").getAsInt()))throw new IllegalArgumentException("返还矿石将溢出，请重新预览并确认放弃溢出部分，尚未清理武器");
            int removed=0,received=0,dropped=0;var failed=new JsonArray();
            if(!preview){
                var backup=new JsonArray();for(var item:eligible){var row=new JsonObject();row.addProperty("guid",Long.toString(item.getGuid()));row.addProperty("id",item.getItemId());row.addProperty("level",item.getLevel());row.addProperty("promote",item.getPromoteLevel());row.addProperty("refinement",item.getRefinement());row.addProperty("exp",item.getExp());row.addProperty("totalExp",item.getTotalExp());backup.add(row);}var snapshot=new JsonObject();snapshot.add("weapons",backup);snapshot.addProperty("oreBefore",ore);LocalGear.audit("recyclebatch",Integer.toString(player.getUid()),snapshot);
                for(var item:eligible){
                    if(!item.isDestroyable()){skipped++;continue;}
                    int actual=rewardPlan(inventory.getItemCountById(104013),1,per)[0];
                    if(actual>0&&!inventory.addItem(104013,actual)){failed.add("返还矿石失败："+item.getGuid());break;}
                    if(!inventory.removeItem(item,1)){if(actual>0)inventory.removeItemById(104013,actual);failed.add("武器删除失败，矿石已撤回："+item.getGuid());continue;}removed++;received+=actual;dropped+=per-actual;
                }player.save();
            }
            var result=new JsonObject();result.addProperty("ok",true);result.addProperty("preview",preview);result.addProperty("eligible",eligible.size());result.addProperty("skipped",skipped);result.addProperty("removed",removed);result.addProperty("reward",preview?plan[0]:received);result.addProperty("overflow",preview?overflow:dropped);result.add("failures",failed);return result;
        }
    }
}
