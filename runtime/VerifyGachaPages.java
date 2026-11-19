import com.mongodb.client.*;
import org.bson.Document;
import java.net.*;
import java.net.http.*;
import java.nio.file.*;
import java.util.*;

/** Read-only check: never prints or persists the account's session key. */
public class VerifyGachaPages {
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
            for(int type:new int[]{200,301,302,500}) {
                var count=db.getCollection("gachas").countDocuments(new Document("ownerId",10001).append("gachaType",type));
                String body=get(client,"/gacha?s="+key+"&gachaType="+type+"&p=0",200);
                if(body.contains("{{REPLACE_"))throw new IllegalStateException("Unrendered records");
                var latest=db.getCollection("gachas").find(new Document("ownerId",10001).append("gachaType",type)).sort(new Document("transactionDate",-1)).first();
                if(latest!=null&&!body.contains("\"item\":"+latest.getInteger("itemID")))throw new IllegalStateException("Latest record missing");
                Files.writeString(Path.of("logs/gacha-history-"+type+".html"),body);
                var actualRows=new ArrayList<com.google.gson.JsonObject>();
                for(int p=0;p<Math.max(1,(count+9)/10);p++) {
                    var html=p==0?body:get(client,"/gacha?s="+key+"&gachaType="+type+"&p="+p,200);
                    var literal=html.split("const records=",2)[1].split(";",2)[0];
                    for(var row:com.google.gson.JsonParser.parseString(literal).getAsJsonArray())actualRows.add(row.getAsJsonObject());
                }
                Collections.reverse(actualRows);
                int gap=0,golds=0;
                var ordered=db.getCollection("gachas").find(new Document("ownerId",10001).append("gachaType",type)).sort(new Document("transactionDate",1).append("_id",1)).into(new ArrayList<>());
                if(actualRows.size()!=ordered.size())throw new IllegalStateException("Pagination mismatch");
                for(int i=0;i<ordered.size();i++) {
                    var doc=ordered.get(i);var actual=actualRows.get(i);int id=doc.getInteger("itemID");gap++;
                    if(actual.get("item").getAsInt()!=id)throw new IllegalStateException("Order mismatch");
                    if(ranks.getOrDefault(id,0)!=actual.get("stars").getAsInt())throw new IllegalStateException("Rank mismatch for "+id);
                    if(actual.get("stars").getAsInt()==5) {
                        if(actual.get("pullsToFive").getAsInt()!=gap)throw new IllegalStateException("Cross-page interval mismatch");
                        if(actual.get("fromFirstRecord").getAsBoolean()!=(golds==0))throw new IllegalStateException("First gold mismatch");
                        gap=0;golds++;
                    }
                }
                var summary=com.google.gson.JsonParser.parseString(body.split("const summary=",2)[1].split(";",2)[0]).getAsJsonObject();
                if(summary.get("total").getAsLong()!=count||summary.get("fiveStars").getAsInt()!=golds||summary.get("sinceLastFive").getAsInt()!=gap)throw new IllegalStateException("Pool summary mismatch");
                Collections.reverse(actualRows);
                var fixture=new com.google.gson.JsonObject();
                fixture.add("summary",summary);
                fixture.add("records",new com.google.gson.Gson().toJsonTree(actualRows));
                Files.writeString(Path.of(System.getProperty("java.io.tmpdir"),"gacha-qa-"+type+".json"),fixture.toString());
                System.out.println("PASS pool="+type+" allPages="+((count+9)/10)+" fiveStars="+golds+" sinceLastFive="+gap+" intervalsMatchDatabase=true");
                System.out.println("History type="+type+" databaseRecords="+count+" HTTP=200 latestRecordVerified="+(latest!=null)+" latestTime="+(latest==null?"none":latest.getDate("transactionDate").toInstant()));
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
