package localfix;

import com.google.gson.*;
import emu.grasscutter.command.*;
import emu.grasscutter.game.player.Player;
import emu.grasscutter.data.GameData;
import emu.grasscutter.game.gacha.GachaBanner;
import java.nio.file.*;
import java.util.*;
import picocli.CommandLine;

@Command(label="localgm", permission="player.give", permissionTargeted="player.give.others")
public final class LocalGm implements CommandHandler {
    private static final Path FILE = Path.of("data", "LocalBanners.json");
    private static final Gson JSON = new GsonBuilder().setPrettyPrinting().create();
    public static void prepareTicketLimits() throws Exception {
        // The local manager explicitly permits 100M; change only the two fate item limits.
        var field=emu.grasscutter.data.excels.ItemData.class.getDeclaredField("stackLimit");
        field.setAccessible(true);
        for(int id:new int[]{223,224}) field.setInt(GameData.getItemDataMap().get(id),100000000);
    }
    public static synchronized void load() throws Exception {
        JsonArray rows = JsonParser.parseString(Files.readString(FILE)).getAsJsonArray();
        Map<Integer,GachaBanner> valid = new LinkedHashMap<>();
        for (var row : rows) {
            GachaBanner b = JSON.fromJson(row, LegacyBanner.class);
            b.onLoad(); b.ensureFallback4Pools();
            if (b.isDeprecated() || b.isDisabled() || valid.containsKey(b.getScheduleId()))
                throw new IllegalArgumentException("Invalid banner configuration");
            for (int id : b.getRateUpItems5())
                if (!GameData.getItemDataMap().containsKey(id)) throw new IllegalArgumentException("Unknown item " + id);
            valid.put(b.getScheduleId(), b);
        }
        if (valid.size() < 3) throw new IllegalArgumentException("Expected at least three banners");
        var system = emu.grasscutter.Grasscutter.getGameServer().getGachaSystem();
        synchronized (system) { system.getGachaBanners().clear(); system.getGachaBanners().putAll(valid); }
    }
    public static final class LegacyBanner extends GachaBanner {
        @Override public boolean hasEpitomized() {
            return getBannerType()!=GachaBanner.BannerType.CHRONICLE&&super.hasEpitomized();
        }
        @Override public emu.grasscutter.net.proto.GachaInfoOuterClass.GachaInfo toProto(Player player) {
            var info=super.toProto(player).toBuilder().setIsNewWish(false).setHMOJLEMLHDK(false);
            // The old prefab has no Chronicle path widgets. Render the independent mixed pool
            // through the supported second-character tab; pulls/history still use this schedule's 500 pool.
            if(getBannerType()==GachaBanner.BannerType.CHRONICLE)info.setGachaType(400);
            return info.build();
        }
    }
    @Override public CommandLine createCommandLine(Player sender, Player target) {
        return new CommandLine(new Args(sender,target));
    }
    @CommandLine.Command(name="localgm")
    private static final class Args implements Runnable {
        private final Player sender, player;
        @CommandLine.Parameters(arity="1..3") private List<String> args;
        Args(Player sender, Player player) { this.sender=sender; this.player=player; }
        public void run() {
            try {
                if (player == null || player.getUid()!=10001) throw new IllegalArgumentException("仅支持本地账号 10001，请先进入游戏");
                switch(args.get(0)) {
                    case "status" -> status();
                    case "heal" -> {StatueCompat.heal(player);status();}
                    case "reload" -> {load();player.sendPacket(new emu.grasscutter.server.packet.send.PacketGetGachaInfoRsp(emu.grasscutter.Grasscutter.getGameServer().getGachaSystem(),player));status();}
                    case "set" -> {
                        if(args.size()!=3) throw new IllegalArgumentException("set needs item and quantity");
                        int id=Integer.parseInt(args.get(1)), n=Integer.parseInt(args.get(2));
                        if(n<0 || n>100000000) throw new IllegalArgumentException("数量范围 0～100000000");
                        if(id==201) player.setPrimogems(n);
                        else if(id==202) player.setMora(n);
                        else if(id==106) {
                            if(n>2000)throw new IllegalArgumentException("原粹树脂范围 0～2000");
                            player.setProperty(emu.grasscutter.game.props.PlayerProperty.PROP_PLAYER_RESIN,n);
                            player.setNextResinRefresh(n>=200?0:emu.grasscutter.utils.Utils.getCurrentSeconds()+480);
                            player.sendPacket(new emu.grasscutter.server.packet.send.PacketResinChangeNotify(player));
                        }
                        else if(id==223 || id==224 || Set.of(104001,104002,104003,104011,104012,104013).contains(id)) {
                            if(id>=104001&&n>99999)throw new IllegalArgumentException("经验书和矿石范围 0～99999");
                            int old=player.getInventory().getItemCountById(id);
                            if(n>old && !player.getInventory().addItem(id,n-old)) throw new IllegalStateException("增加失败");
                            if(n<old && !player.getInventory().removeItemById(id,old-n)) throw new IllegalStateException("扣减失败");
                        } else throw new IllegalArgumentException("Unsupported item");
                        player.save(); status();
                    }
                    case "warehouse" -> {
                        var rows=new JsonArray();
                        for(var item:player.getInventory())if(item.getItemData().getItemType().name().equals("ITEM_WEAPON")&&item.getItemData().getRankLevel()==4) {
                            var row=new JsonObject();row.addProperty("guid",Long.toString(item.getGuid()));row.addProperty("id",item.getItemId());
                            row.addProperty("level",item.getLevel());row.addProperty("refinement",item.getRefinement());
                            row.addProperty("protected",!item.isDestroyable());rows.add(row);
                        }
                        var result=new JsonObject();result.add("weapons",rows);CommandOutput.sendMessage(sender,result.toString());
                    }
                    case "recycle" -> {
                        if(args.size()!=2)throw new IllegalArgumentException("请选择一把四星武器");
                        var inventory=player.getInventory();
                        synchronized(inventory) {
                            var item=inventory.getItemByGuid(Long.parseLong(args.get(1)));
                            if(item==null||item.getItemData().getRankLevel()!=4||!item.getItemData().getItemType().name().equals("ITEM_WEAPON"))throw new IllegalArgumentException("只允许分解四星武器");
                            if(!item.isDestroyable())throw new IllegalArgumentException("锁定或已装备武器不能分解");
                            if(inventory.getItemCountById(104013)>99989)throw new IllegalArgumentException("精锻用魔矿已接近上限，请先消耗");
                            if(!inventory.addItem(104013,10))throw new IllegalStateException("返还矿石失败，武器未分解");
                            if(!inventory.removeItem(item,1)){inventory.removeItemById(104013,10);throw new IllegalStateException("武器未删除，已撤回矿石");}
                            Files.writeString(Path.of("logs","local-weapon-recycle.jsonl"),"{\"time\":"+System.currentTimeMillis()+",\"guid\":\""+item.getGuid()+"\",\"id\":"+item.getItemId()+",\"returnOre\":10}\n",StandardOpenOption.CREATE,StandardOpenOption.APPEND);
                            player.save();status();
                        }
                    }
                    case "banner" -> {
                        if(args.size()!=3) throw new IllegalArgumentException("banner needs character and weapon");
                        int avatar=Integer.parseInt(args.get(1)), weapon=Integer.parseInt(args.get(2));
                        int actualAvatarId=0;
                        for(var row:JsonParser.parseString(Files.readString(Path.of("..","runtime","manager-catalog.json"))).getAsJsonObject().getAsJsonArray("avatars")) {
                            var entry=row.getAsJsonObject();
                            if(entry.get("id").getAsInt()==avatar || entry.get("avatarId").getAsInt()==avatar) {
                                avatar=entry.get("id").getAsInt(); actualAvatarId=entry.get("avatarId").getAsInt(); break;
                            }
                        }
                        if(!GameData.getAvatarDataMap().containsKey(actualAvatarId)
                            || !GameData.getItemDataMap().containsKey(avatar)) throw new IllegalArgumentException("角色 ID 无效");
                        if(!GameData.getAvatarDataMap().get(actualAvatarId).getQualityType().startsWith("QUALITY_ORANGE"))
                            throw new IllegalArgumentException("角色 UP 请选择五星；四星角色可在全角色混合池抽取");
                        var wd=GameData.getItemDataMap().get(weapon);
                        if(wd==null || wd.getRankLevel()!=5 || !wd.getItemType().name().equals("ITEM_WEAPON")) throw new IllegalArgumentException("请输入五星武器 ID");
                        JsonArray rows=JsonParser.parseString(Files.readString(FILE)).getAsJsonArray();
                        for(var row:rows) {
                            var object=row.getAsJsonObject();
                            String type=object.get("bannerType").getAsString();
                            if(type.equals("CHARACTER") || type.equals("WEAPON")) {
                                var up=new JsonArray(); up.add(type.equals("CHARACTER")?avatar:weapon); object.add("rateUpItems5",up);
                                applySkin(object,type.equals("CHARACTER")?avatar:weapon);
                            }
                        }
                        String previous=Files.readString(FILE);
                        Path tmp=FILE.resolveSibling("LocalBanners.json.tmp");
                        Files.writeString(tmp,JSON.toJson(rows));
                        Files.move(tmp,FILE,StandardCopyOption.REPLACE_EXISTING);
                        try { load(); } catch(Exception error) { Files.writeString(FILE,previous); load(); throw error; }
                        player.sendPacket(new emu.grasscutter.server.packet.send.PacketGetGachaInfoRsp(
                            emu.grasscutter.Grasscutter.getGameServer().getGachaSystem(),player));
                        status();
                    }
                    default -> throw new IllegalArgumentException("Unknown operation");
                }
            } catch(Exception error) { CommandOutput.sendMessage(sender,"ERROR: "+error.getMessage()); }
        }
        private void applySkin(JsonObject banner,int id) throws Exception {
            // Keep the complete legacy panel/tab pair that this client has rendered successfully.
            // An item portrait is not a wish-tab asset; unsupported per-item panels can trap the UI.
            banner.addProperty("prefabPath",banner.get("bannerType").getAsString().equals("CHARACTER")
                ? "GachaShowPanel_A022" : "GachaShowPanel_A019");
            banner.remove("previewPrefabPath");
            banner.remove("titlePath");
        }
        private void status() {
            Map<String,Object> result=new LinkedHashMap<>();
            result.put("primogems",player.getPrimogems());
            result.put("mora",player.getMora());
            result.put("resin",player.getProperty(emu.grasscutter.game.props.PlayerProperty.PROP_PLAYER_RESIN));
            for(int id:new int[]{104001,104002,104003,104011,104012,104013})result.put("item"+id,player.getInventory().getItemCountById(id));
            result.put("sceneId",player.getSceneId());
            result.put("paused",player.isPaused());
            var health=new JsonArray();for(var entity:player.getTeamManager().getActiveTeam()) {
                var entry=new JsonObject();entry.addProperty("avatar",entity.getAvatar().getAvatarId());
                entry.addProperty("hp",entity.getFightProperty(emu.grasscutter.game.props.FightProperty.FIGHT_PROP_CUR_HP));
                entry.addProperty("maxHp",entity.getFightProperty(emu.grasscutter.game.props.FightProperty.FIGHT_PROP_MAX_HP));health.add(entry);
            }result.put("teamHealth",health);
            result.put("position",player.getPosition());
            result.put("worldSpawnPlacements",WorldCompat.count());
            if(player.getScene()!=null)result.put("sceneMonsters",player.getScene().getEntities().values().stream().filter(e->e instanceof emu.grasscutter.game.entity.EntityMonster).count());
            result.put("intertwined",player.getInventory().getItemCountById(223));
            result.put("acquaint",player.getInventory().getItemCountById(224));
            result.put("intertwinedMax",GameData.getItemDataMap().get(223).getStackLimit());
            result.put("acquaintMax",GameData.getItemDataMap().get(224).getStackLimit());
            var banners=emu.grasscutter.Grasscutter.getGameServer().getGachaSystem().getGachaBanners();
            result.put("bannerCount",banners.size());
            result.put("legacyCardMode",banners.values().stream().noneMatch(b->b.toProto(player).getIsNewWish()));
            result.put("mapFogEnabled",emu.grasscutter.config.Configuration.GAME_OPTIONS.mapFogEnabled);
            result.put("disabledMapFogAreas",MapCompat.disabledFogAreas());
            result.put("scene3ForcedLocks",player.getForceLockedScenePoints(3).size());
            for(var banner:banners.values()) {
                if(banner.getBannerType()==GachaBanner.BannerType.CHARACTER) result.put("characterUp",banner.getRateUpItems5());
                if(banner.getBannerType()==GachaBanner.BannerType.WEAPON) result.put("weaponUp",banner.getRateUpItems5());
                if(banner.getBannerType()==GachaBanner.BannerType.CHARACTER) result.put("characterPreview",banner.getPreviewPrefabPath());
                if(banner.getBannerType()==GachaBanner.BannerType.WEAPON) result.put("weaponPreview",banner.getPreviewPrefabPath());
                if(banner.getScheduleId()==9104) {
                    result.put("mixedFiveStars",banner.getRateUpItems5().length);
                    result.put("mixedFourStars",banner.getRateUpItems4().length);
                }
            }
            CommandOutput.sendMessage(sender, new Gson().toJson(result));
        }
    }
}
