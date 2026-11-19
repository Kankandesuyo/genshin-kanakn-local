package localfix;

import com.google.gson.*;
import com.google.protobuf.CodedOutputStream;
import emu.grasscutter.data.GameData;
import emu.grasscutter.game.player.Player;
import emu.grasscutter.net.packet.*;
import emu.grasscutter.net.proto.GetMapAreaRspOuterClass.GetMapAreaRsp;
import emu.grasscutter.net.proto.MapAreaInfoOuterClass.MapAreaInfo;
import emu.grasscutter.server.game.GameSession;
import emu.grasscutter.server.packet.send.PacketGetScenePointRsp;
import java.io.ByteArrayOutputStream;
import java.nio.file.*;
import java.util.*;

public final class MapCompat {
    private static final Set<Integer> FOG=new HashSet<>();
    private static final Map<Player,Integer> visits=new WeakHashMap<>();
    private static int globalBoundary;
    public static Set<Integer> disabledFogAreas() { return Set.copyOf(FOG); }
    public static void initialize() throws Exception {
        for(var row:JsonParser.parseString(Files.readString(Path.of("resources/ExcelBinOutput/LimitRegionExcelConfigData.json"))).getAsJsonArray()){
            var data=row.getAsJsonObject();
            if(data.has("sceneId")&&data.get("sceneId").getAsInt()==3&&data.has("openstate")&&data.get("openstate").getAsString().equals("OPEN_STATE_LIMIT_REGION_GLOBAL"))globalBoundary=data.get("id").getAsInt();
        }
        for(var row:JsonParser.parseString(Files.readString(Path.of("resources/ExcelBinOutput/MapAreaConfigData.json"))).getAsJsonArray()) {
            var data=row.getAsJsonObject(); String name=data.has("name")?data.get("name").getAsString():"";
            // Quest 7507611 removes area 61 (Mihai initial MistOpen overlay) when fog clears.
            boolean initialMist=data.has("mapAreaState")&&data.get("mapAreaState").getAsString().equals("MistOpen");
            if(initialMist||name.contains("鹤观") || name.contains("迷雾") || name.contains("雾气") || name.contains("迷雾图")) FOG.add(data.get("id").getAsInt());
        }
        emu.grasscutter.config.Configuration.GAME_OPTIONS.mapFogEnabled=false;
    }
    public static BasePacket mapPacket() {
        var builder=GetMapAreaRsp.newBuilder();
        for(int id=1;id<=200;id++) builder.addMapAreaInfoList(MapAreaInfo.newBuilder().setMapAreaId(id).setIsOpen(!FOG.contains(id)));
        BasePacket packet=new BasePacket(PacketOpcodes.GetMapAreaRsp); packet.setData(builder); return packet;
    }
    public static JsonObject refreshMap(Player player){
        player.sendPacket(mapPacket());var result=new JsonObject();result.addProperty("ok",true);result.add("disabledFogAreas",new Gson().toJsonTree(disabledFogAreas()));return result;
    }
    public static void reveal(Player player,int sceneId) throws Exception {
        var points=GameData.getScenePointsPerScene().get(sceneId);
        if(points==null || points.isEmpty())return;
        player.getForceLockedScenePoints(sceneId).clear();
        player.getUnlockedScenePoints(sceneId).addAll(points);
        BasePacket packet=new BasePacket(PacketOpcodes.ScenePointUnlockNotify); packet.setData(pointPayload(sceneId,points));
        player.sendPacket(packet);
    }
    public static byte[] pointPayload(int sceneId,Collection<Integer> points) throws Exception {
        ByteArrayOutputStream packed=new ByteArrayOutputStream(); var ids=CodedOutputStream.newInstance(packed);
        for(int id:points)ids.writeUInt32NoTag(id); ids.flush();
        ByteArrayOutputStream output=new ByteArrayOutputStream(); var wire=CodedOutputStream.newInstance(output);
        wire.writeUInt32(2,sceneId);
        // Native 7.1: 8 = unhide_point_list; generated unhide accessor is incorrectly wire 4 (lock).
        wire.writeByteArray(8,packed.toByteArray()); wire.writeByteArray(15,packed.toByteArray()); wire.flush();
        return output.toByteArray();
    }
    public static void onReady(Player player) throws Exception {
        int scene=player.getSceneId();
        if(visits.getOrDefault(player,-1)==scene)return;
        visits.put(player,scene);
        for(int id:GameData.getScenePointsPerScene().keySet())reveal(player,id);
        player.sendPacket(mapPacket()); player.sendPacket(new PacketGetScenePointRsp(player,scene));if(scene==3)syncBoundary(player); player.save();
        emu.grasscutter.Grasscutter.getLogger().info("Local map: hidden points revealed and {} fog overlays disabled uid={}",FOG.size(),player.getUid());
    }
    public static JsonObject syncBoundary(Player player){
        var result=new JsonObject();result.addProperty("scene",player.getSceneId());
        if(player.getSceneId()!=3||globalBoundary<=0)throw new IllegalArgumentException("此兼容修复仅适用于普通大世界");
        var region=emu.grasscutter.net.proto.LimitedRegionInfo._LimitedRegionInfo.newBuilder().addLimitedRegionList(globalBoundary);
        var scene=emu.grasscutter.net.proto.SceneDataNotifyOuterClass.SceneDataNotify.newBuilder().setSceneId(3).setLimitedRegionInfo(region).addAllSceneTagIdList(player.getSceneTags().getOrDefault(3,Set.of()));
        BasePacket packet=new BasePacket(PacketOpcodes.SceneDataNotify);packet.setData(scene);player.sendPacket(packet);
        result.addProperty("ok",true);result.addProperty("globalBoundary",globalBoundary);return result;
    }
    @Opcodes(PacketOpcodes.GetMapAreaReq)
    public static final class AreaHandler extends PacketHandler {
        @Override public void handle(GameSession session,byte[] header,byte[] payload) {session.send(mapPacket());}
    }
    @Opcodes(PacketOpcodes.GetScenePointReq)
    public static final class PointHandler extends emu.grasscutter.server.packet.recv.HandlerGetScenePointReq {
        @Override public void handle(GameSession session,byte[] header,byte[] payload) throws Exception {
            super.handle(session,header,payload);
            int scene=emu.grasscutter.net.proto.GetScenePointReqOuterClass.GetScenePointReq.parseFrom(payload).getSceneId();
            reveal(session.getPlayer(),scene>0&&scene<1000?scene:session.getPlayer().getSceneId());
        }
    }
}
