# Starter statue compatibility fallback

Scope: UID 10001, scene 3, activated point 7, player within 12 metres. Adds a ground-level worktop near the player because the native NPC interaction remains invisible. Does not complete quests, alter rewards, or consume offering items.

Options: 10010001 heals the active party through the existing statue manager; 1159 invokes the existing Mondstadt resonance path. Native offering menu remains unresolved. Creation and selection are logged under StatueCompat.

Build: E:\bin\javac.exe -encoding UTF-8 -proc:none -cp "server/grasscutter.jar;server/lib/*" -d runtime/statue-compat/classes runtime/statue-compat/src/localfix/StatueCompat.java
Package: E:\bin\jar.exe --create --file server/plugins/LocalStatueCompat.jar -C runtime/statue-compat/classes .
Rollback: stop local server, move server/plugins/LocalStatueCompat.jar outside plugins, restart server. Source at runtime/statue-compat/src/localfix/StatueCompat.java.

Verification: Compiles against installed server JAR. Live startup and client interaction acceptance must be checked separately. A successfully created entity does not prove the client displays its button.
