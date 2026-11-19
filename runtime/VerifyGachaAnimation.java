import java.util.*;
import emu.grasscutter.game.gacha.*;
import emu.grasscutter.net.proto.GachaItemOuterClass.GachaItem;
import emu.grasscutter.net.proto.DoGachaRspOuterClass.DoGachaRsp;
import emu.grasscutter.server.packet.send.PacketDoGachaRsp;
public class VerifyGachaAnimation {
 public static void main(String[] args)throws Exception {
  var normal=GachaItem.newBuilder().setGachaItem(emu.grasscutter.net.proto.ItemParamOuterClass.ItemParam.newBuilder().setItemId(1002).setCount(1)).build();
  var captured=GachaItem.newBuilder().setGachaItem(emu.grasscutter.net.proto.ItemParamOuterClass.ItemParam.newBuilder().setItemId(1002).setCount(1)).setIsFlashCard(true).build();
  for(boolean flash:new boolean[]{false,true}){
   var packet=new PacketDoGachaRsp(new GachaBanner(),List.of(flash?captured:normal),new PlayerGachaBannerInfo(),true);
   var data=DoGachaRsp.parseFrom(packet.getData());
   if(data.getUnknownFields().hasField(286)!=flash)throw new AssertionError("Wrong special-animation flag");
   if(data.getGachaItemListCount()!=1||data.getGachaItemList(0).getGachaItem().getItemId()!=1002)throw new AssertionError("Reward changed");
  }
  System.out.println("PASS: ordinary gold omits special-animation flag; actual radiance retains it; reward unchanged.");
 }
}
