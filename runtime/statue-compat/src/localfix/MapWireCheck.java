package localfix;
import com.google.protobuf.CodedInputStream;
import java.util.*;
public final class MapWireCheck {
    public static void main(String[] args)throws Exception {
        var input=CodedInputStream.newInstance(MapCompat.pointPayload(3,List.of(382,383)));
        Set<Integer> fields=new HashSet<>(); int scene=0;
        while(!input.isAtEnd()){int tag=input.readTag();int field=tag>>>3;fields.add(field);if(field==2)scene=input.readUInt32();else input.skipField(tag);}
        if(scene!=3 || !fields.equals(Set.of(2,8,15)))throw new IllegalStateException("Unexpected wire fields: "+fields);
        System.out.println("Native point unlock/unhide wire verified: fields 2,8,15; no lock/hide fields.");
    }
}
