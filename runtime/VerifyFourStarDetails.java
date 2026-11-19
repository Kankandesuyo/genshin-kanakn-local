import com.mongodb.client.*;
import org.bson.Document;
import java.net.*;
import java.net.http.*;
import java.nio.file.*;
import java.util.*;

/** Read-only check: never prints or persists the account's session key. */
public class VerifyFourStarDetails {
    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.LoggerContext)org.slf4j.LoggerFactory.getILoggerFactory()).reset();
        try (var mongo=MongoClients.create("mongodb://127.0.0.1:27018")) {
            var db=mongo.getDatabase("astaps_local");
            var account=db.getCollection("accounts").find(new Document("username","player")).first();
            if(account==null)throw new IllegalStateException("Account missing");
            var key=URLEncoder.encode(account.getString("sessionKey"),java.nio.charset.StandardCharsets.UTF_8);
            var client=HttpClient.newHttpClient();
            var ranks=new HashMap<Integer,Integer>();
            for(String table:new String[]{"WeaponExcelConfigData.json","MaterialExcelConfigData.json"})
                for(var value:com.google.gson.JsonParser.parseString(Files.readString(Path.of("server/resources/ExcelBinOutput",table))).getAsJsonArray()) {
                    var item=value.getAsJsonObject();
                    if(item.has("rankLevel"))ranks.put(item.get("id").getAsInt(),item.get("rankLevel").getAsInt());
                }
            for(int schedule:new int[]{9101,9102,9103,9104}) {
                var body=get(client,"/gacha/details?s="+key+"&scheduleId="+schedule,200);
                if(body.contains("{{FIVE_STARS}}"))throw new IllegalStateException("Unrendered pools");
                Files.writeString(Path.of("logs/gacha-details-"+schedule+".html"),body);
                System.out.println("Details schedule="+schedule+" HTTP=200");
            }
            get(client,"/gacha?s=invalid&gachaType=301",403);
            get(client,"/gacha/details?s=invalid&scheduleId=9102",403);
            System.out.println("Unauthorized access rejected (403).");
        }
    }
    static String get(HttpClient client,String path,int expected)throws Exception {
        var result=client.send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:8088"+path)).build(),HttpResponse.BodyHandlers.ofString());
        if(result.statusCode()!=expected)throw new IllegalStateException("HTTP "+result.statusCode()+" expected "+expected);
        return result.body();
    }
}

