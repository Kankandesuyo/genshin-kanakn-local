package localfix;

import emu.grasscutter.plugin.Plugin;
import emu.grasscutter.server.event.EventHandler;
import emu.grasscutter.server.event.game.ServerTickEvent;
import emu.grasscutter.game.player.Player;
import emu.grasscutter.game.entity.EntityGadget;
import emu.grasscutter.game.entity.gadget.GadgetWorktop;
import emu.grasscutter.game.world.Position;
import emu.grasscutter.server.packet.send.PacketGroupSuiteNotify;
import emu.grasscutter.server.packet.send.PacketWorktopOptionNotify;
import java.util.*;

/** Local single-player compatibility for statue interactions and nearby world spawning. */
public final class StatueCompat extends Plugin {
    private long nextCheck;
    private final Map<Integer, EntityGadget> proxies = new HashMap<>();

    @Override public void onEnable() {
        EventHandler.newHandler(this, ServerTickEvent.class, event -> tick());
        emu.grasscutter.command.CommandMap.getInstance().registerCommand("localgm", new LocalGm());
        emu.grasscutter.command.CommandMap.getInstance().registerCommand("localgear", new LocalGear());
        try { LocalGm.prepareTicketLimits(); LocalGm.load(); getLogger().info("Local GM: custom banners loaded; fate limits raised to 100M."); } catch (Exception e) { getLogger().error("Local GM banners failed", e); }
        try { MapCompat.initialize(); getServer().getPacketHandler().registerPacketHandler(MapCompat.AreaHandler.class); getServer().getPacketHandler().registerPacketHandler(MapCompat.PointHandler.class); } catch(Exception error) { getLogger().error("Local map setup failed",error); }
        try { WorldCompat.initialize(); getLogger().info("World compatibility indexed {} monster placements",WorldCompat.count()); } catch(Exception error) { getLogger().error("World compatibility initialization failed",error); }
        getLogger().info("StatueCompat enabled: starter statue heal/resonate fallback; no offering consumption.");
    }
    static int unlockCostumes(Player player){
        int added=0;for(var costume:emu.grasscutter.data.GameData.getAvatarCostumeDataMap().values())if(costume.getId()>0&&!player.getCostumeList().contains(costume.getId())){player.addCostume(costume.getId());added++;}
        int wings=0;for(var cloak:emu.grasscutter.data.GameData.getAvatarFlycloakDataMap().values())if(cloak.getId()>0&&!player.getFlyCloakList().contains(cloak.getId())){player.addFlycloak(cloak.getId());wings++;}
        if(added>0||wings>0)player.save();return added;
    }
    private void tick() {
        if (System.currentTimeMillis() < nextCheck) return;
        nextCheck = System.currentTimeMillis() + 2000;
        // Suppress only the stock rolling welcome banner, including after an announce refresh.
        var announcements=getServer().getAnnouncementSystem();
        for(var entry:announcements.getAnnounceConfigItemMap().values()){
            String content=entry.getContent();
            if(content!=null&&content.replaceAll("<[^>]*>","").startsWith("Welcome to AstaPS")&&entry.isTick()){
                entry.setTick(false);announcements.revoke(entry.getTemplateId());
                getLogger().info("Local display: disabled rolling welcome announcement {}",entry.getTemplateId());
            }
        }
        for (Player player : getServer().getPlayers().values()) {
            if(player.getUid()==10001&&player.isOnline())try{unlockCostumes(player);}catch(Exception error){getLogger().error("Local costume unlock failed",error);}
            if (player.getUid() != 10001 || player.getScene() == null || !player.isOnline() || player.getSceneLoadState() != Player.SceneLoadState.LOADED || player.isPaused()) continue;

            try { MapCompat.onReady(player); } catch(Exception error) { getLogger().error("Local map reveal failed",error); }
            try { WorldCompat.tick(player); } catch(Exception error) { getLogger().error("Local monster spawn failed",error); }
            EntityGadget previous = proxies.get(player.getUid());
            if (previous != null && previous.getScene() != player.getScene()) {
                proxies.remove(player.getUid());
                previous = null;
            }
            emu.grasscutter.data.common.PointData nearby=null;Position anchor=null;double distance=18;
            for(var entry:emu.grasscutter.data.GameData.getScenePointEntryMap().values()) {
                if(entry.getSceneId()!=player.getSceneId()||!emu.grasscutter.game.managers.StatueTalkQuests.isStatuePoint(entry.getPointData()))continue;
                var point=entry.getPointData();
                for(var position:new Position[]{point.getPos(),point.getTranPos()}) {
                    if(position!=null&&player.getPosition().computeDistance(position)<distance){distance=player.getPosition().computeDistance(position);nearby=point;anchor=position;}
                }
            }
            boolean near=nearby!=null;
            if (!near) {
                if (previous != null) {
                    previous.getScene().removeEntity(previous);
                    proxies.remove(player.getUid());
                }
                continue;
            }
            heal(player);
            if (previous != null) {
                if(previous.getPosition().computeDistance(anchor)<4)continue;
                previous.getScene().removeEntity(previous);proxies.remove(player.getUid());
            }
            try {
                final int areaId=nearby.getAreaId();
                // Place on accessible ground next to the player, outside the statue's solid column.
                Position pos = anchor.clone();
                if(Math.abs(pos.getY()-player.getPosition().getY())<6)pos.setY(player.getPosition().getY());
                pos.setX(pos.getX() + 0.8f);
                EntityGadget proxy = new EntityGadget(player.getScene(), 70360001, pos, new Position());
                proxy.setConfigId(90701);
                proxy.setGroupId(0);
                proxy.setInteractEnabled(true);
                proxy.buildContent();
                if (!(proxy.getContent() instanceof GadgetWorktop worktop)) {
                    getLogger().error("StatueCompat: gadget 70360001 is not a worktop; no fallback created.");
                    continue;
                }
                worktop.addWorktopOptions(new int[]{10010001, 1159});
                worktop.setOnSelectWorktopOptionEvent((ctx, option) -> {
                    try {
                        if (option == 10010001) {
                            heal(player);
                            player.dropMessage("队伍已恢复生命。此入口为本地神像兼容交互。");
                        } else if (option == 1159) {
                            var method = player.getProgressManager().getClass().getDeclaredMethod("handleStatueProxyOption", int.class, int.class, int.class);
                            method.setAccessible(true);
                            method.invoke(player.getProgressManager(), areaId, player.getSceneId(), 1159);
                        }
                        getLogger().info("StatueCompat selected uid={} option={}", player.getUid(), option);
                    } catch (Exception ex) { getLogger().error("StatueCompat interaction failed", ex); }
                    return false;
                });
                player.getScene().addEntity(proxy);
                player.sendPacket(new PacketWorktopOptionNotify(proxy));
                proxies.put(player.getUid(), proxy);
                getLogger().info("StatueCompat created uid={} entity={} pos={}", player.getUid(), proxy.getId(), pos);
            } catch (Exception ex) { getLogger().error("StatueCompat spawn failed", ex); }
        }
    }
    public static void heal(Player player) {
        for(var entity:player.getTeamManager().getActiveTeam()) {
            if(!entity.isAlive())player.getTeamManager().reviveAvatar(entity.getAvatar());
            if(entity.getFightProperty(emu.grasscutter.game.props.FightProperty.FIGHT_PROP_CUR_HP)<entity.getFightProperty(emu.grasscutter.game.props.FightProperty.FIGHT_PROP_MAX_HP))
                player.getTeamManager().healAvatar(entity.getAvatar(),100,0);
        }
    }
    @Override public void onDisable() {
        for (EntityGadget entity : proxies.values()) entity.getScene().removeEntity(entity);
        proxies.clear();
        emu.grasscutter.command.CommandMap.getInstance().unregisterCommand("localgm");
        emu.grasscutter.command.CommandMap.getInstance().unregisterCommand("localgear");
    }
}



