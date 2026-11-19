package emu.grasscutter.server.http.handlers;

import static emu.grasscutter.utils.lang.Language.translate;

import com.google.gson.JsonObject;
import emu.grasscutter.Grasscutter;
import emu.grasscutter.database.DatabaseHelper;
import emu.grasscutter.game.player.Player;
import emu.grasscutter.server.http.Router;
import emu.grasscutter.utils.*;
import io.javalin.Javalin;
import io.javalin.http.*;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Handles all gacha-related HTTP requests. */
public final class GachaHandler implements Router {
    private static final Path gachaMappingsPath = FileUtils.getDataUserPath("gacha/mappings.js");

    public static Path getGachaMappingsPath() { return gachaMappingsPath; }

    @Deprecated(forRemoval = true)
    public static final String gachaMappings = gachaMappingsPath.toString();

    /**
     * The client is told these two URLs through GachaInfo.gacha_record_url / gacha_prob_url. Which of
     * the two 7.0 field numbers is which was only recoverable from one dump, so route on the query
     * string instead of trusting it: the history page is the one asked for by gachaType, the details
     * page the one asked for by scheduleId. A swapped pair then still lands on the right page.
     */
    private static void gachaRecords(Context ctx) {
        if (ctx.queryParam("gachaType") == null && ctx.queryParam("scheduleId") != null) {
            gachaDetails(ctx);
            return;
        }

        var sessionKey = ctx.queryParam("s");
        var account = DatabaseHelper.getAccountBySessionKey(sessionKey);
        if (account == null) {
            ctx.status(403).result("Requested account was not found.");
            return;
        }

        // Get page and gacha type.
        int page = 0, gachaType = 0;

        var pageStr = ctx.queryParam("p");
        if (pageStr != null) page = Integer.parseInt(pageStr);

        var gachaTypeStr = ctx.queryParam("gachaType");
        if (gachaTypeStr != null) gachaType = Integer.parseInt(gachaTypeStr);

        // Make request to dispatch server.
        var data = DispatchUtils.fetchGachaRecords(account.getId(), page, gachaType);
        var records = data.get("records").getAsString();
        var maxPage = data.get("maxPage").getAsLong();

        var locale = account.getLocale();
        var template =
                new String(
                                FileUtils.read(FileUtils.getDataPath("gacha/records.html")), StandardCharsets.UTF_8)
                        .replace("'{{REPLACE_RECORDS}}'", Utils.unescapeJson(records))
                        .replace("'{{REPLACE_MAXPAGE}}'", String.valueOf(maxPage))
                        .replace("'{{REPLACE_SUMMARY}}'", data.has("summary") ? data.get("summary").getAsString() : "{}")
                        .replace("{{TITLE}}", translate(locale, "gacha.records.title"))
                        .replace("{{DATE}}", translate(locale, "gacha.records.date"))
                        .replace("{{ITEM}}", translate(locale, "gacha.records.item"))
                        .replace("{{LANGUAGE}}", Utils.getLanguageCode(account.getLocale()));
        ctx.contentType(ContentType.TEXT_HTML);
        ctx.result(template);
    }

