import com.google.protobuf.*;import java.nio.file.*;import java.util.*;
class InspectWingProtocol{public static void main(String[]args)throws Exception{
var set=DescriptorProtos.FileDescriptorSet.parseFrom(Files.readAllBytes(Path.of("server/protocol/7.1/protocol.desc")));
for(var file:set.getFileList())for(var m:file.getMessageTypeList())if(Set.of("AvatarDataNotify","AvatarGainFlycloakNotify","AvatarGainCostumeNotify","AvatarWearFlycloakReq").contains(m.getName())){System.out.println("NATIVE "+m.getName());for(var f:m.getFieldList())System.out.println(f.getNumber()+" "+f.getName()+" "+f.getType());}
System.out.println("GENERATED GAIN "+emu.grasscutter.net.proto.AvatarGainFlycloakNotifyOuterClass.AvatarGainFlycloakNotify.getDescriptor().getFields());
for(var f:emu.grasscutter.net.proto.AvatarDataNotifyOuterClass.AvatarDataNotify.getDescriptor().getFields())System.out.println("GENERATED DATA "+f.getNumber()+" "+f.getName());}}
