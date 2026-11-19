package localfix;

import com.google.gson.Gson;
import emu.grasscutter.data.GameData;
import emu.grasscutter.game.entity.EntityMonster;
import emu.grasscutter.game.player.Player;
import emu.grasscutter.game.world.*;
import java.nio.file.*;
import java.util.*;

/** Local fallback for existing spawn data when a scene's script groups are absent. */
public final class WorldCompat {
    private static final Map<String,List<SpawnDataEntry>> cells=new HashMap<>();
    private static final Map<Scene,Map<String,EntityMonster>> active=new WeakHashMap<>();
    private static final Map<String,Long> killed=new HashMap<>();
    private static int entries;
    private static String cell(int scene,int x,int z){return scene+":"+x+":"+z;}
    private static String key(int scene,SpawnDataEntry entry){return scene+":"+entry.getGroup().getGroupId()+":"+entry.getConfigId();}
    public static void initialize() throws Exception {
        cells.clear();entries=0;
        var groups=new Gson().fromJson(Files.readString(Path.of("data","Spawns.json")),SpawnDataEntry.SpawnGroupEntry[].class);
        for(var group:groups)for(var spawn:group.getSpawns()){
            if(spawn.getMonsterId()<=0 || spawn.getPos()==null || !GameData.getMonsterDataMap().containsKey(spawn.getMonsterId()))continue;
            spawn.setGroup(group);
            cells.computeIfAbsent(cell(group.getSceneId(),(int)Math.floor(spawn.getPos().getX()/200),(int)Math.floor(spawn.getPos().getZ()/200)),k->new ArrayList<>()).add(spawn);
            entries++;
        }
    }
    public static int count(){return entries;}
    public static void tick(Player player){
        var scene=player.getScene();if(scene==null||player.isPaused()||scene.isPaused()||!Set.of(3,4,5,6).contains(scene.getId()))return;
        WorldBossSpawnHelper.ensureNearbyBosses(scene);
        WorldBossDirectSpawner.ensureNearby(player);
        var tracked=active.computeIfAbsent(scene,k->new HashMap<>());long now=System.currentTimeMillis();
        var iterator=tracked.entrySet().iterator();
        while(iterator.hasNext()){
            var trackedEntry=iterator.next();var monster=trackedEntry.getValue();
            if(!monster.isAlive()) {killed.put(trackedEntry.getKey(),now+600000);iterator.remove();}
            else if(monster.getPosition().computeDistance(player.getPosition())>240){scene.removeEntity(monster);iterator.remove();}
            else if(scene.getEntityById(monster.getId())==null)iterator.remove();
        }
        int cx=(int)Math.floor(player.getPosition().getX()/200),cz=(int)Math.floor(player.getPosition().getZ()/200),added=0;
        for(int x=cx-1;x<=cx+1;x++)for(int z=cz-1;z<=cz+1;z++)for(var entry:cells.getOrDefault(cell(scene.getId(),x,z),List.of())){
            if(added>=12||tracked.size()>=60)return;
            String key=key(scene.getId(),entry);if(tracked.containsKey(key)||killed.getOrDefault(key,0L)>now)continue;
            if(entry.getPos().computeDistance(player.getPosition())>140||Math.abs(entry.getPos().getY()-player.getPosition().getY())>45)continue;
            boolean exists=scene.getEntities().values().stream().anyMatch(e->e instanceof EntityMonster&&((e.getGroupId()==entry.getGroup().getGroupId()&&e.getConfigId()==entry.getConfigId())||(e.getEntityTypeId()==entry.getMonsterId()&&e.getPosition().computeDistance(entry.getPos())<8)));
            if(exists)continue;
            var data=GameData.getMonsterDataMap().get(entry.getMonsterId());
            // Boss groups have their own flower/reward/respawn lifecycle; never bypass it here.
            if(data.getType()!=null&&data.getType().name().contains("BOSS"))continue;
            var monster=new EntityMonster(scene,data,entry.getPos().clone(),entry.getRot()==null?new Position():entry.getRot().clone(),scene.getLevelForMonster(entry.getConfigId(),entry.getLevel()));
            monster.setGroupId(entry.getGroup().getGroupId());monster.setConfigId(entry.getConfigId());monster.setPoseId(entry.getPoseId());
            scene.addEntity(monster);tracked.put(key,monster);added++;
        }
    }
}