    private static void gachaDetails(Context ctx) {
        if (ctx.queryParam("scheduleId") == null && ctx.queryParam("gachaType") != null) {
            gachaRecords(ctx);
            return;
        }

        var detailsTemplate = FileUtils.getDataPath("gacha/details.html");
        var sessionKey = ctx.queryParam("s");
        var account = DatabaseHelper.getAccountBySessionKey(sessionKey);
        if (account == null) {
            ctx.status(403).result("Requested account was not found");
            return;
        }

        String template;
        try {
            template = Files.readString(detailsTemplate);
        } catch (IOException e) {
            Grasscutter.getLogger().warn("Failed to read data/gacha/details.html");
            ctx.status(500);
            return;
        }

        // Add translated title etc. to the page.
        var locale = account.getLocale();
        template =
                template
                        .replace("{{TITLE}}", translate(locale, "gacha.details.title"))
                        .replace(
                                "{{AVAILABLE_FIVE_STARS}}", translate(locale, "gacha.details.available_five_stars"))
                        .replace(
                                "{{AVAILABLE_FOUR_STARS}}", translate(locale, "gacha.details.available_four_stars"))
                        .replace(
                                "{{AVAILABLE_THREE_STARS}}",
                                translate(locale, "gacha.details.available_three_stars"))
                        .replace("{{LANGUAGE}}", Utils.getLanguageCode(account.getLocale()));

        // Get the banner info for the banner we want.
        var scheduleIdStr = ctx.queryParam("scheduleId");
        if (scheduleIdStr == null) {
            ctx.status(400).result("Missing scheduleId parameter");
            return;
        }

        var scheduleId = Integer.parseInt(scheduleIdStr);
        var manager = Grasscutter.getGameServer().getGachaSystem();
        var banner = manager.getGachaBanners().get(scheduleId);
        if (banner == null) {
            ctx.status(404).result("No banner with schedule id " + scheduleId);
            return;
        }

        // Add 5-star items.
        var fiveStarItems = new LinkedHashSet<String>();

        Arrays.stream(banner.getRateUpItems5()).forEach(i -> fiveStarItems.add(Integer.toString(i)));
        Arrays.stream(banner.getFallbackItems5Pool1())
                .forEach(i -> fiveStarItems.add(Integer.toString(i)));
        Arrays.stream(banner.getFallbackItems5Pool2())
                .forEach(i -> fiveStarItems.add(Integer.toString(i)));

        template = template.replace("{{FIVE_STARS}}", "[" + String.join(",", fiveStarItems) + "]");

        // Add 4-star items.
        var fourStarItems = new LinkedHashSet<String>();

        Arrays.stream(banner.getRateUpItems4()).forEach(i -> fourStarItems.add(Integer.toString(i)));
        Arrays.stream(banner.getFallbackItems4Pool1())
                .forEach(i -> fourStarItems.add(Integer.toString(i)));
        Arrays.stream(banner.getFallbackItems4Pool2())
                .forEach(i -> fourStarItems.add(Integer.toString(i)));

        template = template.replace("{{FOUR_STARS}}", "[" + String.join(",", fourStarItems) + "]");

        // Add 3-star items.
        var threeStarItems = new LinkedHashSet<String>();
        Arrays.stream(banner.getFallbackItems3()).forEach(i -> threeStarItems.add(Integer.toString(i)));
        template = template.replace("{{THREE_STARS}}", "[" + String.join(",", threeStarItems) + "]");

        // Done.
        ctx.contentType(ContentType.TEXT_HTML);
        ctx.result(template);
    }

    /**
     * Fetches the gacha records for the specified player.
     *
     * @param player The player to fetch the records for.
     * @param response The response to write to.
     * @param page The page to fetch.
     * @param type The gacha type to fetch.
     */
    public static void fetchGachaRecords(Player player, JsonObject response, int page, int type) {
        var playerId = player.getUid();
        // Calculate intervals across the entire pool before paging. Weapon/character pools
        // are filtered separately, and a page boundary must never reset the pull counter.
        var all = new ArrayList<>(DatabaseHelper.getGachaRecords(playerId, 0, type, Integer.MAX_VALUE));
        all.sort(Comparator.comparing(emu.grasscutter.game.gacha.GachaRecord::getTransactionDate)
                .thenComparing(emu.grasscutter.game.gacha.GachaRecord::getId));
        var annotated = new com.google.gson.JsonArray();
        int sinceFive = 0, fiveCount = 0;
        for (var record : all) {
            sinceFive++;
            var entry = new JsonObject();
            entry.addProperty("time", record.getTransactionDate().getTime());
            entry.addProperty("item", record.getItemID());
            var item = emu.grasscutter.data.GameData.getItemDataMap().get(record.getItemID());
            int stars = item == null ? 0 : item.getRankLevel();
            entry.addProperty("stars", stars);
            if (stars == 5) {
                entry.addProperty("pullsToFive", sinceFive);
                entry.addProperty("fromFirstRecord", fiveCount == 0);
                fiveCount++;
                sinceFive = 0;
            }
            annotated.add(entry);
        }
        int safePage = Math.max(0, page);
        var slice = new com.google.gson.JsonArray();
        long start = (long)safePage * 10;
        for (long index = start; index < Math.min(start + 10, all.size()); index++)
            slice.add(annotated.get(all.size() - 1 - (int)index));
        var records = slice.toString();
        long maxPage = (all.size() + 9L) / 10;
        var summary = new JsonObject();
        summary.addProperty("total", all.size());
        summary.addProperty("fiveStars", fiveCount);
        summary.addProperty("sinceLastFive", sinceFive);
        summary.addProperty("gachaType", type);

        // Finish the response.
        response.addProperty("retcode", 0);
        response.addProperty("records", records);
        response.addProperty("maxPage", maxPage);
        response.addProperty("summary", summary.toString());
    }

    @Override
    public void applyRoutes(Javalin javalin) {
        javalin.get("/gacha", GachaHandler::gachaRecords);
        javalin.get("/gacha/details", GachaHandler::gachaDetails);
        javalin.get("/gacha/mappings", ctx -> ctx.result(FileUtils.read(gachaMappingsPath.toString())));
    }
}
