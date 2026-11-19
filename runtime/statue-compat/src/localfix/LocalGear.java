package localfix;

import com.google.gson.*;
import emu.grasscutter.command.*;
import emu.grasscutter.data.GameData;
import emu.grasscutter.game.player.Player;
import emu.grasscutter.game.inventory.*;
import emu.grasscutter.server.packet.send.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import picocli.CommandLine;

@Command(label="localgear",permission="player.give",permissionTargeted="player.give.others")
public final class LocalGear implements CommandHandler {
    static List<emu.grasscutter.data.excels.avatar.AvatarPromoteData> avatarPromotes(int id){
        var rows=new ArrayList<emu.grasscutter.data.excels.avatar.AvatarPromoteData>();for(int level=0;level<=10;level++){var row=GameData.getAvatarPromoteData(id,level);if(row!=null)rows.add(row);}return rows;
    }
    @Override public CommandLine createCommandLine(Player sender,Player target){return new CommandLine(new Args(sender,target));}
    @CommandLine.Command(name="localgear")
    private static class Args implements Runnable {
        final Player sender,player;
        @CommandLine.Parameters(arity="1..2") List<String> args;
        Args(Player sender,Player player){this.sender=sender;this.player=player;}
        public void run(){try{
            if(player==null||player.getUid()!=10001||!player.isOnline())throw new IllegalArgumentException("请先进入本地账号 10001 的游戏世界");
            if(args.get(0).equals("list")){CommandOutput.sendMessage(sender,list(player).toString());return;}
            if(args.get(0).equals("wingsync")){CommandOutput.sendMessage(sender,syncWings(player).toString());return;}
            if(args.get(0).equals("skins")){int added=StatueCompat.unlockCostumes(player);var r=new JsonObject();r.addProperty("ok",true);r.addProperty("added",added);r.addProperty("wingsTotal",GameData.getAvatarFlycloakDataMap().size());r.addProperty("wingsUnlocked",GameData.getAvatarFlycloakDataMap().keySet().intStream().filter(id->player.getFlyCloakList().contains(id)).count());r.addProperty("total",GameData.getAvatarCostumeDataMap().size());r.addProperty("unlocked",GameData.getAvatarCostumeDataMap().keySet().intStream().filter(id->player.getCostumeList().contains(id)).count());CommandOutput.sendMessage(sender,r.toString());return;}
            if(args.size()!=2||args.get(1).length()>128000)throw new IllegalArgumentException("操作参数无效");
            var request=JsonParser.parseString(new String(Base64.getDecoder().decode(args.get(1)),StandardCharsets.UTF_8)).getAsJsonObject();
            var result=switch(args.get(0)){case "recyclecheck"->LocalRecycle.run(player,request,true);case "recyclebatch"->LocalRecycle.run(player,request,false);case "passiverepair"->repairPassives(player);case "talents"->talents(player,request,false);case "talentcheck"->talents(player,request,true);case "maprefresh"->MapCompat.refreshMap(player);case "boundaryreset"->MapCompat.syncBoundary(player);case "world"->world(player,request);case "upgrade"->upgrade(player,request);case "artifact"->artifact(player,request);case "validate"->{makeArtifact(request);var r=new JsonObject();r.addProperty("ok",true);yield r;}default->throw new IllegalArgumentException("未知操作");};
            CommandOutput.sendMessage(sender,result.toString());
        }catch(Exception error){CommandOutput.sendMessage(sender,"ERROR: "+error.getMessage());}}
    }
    public static JsonObject list(Player player){
        var result=new JsonObject();var avatars=new JsonArray();var weapons=new JsonArray();
        for(var avatar:player.getAvatars().getAvatars().values()){
            if(avatar.getTrialAvatarId()!=0)continue;
            var row=new JsonObject();row.addProperty("id",avatar.getAvatarId());row.addProperty("level",avatar.getLevel());row.addProperty("promote",avatar.getPromoteLevel());
            int cap=0,promote=0;for(var p:avatarPromotes(avatar.getAvatarData().getAvatarPromoteId()))if(p.getAvatarPromoteId()==avatar.getAvatarData().getAvatarPromoteId()&&p.getUnlockMaxLevel()<=90&&p.getUnlockMaxLevel()>cap){cap=p.getUnlockMaxLevel();promote=p.getPromoteLevel();}
            row.addProperty("maxLevel",cap);row.addProperty("maxPromote",promote);row.add("passives",new Gson().toJsonTree(avatar.getProudSkillList()));avatars.add(row);
        }
        for(var item:player.getInventory())if(item.getItemType()==ItemType.ITEM_WEAPON){
            var row=new JsonObject();row.addProperty("guid",Long.toString(item.getGuid()));row.addProperty("id",item.getItemId());row.addProperty("level",item.getLevel());row.addProperty("promote",item.getPromoteLevel());row.addProperty("equipped",item.isEquipped());row.addProperty("rank",item.getItemData().getRankLevel());row.addProperty("protected",!item.isDestroyable());
            int cap=0,promote=0;for(var p:GameData.getWeaponPromoteDataMap().values())if(p.getWeaponPromoteId()==item.getItemData().getWeaponPromoteId()&&p.getUnlockMaxLevel()<=90&&p.getUnlockMaxLevel()>cap){cap=p.getUnlockMaxLevel();promote=p.getPromoteLevel();}
            row.addProperty("maxLevel",cap);row.addProperty("maxPromote",promote);weapons.add(row);
        }
        result.add("avatars",avatars);result.add("weapons",weapons);result.addProperty("worldLevel",player.getWorldLevel());return result;
    }
    static JsonObject syncWings(Player player)throws Exception{
        StatueCompat.unlockCostumes(player);
        for(int id:player.getFlyCloakList())player.sendPacket(new PacketAvatarGainFlycloakNotify(id));
        var result=new JsonObject();result.addProperty("ok",true);result.addProperty("synced",player.getFlyCloakList().size());result.add("ids",new Gson().toJsonTree(player.getFlyCloakList()));return result;
    }
    static void syncPassives(Player player,emu.grasscutter.game.avatar.Avatar avatar){
        avatar.recalcStats(true);
        var depot=GameData.getAvatarSkillDepotDataMap().get(avatar.getSkillDepotId());
        if(depot!=null)for(var open:depot.getInherentProudSkillOpens())if(open.getProudSkillGroupId()>0&&open.getNeedAvatarPromoteLevel()<=avatar.getPromoteLevel()){
            int id=open.getProudSkillGroupId()*100+1;if(GameData.getProudSkillDataMap().containsKey(id))avatar.getProudSkillList().add(id);
        }
        player.sendPacket(new PacketProudSkillChangeNotify(avatar));player.sendPacket(new PacketAvatarPropNotify(avatar));
    }
    static JsonObject repairPassives(Player player)throws Exception{
        int count=0;for(var avatar:player.getAvatars().getAvatars().values())if(avatar.getTrialAvatarId()==0){syncPassives(player,avatar);avatar.save();count++;}
        player.save();var result=new JsonObject();result.addProperty("ok",true);result.addProperty("avatars",count);return result;
    }
    static JsonObject world(Player player,JsonObject request)throws Exception{
        int level=request.get("level").getAsInt();
        if(level<0||level>9)throw new IllegalArgumentException("世界等级范围 0～9");
        if(player.getWorld()==null||player.getWorld().getHost()!=player)throw new IllegalArgumentException("请返回自己的世界后修改");
        var before=new JsonObject();before.addProperty("worldLevel",player.getWorldLevel());audit("world",Integer.toString(player.getUid()),before);
        if(!player.setWorldLevel(level)||player.getWorldLevel()!=level)throw new IllegalStateException("世界等级设置失败");
        player.save();var result=new JsonObject();result.addProperty("ok",true);result.addProperty("worldLevel",player.getWorldLevel());return result;
    }
    static JsonObject talents(Player player,JsonObject request,boolean preview)throws Exception{
        var avatar=player.getAvatars().getAvatarById(request.get("id").getAsInt());
        if(avatar==null||avatar.getTrialAvatarId()!=0)throw new IllegalArgumentException("请选择已拥有的非试用角色");
        var targets=new LinkedHashMap<Integer,Integer>();var before=new JsonObject();
        for(var entry:avatar.getSkillLevelMap().entrySet()){
            var levels=GameData.getAvatarSkillLevels(entry.getKey());if(levels==null)continue;
            int cap=levels.stream().filter(level->level>0&&level<=10).mapToInt(Integer::intValue).max().orElse(0);
            if(cap>1){before.addProperty(Integer.toString(entry.getKey()),entry.getValue());targets.put(entry.getKey(),Math.max(cap,entry.getValue()));}
        }
        if(targets.isEmpty())throw new IllegalArgumentException("此角色当前技能组没有可升级天赋数据");
        if(!preview){audit("talents",Integer.toString(avatar.getAvatarId()),before);
            for(var entry:targets.entrySet())if(avatar.getSkillLevelMap().get(entry.getKey())<entry.getValue()&&!avatar.setSkillLevel(entry.getKey(),entry.getValue()))throw new IllegalStateException("天赋升级失败，请重新读取");
            syncPassives(player,avatar);avatar.save();player.save();
        }
        var result=new JsonObject();result.addProperty("ok",true);result.addProperty("preview",preview);result.addProperty("count",targets.size());result.add("levels",new Gson().toJsonTree(targets));return result;
    }
    static JsonObject upgrade(Player player,JsonObject req)throws Exception{
        String type=req.get("type").getAsString();var result=new JsonObject();result.addProperty("ok",true);
        if(type.equals("avatar")){
            int id=req.get("id").getAsInt();var avatar=player.getAvatars().getAvatarById(id);
            if(avatar==null||avatar.getTrialAvatarId()!=0)throw new IllegalArgumentException("请选择已拥有的非试用角色");
            int cap=0,promote=0;for(var p:avatarPromotes(avatar.getAvatarData().getAvatarPromoteId()))if(p.getAvatarPromoteId()==avatar.getAvatarData().getAvatarPromoteId()&&p.getUnlockMaxLevel()<=90&&p.getUnlockMaxLevel()>cap){cap=p.getUnlockMaxLevel();promote=p.getPromoteLevel();}
            if(cap<avatar.getLevel()||cap<1)throw new IllegalArgumentException("角色突破数据不完整，不执行降级");
            var before=new JsonObject();before.addProperty("level",avatar.getLevel());before.addProperty("promote",avatar.getPromoteLevel());before.addProperty("exp",avatar.getExp());audit("avatar",Integer.toString(id),before);
            avatar.setLevel(cap);avatar.setPromoteLevel(promote);avatar.setExp(0);syncPassives(player,avatar);avatar.save();player.save();player.sendPacket(new PacketAvatarPropNotify(avatar));
            result.addProperty("level",avatar.getLevel());result.addProperty("promote",avatar.getPromoteLevel());
        }else if(type.equals("weapon")){
            var item=player.getInventory().getItemByGuid(Long.parseLong(req.get("guid").getAsString()));if(item==null||item.getItemType()!=ItemType.ITEM_WEAPON)throw new IllegalArgumentException("这把武器已不存在，请重新读取");
            int cap=0,promote=0;for(var p:GameData.getWeaponPromoteDataMap().values())if(p.getWeaponPromoteId()==item.getItemData().getWeaponPromoteId()&&p.getUnlockMaxLevel()<=90&&p.getUnlockMaxLevel()>cap){cap=p.getUnlockMaxLevel();promote=p.getPromoteLevel();}
            if(cap<item.getLevel()||cap<1)throw new IllegalArgumentException("武器突破数据不完整，不执行降级");
            var before=new JsonObject();before.addProperty("level",item.getLevel());before.addProperty("promote",item.getPromoteLevel());before.addProperty("exp",item.getExp());before.addProperty("totalExp",item.getTotalExp());audit("weapon",Long.toString(item.getGuid()),before);
            int total=0;for(int level=1;level<cap;level++)total+=GameData.getWeaponExpRequired(item.getItemData().getRankLevel(),level);
            item.setLevel(cap);item.setPromoteLevel(promote);item.setExp(0);item.setTotalExp(total);item.save();
            if(item.isEquipped()){var owner=player.getAvatars().getAvatarById(item.getEquipCharacter());if(owner!=null)owner.recalcStats(true);}
            player.sendPacket(new PacketStoreItemChangeNotify(item));player.save();result.addProperty("level",item.getLevel());result.addProperty("promote",item.getPromoteLevel());
        }else throw new IllegalArgumentException("请选择角色或武器");
        return result;
    }
    static GameItem makeArtifact(JsonObject request){
        int id=request.get("item").getAsInt(),level=request.get("level").getAsInt(),mainId=request.get("main").getAsInt();
        var data=GameData.getItemDataMap().get(id);if(data==null||data.getItemType()!=ItemType.ITEM_RELIQUARY||data.getRankLevel()!=5)throw new IllegalArgumentException("只支持有效的五星圣遗物");
        if(level<0||level>20||level+1>data.getMaxLevel())throw new IllegalArgumentException("圣遗物等级范围 +0～+20");
        var main=GameData.getReliquaryMainPropDataMap().get(mainId);if(main==null||main.getPropDepotId()!=data.getMainPropDepotId())throw new IllegalArgumentException("主词条不适用于这个部位");
        var seen=new HashSet<emu.grasscutter.game.props.FightProperty>();
        var subs=request.getAsJsonArray("subs");if(subs==null||subs.size()!=4)throw new IllegalArgumentException("请选择四种不同副词条");
        var rolls=new ArrayList<Integer>();
        for(var element:subs){var sub=element.getAsJsonObject();int affixId=sub.get("id").getAsInt(),count=sub.get("count").getAsInt();var affix=GameData.getReliquaryAffixDataMap().get(affixId);
            if(affix==null||affix.getDepotId()!=data.getAppendPropDepotId()||!seen.add(affix.getFightProp()))throw new IllegalArgumentException("副词条重复或不适用于这个圣遗物");
            if(count<1||count>1+level/4)throw new IllegalArgumentException("单项强化次数超出该等级上限");
            for(int i=0;i<count;i++)rolls.add(affixId);
        }
        if(rolls.size()!=4+level/4)throw new IllegalArgumentException("四项总次数必须等于 "+(4+level/4)+"（初始四项＋等级强化次数）");
        var relic=new GameItem(data);relic.setLevel(level+1);relic.setExp(0);relic.setMainPropId(mainId);relic.getAppendPropIdList().clear();relic.getAppendPropIdList().addAll(rolls);relic.setLocked(true);return relic;
    }
    static JsonObject artifact(Player player,JsonObject req)throws Exception{
        var relic=makeArtifact(req);if(!player.getInventory().addItem(relic))throw new IllegalStateException("背包空间不足，圣遗物未生成");
        player.save();var result=new JsonObject();result.addProperty("ok",true);result.addProperty("guid",Long.toString(relic.getGuid()));result.addProperty("item",relic.getItemId());result.addProperty("level",relic.getLevel()-1);audit("artifact",Long.toString(relic.getGuid()),req);return result;
    }
    static void audit(String type,String target,JsonObject before)throws Exception{
        var row=new JsonObject();row.addProperty("time",System.currentTimeMillis());row.addProperty("type",type);row.addProperty("target",target);row.add("data",before);
        Files.writeString(Path.of("logs","local-gear-history.jsonl"),row+"\n",StandardOpenOption.CREATE,StandardOpenOption.APPEND);
    }
}
